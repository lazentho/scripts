-- NOXIS LOADER
-- gameId -> raw script url. One line per game.
local SCRIPTS = {
    [10708913337] = 'https://raw.githubusercontent.com/lazentho/scripts/refs/heads/main/AnimeDice.lua',
    [10773907070] = 'https://raw.githubusercontent.com/lazentho/scripts/refs/heads/main/ChessBestMove.lua',
}

local function popup(message)
    local parent = (gethui and gethui()) or game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui')

    local old = parent:FindFirstChild('NOXIS_LOADER')
    if old then
        old:Destroy()
    end

    local gui = Instance.new('ScreenGui')
    gui.Name = 'NOXIS_LOADER'
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 20000
    gui.Parent = parent

    local card = Instance.new('Frame')
    card.Name = 'Card'
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    local viewport = workspace.CurrentCamera.ViewportSize
    card.Position = UDim2.fromOffset(math.floor(viewport.X / 2), math.floor(viewport.Y / 2))
    card.Size = UDim2.fromOffset(480, 190)
    card.BackgroundColor3 = Color3.fromRGB(16, 14, 23)
    card.BorderSizePixel = 0
    card.Parent = gui

    Instance.new('UICorner', card).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new('UIStroke')
    stroke.Color = Color3.fromRGB(64, 54, 92)
    stroke.Parent = card

    local label = Instance.new('TextLabel')
    label.Name = 'Message'
    label.Position = UDim2.fromOffset(28, 16)
    label.Size = UDim2.new(1, -112, 1, -32)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 36
    label.TextColor3 = Color3.fromRGB(235, 231, 247)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.Text = message
    label.Parent = card

    local close = Instance.new('TextButton')
    close.Name = 'Close'
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -14, 0, 14)
    close.Size = UDim2.fromOffset(28, 28)
    close.BackgroundTransparency = 1
    close.AutoButtonColor = false
    close.Font = Enum.Font.GothamBold
    close.Text = '×'
    close.TextSize = 20
    close.TextColor3 = Color3.fromRGB(150, 144, 172)
    close.Parent = card

    close.MouseEnter:Connect(function()
        close.TextColor3 = Color3.fromRGB(235, 231, 247)
    end)
    close.MouseLeave:Connect(function()
        close.TextColor3 = Color3.fromRGB(150, 144, 172)
    end)
    close.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)
end

local url = SCRIPTS[game.GameId] or SCRIPTS[game.PlaceId]
if not url then
    popup('There is no script for this game.')
    return
end

pcall(function()
    local bust = url .. (url:find('?', 1, true) and '&' or '?') .. 'v=' .. tostring(os.time())
    loadstring(game:HttpGet(bust))()
end)
