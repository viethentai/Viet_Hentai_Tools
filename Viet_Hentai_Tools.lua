--[[
    VIỆT HENTAI TOOLS - Fly + NoClip + Server Finder + ESP
    LocalScript for Roblox Studio / executor.

    Phím tắt:
      F              - Bật/tắt bay
      N              - Bật/tắt NoClip
      G              - Bật/tắt ESP
      RightShift     - Ẩn/hiện cửa sổ
      WASD           - Di chuyển
      E / Up arrow   - Bay lên (khi đứng gần vật tương tác, E ưu tiên tương tác)
      Q / Down arrow - Bay xuống
      + / -          - Đổi mốc tốc độ (giữ để lặp lại)

    Icon nút thu gọn:
      Đặt BUBBLE_IMAGE_ID = "rbxassetid://<ID>" để dùng ảnh.
      Để trống "" thì nút hiển thị chữ "VH".
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
local MIN_DISPLAY = 1
local MAX_DISPLAY = 100
local DEFAULT_DISPLAY = 20
local PROMPT_SEARCH_RADIUS = 32

local WINDOW_SIZE = UDim2.fromOffset(520, 400)
local BUBBLE_SIZE = UDim2.fromOffset(52, 52)
local TWEEN_MINIMIZE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local TWEEN_RESTORE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_CLOSE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

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

local serverLoaded = false
local serverLoading = false
local gameName = "Unknown"

local maxDisplay = DEFAULT_DISPLAY
local sortAscending = true -- true: ít -> nhiều, false: nhiều -> ít
local cachedServers = {}   -- danh sách server còn chỗ, lấy từ lần tải gần nhất

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
    corner.CornerRadius = radius
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
    makeCorner(button, UDim.new(0, 7))
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
makeCorner(main, UDim.new(0, 10))

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLOR_STROKE
mainStroke.Thickness = 1.5
mainStroke.Parent = main

-- Header
local title = makeLabel(main, "Title", "Việt Hentai Tools", UDim2.fromOffset(12, 8), UDim2.fromOffset(420, 26), 18)

local minimizeBtn = makeButton(main, "Minimize", "-", UDim2.fromOffset(448, 8), UDim2.fromOffset(30, 26), COLOR_MIN, 16)
local closeBtn = makeButton(main, "Close", "X", UDim2.fromOffset(482, 8), UDim2.fromOffset(30, 26), COLOR_CLOSE)

-- Tabs
local flyTab = makeButton(main, "TabFly", "FLY", UDim2.fromOffset(12, 44), UDim2.fromOffset(96, 30), COLOR_TAB_OFF, 12)
local serverTab = makeButton(main, "TabServer", "SERVER", UDim2.fromOffset(112, 44), UDim2.fromOffset(96, 30), COLOR_TAB_OFF, 12)
local espTab = makeButton(main, "TabESP", "ESP", UDim2.fromOffset(212, 44), UDim2.fromOffset(96, 30), COLOR_TAB_OFF, 12)
local teleportTab = makeButton(main, "TabTeleport", "TELEPORT", UDim2.fromOffset(312, 44), UDim2.fromOffset(96, 30), COLOR_TAB_OFF, 11)
local speedTab = makeButton(main, "TabSpeed", "SPEED", UDim2.fromOffset(412, 44), UDim2.fromOffset(96, 30), COLOR_TAB_OFF, 12)
for _, tab in ipairs({ flyTab, serverTab, espTab, teleportTab, speedTab }) do
    tab.TextColor3 = COLOR_TEXT
end

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
makeCorner(countBox, UDim.new(0, 7))

local plus = makeButton(flyPage, "Plus", "+",
    UDim2.fromOffset(464, 62), UDim2.fromOffset(44, 38), COLOR_PLUS, 18)

local hint = makeLabel(flyPage, "Hint", "E: lên   Q: xuống   E gần vật: tương tác   RightShift: ẩn/hiện",
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

-- Hàng điều khiển: số server hiển thị + kiểu sắp xếp
local maxBox = Instance.new("TextBox")
maxBox.Name = "MaxBox"
maxBox.Position = UDim2.fromOffset(12, 40)
maxBox.Size = UDim2.fromOffset(170, 28)
maxBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
maxBox.BorderSizePixel = 0
maxBox.Font = Enum.Font.GothamBold
maxBox.Text = tostring(maxDisplay)
maxBox.TextColor3 = Color3.fromRGB(25, 30, 35)
maxBox.TextSize = 13
maxBox.ClearTextOnFocus = false
maxBox.PlaceholderText = "Số server hiển thị (1-100)"
maxBox.Parent = serverPage
makeCorner(maxBox, UDim.new(0, 7))

local sortBtn = makeButton(serverPage, "Sort", "SẮP XẾP: ÍT → NHIỀU",
    UDim2.fromOffset(192, 40), UDim2.fromOffset(316, 28), COLOR_MINUS, 12)

local serverList = Instance.new("ScrollingFrame")
serverList.Name = "ServerList"
serverList.Position = UDim2.fromOffset(12, 76)
serverList.Size = UDim2.fromOffset(496, 224)
serverList.BackgroundColor3 = COLOR_LIST
serverList.BorderSizePixel = 0
serverList.CanvasSize = UDim2.new(0, 0, 0, 0)
serverList.AutomaticCanvasSize = Enum.AutomaticSize.Y
serverList.ScrollBarThickness = 5
serverList.Parent = serverPage
makeCorner(serverList, UDim.new(0, 8))

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
-- Bubble (nút tròn, hiện khi thu gọn)
---------------------------------------------------------------------
local bubble = Instance.new("TextButton")
bubble.Name = "Bubble"
bubble.Position = UDim2.fromOffset(10, 200)
bubble.Size = BUBBLE_SIZE
bubble.BackgroundColor3 = COLOR_STROKE
bubble.BorderSizePixel = 0
bubble.AutoButtonColor = false
bubble.Font = Enum.Font.GothamBold
bubble.Text = "VH"
bubble.TextColor3 = COLOR_DARK_TEXT
bubble.TextSize = 16
bubble.ClipsDescendants = true
bubble.Visible = false
bubble.Parent = gui
makeCorner(bubble, UDim.new(0.5, 0)) -- bo tròn thành hình tròn

bubble.Text = "🐱"
bubble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
bubble.BackgroundTransparency = 0
bubble.TextSize = 24

---------------------------------------------------------------------
-- Window minimize / restore animation
-- Thu nhỏ từ từ vào đúng vị trí nút tròn, và phóng ra từ nút tròn.
---------------------------------------------------------------------
local windowOpen = true
local windowBusy = false
local openPosition = main.Position

local function tweenWindow(info, goal, onDone)
    local tween = TweenService:Create(main, info, goal)
    if onDone then
        tween.Completed:Once(onDone)
    end
    tween:Play()
    return tween
end

local function minimizeWindow()
    if not windowOpen or windowBusy then
        return
    end
    windowBusy = true
    windowOpen = false
    openPosition = main.Position

    tweenWindow(TWEEN_MINIMIZE, {
        Size = BUBBLE_SIZE,
        Position = bubble.Position,
    }, function()
        main.Visible = false
        main.Size = WINDOW_SIZE
        main.Position = openPosition
        bubble.Visible = true
        windowBusy = false
    end)
end

local function openWindow()
    if windowOpen or windowBusy then
        return
    end
    windowBusy = true
    windowOpen = true

    bubble.Visible = false
    main.Visible = true
    main.Size = BUBBLE_SIZE
    main.Position = bubble.Position

    tweenWindow(TWEEN_RESTORE, {
        Size = WINDOW_SIZE,
        Position = openPosition,
    }, function()
        windowBusy = false
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
-- TELEPORT tab: save / load / teleport to local positions
---------------------------------------------------------------------
local teleportPage = Instance.new("Frame")
teleportPage.Name = "TeleportPage"
teleportPage.Position = UDim2.fromOffset(0, 84)
teleportPage.Size = UDim2.fromOffset(520, 306)
teleportPage.BackgroundTransparency = 1
teleportPage.Visible = false
teleportPage.Parent = main

local pointNameBox = Instance.new("TextBox")
pointNameBox.Name = "PointName"
pointNameBox.Position = UDim2.fromOffset(12, 10)
pointNameBox.Size = UDim2.fromOffset(330, 34)
pointNameBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
pointNameBox.BorderSizePixel = 0
pointNameBox.Font = Enum.Font.Gotham
pointNameBox.Text = ""
pointNameBox.PlaceholderText = "Tên điểm dịch chuyển..."
pointNameBox.ClearTextOnFocus = false
pointNameBox.TextColor3 = Color3.fromRGB(25, 30, 35)
pointNameBox.TextSize = 13
pointNameBox.Parent = teleportPage
makeCorner(pointNameBox, UDim.new(0, 7))

local savePointBtn = makeButton(teleportPage, "SavePoint", "LƯU VỊ TRÍ",
    UDim2.fromOffset(352, 10), UDim2.fromOffset(156, 34), COLOR_PLUS, 12)

local teleportStatus = makeLabel(teleportPage, "TeleportStatus", "Đang tải điểm đã lưu...",
    UDim2.fromOffset(12, 50), UDim2.fromOffset(496, 22), 11)
teleportStatus.Font = Enum.Font.Gotham
teleportStatus.TextColor3 = COLOR_HINT

local pointList = Instance.new("ScrollingFrame")
pointList.Name = "PointList"
pointList.Position = UDim2.fromOffset(12, 78)
pointList.Size = UDim2.fromOffset(496, 220)
pointList.BackgroundColor3 = COLOR_LIST
pointList.BorderSizePixel = 0
pointList.CanvasSize = UDim2.new(0, 0, 0, 0)
pointList.AutomaticCanvasSize = Enum.AutomaticSize.Y
pointList.ScrollBarThickness = 5
pointList.Parent = teleportPage
makeCorner(pointList, UDim.new(0, 8))

local pointLayout = Instance.new("UIListLayout")
pointLayout.SortOrder = Enum.SortOrder.LayoutOrder
pointLayout.Padding = UDim.new(0, 6)
pointLayout.Parent = pointList

local pointPadding = Instance.new("UIPadding")
pointPadding.PaddingTop = UDim.new(0, 6)
pointPadding.PaddingLeft = UDim.new(0, 6)
pointPadding.PaddingRight = UDim.new(0, 6)
pointPadding.PaddingBottom = UDim.new(0, 6)
pointPadding.Parent = pointList

local savedPoints = {}
local pointFile = "VHT_TeleportPoints_" .. tostring(game.PlaceId) .. ".json"
local fileRead = readfile
local fileWrite = writefile
local fileExists = isfile
local fileStorageAvailable = type(fileRead) == "function"
    and type(fileWrite) == "function"

local function setTeleportStatus(message)
    teleportStatus.Text = message
end

local function persistPoints()
    if not fileStorageAvailable then
        setTeleportStatus("Executor không hỗ trợ lưu file; điểm chỉ giữ đến khi thoát script.")
        return false
    end

    local ok, err = pcall(function()
        fileWrite(pointFile, HttpService:JSONEncode(savedPoints))
    end)
    if not ok then
        setTeleportStatus("Không thể ghi file: " .. tostring(err))
        return false
    end
    return true
end

local function loadPoints()
    if not fileStorageAvailable then
        setTeleportStatus("Không có API file; điểm sẽ không được lưu sau khi thoát.")
        return
    end

    local ok, result = pcall(function()
        if type(fileExists) == "function" and not fileExists(pointFile) then
            return {}
        end
        return HttpService:JSONDecode(fileRead(pointFile))
    end)

    if ok and type(result) == "table" then
        for _, point in ipairs(result) do
            if type(point) == "table"
                and type(point.name) == "string"
                and type(point.x) == "number"
                and type(point.y) == "number"
                and type(point.z) == "number" then
                table.insert(savedPoints, {
                    name = point.name,
                    x = point.x,
                    y = point.y,
                    z = point.z,
                })
            end
        end
    elseif not ok then
        setTeleportStatus("File điểm lưu bị lỗi hoặc không đọc được: " .. tostring(result))
    end
end

local function clearPointRows()
    for _, child in ipairs(pointList:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
end

local function renderSavedPoints()
    clearPointRows()

    for index, point in ipairs(savedPoints) do
        local row = Instance.new("Frame")
        row.Name = "PointRow_" .. tostring(index)
        row.Size = UDim2.new(1, 0, 0, 42)
        row.BackgroundColor3 = COLOR_ROW
        row.BorderSizePixel = 0
        row.LayoutOrder = index
        row.Parent = pointList
        makeCorner(row, UDim.new(0, 7))

        local info = Instance.new("TextLabel")
        info.Name = "PointInfo"
        info.Position = UDim2.fromOffset(9, 0)
        info.Size = UDim2.new(1, -174, 1, 0)
        info.BackgroundTransparency = 1
        info.Font = Enum.Font.Gotham
        info.Text = string.format("%s  |  %.1f, %.1f, %.1f", point.name, point.x, point.y, point.z)
        info.TextColor3 = COLOR_TEXT
        info.TextSize = 11
        info.TextXAlignment = Enum.TextXAlignment.Left
        info.TextTruncate = Enum.TextTruncate.AtEnd
        info.Parent = row

        local goButton = makeButton(row, "Go", "ĐẾN", UDim2.new(1, -158, 0.5, -15),
            UDim2.fromOffset(72, 30), COLOR_PLUS, 11)
        local deleteButton = makeButton(row, "Delete", "XÓA", UDim2.new(1, -80, 0.5, -15),
            UDim2.fromOffset(70, 30), COLOR_CLOSE, 11)

        goButton.Activated:Connect(function()
            local currentCharacter = player.Character
            local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
            if not currentRoot then
                setTeleportStatus("Không tìm thấy nhân vật; hãy đợi nhân vật tải xong.")
                return
            end

            local destination = Vector3.new(point.x, point.y, point.z)
            local ok, err = pcall(function()
                currentRoot.CFrame = CFrame.new(destination + Vector3.new(0, 3, 0))
            end)
            if ok then
                setTeleportStatus("Đã dịch chuyển đến: " .. point.name)
            else
                setTeleportStatus("Teleport thất bại: " .. tostring(err))
            end
        end)

        deleteButton.Activated:Connect(function()
            for pointIndex, savedPoint in ipairs(savedPoints) do
                if savedPoint == point then
                    table.remove(savedPoints, pointIndex)
                    break
                end
            end
            persistPoints()
            renderSavedPoints()
            setTeleportStatus("Đã xóa điểm: " .. point.name)
        end)
    end

    if #savedPoints == 0 then
        setTeleportStatus("Chưa có điểm nào. Đứng tại vị trí muốn lưu rồi nhấn LƯU VỊ TRÍ.")
    elseif fileStorageAvailable then
        setTeleportStatus(string.format("Đã lưu %d điểm | Tự động lưu theo PlaceId này.", #savedPoints))
    end
end

savePointBtn.Activated:Connect(function()
    local currentCharacter = player.Character
    local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
    if not currentRoot then
        setTeleportStatus("Không thể lưu: nhân vật chưa tải xong.")
        return
    end

    local pointName = pointNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if pointName == "" then
        pointName = "Điểm " .. tostring(#savedPoints + 1)
    end

    local position = currentRoot.Position
    table.insert(savedPoints, {
        name = pointName,
        x = position.X,
        y = position.Y,
        z = position.Z,
    })

    local savedToDisk = persistPoints()
    renderSavedPoints()
    if savedToDisk then
        setTeleportStatus("Đã lưu điểm: " .. pointName)
    else
        setTeleportStatus("Đã lưu tạm điểm: " .. pointName .. " (không ghi được file).")
    end
    pointNameBox.Text = ""
end)

loadPoints()
renderSavedPoints()

---------------------------------------------------------------------
-- SPEED tab: numeric WalkSpeed + mutually-exclusive application methods
---------------------------------------------------------------------
local speedPage = Instance.new("Frame")
speedPage.Name = "SpeedPage"
speedPage.Position = UDim2.fromOffset(0, 84)
speedPage.Size = UDim2.fromOffset(520, 306)
speedPage.BackgroundTransparency = 1
speedPage.Visible = false
speedPage.Parent = main

makeLabel(speedPage, "SpeedTitle", "TỐC ĐỘ DI CHUYỂN", UDim2.fromOffset(12, 12),
    UDim2.fromOffset(496, 24), 15)

local walkSpeedBox = Instance.new("TextBox")
walkSpeedBox.Name = "WalkSpeedBox"
walkSpeedBox.Position = UDim2.fromOffset(12, 48)
walkSpeedBox.Size = UDim2.fromOffset(330, 38)
walkSpeedBox.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
walkSpeedBox.BorderSizePixel = 0
walkSpeedBox.Font = Enum.Font.GothamBold
walkSpeedBox.Text = "32"
walkSpeedBox.PlaceholderText = "Nhập WalkSpeed (0.1 - 500)"
walkSpeedBox.ClearTextOnFocus = false
walkSpeedBox.TextColor3 = Color3.fromRGB(25, 30, 35)
walkSpeedBox.TextSize = 15
walkSpeedBox.Parent = speedPage
makeCorner(walkSpeedBox, UDim.new(0, 7))

local applySpeedBtn = makeButton(speedPage, "ApplyWalkSpeed", "ÁP DỤNG",
    UDim2.fromOffset(352, 48), UDim2.fromOffset(156, 38), COLOR_PLUS, 13)

local speedModeLabel = makeLabel(speedPage, "SpeedModeLabel", "PHƯƠNG PHÁP ÁP DỤNG (CHỌN 1)",
    UDim2.fromOffset(12, 102), UDim2.fromOffset(496, 22), 12)
speedModeLabel.TextColor3 = COLOR_HINT

local directSpeedBtn = makeButton(speedPage, "SpeedModeDirect", "CÁCH 1: ĐẶT WALKSpeed",
    UDim2.fromOffset(12, 132), UDim2.fromOffset(244, 44), COLOR_NOCLIP_OFF, 12)
local loopSpeedBtn = makeButton(speedPage, "SpeedModeLoop", "CÁCH 2: GIỮ WALKSpeed",
    UDim2.fromOffset(264, 132), UDim2.fromOffset(244, 44), COLOR_NOCLIP_OFF, 12)

local speedStatus = makeLabel(speedPage, "SpeedStatus", "Nhập tốc độ rồi nhấn ÁP DỤNG.",
    UDim2.fromOffset(12, 190), UDim2.fromOffset(496, 34), 12)
speedStatus.Font = Enum.Font.Gotham
speedStatus.TextColor3 = COLOR_HINT
speedStatus.TextWrapped = true

local SPEED_MIN = 0.1
local SPEED_MAX = 500
local requestedWalkSpeed = 32
local speedMode = nil -- nil / "direct" / "loop"
local speedConnection = nil
local originalWalkSpeed = nil
local speedTargetHumanoid = nil

local function setSpeedStatus(message)
    speedStatus.Text = message
end

local function updateSpeedModeButtons()
    directSpeedBtn.Text = "CÁCH 1: ĐẶT WALKSpeed" .. (speedMode == "direct" and " [ON]" or " [OFF]")
    loopSpeedBtn.Text = "CÁCH 2: GIỮ WALKSpeed" .. (speedMode == "loop" and " [ON]" or " [OFF]")
    directSpeedBtn.BackgroundColor3 = speedMode == "direct" and COLOR_FLY_ON or COLOR_NOCLIP_OFF
    loopSpeedBtn.BackgroundColor3 = speedMode == "loop" and COLOR_FLY_ON or COLOR_NOCLIP_OFF
end

local function captureSpeedBaseline(hum)
    if speedTargetHumanoid ~= hum then
        speedTargetHumanoid = hum
        originalWalkSpeed = hum and hum.WalkSpeed or nil
    end
end

local function applyRequestedWalkSpeed()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then
        setSpeedStatus("Chưa tìm thấy Humanoid. Hãy đợi nhân vật tải xong.")
        return false
    end
    captureSpeedBaseline(hum)
    local ok, err = pcall(function()
        hum.WalkSpeed = requestedWalkSpeed
    end)
    if not ok then
        setSpeedStatus("Không thể đặt WalkSpeed: " .. tostring(err))
        return false
    end
    return true
end

local function stopSpeedMode(restore)
    if speedConnection then
        speedConnection:Disconnect()
        speedConnection = nil
    end

    local hum = speedTargetHumanoid
    if restore and hum and hum.Parent and originalWalkSpeed then
        pcall(function()
            hum.WalkSpeed = originalWalkSpeed
        end)
    end

    speedMode = nil
    speedTargetHumanoid = nil
    originalWalkSpeed = nil
    updateSpeedModeButtons()
end

local function setSpeedMode(mode)
    if speedMode == mode then
        stopSpeedMode(true)
        setSpeedStatus("Đã tắt chế độ tăng tốc và khôi phục tốc độ trước đó.")
        return
    end

    stopSpeedMode(true)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then
        setSpeedStatus("Chưa tìm thấy nhân vật. Hãy thử bật lại sau.")
        return
    end

    speedMode = mode
    captureSpeedBaseline(hum)
    if not applyRequestedWalkSpeed() then
        stopSpeedMode(false)
        return
    end

    if mode == "loop" then
        speedConnection = RunService.Heartbeat:Connect(function()
            local currentCharacter = player.Character
            local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
            if currentHumanoid then
                captureSpeedBaseline(currentHumanoid)
                if currentHumanoid.WalkSpeed ~= requestedWalkSpeed then
                    pcall(function()
                        currentHumanoid.WalkSpeed = requestedWalkSpeed
                    end)
                end
            end
        end)
        setSpeedStatus(string.format("Đang bật giữ tốc độ %.1f. Nếu game ghi đè WalkSpeed, script sẽ đặt lại mỗi frame.", requestedWalkSpeed))
    else
        setSpeedStatus(string.format("Đã đặt WalkSpeed = %.1f một lần. Nếu game tự ghi đè, hãy thử CÁCH 2.", requestedWalkSpeed))
    end
    updateSpeedModeButtons()
end

local function readRequestedWalkSpeed()
    local value = tonumber(walkSpeedBox.Text)
    if not value or value < SPEED_MIN or value > SPEED_MAX then
        setSpeedStatus("Giá trị không hợp lệ. Hãy nhập số từ 0.1 đến 500.")
        walkSpeedBox.Text = tostring(requestedWalkSpeed)
        return false
    end
    requestedWalkSpeed = value
    walkSpeedBox.Text = tostring(requestedWalkSpeed)
    if speedMode then
        local activeMode = speedMode
        setSpeedMode(activeMode)
        if speedMode ~= activeMode then
            setSpeedMode(activeMode)
        end
        setSpeedStatus(string.format("Đã cập nhật tốc độ: %.1f | Phương pháp: %s",
            requestedWalkSpeed, activeMode == "loop" and "Giữ WalkSpeed" or "Đặt một lần"))
    else
        setSpeedStatus(string.format("Đã lưu mức tốc độ %.1f. Chọn một phương pháp để bật.", requestedWalkSpeed))
    end
    return true
end

applySpeedBtn.Activated:Connect(readRequestedWalkSpeed)
walkSpeedBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        readRequestedWalkSpeed()
    end
end)
directSpeedBtn.Activated:Connect(function()
    setSpeedMode("direct")
end)
loopSpeedBtn.Activated:Connect(function()
    setSpeedMode("loop")
end)
updateSpeedModeButtons()

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
local stopFlight

local promptParams = OverlapParams.new()
promptParams.FilterType = Enum.RaycastFilterType.Exclude

-- Kiểm tra có ProximityPrompt (vật cần tương tác bằng E) gần nhân vật không.
local function hasInteractableNearby(rootPart)
    promptParams.FilterDescendantsInstances = character and { character } or {}

    local parts = workspace:GetPartBoundsInRadius(rootPart.Position, PROMPT_SEARCH_RADIUS, promptParams)
    for _, part in ipairs(parts) do
        for _, inst in ipairs(part:GetDescendants()) do
            if inst:IsA("ProximityPrompt") and inst.Enabled then
                local distance = (part.Position - rootPart.Position).Magnitude
                if distance <= inst.MaxActivationDistance then
                    return true
                end
            end
        end
    end

    return false
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

stopFlight = function()
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

        -- E / Up: bay lên. Nếu đang đứng gần vật tương tác thì E dành cho tương tác.
        -- Q / Down: bay xuống.
        local upHeld = UserInputService:IsKeyDown(Enum.KeyCode.E)
            or UserInputService:IsKeyDown(Enum.KeyCode.Up)
        local downHeld = UserInputService:IsKeyDown(Enum.KeyCode.Q)
            or UserInputService:IsKeyDown(Enum.KeyCode.Down)

        local vertical = 0
        if upHeld and not hasInteractableNearby(root) then
            vertical += 1
        end
        if downHeld then
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
    makeCorner(row, UDim.new(0, 8))

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
    makeCorner(joinBtn, UDim.new(0, 7))

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

-- Vẽ lại danh sách từ cache theo số lượng và kiểu sắp xếp hiện tại.
-- Không gọi lại API nên đổi số lượng/sắp xếp thì tức thì.
local loadServers -- khai báo trước, định nghĩa ở phần dưới

local function renderServers(list)
    local sorted = {}
    for _, server in ipairs(list) do
        table.insert(sorted, server)
    end

    table.sort(sorted, function(a, b)
        if sortAscending then
            return a.playing < b.playing
        end
        return a.playing > b.playing
    end)

    clearServerList()

    local shown = 0
    for _, server in ipairs(sorted) do
        if shown >= maxDisplay then
            break
        end
        shown += 1
        createServerEntry(server, shown)
    end

    return shown, #sorted
end

local function refreshServerView(note)
    local shown, total = renderServers(cachedServers)

    if total == 0 then
        setStatus("Không có server nào còn chỗ." .. (note and (" | " .. note) or ""))
    else
        local text = string.format("Hiển thị %d / %d server còn chỗ", shown, total)
        if note then
            text = text .. " | " .. note
        end
        setStatus(text)
    end
end

local function updateSortButton()
    sortBtn.Text = sortAscending and "SẮP XẾP: ÍT → NHIỀU" or "SẮP XẾP: NHIỀU → ÍT"
end

local function setMaxDisplay(value)
    value = math.floor(tonumber(value) or maxDisplay)
    value = math.clamp(value, MIN_DISPLAY, MAX_DISPLAY)
    local changed = value ~= maxDisplay
    maxDisplay = value
    maxBox.Text = tostring(maxDisplay)

    -- Đổi số lượng thì quét lại đúng bằng số đó
    if changed and serverLoaded and not serverLoading then
        loadServers()
    end
end

-- Chọn kích thước trang nhỏ nhất đủ dùng, để mỗi lần gọi API tải ít dữ liệu hơn.
local function getPageLimit(needed)
    if needed <= 10 then return 10 end
    if needed <= 25 then return 25 end
    if needed <= 50 then return 50 end
    return 100
end

-- Lấy một trang server. Tự thử lại khi bị giới hạn tốc độ (HTTP 429).
local function fetchPage(cursor, limit)
    if not requestFunc then
        return nil, "Executor không hỗ trợ HTTP request"
    end

    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d",
        game.PlaceId, limit
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

loadServers = function()
    if serverLoading then
        return
    end
    serverLoading = true
    serverLoaded = true

    -- Quét đúng bằng số server người dùng muốn hiển thị
    local target = maxDisplay
    local limit = getPageLimit(target)

    setStatus(string.format("Đang quét... 0 / %d server", target))
    refreshBtn.Text = "ĐANG QUÉT"

    task.spawn(function()
        local found = {}
        local seen = {}
        local cursor = nil
        local pages = 0
        local errorMsg = nil

        repeat
            local data, err = fetchPage(cursor, limit)
            if not data then
                errorMsg = err
                break
            end

            for _, server in ipairs(data.data or {}) do
                if #found >= target then
                    break
                end
                if server.playing < server.maxPlayers and not seen[server.id] then
                    seen[server.id] = true
                    table.insert(found, server)
                end
            end

            pages += 1
            cursor = data.nextPageCursor

            -- Hiển thị ngay khi có kết quả, không đợi quét xong
            renderServers(found)
            setStatus(string.format("Đang quét... %d / %d server", #found, target))

            if #found < target and cursor and pages < MAX_SERVER_PAGES then
                task.wait(PAGE_DELAY)
            end
        until #found >= target or not cursor or pages >= MAX_SERVER_PAGES

        if errorMsg and #found == 0 then
            -- Lỗi và chưa có kết quả nào: giữ nguyên danh sách cũ
            setStatus("Lỗi: " .. errorMsg .. " (giữ danh sách cũ)")
        else
            cachedServers = found
            refreshServerView(errorMsg and ("quét chưa đủ: " .. errorMsg) or nil)
        end

        refreshBtn.Text = "LÀM MỚI"
        serverLoading = false
    end)
end

---------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------
local function showTab(tabName)
    flyPage.Visible = tabName == "FLY"
    serverPage.Visible = tabName == "SERVER"
    espPage.Visible = tabName == "ESP"
    teleportPage.Visible = tabName == "TELEPORT"
    speedPage.Visible = tabName == "SPEED"

    flyTab.BackgroundColor3 = tabName == "FLY" and COLOR_TAB_ON or COLOR_TAB_OFF
    serverTab.BackgroundColor3 = tabName == "SERVER" and COLOR_TAB_ON or COLOR_TAB_OFF
    espTab.BackgroundColor3 = tabName == "ESP" and COLOR_TAB_ON or COLOR_TAB_OFF
    teleportTab.BackgroundColor3 = tabName == "TELEPORT" and COLOR_TAB_ON or COLOR_TAB_OFF
    speedTab.BackgroundColor3 = tabName == "SPEED" and COLOR_TAB_ON or COLOR_TAB_OFF

    if tabName == "SERVER" and not serverLoaded then
        loadServers()
    end
end

updateSortButton()
showTab("FLY")

---------------------------------------------------------------------
-- Connections
---------------------------------------------------------------------
toggle.Activated:Connect(toggleFlight)
noclipButton.Activated:Connect(toggleNoclip)
flyTab.Activated:Connect(function() showTab("FLY") end)
serverTab.Activated:Connect(function() showTab("SERVER") end)
espTab.Activated:Connect(function() showTab("ESP") end)
teleportTab.Activated:Connect(function() showTab("TELEPORT") end)
speedTab.Activated:Connect(function() showTab("SPEED") end)
refreshBtn.Activated:Connect(loadServers)
minimizeBtn.Activated:Connect(minimizeWindow)

maxBox.FocusLost:Connect(function()
    setMaxDisplay(maxBox.Text)
end)

sortBtn.Activated:Connect(function()
    sortAscending = not sortAscending
    updateSortButton()
    if serverLoaded and not serverLoading then
        refreshServerView()
    end
end)

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
    stopSpeedMode(true)

    if windowOpen then
        windowOpen = false
        local tween = TweenService:Create(main, TWEEN_CLOSE, {
            Size = BUBBLE_SIZE,
            Position = bubble.Position,
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

    if speedMode then
        task.defer(function()
            local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
            if newHumanoid and speedMode then
                speedTargetHumanoid = nil
                originalWalkSpeed = nil
                captureSpeedBaseline(newHumanoid)
                pcall(function()
                    newHumanoid.WalkSpeed = requestedWalkSpeed
                end)
            end
        end)
    end
end)
