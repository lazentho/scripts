--[[
    NOXIS · Anime Dice  (gameId 10708913337)
    Auto best · sell all · auto collect · auto rebirth

    Builds its pages on the NOXIS HUB base:
        getgenv().NOXIS_BASE_URL = '<local base url>'   (optional, testing)
]]

local REPO = 'https://raw.githubusercontent.com/lazentho/Base/refs/heads/main/'
local BASE_URL = getgenv().NOXIS_BASE_URL or (REPO .. 'NoxisHub.lua?v=' .. tostring(os.time()))

getgenv().NOXIS_DEMO = false
local Hub = loadstring(game:HttpGet(BASE_URL))()
getgenv().NOXIS_DEMO = nil

local RS = game:GetService('ReplicatedStorage')
local Net = RS:WaitForChild('Network')
local PlotRE = Net:WaitForChild('PlotService'):WaitForChild('RE')
local SellRE = Net:WaitForChild('SellService'):WaitForChild('RE')
local SellRF = Net:WaitForChild('SellService'):WaitForChild('RF')
local SellInventory = SellRF:WaitForChild('SellInventory')
local RebirthRE = Net:WaitForChild('RebirthService'):WaitForChild('RE')

local Data = require(RS.Framework.Features.Data.DataController)
local Rebirths = require(RS.Framework.Features.Rebirth.Rebirths)
local PlotConfig = require(RS.Framework.Features.Plot.PlotConfig)
local EntryRegistry = require(RS.Framework.Features.Inventory.EntryRegistry)

local MAX_SLOTS = PlotConfig.GetMaxSlots()

local S = {
    autoBest = false,
    autoSellFull = false,
    fullAt = 200,
    lastSellAll = 0,
    autoCollect = false,
    collectEvery = 5,
    autoRebirth = false,
    lastBest = 0,
    lastRebirth = 0,
    pendingBest = false,
}

local statusBest, slotsLabel, progress

local function compact(n)
    n = tonumber(n) or 0
    local suffix = { { 1e12, 't' }, { 1e9, 'b' }, { 1e6, 'm' }, { 1e3, 'k' } }
    for _, pair in ipairs(suffix) do
        if n >= pair[1] then
            local text = string.format('%.2f', n / pair[1]):gsub('%.?0+$', '')
            return text .. pair[2]
        end
    end
    return tostring(math.floor(n))
end

local function fireBest(reason)
    if not S.autoBest or Hub._destroyed then return end
    local now = os.clock()
    if now - S.lastBest < 2 then return end
    S.lastBest = now
    local ok = pcall(function()
        PlotRE.EquipBest:FireServer()
    end)
    if statusBest then
        statusBest:Set(ok and ('requested · ' .. reason) or 'failed')
    end
end

local function scheduleBest(reason)
    if not S.autoBest or S.pendingBest then return end
    S.pendingBest = true
    task.delay(1.5, function()
        S.pendingBest = false
        fireBest(reason)
    end)
end

local function isUnit(entry)
    if type(entry) ~= 'table' or not entry.name then return false end
    local config = EntryRegistry.getEntryConfig(entry.name)
    return config ~= nil and config.kind == 'Unit'
end

local function inventoryUnits()
    local units = {}
    local ok, inv = pcall(function()
        return Data.Inventory()
    end)
    if ok and type(inv) == 'table' then
        for key, entry in pairs(inv) do
            if isUnit(entry) then units[key] = entry end
        end
    end
    return units
end

local function sellableKeys()
    local units = inventoryUnits()
    local plotted = {}
    for i = 1, MAX_SLOTS do
        local slot = Data.Slots[tostring(i)]
        local value = slot and slot()
        if value and value.unitId then plotted[value.unitId] = true end
    end
    local keys = {}
    for key, entry in pairs(units) do
        if not plotted[key] and not ((entry.attributes or {}).locked) then
            table.insert(keys, key)
        end
    end
    return keys
end

local function sellAll(quiet)
    local keys = sellableKeys()
    if #keys == 0 then
        if not quiet then Hub:Notify('Nothing to sell', 'info') end
        return
    end
    local ok, _, total = pcall(function()
        return SellInventory:InvokeServer(keys)
    end)
    if not ok then
        Hub:Notify('Sell failed', 'error')
        return
    end
    Hub:Notify('Sold ' .. #keys .. ' units · $' .. compact(tonumber(total) or 0), 'success')
end

local page = Hub:Page('Main', 'AD')
page:Sub('Anime Dice · auto best · sell all · auto collect · rebirth')

local bestSec = page:Section('AUTO BEST')
local bestToggle = bestSec:Toggle({
    id = 'ad_autobest',
    title = 'Auto best',
    desc = 'Re-equips your strongest units when the plot changes',
    icon = 'AB',
    value = false,
    apply = function(v)
        S.autoBest = v
    end,
    callback = function(v)
        S.autoBest = v
        if v then
            fireBest('enabled')
            Hub:Notify('Auto best enabled', 'success')
        else
            Hub:Notify('Auto best disabled', 'info')
        end
    end,
})
statusBest = bestSec:Label({
    title = 'Last action',
    desc = 'What the plot received most recently',
    icon = 'LA',
    value = 'idle',
})
slotsLabel = bestSec:Label({
    title = 'Plot',
    desc = 'Units currently placed',
    icon = 'PL',
    value = '—',
})

local allSec = page:Section('SELL ALL')

allSec:Button({
    title = 'Sell all now',
    desc = 'Sells every unit except locked and plotted',
    text = 'SELL',
    icon = 'SA',
    callback = function()
        sellAll()
    end,
})

local fullToggle = allSec:Toggle({
    id = 'ad_sellfull',
    title = 'Auto sell when full',
    desc = 'Sells everything once the inventory reaches the limit',
    icon = 'SF',
    value = false,
    apply = function(v)
        S.autoSellFull = v
    end,
    callback = function(v)
        S.autoSellFull = v
        Hub:Notify(v and ('Sell when full · ' .. S.fullAt .. ' units') or 'Sell when full disabled', v and 'success' or 'info')
    end,
})

local fullSlider = allSec:Slider({
    id = 'ad_fulllimit',
    title = 'Full at',
    desc = 'Inventory count that triggers the sale',
    icon = 'FL',
    min = 10,
    max = 1000,
    step = 10,
    value = S.fullAt,
    apply = function(v)
        S.fullAt = v
    end,
    callback = function(v)
        S.fullAt = v
    end,
})

local countLabel = allSec:Label({
    title = 'Inventory',
    desc = 'Units currently owned',
    icon = 'IN',
    value = '—',
})

local collectSec = page:Section('AUTO COLLECT')
local collectToggle = collectSec:Toggle({
    id = 'ad_autocollect',
    title = 'Auto collect',
    desc = 'Claims plot balance on a timer',
    icon = 'AC',
    value = false,
    apply = function(v)
        S.autoCollect = v
    end,
    callback = function(v)
        S.autoCollect = v
        Hub:Notify('Auto collect ' .. (v and 'enabled' or 'disabled'), v and 'success' or 'info')
    end,
})
collectSec:Slider({
    id = 'ad_collectevery',
    title = 'Interval',
    desc = 'How often balance is claimed',
    icon = 'IV',
    min = 2,
    max = 15,
    step = 1,
    value = 5,
    suffix = 's',
    apply = function(v)
        S.collectEvery = v
    end,
    callback = function(v)
        S.collectEvery = v
    end,
})

local rebirthSec = page:Section('AUTO REBIRTH')
local rebirthToggle = rebirthSec:Toggle({
    id = 'ad_autorebirth',
    title = 'Auto rebirth',
    desc = 'Rebirths as soon as cash covers the cost',
    icon = 'RB',
    value = false,
    apply = function(v)
        S.autoRebirth = v
    end,
    callback = function(v)
        S.autoRebirth = v
        Hub:Notify('Auto rebirth ' .. (v and 'enabled' or 'disabled'), v and 'success' or 'info')
    end,
})
progress = rebirthSec:Label({
    title = 'Progress',
    desc = 'Cash toward the next rebirth',
    icon = 'PG',
    value = '—',
})

-- stored menu state never re-arms automation on its own
bestToggle:Set(false, true)
collectToggle:Set(false, true)
rebirthToggle:Set(false, true)
fullToggle:Set(false, true)
S.autoBest, S.autoCollect, S.autoRebirth, S.autoSellFull = false, false, false, false

-- per-roll auto sell is intentionally off; all selling goes through SELL ALL
pcall(function()
    SellRE.UpdateAutoSell:FireServer(0)
end)

pcall(function()
    Data.Inventory.OnKeyAdded(function()
        scheduleBest('new unit')
    end)
    Data.Inventory.OnKeyRemoved(function()
        scheduleBest('unit sold')
    end)
    for i = 1, MAX_SLOTS do
        local slot = Data.Slots[tostring(i)]
        if slot then
            slot.Changed(function()
                scheduleBest('slot change')
            end)
        end
    end
end)

task.spawn(function()
    while not Hub._destroyed do
        task.wait(15)
        if S.autoBest then
            fireBest('periodic')
        end
    end
end)

task.spawn(function()
    while not Hub._destroyed do
        if S.autoCollect then
            for i = 1, MAX_SLOTS do
                pcall(function()
                    PlotRE.CollectBalance:FireServer(i)
                end)
            end
        end
        task.wait(S.collectEvery)
    end
end)

task.spawn(function()
    while not Hub._destroyed do
        if S.autoRebirth then
            pcall(function()
                local index = Data.Rebirth()
                local nextCfg = Rebirths.GetNext(index)
                if nextCfg and nextCfg.cost and Data.Money() >= nextCfg.cost
                    and os.clock() - S.lastRebirth > 6 then
                    S.lastRebirth = os.clock()
                    RebirthRE.Rebirth:FireServer()
                    Hub:Notify('Rebirth fired', 'success')
                end
            end)
        end
        task.wait(2)
    end
end)

task.spawn(function()
    while not Hub._destroyed do
        pcall(function()
            local money = Data.Money()
            local index = Data.Rebirth()
            local cfg = Rebirths.GetNext(index)
            local cost = cfg and cfg.cost or 0
            if progress then
                if cost and cost > 0 then
                    local pct = math.floor(math.min(money / cost, 1) * 100)
                    progress:Set(compact(money) .. ' / ' .. compact(cost) .. ' · ' .. pct .. '%')
                else
                    progress:Set(compact(money) .. ' · max')
                end
            end
            local used = 0
            for i = 1, MAX_SLOTS do
                local slot = Data.Slots[tostring(i)]
                local value = slot and slot()
                if value and value.unitId then
                    used += 1
                end
            end
            if slotsLabel then
                slotsLabel:Set(used .. '/' .. MAX_SLOTS .. ' slots')
            end
            local units = inventoryUnits()
            local unitCount = 0
            for _ in pairs(units) do
                unitCount += 1
            end
            if countLabel then
                countLabel:Set(unitCount .. ' units')
            end
            if S.autoSellFull and unitCount >= S.fullAt and os.clock() - S.lastSellAll > 5 then
                S.lastSellAll = os.clock()
                task.spawn(function()
                    sellAll(true)
                end)
            end
        end)
        task.wait(1.5)
    end
end)

getgenv().AnimeDice = {
    hub = Hub,
    state = S,
    ui = {
        best = bestToggle,
        status = statusBest,
        slots = slotsLabel,
        full = fullToggle,
        fullAt = fullSlider,
        count = countLabel,
        collect = collectToggle,
        rebirth = rebirthToggle,
        progress = progress,
    },
}

Hub:Notify('Anime Dice tools ready', 'success')
print('[NOXIS] Anime Dice menu built')
