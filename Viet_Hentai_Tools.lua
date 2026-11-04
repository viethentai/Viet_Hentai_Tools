--[[
    VIỆT HENTAI TOOLS - Fly + NoClip + Server Finder + ESP
    LocalScript for Roblox Studio / executor.

    Phím tắt:
      F              - Bật/tắt bay
      N              - Bật/tắt NoClip
      G              - Bật/tắt ESP
      RightShift     - Ẩn/hiện cửa sổ
      WASD           - Di chuyển
      Q / E          - Lên / xuống (hoặc phím mũi tên Up / Down)
      + / -          - Đổi mốc tốc độ (giữ để lặp lại)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- HTTP request function của executor (nếu có)
local requestFunc = (syn and syn.request)
    or (http and http.request)
    or http_request
    or (fluxus and fluxus.request)
    or request

---------------------------------------------------------------------
-- Constants & state
---------------------------------------------------------------------
local MIN_LEVEL = 1
local MAX_LEVEL = 30
local speedLevel = 1
local BASE_SPEED = 16
local VERTICAL_SPEED = 16

-- Mỗi mốc gấp 1.5 lần mốc trước: mốc n = 1.5^(n-1) lần tốc độ gốc
local function getSpeedMultiplier(level)
    return 1.5 ^ (level - 1)
end

local function getSpeedValue(level)
    return BASE_SPEED * getSpeedMultiplier(level)
end

local function formatSpeed(level)
    return string.format("Mốc %d  (%.4g studs/s)", level, getSpeedValue(level))
end

local CHANGE_INTERVAL = 0.12
local MAX_SERVER_PAGES = 20
local PAGE_DELAY = 0.25

local WINDOW_SIZE = UDim2.fromOffset(520, 400)
local BUBBLE_SIZE = UDim2.fromOffset(56, 36)
local TWEEN_OPEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_CLOSE = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local COLOR_BG = Color3.fromRGB(28, 32, 42)
local COLOR_STROKE = Color3.fromRGB(80, 190, 170)
local COLOR_TEXT = Color3.fromRGB(240, 245, 250)
local COLOR_HINT = Color3.fromRGB(150, 160, 175)
local COLOR_DARK_TEXT = Color3.fromRGB(15, 20, 25)
local COLOR_FLY_ON = Color3.fromRGB(100, 235, 150)
local COLOR_FLY_OFF = Color3.fromRGB(255, 205, 85)
local COLOR_NOCLIP_ON = Color3.fromRGB(90, 200, 255)
local COLOR_NOCLIP_OFF = Color3.fromRGB(150, 155, 165)
local COLOR_CLOSE = Color3.fromRGB(245, 100, 100)
local COLOR_MIN = Color3.fromRGB(255, 205, 85)
local COLOR_MINUS = Color3.fromRGB(120, 190, 245)
local COLOR_PLUS = Color3.fromRGB(120, 235, 170)
local COLOR_TAB_ON = Color3.fromRGB(110, 150, 255)
local COLOR_TAB_OFF = Color3.fromRGB(70, 76, 92)
local COLOR_JOIN = Color3.fromRGB(85, 85, 255)
local COLOR_CURRENT = Color3.fromRGB(90, 96, 110)
local COLOR_ROW = Color3.fromRGB(50, 56, 70)
local COLOR_LIST = Color3.fromRGB(40, 45, 56)

local flying = false
local noclip = false

local character, humanoid, root
local attachment, velocity, orientation
local oldAutoRotate
local oldPlatformStand
local renderConnection

local noclipConnection
local noclipChanged = {} -- [BasePart] = true, parts whose CanCollide we turned off

local currentTab = "FLY"
local serverLoaded = false
local serverLoading = false
local gameName = "Unknown"

---------------------------------------------------------------------
-- Cleanup old copies & notify
---------------------------------------------------------------------
for _, name in ipairs({ "FlyV4_HTZ", "LowServerFinder", "HTZ_Hub", "VietHentaiTools" }) do
    local old = playerGui:FindFirstChild(name)
    if old then
        old:Destroy()
    end
end

task.spawn(function()
    local message = {
        Title = "Việt Hentai Tools",
        Text = "Đã sẵn sàng!",
        Duration = 5
    }
    for _ = 1, 8 do
        local success = pcall(function()
            StarterGui:SetCore("SendNotification", message)
        end)
        if success then
            break
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        gameName = info.Name or gameName
    end)
end)

---------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------
local function makeCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function makeButton(parent, name, text, position, size, color, textSize)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = position
    button.Size = size
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = COLOR_DARK_TEXT
    button.TextSize = textSize or 13
    button.AutoButtonColor = true
    button.Parent = parent
    makeCorner(button, 7)
    return button
end

local function makeLabel(parent, name, text, position, size, textSize)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = position
    label.Size = size
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = text
    label.TextColor3 = COLOR_TEXT
    label.TextSize = textSize or 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = parent
    return label
end

-- Nút thu gọn: kéo thả được, và chỉ mở cửa sổ khi là một cú nhấp thật sự
-- (không mở khi thả chuột sau khi kéo).
local DRAG_THRESHOLD = 5

local function setupBubble(bubbleBtn, onClick)
    local dragging = false
    local moved = false
    local mouseStart
    local posStartX, posStartY

    bubbleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            mouseStart = input.Position
            posStartX = bubbleBtn.Position.X.Offset
            posStartY = bubbleBtn.Position.Y.Offset
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - mouseStart
        if not moved and delta.Magnitude > DRAG_THRESHOLD then
            moved = true
        end
        if moved then
            bubbleBtn.Position = UDim2.fromOffset(posStartX + delta.X, posStartY + delta.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if not moved then
                onClick()
            end
        end
    end)
end

---------------------------------------------------------------------
-- Main GUI
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "VietHentaiTools"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = WINDOW_SIZE
main.Position = UDim2.new(0.08, 0, 0.12, 0)
main.BackgroundColor3 = COLOR_BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.ClipsDescendants = true
main.Parent = gui
makeCorner(main, 10)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLOR_STROKE
mainStroke.Thickness = 1.5
mainStroke.Parent = main

-- Header
local title = makeLabel(main, "Title", "Việt Hentai Tools", UDim2.fromOffset(12, 8), UDim2.fromOffset(420, 26), 18)

local minimizeBtn = makeButton(main, "Minimize", "-", UDim2.fromOffset(448, 8), UDim2.fromOffset(30, 26), COLOR_MIN, 16)
local closeBtn = makeButton(main, "Close", "X", UDim2.fromOffset(482, 8), UDim2.fromOffset(30, 26), COLOR_CLOSE)

-- Tabs
local flyTab = makeButton(main, "TabFly", "FLY", UDim2.fromOffset(12, 44), UDim2.fromOffset(120, 30), COLOR_TAB_OFF)
local serverTab = makeButton(main, "TabServer", "SERVER", UDim2.fromOffset(138, 44), UDim2.fromOffset(120, 30), COLOR_TAB_OFF)
local espTab = makeButton(main, "TabESP", "ESP", UDim2.fromOffset(264, 44), UDim2.fromOffset(120, 30), COLOR_TAB_OFF)
flyTab.TextColor3 = COLOR_TEXT
serverTab.TextColor3 = COLOR_TEXT
espTab.TextColor3 = COLOR_TEXT

---------------------------------------------------------------------
-- FLY page
---------------------------------------------------------------------
local flyPage = Instance.new("Frame")
flyPage.Name = "FlyPage"
flyPage.Position = UDim2.fromOffset(0, 84)
flyPage.Size = UDim2.fromOffset(520, 306)
flyPage.BackgroundTransparency = 1
flyPage.Parent = main

local toggle = makeButton(flyPage, "ToggleFly", "FLY: OFF",
    UDim2.fromOffset(12, 10), UDim2.fromOffset(244, 40), COLOR_FLY_OFF, 14)

local noclipButton = makeButton(flyPage, "ToggleNoClip", "NOCLIP: OFF",
    UDim2.fromOffset(264, 10), UDim2.fromOffset(244, 40), COLOR_NOCLIP_OFF, 14)

local minus = makeButton(flyPage, "Minus", "-",
    UDim2.fromOffset(12, 62), UDim2.fromOffset(44, 38), COLOR_MINUS, 18)

local countBox = Instance.new("TextBox")
countBox.Name = "SpeedBox"
countBox.Position = UDim2.fromOffset(64, 62)
countBox.Size = UDim2.fromOffset(392, 38)
countBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
countBox.BorderSizePixel = 0
countBox.Font = Enum.Font.GothamBold
countBox.Text = formatSpeed(speedLevel)
countBox.TextColor3 = Color3.fromRGB(25, 30, 35)
countBox.TextSize = 16
countBox.ClearTextOnFocus = false
countBox.PlaceholderText = "Mốc (1-30)"
countBox.Parent = flyPage
makeCorner(countBox, 7)

local plus = makeButton(flyPage, "Plus", "+",
    UDim2.fromOffset(464, 62), UDim2.fromOffset(44, 38), COLOR_PLUS, 18)

local hint = makeLabel(flyPage, "Hint", "F: Bay   N: NoClip   WASD/Q/E: di chuyển   RightShift: ẩn/hiện",
    UDim2.fromOffset(12, 116), UDim2.fromOffset(496, 22), 11)
hint.Font = Enum.Font.Gotham
hint.TextColor3 = COLOR_HINT
hint.TextXAlignment = Enum.TextXAlignment.Center

---------------------------------------------------------------------
-- SERVER page
---------------------------------------------------------------------
local serverPage = Instance.new("Frame")
serverPage.Name = "ServerPage"
serverPage.Position = UDim2.fromOffset(0, 84)
serverPage.Size = UDim2.fromOffset(520, 306)
serverPage.BackgroundTransparency = 1
serverPage.Visible = false
serverPage.Parent = main

local serverStatus = makeLabel(serverPage, "Status", "Chưa tải",
    UDim2.fromOffset(12, 6), UDim2.fromOffset(360, 26), 13)
serverStatus.Font = Enum.Font.Gotham

local refreshBtn = makeButton(serverPage, "Refresh", "LÀM MỚI",
    UDim2.fromOffset(380, 6), UDim2.fromOffset(128, 26), COLOR_PLUS, 12)

local serverList = Instance.new("ScrollingFrame")
serverList.Name = "ServerList"
serverList.Position = UDim2.fromOffset(12, 40)
serverList.Size = UDim2.fromOffset(496, 260)
serverList.BackgroundColor3 = COLOR_LIST
serverList.BorderSizePixel = 0
serverList.CanvasSize = UDim2.new(0, 0, 0, 0)
serverList.AutomaticCanvasSize = Enum.AutomaticSize.Y
serverList.ScrollBarThickness = 5
serverList.Parent = serverPage
makeCorner(serverList, 8)

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = serverList

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.Parent = serverList

---------------------------------------------------------------------
-- Bubble (hiện khi thu gọn)
---------------------------------------------------------------------
local bubble = makeButton(gui, "Bubble", "VH",
    UDim2.fromOffset(10, 200), BUBBLE_SIZE, COLOR_STROKE, 13)
bubble.Visible = false

---------------------------------------------------------------------
-- Window open / close animation
---------------------------------------------------------------------
local windowOpen = true
local windowBusy = false
local openPosition = main.Position

-- Vị trí thu nhỏ về đúng tâm của cửa sổ
local function closedPositionFor(pos)
    return UDim2.new(
        pos.X.Scale, pos.X.Offset + WINDOW_SIZE.X.Offset / 2,
        pos.Y.Scale, pos.Y.Offset + WINDOW_SIZE.Y.Offset / 2
    )
end

local function showBubble()
    bubble.Visible = true
    bubble.Size = UDim2.fromOffset(0, 0)
    TweenService:Create(bubble, TWEEN_OPEN, { Size = BUBBLE_SIZE }):Play()
end

local function hideBubble(onDone)
    local tween = TweenService:Create(bubble, TWEEN_CLOSE, { Size = UDim2.fromOffset(0, 0) })
    tween.Completed:Once(function()
        bubble.Visible = false
        if onDone then
            onDone()
        end
    end)
    tween:Play()
end

local function closeWindow(onDone)
    if not windowOpen or windowBusy then
        return
    end
    windowBusy = true
    windowOpen = false
    openPosition = main.Position

    local tween = TweenService:Create(main, TWEEN_CLOSE, {
        Size = UDim2.fromOffset(0, 0),
        Position = closedPositionFor(openPosition),
    })
    tween.Completed:Once(function()
        main.Visible = false
        main.Size = WINDOW_SIZE
        main.Position = openPosition
        windowBusy = false
        if onDone then
            onDone()
        end
    end)
    tween:Play()
end

local function openWindow()
    if windowOpen or windowBusy then
        return
    end
    windowBusy = true
    windowOpen = true

    hideBubble(function()
        main.Visible = true
        main.Size = UDim2.fromOffset(0, 0)
        main.Position = closedPositionFor(openPosition)

        local tween = TweenService:Create(main, TWEEN_OPEN, {
            Size = WINDOW_SIZE,
            Position = openPosition,
        })
        tween.Completed:Once(function()
            windowBusy = false
        end)
        tween:Play()
    end)
end

local function minimizeWindow()
    closeWindow(function()
        showBubble()
    end)
end

local function toggleWindow()
    if windowOpen then
        minimizeWindow()
    else
        openWindow()
    end
end

setupBubble(bubble, openWindow)

---------------------------------------------------------------------
-- ESP (Drawing API)
---------------------------------------------------------------------
local ESP = {
    Enabled = false,
    Boxes = true,
    Names = true,
    Distance = true,
    Health = true,
    Tracers = false,
    TeamCheck = false,
    MaxDistance = 1500,
    EnemyColor = Color3.fromRGB(255, 60, 60),
    TeamColor = Color3.fromRGB(60, 255, 120),
}

ESP.Available = pcall(function()
    Drawing.new("Line"):Remove()
end)

local espObjects = {}
local espConnection

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do
        d[k] = v
    end
    return d
end

local function createESP(targetPlayer)
    local existing = espObjects[targetPlayer]
    if existing then
        return existing
    end

    local obj = {
        Outline = newDrawing("Square", { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0), Transparency = 0.6, Visible = false }),
        Box = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false }),
        Name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.new(1, 1, 1), Visible = false }),
        Tracer = newDrawing("Line", { Thickness = 1, Visible = false }),
        HpBack = newDrawing("Line", { Thickness = 3, Color = Color3.new(0, 0, 0), Visible = false }),
        HpFill = newDrawing("Line", { Thickness = 2, Visible = false }),
    }

    espObjects[targetPlayer] = obj
    return obj
end

local function hideObj(obj)
    for _, d in pairs(obj) do
        d.Visible = false
    end
end

local function removeESP(targetPlayer)
    local obj = espObjects[targetPlayer]
    if not obj then
        return
    end
    for _, d in pairs(obj) do
        d:Remove()
    end
    espObjects[targetPlayer] = nil
end

local function isTeammate(targetPlayer)
    return player.Team ~= nil and targetPlayer.Team == player.Team
end

local function toScreen(camera, worldPos)
    local v = camera:WorldToViewportPoint(worldPos)
    return Vector2.new(v.X, v.Y), v.Z > 0
end

local function updateESPPlayer(targetPlayer, obj, camera, localRoot)
    local char = targetPlayer.Character
    local targetRoot = char and char:FindFirstChild("HumanoidRootPart")
    local head = char and char:FindFirstChild("Head")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if not (ESP.Enabled and targetRoot and head and hum and hum.Health > 0) then
        hideObj(obj)
        return
    end

    local distance = localRoot and (targetRoot.Position - localRoot.Position).Magnitude or 0
    if distance > ESP.MaxDistance then
        hideObj(obj)
        return
    end

    local headTop, headInFront = toScreen(camera, head.Position + Vector3.new(0, head.Size.Y / 2 + 0.3, 0))
    local footBottom, footInFront = toScreen(camera, targetRoot.Position - Vector3.new(0, 3, 0))
    if not (headInFront and footInFront) then
        hideObj(obj)
        return
    end

    local color = (ESP.TeamCheck and isTeammate(targetPlayer)) and ESP.TeamColor or ESP.EnemyColor

    local height = math.abs(footBottom.Y - headTop.Y)
    local width = height / 2
    local centerX = (headTop.X + footBottom.X) / 2
    local boxPos = Vector2.new(centerX - width / 2, headTop.Y)
    local boxSize = Vector2.new(width, height)

    -- Hộp
    obj.Outline.Visible = ESP.Boxes
    obj.Box.Visible = ESP.Boxes
    if ESP.Boxes then
        obj.Outline.Position = boxPos
        obj.Outline.Size = boxSize
        obj.Box.Position = boxPos
        obj.Box.Size = boxSize
        obj.Box.Color = color
    end

    -- Tên + khoảng cách
    local labelParts = {}
    if ESP.Names then
        table.insert(labelParts, targetPlayer.DisplayName)
    end
    if ESP.Distance then
        table.insert(labelParts, string.format("[%dm]", distance))
    end

    obj.Name.Visible = #labelParts > 0
    if obj.Name.Visible then
        obj.Name.Text = table.concat(labelParts, " ")
        obj.Name.Color = color
        obj.Name.Position = Vector2.new(centerX, boxPos.Y - 16)
    end

    -- Thanh máu (bên trái hộp, đỏ -> xanh)
    obj.HpBack.Visible = ESP.Health
    obj.HpFill.Visible = ESP.Health
    if ESP.Health then
        local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        local x = boxPos.X - 5
        obj.HpBack.From = Vector2.new(x, boxPos.Y)
        obj.HpBack.To = Vector2.new(x, boxPos.Y + height)
        obj.HpFill.From = Vector2.new(x, boxPos.Y + height)
        obj.HpFill.To = Vector2.new(x, boxPos.Y + height * (1 - ratio))
        obj.HpFill.Color = Color3.fromHSV(ratio * 0.33, 1, 1)
    end

    -- Tracer (từ đáy màn hình tới chân người chơi)
    obj.Tracer.Visible = ESP.Tracers
    if ESP.Tracers then
        local vp = camera.ViewportSize
        obj.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
        obj.Tracer.To = Vector2.new(centerX, footBottom.Y)
        obj.Tracer.Color = color
    end
end

local function refreshESP()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local localChar = player.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            updateESPPlayer(targetPlayer, createESP(targetPlayer), camera, localRoot)
        end
    end
end

local function setESPEnabled(state)
    ESP.Enabled = state and ESP.Available

    if ESP.Enabled then
        if not espConnection then
            espConnection = RunService.RenderStepped:Connect(refreshESP)
        end
    else
        if espConnection then
            espConnection:Disconnect()
            espConnection = nil
        end
        for _, obj in pairs(espObjects) do
            hideObj(obj)
        end
    end
end

function ESP.Destroy()
    setESPEnabled(false)
    for targetPlayer in pairs(espObjects) do
        removeESP(targetPlayer)
    end
end

Players.PlayerRemoving:Connect(removeESP)

---------------------------------------------------------------------
-- ESP tab UI
---------------------------------------------------------------------
local espPage = Instance.new("Frame")
espPage.Name = "ESPPage"
espPage.Position = UDim2.fromOffset(0, 84)
espPage.Size = UDim2.fromOffset(520, 306)
espPage.BackgroundTransparency = 1
espPage.Visible = false
espPage.Parent = main

local espToggles = {
    { key = "Enabled", text = "ESP" },
    { key = "Boxes", text = "BOX" },
    { key = "Names", text = "TÊN" },
    { key = "Distance", text = "KHOẢNG CÁCH" },
    { key = "Health", text = "MÁU" },
    { key = "Tracers", text = "TRACER" },
    { key = "TeamCheck", text = "TEAM CHECK" },
}
local espButtons = {}

local function refreshESPButtons()
    for _, item in ipairs(espToggles) do
        local on = ESP[item.key]
        local btn = espButtons[item.key]
        btn.Text = item.text .. (on and ": ON" or ": OFF")
        btn.BackgroundColor3 = on and COLOR_FLY_ON or COLOR_NOCLIP_OFF
    end
end

for i, item in ipairs(espToggles) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local btn = makeButton(espPage, "ESP_" .. item.key, item.text,
        UDim2.fromOffset(12 + col * 252, 10 + row * 46),
        UDim2.fromOffset(244, 40), COLOR_NOCLIP_OFF, 14)
    espButtons[item.key] = btn

    btn.Activated:Connect(function()
        if item.key == "Enabled" then
            setESPEnabled(not ESP.Enabled)
        else
            ESP[item.key] = not ESP[item.key]
        end
        refreshESPButtons()
    end)
end

local espHint = makeLabel(espPage, "Hint", "G: bật/tắt ESP",
    UDim2.fromOffset(12, 200), UDim2.fromOffset(496, 22), 11)
espHint.Font = Enum.Font.Gotham
espHint.TextColor3 = COLOR_HINT
espHint.TextXAlignment = Enum.TextXAlignment.Center

if not ESP.Available then
    espHint.Text = "Executor không hỗ trợ Drawing API, ESP không khả dụng"
end

refreshESPButtons()

---------------------------------------------------------------------
-- Visual state helpers (FLY / NOCLIP)
---------------------------------------------------------------------
local function refreshToggles()
    if flying then
        toggle.Text = "FLY: ON"
        toggle.BackgroundColor3 = COLOR_FLY_ON
    else
        toggle.Text = "FLY: OFF"
        toggle.BackgroundColor3 = COLOR_FLY_OFF
    end

    if noclip then
        noclipButton.Text = "NOCLIP: ON"
        noclipButton.BackgroundColor3 = COLOR_NOCLIP_ON
    else
        noclipButton.Text = "NOCLIP: OFF"
        noclipButton.BackgroundColor3 = COLOR_NOCLIP_OFF
    end
end

refreshToggles()

---------------------------------------------------------------------
-- Speed controls (mốc 1-30, hold-to-repeat, mouse & touch)
---------------------------------------------------------------------
local function updateCountBox()
    countBox.Text = formatSpeed(speedLevel)
end

local function setSpeed(value)
    value = math.floor(tonumber(value) or MIN_LEVEL)
    speedLevel = math.clamp(value, MIN_LEVEL, MAX_LEVEL)
    updateCountBox()
end

local function changeSpeed(amount)
    setSpeed(speedLevel + amount)
end

-- Khi bấm vào ô: hiện số mốc để gõ trực tiếp
countBox.Focused:Connect(function()
    countBox.Text = tostring(speedLevel)
end)

countBox.FocusLost:Connect(function()
    setSpeed(countBox.Text)
end)

local holdTokens = {}

local function bindHold(button, amount)
    button.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local token = {}
        holdTokens[button] = token
        changeSpeed(amount)

        task.spawn(function()
            task.wait(0.35)
            while holdTokens[button] == token do
                changeSpeed(amount)
                task.wait(CHANGE_INTERVAL)
            end
        end)
    end)

    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            holdTokens[button] = nil
        end
    end)
end

bindHold(plus, 1)
bindHold(minus, -1)

---------------------------------------------------------------------
-- Character helpers
---------------------------------------------------------------------
local function getCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- NoClip
---------------------------------------------------------------------
local function restoreCollisions()
    for part, wasCollidable in pairs(noclipChanged) do
        if part and part.Parent then
            part.CanCollide = wasCollidable
        end
    end
    table.clear(noclipChanged)
end

local function startNoclip()
    if noclipConnection then
        return
    end

    noclipConnection = RunService.Stepped:Connect(function()
        local char = player.Character
        if not char then
            return
        end

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                noclipChanged[part] = true
                part.CanCollide = false
            end
        end
    end)
end

local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    restoreCollisions()
end

local function setNoclip(state)
    noclip = state
    if noclip then
        startNoclip()
    else
        stopNoclip()
    end
    refreshToggles()
end

local function toggleNoclip()
    setNoclip(not noclip)
end

---------------------------------------------------------------------
-- Flight
---------------------------------------------------------------------
local function stopFlight()
    flying = false
    refreshToggles()

    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end

    if velocity then velocity:Destroy(); velocity = nil end
    if orientation then orientation:Destroy(); orientation = nil end
    if attachment then attachment:Destroy(); attachment = nil end

    if humanoid and humanoid.Parent then
        humanoid.AutoRotate = oldAutoRotate == nil and true or oldAutoRotate
        humanoid.PlatformStand = oldPlatformStand == nil and false or oldPlatformStand
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

local function getKeyboardMove(camera)
    local forward = 0
    local sideways = 0

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then sideways += 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then sideways -= 1 end

    local look = camera.CFrame.LookVector
    local right = camera.CFrame.RightVector
    local direction = look * forward
    local flatRight = Vector3.new(right.X, 0, right.Z)

    if flatRight.Magnitude > 0 then
        direction += flatRight.Unit * sideways
    end
    if direction.Magnitude > 1 then
        direction = direction.Unit
    end

    return direction
end

local function startFlight()
    getCharacter()
    if not humanoid or not root or humanoid.Health <= 0 then
        return
    end

    flying = true
    refreshToggles()

    oldAutoRotate = humanoid.AutoRotate
    oldPlatformStand = humanoid.PlatformStand

    humanoid.AutoRotate = false
    humanoid.PlatformStand = false

    attachment = Instance.new("Attachment")
    attachment.Name = "FlyV4Attachment"
    attachment.Parent = root

    velocity = Instance.new("LinearVelocity")
    velocity.Name = "FlyV4Velocity"
    velocity.Attachment0 = attachment
    velocity.RelativeTo = Enum.ActuatorRelativeTo.World
    velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    velocity.MaxForce = math.huge
    velocity.VectorVelocity = Vector3.zero
    velocity.Parent = root

    orientation = Instance.new("AlignOrientation")
    orientation.Name = "FlyV4Orientation"
    orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
    orientation.Attachment0 = attachment
    orientation.MaxTorque = math.huge
    orientation.Responsiveness = 20
    orientation.Parent = root

    humanoid:ChangeState(Enum.HumanoidStateType.Physics)

    renderConnection = RunService.RenderStepped:Connect(function()
        if not flying or not character or not character.Parent
            or not humanoid or humanoid.Health <= 0
            or not root or not root.Parent then
            stopFlight()
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then return end

        local moveDirection = getKeyboardMove(camera)
        local vertical = 0

        if UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
            vertical += 1
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.E)
            or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
            vertical -= 1
        end

        local multiplier = getSpeedMultiplier(speedLevel)
        local moveVelocity = moveDirection * (BASE_SPEED * multiplier)
            + Vector3.new(0, vertical * VERTICAL_SPEED * multiplier, 0)

        velocity.VectorVelocity = moveVelocity

        local look = camera.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude > 0.001 then
            orientation.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
        end
    end)
end

local function toggleFlight()
    if flying then
        stopFlight()
    else
        startFlight()
    end
end

---------------------------------------------------------------------
-- Server finder
---------------------------------------------------------------------
local function setStatus(text)
    serverStatus.Text = text
end

local function clearServerList()
    for _, child in ipairs(serverList:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function createServerEntry(server, order)
    local row = Instance.new("Frame")
    row.Name = "ServerRow"
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = COLOR_ROW
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = serverList
    makeCorner(row, 8)

    local info = Instance.new("TextLabel")
    info.Name = "ServerInfo"
    info.Position = UDim2.fromOffset(10, 0)
    info.Size = UDim2.new(1, -120, 1, 0)
    info.BackgroundTransparency = 1
    info.Font = Enum.Font.Gotham
    info.TextSize = 13
    info.TextColor3 = COLOR_TEXT
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Center
    info.TextTruncate = Enum.TextTruncate.AtEnd
    info.Text = string.format("👥 %d / %d\nID: %s", server.playing, server.maxPlayers, tostring(server.id))
    info.Parent = row

    local isCurrent = server.id == game.JobId

    local joinBtn = Instance.new("TextButton")
    joinBtn.Name = "Join"
    joinBtn.Position = UDim2.new(1, -100, 0.5, -17)
    joinBtn.Size = UDim2.fromOffset(88, 34)
    joinBtn.BackgroundColor3 = isCurrent and COLOR_CURRENT or COLOR_JOIN
    joinBtn.BorderSizePixel = 0
    joinBtn.Font = Enum.Font.GothamBold
    joinBtn.TextSize = 13
    joinBtn.TextColor3 = COLOR_TEXT
    joinBtn.Text = isCurrent and "HIỆN TẠI" or "JOIN 🚀"
    joinBtn.AutoButtonColor = not isCurrent
    joinBtn.Parent = row
    makeCorner(joinBtn, 7)

    if not isCurrent then
        joinBtn.Activated:Connect(function()
            setStatus("Đang teleport...")
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, player)
            end)
            if not ok then
                setStatus("Teleport lỗi: " .. tostring(err))
            end
        end)
    end
end

-- Lấy một trang server. Tự thử lại khi bị giới hạn tốc độ (HTTP 429).
local function fetchPage(cursor)
    if not requestFunc then
        return nil, "Executor không hỗ trợ HTTP request"
    end

    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
        game.PlaceId
    )
    if cursor then
        url = url .. "&cursor=" .. cursor
    end

    local lastError = "không rõ lỗi"

    for attempt = 1, 3 do
        local ok, response = pcall(requestFunc, { Url = url, Method = "GET" })
        if not ok or not response then
            return nil, "request thất bại"
        end

        if response.StatusCode == 429 then
            lastError = "bị giới hạn tốc độ, thử lại sau"
            task.wait(2 * attempt)
        else
            if not response.Body then
                return nil, "không có dữ liệu"
            end

            local decoded, data = pcall(function()
                return HttpService:JSONDecode(response.Body)
            end)
            if not decoded or type(data) ~= "table" then
                return nil, "không đọc được dữ liệu"
            end

            return data
        end
    end

    return nil, lastError
end

local function loadServers()
    if serverLoading then
        return
    end
    serverLoading = true
    serverLoaded = true

    setStatus("Đang tải danh sách server...")
    refreshBtn.Text = "ĐANG TẢI"

    task.spawn(function()
        local servers = {}
        local cursor = nil
        local pages = 0
        local errorMsg = nil

        repeat
            local data, err = fetchPage(cursor)
            if not data then
                errorMsg = err
                break
            end

            for _, server in ipairs(data.data or {}) do
                table.insert(servers, server)
            end

            cursor = data.nextPageCursor
            pages += 1
            if cursor and pages < MAX_SERVER_PAGES then
                task.wait(PAGE_DELAY)
            end
        until not cursor or pages >= MAX_SERVER_PAGES

        if errorMsg and #servers == 0 then
            -- Lỗi và không lấy được gì: giữ nguyên danh sách cũ
            setStatus("Lỗi: " .. errorMsg .. " (giữ danh sách cũ)")
        else
            table.sort(servers, function(a, b)
                return a.playing < b.playing
            end)

            -- Chỉ xóa danh sách cũ khi đã có dữ liệu mới
            clearServerList()

            local count = 0
            for _, server in ipairs(servers) do
                if server.playing < server.maxPlayers then
                    count += 1
                    createServerEntry(server, count)
                end
            end

            if count == 0 then
                setStatus("Không có server nào còn chỗ.")
            elseif errorMsg then
                setStatus(string.format("%d server (tải chưa đủ: %s)", count, errorMsg))
            else
                setStatus(string.format("Tìm thấy %d server còn chỗ, ít người trước", count))
            end
        end

        refreshBtn.Text = "LÀM MỚI"
        serverLoading = false
    end)
end

---------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------
local function showTab(tabName)
    currentTab = tabName
    flyPage.Visible = tabName == "FLY"
    serverPage.Visible = tabName == "SERVER"
    espPage.Visible = tabName == "ESP"

    flyTab.BackgroundColor3 = tabName == "FLY" and COLOR_TAB_ON or COLOR_TAB_OFF
    serverTab.BackgroundColor3 = tabName == "SERVER" and COLOR_TAB_ON or COLOR_TAB_OFF
    espTab.BackgroundColor3 = tabName == "ESP" and COLOR_TAB_ON or COLOR_TAB_OFF

    if tabName == "SERVER" and not serverLoaded then
        loadServers()
    end
end

showTab("FLY")

---------------------------------------------------------------------
-- Connections
---------------------------------------------------------------------
toggle.Activated:Connect(toggleFlight)
noclipButton.Activated:Connect(toggleNoclip)
flyTab.Activated:Connect(function() showTab("FLY") end)
serverTab.Activated:Connect(function() showTab("SERVER") end)
espTab.Activated:Connect(function() showTab("ESP") end)
refreshBtn.Activated:Connect(loadServers)
minimizeBtn.Activated:Connect(minimizeWindow)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == Enum.KeyCode.F then
        toggleFlight()
    elseif input.KeyCode == Enum.KeyCode.N then
        toggleNoclip()
    elseif input.KeyCode == Enum.KeyCode.G then
        setESPEnabled(not ESP.Enabled)
        refreshESPButtons()
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        toggleWindow()
    end
end)

closeBtn.Activated:Connect(function()
    if flying then
        stopFlight()
    end
    -- Luôn tắt NoClip và ESP để khôi phục trạng thái trước khi đóng.
    setNoclip(false)
    ESP.Destroy()

    if windowOpen then
        windowOpen = false
        local tween = TweenService:Create(main, TWEEN_CLOSE, {
            Size = UDim2.fromOffset(0, 0),
            Position = closedPositionFor(main.Position),
        })
        tween.Completed:Once(function()
            gui:Destroy()
        end)
        tween:Play()
    else
        gui:Destroy()
    end
end)

player.CharacterAdded:Connect(function(newCharacter)
    if flying then
        stopFlight()
    end
    table.clear(noclipChanged)
    character = newCharacter
    humanoid = nil
    root = nil
end)
