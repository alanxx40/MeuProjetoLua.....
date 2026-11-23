--[[
    V4ware V20 - Clean Control Center
    Lightweight UI / diagnostics shell for an experience you own or are authorized to test.

    Install as a LocalScript in StarterPlayerScripts or StarterGui in Roblox Studio.
    This file creates UI and reads client performance stats only.
    It does not load remote code, modify weapons, target players, or bypass game systems.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local OLD_GUI_NAME = "V4wareV20"
local oldGui = playerGui:FindFirstChild(OLD_GUI_NAME)
if oldGui then
    oldGui:Destroy()
end

local Theme = {
    background = Color3.fromRGB(12, 13, 16),
    panel = Color3.fromRGB(17, 19, 23),
    surface = Color3.fromRGB(23, 26, 31),
    surfaceHover = Color3.fromRGB(30, 34, 40),
    stroke = Color3.fromRGB(43, 47, 55),
    text = Color3.fromRGB(239, 242, 247),
    muted = Color3.fromRGB(139, 146, 158),
    accent = Color3.fromRGB(222, 230, 242),
    green = Color3.fromRGB(102, 205, 151),
    red = Color3.fromRGB(229, 112, 112),
}

local ACCENTS = {
    Silver = Color3.fromRGB(222, 230, 242),
    Ice = Color3.fromRGB(133, 196, 230),
}

local SETTINGS = {
    openKey = Enum.KeyCode.Insert,
    monitorEnabled = true,
    compact = false,
    accentName = "Silver",
}

local function create(className, parent, properties)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return create("UICorner", parent, {
        CornerRadius = UDim.new(0, radius or 10),
    })
end

local function stroke(parent, color, transparency)
    return create("UIStroke", parent, {
        Color = color or Theme.stroke,
        Transparency = transparency or 0,
        Thickness = 1,
    })
end

local function label(parent, text, size, position, fontSize, color, font)
    return create("TextLabel", parent, {
        BackgroundTransparency = 1,
        Text = text,
        Size = size,
        Position = position,
        Font = font or Enum.Font.Gotham,
        TextSize = fontSize or 13,
        TextColor3 = color or Theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local function button(parent, text, size, position)
    local item = create("TextButton", parent, {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.surface,
        BorderSizePixel = 0,
        Text = text,
        Size = size,
        Position = position,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Theme.text,
    })
    corner(item, 8)
    stroke(item)
    return item
end

local screenGui = create("ScreenGui", playerGui, {
    Name = OLD_GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 40,
})

local main = create("Frame", screenGui, {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(700, 480),
    BackgroundColor3 = Theme.background,
    BorderSizePixel = 0,
})
corner(main, 14)
stroke(main, Theme.stroke)

local sizeConstraint = create("UISizeConstraint", main, {
    MinSize = Vector2.new(540, 68),
    MaxSize = Vector2.new(820, 580),
})

local header = create("Frame", main, {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 68),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
})
corner(header, 14)

-- Square off the lower corners of the header so it joins the body cleanly.
create("Frame", header, {
    Position = UDim2.new(0, 0, 1, -14),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
})

local logoMark = create("Frame", header, {
    Position = UDim2.fromOffset(18, 17),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = Theme.surfaceHover,
    BorderSizePixel = 0,
})
corner(logoMark, 9)
stroke(logoMark)
label(logoMark, "V4", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), 13, Theme.text, Enum.Font.GothamBold).TextXAlignment = Enum.TextXAlignment.Center

label(header, "V4ware", UDim2.fromOffset(180, 24), UDim2.fromOffset(62, 15), 19, Theme.text, Enum.Font.GothamMedium)
label(header, "CLEAN CONTROL CENTER", UDim2.fromOffset(220, 15), UDim2.fromOffset(63, 39), 9, Theme.muted, Enum.Font.Gotham)

local onlineDot = create("Frame", header, {
    Position = UDim2.new(1, -128, 0, 27),
    Size = UDim2.fromOffset(7, 7),
    BackgroundColor3 = Theme.green,
    BorderSizePixel = 0,
})
corner(onlineDot, 8)
label(header, "READY", UDim2.fromOffset(48, 18), UDim2.new(1, -115, 0, 21), 10, Theme.muted, Enum.Font.GothamMedium)

local minimizeButton = button(header, "—", UDim2.fromOffset(28, 28), UDim2.new(1, -74, 0, 20))

minimizeButton.TextSize = 15
local closeButton = button(header, "×", UDim2.fromOffset(28, 28), UDim2.new(1, -40, 0, 20))
closeButton.TextSize = 17

local body = create("Frame", main, {
    Name = "Body",
    Position = UDim2.fromOffset(0, 68),
    Size = UDim2.new(1, 0, 1, -68),
    BackgroundTransparency = 1,
})

local sidebar = create("Frame", body, {
    Name = "Sidebar",
    Size = UDim2.new(0, 158, 1, 0),
    BackgroundColor3 = Theme.panel,
    BorderSizePixel = 0,
})
create("Frame", sidebar, {
    Position = UDim2.new(1, -1, 0, 0),
    Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = Theme.stroke,
    BorderSizePixel = 0,
})

label(sidebar, "WORKSPACE", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 18), 9, Theme.muted, Enum.Font.GothamMedium)

local navHolder = create("Frame", sidebar, {
    Position = UDim2.fromOffset(10, 48),
    Size = UDim2.new(1, -20, 0, 190),
    BackgroundTransparency = 1,
})
create("UIListLayout", navHolder, {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local sidebarFooter = label(sidebar, "V20  •  LIGHTWEIGHT", UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 1, -28), 9, Theme.muted, Enum.Font.Gotham)

local content = create("Frame", body, {
    Name = "Content",
    Position = UDim2.fromOffset(158, 0),
    Size = UDim2.new(1, -158, 1, 0),
    BackgroundTransparency = 1,
})

local pages = {}
local navButtons = {}
local activePage = "Overview"

local function makePage(name)
    local page = create("Frame", content, {
        Name = name,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    })
    pages[name] = page
    return page
end

local overviewPage = makePage("Overview")
local systemPage = makePage("System")
local settingsPage = makePage("Settings")
local consolePage = makePage("Console")

local function pageHeading(parent, titleText, description)
    label(parent, titleText, UDim2.new(1, -40, 0, 28), UDim2.fromOffset(22, 18), 19, Theme.text, Enum.Font.GothamMedium)
    label(parent, description, UDim2.new(1, -40, 0, 18), UDim2.fromOffset(23, 47), 11, Theme.muted, Enum.Font.Gotham)
end

local function makeNav(name, subtitle)
    local nav = create("TextButton", navHolder, {
        Name = name .. "Button",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Theme.panel,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = #navHolder:GetChildren(),
    })
    corner(nav, 8)
    local indicator = create("Frame", nav, {
        Position = UDim2.fromOffset(0, 8),
        Size = UDim2.fromOffset(3, 22),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
        Visible = false,
    })
    corner(indicator, 3)
    label(nav, name, UDim2.new(1, -18, 0, 18), UDim2.fromOffset(13, 3), 12, Theme.muted, Enum.Font.GothamMedium)
    label(nav, subtitle, UDim2.new(1, -18, 0, 13), UDim2.fromOffset(13, 20), 9, Theme.muted, Enum.Font.Gotham)
    navButtons[name] = {button = nav, indicator = indicator}
    return nav
end

local function makeStatCard(parent, titleText, initialValue, x, y, width)
    local card = create("Frame", parent, {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, 84),
        BackgroundColor3 = Theme.surface,
        BorderSizePixel = 0,
    })
    corner(card, 10)
    stroke(card)
    label(card, titleText, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 11), 9, Theme.muted, Enum.Font.GothamMedium)
    local value = label(card, initialValue, UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 34), 21, Theme.text, Enum.Font.GothamMedium)
    return value
end

-- Overview page
pageHeading(overviewPage, "Overview", "A simple view of your current client session.")

local overviewFps = makeStatCard(overviewPage, "FRAME RATE", "--", 22, 82, 210)
local overviewPing = makeStatCard(overviewPage, "NETWORK PING", "-- ms", 244, 82, 210)
local overviewMemory = makeStatCard(overviewPage, "CLIENT MEMORY", "-- MB", 22, 178, 210)
local overviewPlayers = makeStatCard(overviewPage, "PLAYERS IN SESSION", "--", 244, 178, 210)

local overviewStatus = create("Frame", overviewPage, {
    Position = UDim2.fromOffset(22, 276),
    Size = UDim2.new(1, -44, 0, 72),
    BackgroundColor3 = Theme.surface,
    BorderSizePixel = 0,
})
corner(overviewStatus, 10)
stroke(overviewStatus)
label(overviewStatus, "SESSION STATUS", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(13, 10), 9, Theme.muted, Enum.Font.GothamMedium)
local overviewStatusValue = label(overviewStatus, "CLIENT READY  •  MONITOR ENABLED", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(13, 29), 11, Theme.text, Enum.Font.GothamMedium)
local overviewSession = label(overviewStatus, "Session 00:00:00", UDim2.new(1, -24, 0, 13), UDim2.fromOffset(13, 51), 9, Theme.muted, Enum.Font.Gotham)

-- System page
pageHeading(systemPage, "System monitor", "Live client telemetry. Sampling pauses when this page is not visible.")

local systemFps = makeStatCard(systemPage, "FRAME RATE", "--", 22, 82, 210)
local systemPing = makeStatCard(systemPage, "NETWORK PING", "-- ms", 244, 82, 210)
local systemMemory = makeStatCard(systemPage, "CLIENT MEMORY", "-- MB", 22, 178, 210)
local systemPlayers = makeStatCard(systemPage, "PLAYERS IN SESSION", "--", 244, 178, 210)

local systemNote = create("Frame", systemPage, {
    Position = UDim2.fromOffset(22, 276),
    Size = UDim2.new(1, -44, 0, 72),
    BackgroundColor3 = Theme.surface,
    BorderSizePixel = 0,
})
corner(systemNote, 10)
stroke(systemNote)
label(systemNote, "PERFORMANCE MODE", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(13, 10), 9, Theme.muted, Enum.Font.GothamMedium)
label(systemNote, "Low-frequency updates  •  No animated graphs  •  No background polling while hidden", UDim2.new(1, -24, 0, 32), UDim2.fromOffset(13, 29), 10, Theme.text, Enum.Font.Gotham)

-- Settings page
pageHeading(settingsPage, "Settings", "Small controls to personalize the control center.")

local settingsList = create("Frame", settingsPage, {
    Position = UDim2.fromOffset(22, 82),
    Size = UDim2.new(1, -44, 0, 250),
    BackgroundTransparency = 1,
})
create("UIListLayout", settingsList, {
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local waitingForKey = false
local keyButton
local monitorButton
local compactButton
local accentButton

local function settingRow(titleText, description, buttonText)
    local row = create("Frame", settingsList, {
        LayoutOrder = #settingsList:GetChildren() + 1,
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundColor3 = Theme.surface,
        BorderSizePixel = 0,
    })
    corner(row, 9)
    stroke(row)
    label(row, titleText, UDim2.new(1, -150, 0, 18), UDim2.fromOffset(12, 7), 11, Theme.text, Enum.Font.GothamMedium)
    label(row, description, UDim2.new(1, -150, 0, 14), UDim2.fromOffset(12, 28), 9, Theme.muted, Enum.Font.Gotham)
    local control = button(row, buttonText, UDim2.fromOffset(112, 30), UDim2.new(1, -124, 0.5, -15))
    return control
end

keyButton = settingRow("Panel shortcut", "Press a key to open or close the panel.", SETTINGS.openKey.Name)
monitorButton = settingRow("System monitor", "Pause telemetry sampling when not needed.", "ON")
compactButton = settingRow("Compact layout", "Use a smaller panel footprint.", "OFF")
accentButton = settingRow("Accent color", "Switch between silver and ice blue.", SETTINGS.accentName)

local settingsHint = label(settingsPage, "Tip: the monitor only samples while Overview or System is open.", UDim2.new(1, -44, 0, 30), UDim2.fromOffset(22, 350), 9, Theme.muted, Enum.Font.Gotham)

-- Console page
pageHeading(consolePage, "Live console", "A short local log for UI and diagnostic events.")

local clearConsole = button(consolePage, "CLEAR LOG", UDim2.fromOffset(92, 28), UDim2.new(1, -114, 0, 22))
clearConsole.TextSize = 9

local consoleBox = create("ScrollingFrame", consolePage, {
    Position = UDim2.fromOffset(22, 68),
    Size = UDim2.new(1, -44, 1, -90),
    BackgroundColor3 = Theme.surface,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.muted,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
corner(consoleBox, 9)
stroke(consoleBox)
create("UIPadding", consoleBox, {
    PaddingTop = UDim.new(0, 9),
    PaddingBottom = UDim.new(0, 9),
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
})
local consoleLayout = create("UIListLayout", consoleBox, {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local logCount = 0
local MAX_LOGS = 50
local logEntries = {}

local function addLog(message, kind)
    logCount += 1
    local now = os.date("%H:%M:%S")
    local color = Theme.muted
    if kind == "success" then color = Theme.green end
    if kind == "error" then color = Theme.red end

    local entry = create("TextLabel", consoleBox, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 0, 18),
        Text = string.format("[%s]  %s", now, tostring(message)),
        Font = Enum.Font.Code,
        TextSize = 10,
        TextColor3 = color,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = logCount,
    })
    table.insert(logEntries, entry)

    while #logEntries > MAX_LOGS do
        local first = table.remove(logEntries, 1)
        if first then first:Destroy() end
    end

    task.defer(function()
        if consoleBox.Parent then
            consoleBox.CanvasPosition = Vector2.new(0, math.max(0, consoleLayout.AbsoluteContentSize.Y))
        end
    end)
end

clearConsole.MouseButton1Click:Connect(function()
    for _, entry in ipairs(logEntries) do
        if entry then entry:Destroy() end
    end
    table.clear(logEntries)
    addLog("Console cleared.", "success")
end)

-- Navigation
makeNav("Overview", "Session summary")
makeNav("System", "Performance")
makeNav("Settings", "Preferences")
makeNav("Console", "Diagnostics")

local function setPage(name)
    activePage = name
    for pageName, page in pairs(pages) do
        page.Visible = pageName == name
    end
    for navName, nav in pairs(navButtons) do
        local active = navName == name
        nav.indicator.Visible = active
        nav.button.BackgroundTransparency = active and 0 or 1
        nav.button.BackgroundColor3 = active and Theme.surface or Theme.panel
        local textLabel = nav.button:FindFirstChildOfClass("TextLabel")
        if textLabel then
            textLabel.TextColor3 = active and Theme.text or Theme.muted
        end
    end
end

for name, nav in pairs(navButtons) do
    nav.button.MouseButton1Click:Connect(function()
        setPage(name)
    end)
end

-- Toast notification
local toast = create("TextLabel", screenGui, {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -22, 1, -22),
    Size = UDim2.fromOffset(240, 34),
    BackgroundColor3 = Theme.surfaceHover,
    BorderSizePixel = 0,
    Text = "",
    TextColor3 = Theme.text,
    TextSize = 11,
    Font = Enum.Font.GothamMedium,
    Visible = false,
    ZIndex = 20,
})
corner(toast, 8)
stroke(toast)

local toastToken = 0
local function notify(message)
    toastToken += 1
    local token = toastToken
    toast.Text = tostring(message)
    toast.Visible = true
    task.delay(2.2, function()
        if toast.Parent and toastToken == token then
            toast.Visible = false
        end
    end)
end

-- Monitor sampling
local sessionStart = os.clock()
local frameCount = 0
local fpsValue = 0
local renderConnection = nil

local function shouldSample()
    return screenGui.Enabled
        and main.Visible
        and SETTINGS.monitorEnabled
        and (activePage == "Overview" or activePage == "System")
end

local function refreshFrameSampler()
    if shouldSample() and not renderConnection then
        frameCount = 0
        renderConnection = RunService.RenderStepped:Connect(function()
            frameCount += 1
        end)
    elseif not shouldSample() and renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end
end

local function readPing()
    local success, result = pcall(function()
        local item = Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
        if not item then
            return nil
        end
        return math.floor(item:GetValue())
    end)
    if success and result then
        return tostring(result) .. " ms"
    end
    return "N/A"
end

local function readMemory()
    local success, result = pcall(function()
        return math.floor(Stats:GetTotalMemoryUsageMb())
    end)
    if success and result then
        return tostring(result) .. " MB"
    end
    return "N/A"
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function updateMonitor()
    if not shouldSample() then
        refreshFrameSampler()
        return
    end

    if renderConnection then
        fpsValue = frameCount
        frameCount = 0
    else
        fpsValue = 0
    end

    local fpsText = fpsValue > 0 and tostring(fpsValue) or "N/A"
    local pingText = readPing()
    local memoryText = readMemory()
    local playerText = tostring(#Players:GetPlayers())
    local sessionText = "Session " .. formatDuration(os.clock() - sessionStart)

    overviewFps.Text = fpsText
    overviewPing.Text = pingText
    overviewMemory.Text = memoryText
    overviewPlayers.Text = playerText
    overviewSession.Text = sessionText

    systemFps.Text = fpsText
    systemPing.Text = pingText
    systemMemory.Text = memoryText
    systemPlayers.Text = playerText
end

task.spawn(function()
    while screenGui.Parent do
        if shouldSample() then
            updateMonitor()
        else
            refreshFrameSampler()
        end
        task.wait(1)
    end
end)

-- Settings interactions
keyButton.MouseButton1Click:Connect(function()
    waitingForKey = true
    keyButton.Text = "PRESS KEY..."
    notify("Press a key for the panel shortcut.")
end)

monitorButton.MouseButton1Click:Connect(function()
    SETTINGS.monitorEnabled = not SETTINGS.monitorEnabled
    monitorButton.Text = SETTINGS.monitorEnabled and "ON" or "OFF"
    overviewStatusValue.Text = SETTINGS.monitorEnabled and "CLIENT READY  •  MONITOR ENABLED" or "CLIENT READY  •  MONITOR PAUSED"
    refreshFrameSampler()
    addLog("System monitor " .. (SETTINGS.monitorEnabled and "enabled." or "paused."), "success")
    notify("System monitor " .. (SETTINGS.monitorEnabled and "enabled." or "paused."))
end)

compactButton.MouseButton1Click:Connect(function()
    SETTINGS.compact = not SETTINGS.compact
    compactButton.Text = SETTINGS.compact and "ON" or "OFF"
    main.Size = SETTINGS.compact and UDim2.fromOffset(620, 430) or UDim2.fromOffset(700, 480)
    notify(SETTINGS.compact and "Compact layout enabled." or "Standard layout enabled.")
    addLog("Layout changed: " .. (SETTINGS.compact and "compact." or "standard."), "success")
end)

local function applyAccent()
    Theme.accent = ACCENTS[SETTINGS.accentName]
    logoMark.BackgroundColor3 = Theme.surfaceHover
    for _, nav in pairs(navButtons) do
        nav.indicator.BackgroundColor3 = Theme.accent
    end
end

accentButton.MouseButton1Click:Connect(function()
    SETTINGS.accentName = SETTINGS.accentName == "Silver" and "Ice" or "Silver"
    accentButton.Text = SETTINGS.accentName
    applyAccent()
    addLog("Accent changed to " .. SETTINGS.accentName .. ".", "success")
    notify("Accent: " .. SETTINGS.accentName)
end)

-- Header drag
do
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position
            dragInput = input

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local minimized = false
minimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(700, 68) or (SETTINGS.compact and UDim2.fromOffset(620, 430) or UDim2.fromOffset(700, 480))
    minimizeButton.Text = minimized and "+" or "—"
    refreshFrameSampler()
end)

closeButton.MouseButton1Click:Connect(function()
    main.Visible = false
    refreshFrameSampler()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if waitingForKey then
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
            SETTINGS.openKey = input.KeyCode
            keyButton.Text = SETTINGS.openKey.Name
            waitingForKey = false
            addLog("Panel shortcut changed to " .. SETTINGS.openKey.Name .. ".", "success")
            notify("Shortcut updated.")
        end
        return
    end

    if gameProcessed then
        return
    end

    if input.KeyCode == SETTINGS.openKey then
        if minimized then
            minimized = false
            body.Visible = true
            main.Size = SETTINGS.compact and UDim2.fromOffset(620, 430) or UDim2.fromOffset(700, 480)
            minimizeButton.Text = "—"
        else
            main.Visible = not main.Visible
        end
        refreshFrameSampler()
    end
end)

-- Keep the monitor sampler in sync with page visibility and panel visibility.
local originalSetPage = setPage
setPage = function(name)
    originalSetPage(name)
    refreshFrameSampler()
end

main:GetPropertyChangedSignal("Visible"):Connect(refreshFrameSampler)

-- Startup
keyButton.Text = SETTINGS.openKey.Name
monitorButton.Text = SETTINGS.monitorEnabled and "ON" or "OFF"
compactButton.Text = "OFF"
accentButton.Text = SETTINGS.accentName
setPage("Overview")
addLog("V4ware V20 initialized.", "success")
addLog("Local diagnostics ready.", "success")
refreshFrameSampler()

print("[V4ware V20] Clean Control Center initialized.")
