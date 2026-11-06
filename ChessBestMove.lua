--[[
    NOXIS · RoChess best move  (cyan = you, red = enemy)
    Lichess cloud -> Stockfish 15 -> local quick analysis
]]

local REPO = 'https://raw.githubusercontent.com/lazentho/Base/refs/heads/main/'
local BASE_URL = getgenv().NOXIS_BASE_URL or (REPO .. 'NoxisHub.lua?v=' .. tostring(os.time()))

local previous = getgenv().ChessBestMove
if previous then
    if type(previous.Unload) == 'function' then pcall(previous.Unload) end
    if previous.hub and previous.hub.Destroy then pcall(function() previous.hub:Destroy() end) end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("LynxBestMove")
if oldGui then oldGui:Destroy() end

local Chess = ReplicatedStorage:WaitForChild("Chess")
local ChessClient = ReplicatedStorage:WaitForChild("ChessClient")
local Engine = require(Chess:WaitForChild("Engine"))
local Bot = require(Chess:WaitForChild("Bot"))
local App = require(ChessClient:WaitForChild("App"))

local ARROW_ID = "lynx_best"
local ARROW_ME = Color3.fromRGB(80, 195, 255)
local ARROW_ENEMY = Color3.fromRGB(255, 88, 88)
local STOCKFISH_DEPTH = 15
local CLOUD_TIMEOUT = 2.5
local STOCKFISH_TIMEOUT = 8

local state = {
    Enabled = true,
    Token = 0,
    LastKey = nil,
    LastDraw = nil,
    Cache = {},
    CacheOrder = {},
}

local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function encodeFen(fen)
    return (fen:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function httpGet(url, timeout)
    local holder = { done = false, body = nil }
    task.spawn(function()
        local ok, body = pcall(game.HttpGet, game, url)
        if ok then
            holder.body = body
        end
        holder.done = true
    end)
    local deadline = os.clock() + timeout
    while not holder.done and os.clock() < deadline do
        task.wait(0.05)
    end
    return holder.done and holder.body or nil
end

local function stmSign(fen)
    return string.match(fen, "%s([wb])%s") == "w" and 1 or -1
end

-- API scores are White-perspective; convert to side-to-move.
local function tryCloud(fen, sign)
    local body = httpGet(
        "https://lichess.org/api/cloud-eval?fen=" .. encodeFen(fen) .. "&multiPv=1",
        CLOUD_TIMEOUT
    )
    if not body then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or type(data) ~= "table" or type(data.pvs) ~= "table" then return nil end
    local pv = data.pvs[1]
    if type(pv) ~= "table" or type(pv.moves) ~= "string" then return nil end
    local move = string.match(pv.moves, "^%S+")
    if not move or #move < 4 then return nil end
    local cp = tonumber(pv.cp)
    local mate = tonumber(pv.mate)
    return {
        best = move,
        cp = cp and cp * sign or nil,
        mate = mate and mate * sign or nil,
        depth = tonumber(data.depth),
        source = "Lichess",
    }
end

local function tryStockfish(fen, sign)
    local body = httpGet(
        "https://stockfish.online/api/s/v2.php?fen=" .. encodeFen(fen) .. "&depth=" .. tostring(STOCKFISH_DEPTH),
        STOCKFISH_TIMEOUT
    )
    if not body then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not ok or type(data) ~= "table" or not data.success then return nil end
    local move = string.match(tostring(data.bestmove or ""), "bestmove%s+(%S+)")
    if not move or #move < 4 then return nil end
    local evaluation = tonumber(data.evaluation)
    local mate = tonumber(data.mate)
    return {
        best = move,
        cp = evaluation and evaluation * 100 * sign or nil,
        mate = mate and mate * sign or nil,
        depth = STOCKFISH_DEPTH,
        source = "Stockfish",
    }
end

local function tryLocal(fen, sign)
    local ok, result = pcall(Bot.analyse, fen, {}, 0.5, 20)
    if not ok or type(result) ~= "table" or not result.best then return nil end
    return {
        best = result.best,
        cp = result.score and result.score * sign or nil,
        mate = result.mate and result.mate * sign or nil,
        depth = result.depth,
        source = "Local quick",
    }
end

local function store(fen, result)
    if not state.Cache[fen] then
        table.insert(state.CacheOrder, fen)
        if #state.CacheOrder > 40 then
            local oldest = table.remove(state.CacheOrder, 1)
            state.Cache[oldest] = nil
        end
    end
    state.Cache[fen] = result
end

local function formatEval(result)
    if result.mate ~= nil then
        return (result.mate > 0 and "+M" or "-M") .. tostring(math.abs(result.mate))
    end
    if result.cp == nil then return "?" end
    return string.format("%+.2f", result.cp / 100)
end

local bestLabel, statusLabel
local fallbackStatus = 'waiting for a game...'

local function clearArrow()
    state.LastDraw = nil
    pcall(function()
        if App.board then
            App.board:setArrow(ARROW_ID, nil)
        end
    end)
end

local function drawArrow(fromSq, toSq, mine)
    local color = mine and ARROW_ME or ARROW_ENEMY
    state.LastDraw = { from = fromSq, to = toSq, color = color }
    pcall(function()
        App.board:setArrow(ARROW_ID, fromSq, toSq, color, 0.12)
    end)
end

local function activeSession()
    local session = App.session
    if not session or session.kind == "idle" or session.over then
        return nil
    end
    if not session.engine or session.viewPly ~= #session.ucis then
        return nil
    end
    return session
end

local function sessionKey(session)
    return session.engine:getFen() .. "|" .. tostring(#session.ucis) .. "|" .. tostring(session.version)
end

local function stillCurrent(session, key, token, fen)
    return token == state.Token
        and state.Enabled
        and App.session == session
        and not session.over
        and session.viewPly == #session.ucis
        and sessionKey(session) == key
        and session.engine:getFen() == fen
end

local function render(session, key, result, elapsed)
    local fen = session.engine:getFen()
    local moveEngine = Engine.new(fen)
    local bestMove = moveEngine:moveFromUci(result.best)
    if not bestMove then
        statusLabel:Set('no legal best move')
        bestLabel:Set('--')
        clearArrow()
        return
    end

    local san = moveEngine:moveToSan(bestMove) or result.best
    local fromSq = Engine.algToIndex64(string.sub(result.best, 1, 2))
    local toSq = Engine.algToIndex64(string.sub(result.best, 3, 4))
    local mine = session:isMyTurn()

    bestLabel:Set(string.format(
        "%s · %s · %s",
        mine and "You" or "Enemy",
        san,
        formatEval(result)
    ))
    statusLabel:Set(string.format(
        "%s d%s · %s · %s",
        result.source,
        tostring(result.depth or "?"),
        elapsed > 0 and string.format("%.1fs", elapsed) or "cached",
        mine and "your move" or "enemy move"
    ))

    if fromSq and toSq then
        drawArrow(fromSq, toSq, mine)
    end
end

local sfBusy = false

local function analyse(session, key, token)
    local fen = session.engine:getFen()
    local sign = stmSign(fen)
    local t0 = os.clock()

    task.spawn(function()
        local cached = state.Cache[fen]
        if cached then
            if stillCurrent(session, key, token, fen) then
                render(session, key, cached, 0)
            end
            return
        end

        local cloudResult = tryCloud(fen, sign)
        if cloudResult then
            store(fen, cloudResult)
            if stillCurrent(session, key, token, fen) then
                render(session, key, cloudResult, os.clock() - t0)
            end
            return
        end

        if not stillCurrent(session, key, token, fen) then
            return
        end

        local upgraded = false
        task.spawn(function()
            local quick = tryLocal(fen, sign)
            if quick and not upgraded then
                store(fen, quick)
                if stillCurrent(session, key, token, fen) then
                    render(session, key, quick, os.clock() - t0)
                end
            end
        end)

        if not sfBusy then
            sfBusy = true
            local sf = tryStockfish(fen, sign)
            sfBusy = false
            if sf then
                upgraded = true
                store(fen, sf)
                if stillCurrent(session, key, token, fen) then
                    render(session, key, sf, os.clock() - t0)
                end
            end
        end
    end)
end

-- menu

getgenv().NOXIS_DEMO = false
getgenv().NOXIS_CFG = { Name = 'NOXIS', Subtitle = 'CHESS', Version = 'v1.0' }
local Hub = loadstring(game:HttpGet(BASE_URL))()
getgenv().NOXIS_DEMO = nil
getgenv().NOXIS_CFG = nil

local page = Hub:Page('Chess', 'CH')
page:Sub('Best move · cyan = you · red = enemy')

local sec = page:Section('BEST MOVE')
bestLabel = sec:Label({
    title = 'Best move',
    desc = 'Top line for the side to move',
    icon = 'BM',
    value = '--',
})
statusLabel = sec:Label({
    title = 'Status',
    desc = 'Source · depth · time',
    icon = 'ST',
    value = fallbackStatus,
})

sec:Toggle({
    id = 'ch_hints',
    title = 'Hints',
    desc = 'Draw the arrow and update the analysis',
    icon = 'HN',
    value = true,
    apply = function(v)
        state.Enabled = v
    end,
    callback = function(v)
        state.Enabled = v
        if not v then
            state.Token += 1
            state.LastKey = 'off'
            clearArrow()
            bestLabel:Set('--')
            statusLabel:Set('hints off')
        end
    end,
})

local function unload()
    state.Token += 1
    clearArrow()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
    if getgenv().ChessBestMove and getgenv().ChessBestMove.hub == Hub then
        getgenv().ChessBestMove = nil
    end
end

getgenv().ChessBestMove = {
    hub = Hub,
    state = state,
    Unload = unload,
}

local acc = 0
track(RunService.Heartbeat:Connect(function(dt)
    if Hub._destroyed then
        unload()
        return
    end

    acc += dt
    if acc < 0.25 then return end
    acc = 0

    if not state.Enabled then
        if state.LastKey ~= "off" then
            state.LastKey = "off"
            state.Token += 1
            clearArrow()
            bestLabel:Set('--')
            statusLabel:Set('hints off')
        end
        return
    end

    local session = activeSession()
    if not session then
        if state.LastKey ~= nil then
            state.LastKey = nil
            state.Token += 1
            clearArrow()
            bestLabel:Set('--')
            local any = App.session
            if any and any.kind ~= "idle" and not any.over then
                statusLabel:Set('reviewing history...')
            else
                statusLabel:Set(fallbackStatus)
            end
        end
        return
    end

    local key = sessionKey(session)
    if key ~= state.LastKey then
        state.LastKey = key
        state.Token += 1
        clearArrow()
        bestLabel:Set('--')
        statusLabel:Set(session:isMyTurn() and 'analysing your move...' or 'analysing opponent...')
        analyse(session, key, state.Token)
    elseif state.LastDraw and App.board and App.board.arrows and not App.board.arrows[ARROW_ID] then
        drawArrow(state.LastDraw.from, state.LastDraw.to, state.LastDraw.color == ARROW_ME)
    end
end))

print('[Chess] best move ready | cyan=you red=enemy | Lichess -> Stockfish 15 -> local')
