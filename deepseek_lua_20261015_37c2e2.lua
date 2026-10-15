--[[
============================================================
    TRKIEN LT2 HUB v3.3 - LAG FIXED
    Author : trkien depzai
    Fixes  : 9 bugs + lag throttle (Heartbeat 60fps -> 0.5-5s)
============================================================
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local Workspace    = game:GetService("Workspace")
local Lighting     = game:GetService("Lighting")
local LocalPlayer  = Players.LocalPlayer

-- ================= CONFIG =================
local CONFIG = {
    AutoFarm       = false,
    AutoChop       = true,
    AutoPickup     = true,
    AutoSell       = false,
    AutoEquipAxe   = true,
    ESP            = false,
    Fullbright     = false,
    InfiniteJump   = false,
    LagFix         = true,
    AntiAFK        = true,

    WalkSpeed      = 50,
    ChopRange      = 45,
    PickupRange    = 30,
    SellRange      = 20,
    RenderDist     = 400,
    FarmDelay      = 0.3,

    BasePos        = Vector3.new(0, 0, 0),
    SellPos        = Vector3.new(0, 0, 0),
    TargetWood     = "Oak",
}

local KEYS = {
    ToggleGUI   = Enum.KeyCode.RightControl,
    TeleBase    = Enum.KeyCode.B,
    TeleSell    = Enum.KeyCode.V,
    TeleTree    = Enum.KeyCode.T,
    ToggleFarm  = Enum.KeyCode.F,
}

local STATE = {
    Running     = true,
    FarmPhase   = "CHOP",
    LastPos     = Vector3.new(),
    ESPCache    = {},
    CurrentTab  = "Farm",
    WaitingKey  = nil,
}

local AxeModule = {
    PreferredAxe  = "auto",
    CheckInterval = 0.5,
    LastCheck     = 0,
    CurrentAxe    = nil,
}

local AXE_PRIORITY = {
    "basic", "plain", "steel", "gold", "frost",
    "sinister", "spooky",
    "axe", "hatchet",
    "apocalypse",
    "phantom",
    "chainsaw",
}

-- ================= UTILS =================
local function log(msg)
    print("[TRKIEN] " .. tostring(msg))
end

local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function isTree(o)
    if not o or not o:IsA("Model") then return false end
    local n = o.Name:lower()
    if n:find("tree") then return true end
    if n:find("log") and not n:find("login") then
        if o.PrimaryPart and #o:GetChildren() > 2 then return true end
    end
    return false
end

local function isWood(o)
    if not o or not o:IsA("BasePart") then return false end
    local n = o.Name:lower()
    return n:find("log") or n:find("wood") or n:find("plank")
end

local function isSell(o)
    if not o or not o:IsA("BasePart") then return false end
    local n = o.Name:lower()
    return n:find("sell") or n:find("shop") or n:find("market")
end

local function dist(a, b) return (a - b).Magnitude end

-- FIX LAG: chi quet folder cap 1, éo quet het Workspace
local function forEachInFolders(callback)
    for _, folder in pairs(Workspace:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Model") then
            for _, o in pairs(folder:GetChildren()) do
                callback(o)
            end
        end
    end
end

-- ================= AXE =================
local function getBackpack()
    return LocalPlayer:FindFirstChildOfClass("Backpack")
end

local function getCharTools()
    local c = LocalPlayer.Character
    if not c then return {} end
    local t = {}
    for _, o in pairs(c:GetChildren()) do
        if o:IsA("Tool") then table.insert(t, o) end
    end
    return t
end

local function getAllAxes()
    local axes = {}
    local bp = getBackpack()
    if bp then
        for _, o in pairs(bp:GetChildren()) do
            if o:IsA("Tool") then table.insert(axes, o) end
        end
    end
    for _, o in pairs(getCharTools()) do
        table.insert(axes, o)
    end
    return axes
end

local function axeScore(name)
    local n = name:lower()
    for i, key in ipairs(AXE_PRIORITY) do
        if n:find(key) then
            return #AXE_PRIORITY - i + 1
        end
    end
    return 0
end

local function isAxe(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local n = tool.Name:lower()
    return n:find("axe") or n:find("hatchet") or n:find("chainsaw")
        or n:find("apocalypse") or n:find("sinister") or n:find("spooky")
end

local function equipTool(tool)
    local c = LocalPlayer.Character
    if not c then return false end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    pcall(function() hum:EquipTool(tool) end)
    return true
end

local function autoEquipAxe()
    if not CONFIG.AutoEquipAxe then return end
    if tick() - AxeModule.LastCheck < AxeModule.CheckInterval then return end
    AxeModule.LastCheck = tick()

    local axes = getAllAxes()
    if #axes == 0 then return end

    local realAxes = {}
    for _, t in ipairs(axes) do
        if isAxe(t) then table.insert(realAxes, t) end
    end
    if #realAxes == 0 then return end

    local chosen
    if AxeModule.PreferredAxe == "auto" then
        local best, bestScore = nil, -1
        for _, t in ipairs(realAxes) do
            local s = axeScore(t.Name)
            if s > bestScore then best, bestScore = t, s end
        end
        chosen = best
    else
        for _, t in ipairs(realAxes) do
            if t.Name:lower():find(AxeModule.PreferredAxe:lower()) then
                chosen = t
                break
            end
        end
    end
    if not chosen then return end

    local c = LocalPlayer.Character
    if c and chosen.Parent == c then
        AxeModule.CurrentAxe = chosen.Name
        return
    end

    if equipTool(chosen) then
        AxeModule.CurrentAxe = chosen.Name
        log("Equipped: " .. chosen.Name)
    end
end

-- ================= GUI =================
local currentGui = nil

local function buildGUI()
    local parent = LocalPlayer:WaitForChild("PlayerGui")
    local old = parent:FindFirstChild("TRKIEN_HUB")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "TRKIEN_HUB"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent
    currentGui = gui

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, 500, 0, 340)
    main.Position = UDim2.new(0.5, -250, 0.5, -170)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(255, 60, 60)
    stroke.Thickness = 1.5

    local header = Instance.new("Frame", main)
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    header.BorderSizePixel = 0
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "TRKIEN LT2 HUB  •  v3.3"
    title.TextColor3 = Color3.fromRGB(255, 70, 70)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left

    local minBtn = Instance.new("TextButton", header)
    minBtn.Size = UDim2.new(0, 28, 0, 28)
    minBtn.Position = UDim2.new(1, -64, 0, 6)
    minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.BorderSizePixel = 0
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -32, 0, 6)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 25, 25)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.BorderSizePixel = 0
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        main.Size = minimized and UDim2.new(0, 500, 0, 40) or UDim2.new(0, 500, 0, 340)
        main.Position = minimized and UDim2.new(0.5, -250, 0, 50) or UDim2.new(0.5, -250, 0.5, -170)
    end)

    local tabBar = Instance.new("Frame", main)
    tabBar.Size = UDim2.new(1, -20, 0, 30)
    tabBar.Position = UDim2.new(0, 10, 0, 48)
    tabBar.BackgroundTransparency = 1

    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 5)

    local content = Instance.new("Frame", main)
    content.Size = UDim2.new(1, -20, 1, -95)
    content.Position = UDim2.new(0, 10, 0, 85)
    content.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    content.BorderSizePixel = 0
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

    local pages = {}
    local tabButtons = {}

    local function switchTab(name)
        STATE.CurrentTab = name
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, b in pairs(tabButtons) do
            b.BackgroundColor3 = (n == name) and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(40, 40, 50)
            b.TextColor3 = (n == name) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
        end
    end

    local function addTab(name)
        local btn = Instance.new("TextButton", tabBar)
        btn.Size = UDim2.new(0, 110, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(180, 180, 180)
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 13
        btn.BorderSizePixel = 0
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        btn.MouseButton1Click:Connect(function() switchTab(name) end)
        tabButtons[name] = btn

        local page = Instance.new("ScrollingFrame", content)
        page.Size = UDim2.new(1, -10, 1, -10)
        page.Position = UDim2.new(0, 5, 0, 5)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 4
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = false
        local lay = Instance.new("UIListLayout", page)
        lay.Padding = UDim.new(0, 5)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        pages[name] = page
        return page
    end

    local function makeRow(parent, text, key, isToggle, onToggle)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, -10, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(0.6, 0, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 13
        lbl.TextXAlignment = Enum.TextXAlignment.Left

        if isToggle then
            local btn = Instance.new("TextButton", row)
            btn.Size = UDim2.new(0, 90, 0, 24)
            btn.Position = UDim2.new(1, -180, 0, 5)
            btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(30, 100, 40) or Color3.fromRGB(50, 50, 60)
            btn.Text = CONFIG[key] and "ON" or "OFF"
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 12
            btn.BorderSizePixel = 0
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
            btn.MouseButton1Click:Connect(function()
                CONFIG[key] = not CONFIG[key]
                btn.Text = CONFIG[key] and "ON" or "OFF"
                btn.BackgroundColor3 = CONFIG[key] and Color3.fromRGB(30, 100, 40) or Color3.fromRGB(50, 50, 60)
            end)
        end

        if onToggle then
            local act = Instance.new("TextButton", row)
            act.Size = UDim2.new(0, 80, 0, 24)
            act.Position = UDim2.new(1, -85, 0, 5)
            act.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
            act.Text = "Chay"
            act.TextColor3 = Color3.fromRGB(220, 220, 220)
            act.Font = Enum.Font.Gotham
            act.TextSize = 12
            act.BorderSizePixel = 0
            Instance.new("UICorner", act).CornerRadius = UDim.new(0, 5)
            act.MouseButton1Click:Connect(onToggle)
        end
        return row
    end

    local function makeSection(parent, text)
        local lbl = Instance.new("TextLabel", parent)
        lbl.Size = UDim2.new(1, -10, 0, 24)
        lbl.BackgroundColor3 = Color3.fromRGB(50, 20, 25)
        lbl.Text = "  " .. text
        lbl.TextColor3 = Color3.fromRGB(255, 150, 150)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.BorderSizePixel = 0
        Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 5)
        return lbl
    end

    local farmPage = addTab("Farm")
    makeSection(farmPage, "AUTO FARM")
    makeRow(farmPage, "Auto Farm (loop)", "AutoFarm", true)
    makeRow(farmPage, "Auto Chop", "AutoChop", true)
    makeRow(farmPage, "Auto Equip Riu", "AutoEquipAxe", true)
    makeRow(farmPage, "Auto Pickup", "AutoPickup", true)
    makeRow(farmPage, "Auto Sell", "AutoSell", true)

    makeSection(farmPage, "TELEPORT")
    makeRow(farmPage, "Ve Base", nil, false, function()
        if CONFIG.BasePos.Magnitude < 1 then log("Chua luu Base!"); return end
        local r = getRoot(); if r then r.CFrame = CFrame.new(CONFIG.BasePos) end
    end)
    makeRow(farmPage, "Den Sell", nil, false, function()
        if CONFIG.SellPos.Magnitude < 1 then log("Chua luu Sell!"); return end
        local r = getRoot(); if r then r.CFrame = CFrame.new(CONFIG.SellPos) end
    end)
    makeRow(farmPage, "Luu Base", nil, false, function()
        local r = getRoot(); if r then CONFIG.BasePos = r.Position; log("Base saved") end
    end)
    makeRow(farmPage, "Luu Sell", nil, false, function()
        local r = getRoot(); if r then CONFIG.SellPos = r.Position; log("Sell saved") end
    end)

    local visPage = addTab("Visual")
    makeSection(visPage, "VISUAL")
    makeRow(visPage, "ESP Cay", "ESP", true)
    makeRow(visPage, "Fullbright", "Fullbright", true)
    makeRow(visPage, "Infinite Jump", "InfiniteJump", true)

    makeSection(visPage, "LAG FIX")
    makeRow(visPage, "Lag Fix", "LagFix", true)
    makeRow(visPage, "Render 400", nil, false, function() CONFIG.RenderDist = 400 end)
    makeRow(visPage, "Render 200", nil, false, function() CONFIG.RenderDist = 200 end)
    makeRow(visPage, "Render 100", nil, false, function() CONFIG.RenderDist = 100 end)

    makeSection(visPage, "MOVEMENT")
    makeRow(visPage, "WS +10", nil, false, function() CONFIG.WalkSpeed = CONFIG.WalkSpeed + 10 end)
    makeRow(visPage, "WS -10", nil, false, function() CONFIG.WalkSpeed = math.max(16, CONFIG.WalkSpeed - 10) end)
    makeRow(visPage, "WS Reset", nil, false, function() CONFIG.WalkSpeed = 50 end)

    local miscPage = addTab("Misc")
    makeSection(miscPage, "ANTI")
    makeRow(miscPage, "Anti AFK", "AntiAFK", true)

    makeSection(miscPage, "SERVER")
    makeRow(miscPage, "Reset Nhan Vat", nil, false, function()
        local c = LocalPlayer.Character; if c then c:BreakJoints() end
    end)
    makeRow(miscPage, "Rejoin", nil, false, function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end)

    local keyPage = addTab("Keybind")
    makeSection(keyPage, "PHIM TAT")

    local keyRows = {}
    for action, key in pairs(KEYS) do
        local row = makeRow(keyPage, action, nil, false, function()
            STATE.WaitingKey = action
            log("Bam phim moi cho " .. action)
        end)
        local keyLbl = Instance.new("TextLabel", row)
        keyLbl.Size = UDim2.new(0, 80, 0, 24)
        keyLbl.Position = UDim2.new(1, -180, 0, 5)
        keyLbl.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
        keyLbl.Text = key.Name
        keyLbl.TextColor3 = Color3.fromRGB(200, 220, 255)
        keyLbl.Font = Enum.Font.GothamBold
        keyLbl.TextSize = 12
        keyLbl.BorderSizePixel = 0
        Instance.new("UICorner", keyLbl).CornerRadius = UDim.new(0, 5)
        keyRows[action] = keyLbl
    end

    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if STATE.WaitingKey then
            KEYS[STATE.WaitingKey] = input.KeyCode
            if keyRows[STATE.WaitingKey] then
                keyRows[STATE.WaitingKey].Text = input.KeyCode.Name
            end
            log("Dat " .. STATE.WaitingKey .. " = " .. input.KeyCode.Name)
            STATE.WaitingKey = nil
            return
        end

        if input.KeyCode == KEYS.ToggleGUI then
            gui.Enabled = not gui.Enabled
        elseif input.KeyCode == KEYS.TeleBase then
            if CONFIG.BasePos.Magnitude < 1 then log("Chua luu Base!"); return end
            local r = getRoot(); if r then r.CFrame = CFrame.new(CONFIG.BasePos) end
        elseif input.KeyCode == KEYS.TeleSell then
            if CONFIG.SellPos.Magnitude < 1 then log("Chua luu Sell!"); return end
            local r = getRoot(); if r then r.CFrame = CFrame.new(CONFIG.SellPos) end
        elseif input.KeyCode == KEYS.TeleTree then
            local r = getRoot()
            if r then
                forEachInFolders(function(o)
                    if isTree(o) and o.Name:lower():find(CONFIG.TargetWood:lower()) then
                        local p = o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")
                        if p then r.CFrame = p.CFrame * CFrame.new(0, 5, 0) end
                    end
                end)
            end
        elseif input.KeyCode == KEYS.ToggleFarm then
            CONFIG.AutoFarm = not CONFIG.AutoFarm
            log("AutoFarm = " .. tostring(CONFIG.AutoFarm))
        end
    end)

    switchTab("Farm")
    return gui
end

-- ================= FEATURES =================
local function findNearestTree()
    local root = getRoot()
    if not root then return nil end
    local near, nd = nil, CONFIG.ChopRange
    forEachInFolders(function(o)
        if isTree(o) then
            local p = o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")
            if p then
                local d = dist(p.Position, root.Position)
                if d < nd then near, nd = p, d end
            end
        end
    end)
    return near
end

local function autoChop()
    if not CONFIG.AutoChop then return false end
    autoEquipAxe()
    local root = getRoot(); if not root then return false end
    local tree = findNearestTree()
    if not tree then return false end
    root.CFrame = tree.CFrame * CFrame.new(0, 0, 3)
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
    return true
end

local function autoPickup()
    if not CONFIG.AutoPickup then return end
    local root = getRoot(); if not root then return end
    forEachInFolders(function(o)
        if isWood(o) and dist(o.Position, root.Position) < CONFIG.PickupRange then
            o.CFrame = root.CFrame
        end
    end)
end

local function autoSell()
    if not CONFIG.AutoSell then return end
    local root = getRoot(); if not root then return end
    local near, nd = nil, CONFIG.SellRange
    forEachInFolders(function(o)
        if isSell(o) then
            local d = dist(o.Position, root.Position)
            if d < nd then near, nd = o, d end
        end
    end)
    if near then
        root.CFrame = near.CFrame
        local c = LocalPlayer.Character
        if c then
            for _, t in pairs(c:GetChildren()) do
                if t:IsA("Tool") and not isAxe(t) then
                    pcall(function() t:Activate() end)
                end
            end
        end
    elseif CONFIG.SellPos.Magnitude > 0 then
        root.CFrame = CFrame.new(CONFIG.SellPos)
    end
end

local farmNoTreeCount = 0
local function autoFarm()
    if not CONFIG.AutoFarm then return end
    if STATE.FarmPhase == "CHOP" then
        local ok = autoChop()
        if not ok then
            farmNoTreeCount = farmNoTreeCount + 1
            if farmNoTreeCount > 3 then
                STATE.FarmPhase = "SELL"
                farmNoTreeCount = 0
            end
        else
            farmNoTreeCount = 0
        end
    elseif STATE.FarmPhase == "SELL" then
        autoSell()
        task.wait(CONFIG.FarmDelay)
        STATE.FarmPhase = "CHOP"
    end
    autoPickup()
end

local lastESPScan = 0
local function updateESP()
    if not CONFIG.ESP then
        for o, h in pairs(STATE.ESPCache) do
            pcall(function() if h and h.Parent then h:Destroy() end end)
        end
        STATE.ESPCache = {}
        return
    end
    if tick() - lastESPScan < 5 then return end
    lastESPScan = tick()
    forEachInFolders(function(o)
        if isTree(o) and not STATE.ESPCache[o] then
            local p = o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")
            if p then
                local h = Instance.new("Highlight", p)
                h.FillColor = Color3.fromRGB(0, 255, 120)
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                STATE.ESPCache[o] = h
            end
        end
    end)
end

local function updateFullbright()
    if CONFIG.Fullbright then
        Lighting.Brightness = 3
        Lighting.ClockTime = 12
        Lighting.FogEnd = 1e6
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    else
        Lighting.Brightness = 2
        Lighting.GlobalShadows = true
        Lighting.FogEnd = 1000
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
    end
end

local lastLagRun = 0
local function lagFix()
    if not CONFIG.LagFix then return end
    if tick() - lastLagRun < 5 then return end
    lastLagRun = tick()
    local root = getRoot()
    local char = LocalPlayer.Character
    forEachInFolders(function(o)
        if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Smoke") or o:IsA("Fire") then
            o.Enabled = false
        elseif o:IsA("BasePart") and root then
            if char and o:IsDescendantOf(char) then
                o.LocalTransparencyModifier = 0
            else
                local d = dist(o.Position, root.Position)
                o.LocalTransparencyModifier = d > CONFIG.RenderDist and 1 or 0
            end
        end
    end)
end

UIS.JumpRequest:Connect(function()
    if CONFIG.InfiniteJump then
        local h = getHum()
        if h then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
            task.wait(0.05)
            h:ChangeState(Enum.HumanoidStateType.Freefall)
        end
    end
end)

LocalPlayer.Idled:Connect(function()
    if CONFIG.AntiAFK then
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end
end)

-- ================= MAIN LOOP (THROTTLED) =================
buildGUI()

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    pcall(buildGUI)
end)

local lastChop = 0
local lastPickup = 0
local lastFarm = 0

RunService.Heartbeat:Connect(function()
    if not STATE.Running then return end
    local h = getHum()
    if h then h.WalkSpeed = CONFIG.WalkSpeed end

    local now = tick()

    if now - lastChop > 0.5 then
        lastChop = now
        pcall(autoEquipAxe)
        pcall(autoChop)
    end

    if now - lastPickup > 0.5 then
        lastPickup = now
        pcall(autoPickup)
    end

    if now - lastFarm > 1 then
        lastFarm = now
        pcall(autoFarm)
    end
end)

task.spawn(function()
    while task.wait(2) do
        pcall(updateESP)
        pcall(updateFullbright)
        pcall(lagFix)
    end
end)

log("TRKIEN LT2 HUB v3.3 loaded - lag fixed")
