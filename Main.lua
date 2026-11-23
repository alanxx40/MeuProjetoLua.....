--[[
    V4ware V22 - Studio QA / Hitbox Lab
    LocalScript for Roblox Studio experiences you own or are authorized to test.

    Install:
      StarterPlayer > StarterPlayerScripts > LocalScript

    Hitbox Lab scope:
      * Visual debug boxes only (BoxHandleAdornment)
      * Only Models explicitly tagged "V4wareTestDummy"
      * Player characters are excluded
      * Does NOT change collision, damage, targeting, or server-side hitboxes
      * X/Y/Z are visual scale multipliers relative to HumanoidRootPart size
      * Transparency: 0 = opaque, 1 = invisible

    This is a Studio QA panel, not an executor script.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "V4wareV22StudioQA"
local DUMMY_TAG = "V4wareTestDummy"

local previous = PlayerGui:FindFirstChild(GUI_NAME)
if previous then
    previous:Destroy()
end

local Theme = {
    Background = Color3.fromRGB(11, 13, 17),
    Header = Color3.fromRGB(16, 19, 24),
    Sidebar = Color3.fromRGB(16, 19, 24),
    Panel = Color3.fromRGB(20, 24, 30),
    Card = Color3.fromRGB(25, 30, 37),
    CardHover = Color3.fromRGB(31, 37, 45),
    Border = Color3.fromRGB(44, 51, 61),
    Text = Color3.fromRGB(239, 243, 248),
    Muted = Color3.fromRGB(139, 149, 163),
    Dim = Color3.fromRGB(94, 105, 120),
    Accent = Color3.fromRGB(155, 190, 225),
    Green = Color3.fromRGB(111, 207, 151),
    Red = Color3.fromRGB(224, 119, 119),
    Amber = Color3.fromRGB(226, 185, 112),
}

local AccentOptions = {
    Ice = Color3.fromRGB(155, 190, 225),
    Mint = Color3.fromRGB(135, 205, 178),
    Violet = Color3.fromRGB(177, 164, 222),
}

local Settings = {
    OpenKey = Enum.KeyCode.Insert,
    Compact = false,
    AccentName = "Ice",
    HitboxEnabled = false,
    HitboxX = 1.50,
    HitboxY = 1.50,
    HitboxZ = 1.25,
    HitboxTransparency = 0.50,
    HitboxColor = Color3.fromRGB(125, 185, 235),
}

local function create(className, parent, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    create("UICorner", parent, {
        CornerRadius = UDim.new(0, radius or 10),
    })
end

local function addStroke(parent, color, transparency)
    create("UIStroke", parent, {
        Color = color or Theme.Border,
        Transparency = transparency or 0,
        Thickness = 1,
    })
end

local function tween(object, properties, duration)
    if not object or not object.Parent then
        return
    end
    local info = TweenInfo.new(duration or 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local animation = TweenService:Create(object, info, properties)
    animation:Play()
    return animation
end

local function makeLabel(parent, value, position, size, fontSize, color, font, alignment)
    return create("TextLabel", parent, {
        BackgroundTransparency = 1,
        Position = position,
        Size = size,
        Text = value,
        Font = font or Enum.Font.Gotham,
        TextSize = fontSize or 12,
        TextColor3 = color or Theme.Text,
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local function makeButton(parent, value, position, size, accent)
    local button = create("TextButton", parent, {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
        Text = value,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Theme.Text,
    })
    addCorner(button, 8)
    addStroke(button)

    local normalColor = Theme.Card
    local hoverColor = accent and Color3.fromRGB(37, 47, 59) or Theme.CardHover

    button.MouseEnter:Connect(function()
        tween(button, {
            BackgroundColor3 = hoverColor,
            Size = size + UDim2.fromOffset(2, 2),
            Position = position - UDim2.fromOffset(1, 1),
        }, 0.12)
    end)

    button.MouseLeave:Connect(function()
        tween(button, {
            BackgroundColor3 = normalColor,
            Size = size,
            Position = position,
        }, 0.12)
    end)

    return button
end

local ScreenGui = create("ScreenGui", PlayerGui, {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 55,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local Main = create("Frame", ScreenGui, {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(760, 520),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
})
addCorner(Main, 16)
addStroke(Main)

create("UISizeConstraint", Main, {
    MinSize = Vector2.new(620, 440),
    MaxSize = Vector2.new(900, 650),
})

-- Header
local Header = create("Frame", Main, {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 70),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
})
addCorner(Header, 16)
create("Frame", Header, {
    Position = UDim2.new(0, 0, 1, -14),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
})

local Logo = create("Frame", Header, {
    Position = UDim2.fromOffset(19, 16),
    Size = UDim2.fromOffset(38, 38),
    BackgroundColor3 = Theme.CardHover,
    BorderSizePixel = 0,
})
addCorner(Logo, 11)
addStroke(Logo)
local LogoText = makeLabel(Logo, "V4", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 13, Theme.Accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)

makeLabel(Header, "V4ware", UDim2.fromOffset(68, 13), UDim2.fromOffset(170, 25), 19, Theme.Text, Enum.Font.GothamSemibold)
makeLabel(Header, "STUDIO QA  •  CLEAN CONTROL CENTER", UDim2.fromOffset(69, 38), UDim2.fromOffset(260, 15), 9, Theme.Muted, Enum.Font.GothamMedium)

local ReadyPill = create("Frame", Header, {
    Position = UDim2.new(1, -150, 0, 23),
    Size = UDim2.fromOffset(72, 24),
    BackgroundColor3 = Color3.fromRGB(24, 43, 36),
    BorderSizePixel = 0,
})
addCorner(ReadyPill, 12)
local ReadyDot = create("Frame", ReadyPill, {
    Position = UDim2.fromOffset(9, 8),
    Size = UDim2.fromOffset(7, 7),
    BackgroundColor3 = Theme.Green,
    BorderSizePixel = 0,
})
addCorner(ReadyDot, 8)
makeLabel(ReadyPill, "READY", UDim2.fromOffset(22, 0), UDim2.new(1, -24, 1, 0), 9, Theme.Green, Enum.Font.GothamBold)

local MinimizeButton = makeButton(Header, "–", UDim2.new(1, -69, 0, 21), UDim2.fromOffset(28, 28))
MinimizeButton.TextSize = 16
local CloseButton = makeButton(Header, "×", UDim2.new(1, -35, 0, 21), UDim2.fromOffset(28, 28))
CloseButton.TextSize = 17

-- Main body and sidebar
local Body = create("Frame", Main, {
    Position = UDim2.fromOffset(0, 70),
    Size = UDim2.new(1, 0, 1, -70),
    BackgroundTransparency = 1,
})

local Sidebar = create("Frame", Body, {
    Size = UDim2.new(0, 174, 1, 0),
    BackgroundColor3 = Theme.Sidebar,
    BorderSizePixel = 0,
})
create("Frame", Sidebar, {
    Position = UDim2.new(1, -1, 0, 0),
    Size = UDim2.new(0, 1, 1, 0),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0,
})

makeLabel(Sidebar, "WORKSPACE", UDim2.fromOffset(18, 18), UDim2.new(1, -36, 0, 15), 9, Theme.Dim, Enum.Font.GothamBold)

local NavHolder = create("Frame", Sidebar, {
    Position = UDim2.fromOffset(10, 47),
    Size = UDim2.new(1, -20, 0, 235),
    BackgroundTransparency = 1,
})
create("UIListLayout", NavHolder, {
    Padding = UDim.new(0, 7),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local BuildCard = create("Frame", Sidebar, {
    Position = UDim2.new(0, 12, 1, -58),
    Size = UDim2.new(1, -24, 0, 42),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
})
addCorner(BuildCard, 9)
makeLabel(BuildCard, "BUILD", UDim2.fromOffset(10, 5), UDim2.new(1, -20, 0, 12), 8, Theme.Dim, Enum.Font.GothamBold)
makeLabel(BuildCard, "V22  •  STUDIO QA", UDim2.fromOffset(10, 19), UDim2.new(1, -20, 0, 15), 9, Theme.Muted, Enum.Font.GothamMedium)

local Content = create("Frame", Body, {
    Position = UDim2.fromOffset(174, 0),
    Size = UDim2.new(1, -174, 1, 0),
    BackgroundTransparency = 1,
})

local Pages = {}
local NavItems = {}
local CurrentPage = "Overview"

local function createPage(name)
    local page = create("Frame", Content, {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    })
    Pages[name] = page
    return page
end

local OverviewPage = createPage("Overview")
local SystemPage = createPage("System")
local HitboxPage = createPage("HitboxLab")
local SettingsPage = createPage("Settings")
local ConsolePage = createPage("Console")

local function pageHeading(parent, title, subtitle)
    makeLabel(parent, title, UDim2.fromOffset(24, 16), UDim2.new(1, -48, 0, 29), 20, Theme.Text, Enum.Font.GothamSemibold)
    makeLabel(parent, subtitle, UDim2.fromOffset(25, 46), UDim2.new(1, -50, 0, 18), 10, Theme.Muted, Enum.Font.Gotham)
end

local function createNavItem(name, subtitle, glyph)
    local button = create("TextButton", NavHolder, {
        Name = name .. "Nav",
        Size = UDim2.new(1, 0, 0, 43),
        BackgroundColor3 = Theme.Sidebar,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #NavHolder:GetChildren() + 1,
    })
    addCorner(button, 9)

    local indicator = create("Frame", button, {
        Position = UDim2.fromOffset(0, 9),
        Size = UDim2.fromOffset(3, 25),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
    })
    addCorner(indicator, 3)

    local glyphLabel = makeLabel(button, glyph, UDim2.fromOffset(11, 0), UDim2.fromOffset(21, 42), 13, Theme.Muted, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
    local titleLabel = makeLabel(button, name, UDim2.fromOffset(39, 5), UDim2.new(1, -46, 0, 17), 11, Theme.Muted, Enum.Font.GothamSemibold)
    makeLabel(button, subtitle, UDim2.fromOffset(39, 22), UDim2.new(1, -46, 0, 13), 8, Theme.Dim, Enum.Font.Gotham)

    button.MouseEnter:Connect(function()
        if CurrentPage ~= name then
            tween(button, {BackgroundColor3 = Theme.Card, BackgroundTransparency = 0.25}, 0.12)
            tween(glyphLabel, {TextColor3 = Theme.Text}, 0.12)
        end
    end)
    button.MouseLeave:Connect(function()
        if CurrentPage ~= name then
            tween(button, {BackgroundTransparency = 1}, 0.12)
            tween(glyphLabel, {TextColor3 = Theme.Muted}, 0.12)
        end
    end)

    NavItems[name] = {
        Button = button,
        Indicator = indicator,
        Title = titleLabel,
        Glyph = glyphLabel,
    }
    return button
end

createNavItem("Overview", "Session summary", "⌂")
createNavItem("System", "Performance", "◫")
createNavItem("Hitbox Lab", "NPC visual testing", "▣")
createNavItem("Settings", "Preferences", "⚙")
createNavItem("Console", "Diagnostics", "≡")

local function createStatCard(parent, x, y, title, initial, glyph)
    local card = create("Frame", parent, {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(226, 91),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
    })
    addCorner(card, 11)
    local cardStroke = addStroke(card)

    local iconBox = create("Frame", card, {
        Position = UDim2.new(1, -42, 0, 12),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = Theme.CardHover,
        BorderSizePixel = 0,
    })
    addCorner(iconBox, 8)
    makeLabel(iconBox, glyph, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 12, Theme.Muted, Enum.Font.GothamSemibold, Enum.TextXAlignment.Center)
    makeLabel(card, title, UDim2.fromOffset(14, 12), UDim2.new(1, -62, 0, 14), 9, Theme.Muted, Enum.Font.GothamBold)
    local value = makeLabel(card, initial, UDim2.fromOffset(14, 38), UDim2.new(1, -28, 0, 30), 22, Theme.Text, Enum.Font.GothamSemibold)

    card.MouseEnter:Connect(function()
        tween(card, {BackgroundColor3 = Theme.CardHover}, 0.13)
        tween(cardStroke, {Transparency = 0.15, Color = Theme.Accent}, 0.13)
    end)
    card.MouseLeave:Connect(function()
        tween(card, {BackgroundColor3 = Theme.Card}, 0.13)
        tween(cardStroke, {Transparency = 0, Color = Theme.Border}, 0.13)
    end)

    return value
end

-- Overview page
pageHeading(OverviewPage, "Welcome to V4ware.", "A simple overview of your local Studio test session.")
local OverviewFPS = createStatCard(OverviewPage, 24, 82, "FRAME RATE", "--", "◴")
local OverviewPing = createStatCard(OverviewPage, 264, 82, "NETWORK PING", "-- ms", "⌁")
local OverviewMemory = createStatCard(OverviewPage, 24, 186, "CLIENT MEMORY", "-- MB", "▤")
local OverviewPlayers = createStatCard(OverviewPage, 264, 186, "PLAYERS IN SESSION", "--", "◎")

local OverviewSessionCard = create("Frame", OverviewPage, {
    Position = UDim2.fromOffset(24, 298),
    Size = UDim2.new(1, -48, 0, 78),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
})
addCorner(OverviewSessionCard, 11)
addStroke(OverviewSessionCard)
makeLabel(OverviewSessionCard, "SESSION STATUS", UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 14), 9, Theme.Muted, Enum.Font.GothamBold)
local OverviewStatus = makeLabel(OverviewSessionCard, "CLIENT READY  •  STUDIO QA MODE", UDim2.fromOffset(14, 28), UDim2.new(1, -28, 0, 17), 10, Theme.Text, Enum.Font.GothamSemibold)
local OverviewSession = makeLabel(OverviewSessionCard, "Session 00:00:00", UDim2.fromOffset(14, 51), UDim2.new(1, -28, 0, 13), 9, Theme.Muted, Enum.Font.Gotham)

-- System page
pageHeading(SystemPage, "System monitor", "Low-frequency client telemetry.")
local SystemFPS = createStatCard(SystemPage, 24, 82, "FRAME RATE", "--", "◴")
local SystemPing = createStatCard(SystemPage, 264, 82, "NETWORK PING", "-- ms", "⌁")
local SystemMemory = createStatCard(SystemPage, 24, 186, "CLIENT MEMORY", "-- MB", "▤")
local SystemPlayers = createStatCard(SystemPage, 264, 186, "PLAYERS IN SESSION", "--", "◎")

local SystemInfo = create("Frame", SystemPage, {
    Position = UDim2.fromOffset(24, 298),
    Size = UDim2.new(1, -48, 0, 78),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
})
addCorner(SystemInfo, 11)
addStroke(SystemInfo)
makeLabel(SystemInfo, "LIGHTWEIGHT MODE", UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 14), 9, Theme.Muted, Enum.Font.GothamBold)
makeLabel(SystemInfo, "No animated graphs  •  No blur  •  No per-frame UI refresh", UDim2.fromOffset(14, 29), UDim2.new(1, -28, 0, 17), 10, Theme.Text, Enum.Font.Gotham)
makeLabel(SystemInfo, "Metrics refresh once per second while Overview or System is open.", UDim2.fromOffset(14, 51), UDim2.new(1, -28, 0, 13), 9, Theme.Muted, Enum.Font.Gotham)

-- Hitbox Lab page: visual adornments on explicitly tagged NPC test dummies only.
pageHeading(HitboxPage, "Hitbox Lab", "Visual debug boxes for tagged NPC test dummies only.")

local HitboxInfo = create("Frame", HitboxPage, {
    Position = UDim2.fromOffset(24, 78),
    Size = UDim2.new(1, -48, 0, 58),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
})
addCorner(HitboxInfo, 10)
addStroke(HitboxInfo)
makeLabel(HitboxInfo, "VISUAL DEBUG ONLY", UDim2.fromOffset(13, 7), UDim2.new(1, -26, 0, 14), 9, Theme.Accent, Enum.Font.GothamBold)
makeLabel(HitboxInfo, "Only models tagged V4wareTestDummy are shown. Player characters are excluded.", UDim2.fromOffset(13, 27), UDim2.new(1, -26, 0, 18), 9, Theme.Muted, Enum.Font.Gotham)

local HitboxCard = create("Frame", HitboxPage, {
    Position = UDim2.fromOffset(24, 148),
    Size = UDim2.new(1, -48, 0, 212),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
})
addCorner(HitboxCard, 11)
addStroke(HitboxCard)

makeLabel(HitboxCard, "VISUALIZATION", UDim2.fromOffset(14, 11), UDim2.new(1, -28, 0, 14), 9, Theme.Muted, Enum.Font.GothamBold)

local HitboxToggle = makeButton(HitboxCard, "OFF", UDim2.new(1, -91, 0, 7), UDim2.fromOffset(76, 28), true)
local HitboxToggleLabel = makeLabel(HitboxCard, "Show test-dummy boxes", UDim2.fromOffset(14, 7), UDim2.new(1, -120, 0, 28), 10, Theme.Text, Enum.Font.GothamSemibold)

local function createValueField(parent, labelText, x, y, defaultValue)
    makeLabel(parent, labelText, UDim2.fromOffset(x, y), UDim2.fromOffset(105, 20), 10, Theme.Muted, Enum.Font.GothamMedium)
    local box = create("TextBox", parent, {
        Position = UDim2.fromOffset(x + 105, y - 1),
        Size = UDim2.fromOffset(76, 27),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Text = tostring(defaultValue),
        PlaceholderText = "1.00",
        ClearTextOnFocus = false,
        TextColor3 = Theme.Text,
        PlaceholderColor3 = Theme.Dim,
        TextSize = 10,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    addCorner(box, 7)
    addStroke(box)
    return box
end

local XField = createValueField(HitboxCard, "Scale X", 14, 56, Settings.HitboxX)
local YField = createValueField(HitboxCard, "Scale Y", 218, 56, Settings.HitboxY)
local ZField = createValueField(HitboxCard, "Scale Z", 14, 98, Settings.HitboxZ)
local TransparencyField = createValueField(HitboxCard, "Transparency", 218, 98, Settings.HitboxTransparency)

local ApplyHitboxButton = makeButton(HitboxCard, "APPLY VALUES", UDim2.fromOffset(14, 151), UDim2.fromOffset(142, 31), true)
local ResetHitboxButton = makeButton(HitboxCard, "RESET DEFAULTS", UDim2.fromOffset(164, 151), UDim2.fromOffset(142, 31))
local HitboxStatus = makeLabel(HitboxPage, "0 tagged test dummies found.", UDim2.fromOffset(25, 370), UDim2.new(1, -50, 0, 18), 9, Theme.Muted, Enum.Font.Gotham)

-- Settings page
pageHeading(SettingsPage, "Preferences", "Small adjustments to the control center.")
local SettingsHolder = create("Frame", SettingsPage, {
    Position = UDim2.fromOffset(24, 82),
    Size = UDim2.new(1, -48, 0, 260),
    BackgroundTransparency = 1,
})
create("UIListLayout", SettingsHolder, {
    Padding = UDim.new(0, 9),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local WaitingForKey = false

local function preferenceRow(title, description, initial, order)
    local row = create("Frame", SettingsHolder, {
        Size = UDim2.new(1, 0, 0, 55),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
        LayoutOrder = order,
    })
    addCorner(row, 10)
    addStroke(row)
    makeLabel(row, title, UDim2.fromOffset(13, 6), UDim2.new(1, -150, 0, 17), 10, Theme.Text, Enum.Font.GothamSemibold)
    makeLabel(row, description, UDim2.fromOffset(13, 27), UDim2.new(1, -150, 0, 14), 8, Theme.Muted, Enum.Font.Gotham)
    return makeButton(row, initial, UDim2.new(1, -124, 0.5, -15), UDim2.fromOffset(110, 30))
end

local KeyButton = preferenceRow("Panel shortcut", "Click and press a new keyboard key.", Settings.OpenKey.Name, 1)
local CompactButton = preferenceRow("Compact layout", "Reduce the panel footprint.", "OFF", 2)
local AccentButton = preferenceRow("Accent color", "Cycle through subtle accent colors.", Settings.AccentName, 3)
makeLabel(SettingsPage, "Tip: the Hitbox Lab draws local debug boxes only; it does not alter collisions.", UDim2.fromOffset(24, 350), UDim2.new(1, -48, 0, 25), 9, Theme.Muted, Enum.Font.Gotham)

-- Console page
pageHeading(ConsolePage, "Diagnostics", "Local status messages. Maximum 50 entries.")
local ClearLogButton = makeButton(ConsolePage, "CLEAR LOG", UDim2.new(1, -120, 0, 20), UDim2.fromOffset(96, 29))
ClearLogButton.TextSize = 9
local LogBox = create("ScrollingFrame", ConsolePage, {
    Position = UDim2.fromOffset(24, 65),
    Size = UDim2.new(1, -48, 1, -89),
    BackgroundColor3 = Theme.Card,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Dim,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
addCorner(LogBox, 10)
addStroke(LogBox)
create("UIPadding", LogBox, {
    PaddingTop = UDim.new(0, 10),
    PaddingBottom = UDim.new(0, 10),
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12),
})
local LogLayout = create("UIListLayout", LogBox, {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
})
local Logs = {}
local LogIndex = 0

local function addLog(message, kind)
    LogIndex += 1
    local color = Theme.Muted
    if kind == "ok" then color = Theme.Green end
    if kind == "warn" then color = Theme.Amber end
    if kind == "error" then color = Theme.Red end

    local entry = create("TextLabel", LogBox, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 0, 17),
        Text = string.format("[%s]  %s", os.date("%H:%M:%S"), tostring(message)),
        Font = Enum.Font.Code,
        TextSize = 10,
        TextColor3 = color,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        LayoutOrder = LogIndex,
    })
    table.insert(Logs, entry)

    while #Logs > 50 do
        local oldest = table.remove(Logs, 1)
        if oldest then oldest:Destroy() end
    end

    task.defer(function()
        if LogBox.Parent then
            LogBox.CanvasPosition = Vector2.new(0, math.max(0, LogLayout.AbsoluteContentSize.Y))
        end
    end)
end

ClearLogButton.MouseButton1Click:Connect(function()
    for _, entry in ipairs(Logs) do
        if entry then entry:Destroy() end
    end
    table.clear(Logs)
    addLog("Log cleared.", "ok")
end)

-- Notifications
local Toast = create("TextLabel", ScreenGui, {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -22, 1, -22),
    Size = UDim2.fromOffset(250, 36),
    BackgroundColor3 = Theme.CardHover,
    BorderSizePixel = 0,
    Text = "",
    TextColor3 = Theme.Text,
    TextSize = 10,
    Font = Enum.Font.GothamMedium,
    Visible = false,
    ZIndex = 20,
})
addCorner(Toast, 9)
addStroke(Toast)

local ToastToken = 0
local function notify(message)
    ToastToken += 1
    local currentToken = ToastToken
    Toast.Text = tostring(message)
    Toast.Visible = true
    task.delay(2, function()
        if Toast.Parent and ToastToken == currentToken then
            Toast.Visible = false
        end
    end)
end

-- Hitbox Lab internals: local-only adornments for tagged NPC test dummies.
local HitboxAdornments = {}

local function isPlayerCharacter(model)
    return model:IsA("Model") and Players:GetPlayerFromCharacter(model) ~= nil
end

local function getDummyRoot(model)
    if not model or not model:IsA("Model") or isPlayerCharacter(model) then
        return nil
    end
    if not CollectionService:HasTag(model, DUMMY_TAG) then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function destroyAdornment(model)
    local adornment = HitboxAdornments[model]
    if adornment then
        adornment:Destroy()
        HitboxAdornments[model] = nil
    end
end

local function updateAdornment(model)
    local root = getDummyRoot(model)
    if not Settings.HitboxEnabled or not root then
        destroyAdornment(model)
        return
    end

    local adornment = HitboxAdornments[model]
    if not adornment or not adornment.Parent then
        adornment = Instance.new("BoxHandleAdornment")
        adornment.Name = "V4wareLocalHitboxDebug"
        adornment.Adornee = root
        adornment.AlwaysOnTop = true
        adornment.ZIndex = 0
        adornment.Parent = Workspace
        HitboxAdornments[model] = adornment
    end

    adornment.Adornee = root
    adornment.Size = Vector3.new(
        math.max(0.1, root.Size.X * Settings.HitboxX),
        math.max(0.1, root.Size.Y * Settings.HitboxY),
        math.max(0.1, root.Size.Z * Settings.HitboxZ)
    )
    adornment.Color3 = Settings.HitboxColor
    adornment.Transparency = math.clamp(Settings.HitboxTransparency, 0, 1)
    adornment.Visible = true
end

local function countTaggedDummies()
    local count = 0
    for _, instance in ipairs(CollectionService:GetTagged(DUMMY_TAG)) do
        if getDummyRoot(instance) then
            count += 1
        end
    end
    return count
end

local function refreshHitboxes()
    local tagged = CollectionService:GetTagged(DUMMY_TAG)
    local alive = {}

    for _, model in ipairs(tagged) do
        if model:IsA("Model") then
            alive[model] = true
            updateAdornment(model)
        end
    end

    for model in pairs(HitboxAdornments) do
        if not alive[model] or not model.Parent then
            destroyAdornment(model)
        end
    end

    HitboxStatus.Text = string.format("%d tagged test dummy(s) found  •  Tag: %s", countTaggedDummies(), DUMMY_TAG)
end

local function clearAllHitboxes()
    for model in pairs(HitboxAdornments) do
        destroyAdornment(model)
    end
end

local function setHitboxEnabled(enabled)
    Settings.HitboxEnabled = enabled
    HitboxToggle.Text = enabled and "ON" or "OFF"
    HitboxToggle.BackgroundColor3 = enabled and Color3.fromRGB(24, 43, 36) or Theme.Card
    HitboxToggle.TextColor3 = enabled and Theme.Green or Theme.Text

    if enabled then
        refreshHitboxes()
        addLog("Local test-dummy visualization enabled.", "ok")
        notify("Hitbox visualization ON")
    else
        clearAllHitboxes()
        HitboxStatus.Text = string.format("%d tagged test dummy(s) found  •  visualization OFF", countTaggedDummies())
        addLog("Local test-dummy visualization disabled.", "ok")
        notify("Hitbox visualization OFF")
    end
end

local function parseNumber(field, fallback, minimum, maximum)
    local value = tonumber(string.gsub(field.Text, ",", "."))
    if not value then
        field.Text = tostring(fallback)
        return fallback
    end
    value = math.clamp(value, minimum, maximum)
    field.Text = string.format("%.2f", value)
    return value
end

local function applyHitboxValues()
    Settings.HitboxX = parseNumber(XField, Settings.HitboxX, 0.25, 5)
    Settings.HitboxY = parseNumber(YField, Settings.HitboxY, 0.25, 5)
    Settings.HitboxZ = parseNumber(ZField, Settings.HitboxZ, 0.25, 5)
    Settings.HitboxTransparency = parseNumber(TransparencyField, Settings.HitboxTransparency, 0, 1)

    if Settings.HitboxEnabled then
        refreshHitboxes()
    end

    addLog(string.format(
        "Visual scales applied: X %.2f / Y %.2f / Z %.2f / Transparency %.2f",
        Settings.HitboxX, Settings.HitboxY, Settings.HitboxZ, Settings.HitboxTransparency
    ), "ok")
    notify("Hitbox Lab values applied")
end

HitboxToggle.MouseButton1Click:Connect(function()
    setHitboxEnabled(not Settings.HitboxEnabled)
end)

ApplyHitboxButton.MouseButton1Click:Connect(applyHitboxValues)

ResetHitboxButton.MouseButton1Click:Connect(function()
    Settings.HitboxX = 1.50
    Settings.HitboxY = 1.50
    Settings.HitboxZ = 1.25
    Settings.HitboxTransparency = 0.50
    XField.Text = "1.50"
    YField.Text = "1.50"
    ZField.Text = "1.25"
    TransparencyField.Text = "0.50"
    applyHitboxValues()
    notify("Default values restored")
end)

-- React to tag changes without a permanent frame loop.
CollectionService:GetInstanceAddedSignal(DUMMY_TAG):Connect(function(instance)
    if Settings.HitboxEnabled and instance:IsA("Model") then
        updateAdornment(instance)
    end
    HitboxStatus.Text = string.format("%d tagged test dummy(s) found.", countTaggedDummies())
end)

CollectionService:GetInstanceRemovedSignal(DUMMY_TAG):Connect(function(instance)
    destroyAdornment(instance)
    HitboxStatus.Text = string.format("%d tagged test dummy(s) found.", countTaggedDummies())
end)

-- Navigation
local function setPage(name)
    CurrentPage = name
    for pageName, pageObject in pairs(Pages) do
        pageObject.Visible = pageName == name
    end

    for navName, item in pairs(NavItems) do
        local active = navName == name
        item.Indicator.Visible = active
        item.Button.BackgroundTransparency = active and 0 or 1
        item.Button.BackgroundColor3 = active and Theme.Panel or Theme.Sidebar
        item.Title.TextColor3 = active and Theme.Text or Theme.Muted
        item.Glyph.TextColor3 = active and Theme.Accent or Theme.Muted
    end

    if name == "Hitbox Lab" then
        HitboxStatus.Text = string.format("%d tagged test dummy(s) found  •  Tag: %s", countTaggedDummies(), DUMMY_TAG)
    end
end

for name, item in pairs(NavItems) do
    item.Button.MouseButton1Click:Connect(function()
        setPage(name)
    end)
end

-- Lightweight system metrics: sample once per second only on visible monitor pages.
local SessionStarted = os.clock()
local FrameCount = 0
local LastFPS = 0
local RenderConnection = nil

local function needsSampling()
    return ScreenGui.Enabled and Main.Visible and Body.Visible
        and (CurrentPage == "Overview" or CurrentPage == "System")
end

local function refreshFrameSampler()
    local wanted = needsSampling()
    if wanted and not RenderConnection then
        FrameCount = 0
        RenderConnection = RunService.RenderStepped:Connect(function()
            FrameCount += 1
        end)
    elseif not wanted and RenderConnection then
        RenderConnection:Disconnect()
        RenderConnection = nil
    end
end

local function readPing()
    local ok, value = pcall(function()
        local item = Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
        if not item then return nil end
        return math.floor(item:GetValue())
    end)
    if ok and value then return tostring(value) .. " ms" end
    return "N/A"
end

local function readMemory()
    local ok, value = pcall(function()
        return math.floor(Stats:GetTotalMemoryUsageMb())
    end)
    if ok and value then return tostring(value) .. " MB" end
    return "N/A"
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d",
        math.floor(seconds / 3600),
        math.floor((seconds % 3600) / 60),
        seconds % 60
    )
end

local function updateMetrics()
    if not needsSampling() then
        refreshFrameSampler()
        return
    end

    if RenderConnection then
        LastFPS = FrameCount
        FrameCount = 0
    end

    local fpsText = LastFPS > 0 and tostring(LastFPS) or "N/A"
    local pingText = readPing()
    local memoryText = readMemory()
    local playerText = tostring(#Players:GetPlayers())

    OverviewFPS.Text, SystemFPS.Text = fpsText, fpsText
    OverviewPing.Text, SystemPing.Text = pingText, pingText
    OverviewMemory.Text, SystemMemory.Text = memoryText, memoryText
    OverviewPlayers.Text, SystemPlayers.Text = playerText, playerText
    OverviewSession.Text = "Session " .. formatDuration(os.clock() - SessionStarted)
end

task.spawn(function()
    while ScreenGui.Parent do
        if needsSampling() then
            updateMetrics()
        else
            refreshFrameSampler()
        end
        task.wait(1)
    end
end)

-- Settings interactions
KeyButton.MouseButton1Click:Connect(function()
    WaitingForKey = true
    KeyButton.Text = "PRESS KEY..."
    notify("Press a key for the panel shortcut.")
end)

CompactButton.MouseButton1Click:Connect(function()
    Settings.Compact = not Settings.Compact
    CompactButton.Text = Settings.Compact and "ON" or "OFF"
    Main.Size = Settings.Compact and UDim2.fromOffset(680, 480) or UDim2.fromOffset(760, 520)
    notify(Settings.Compact and "Compact layout enabled." or "Standard layout enabled.")
end)

local function applyAccent()
    Theme.Accent = AccentOptions[Settings.AccentName]
    LogoText.TextColor3 = Theme.Accent
    for _, item in pairs(NavItems) do
        item.Indicator.BackgroundColor3 = Theme.Accent
    end
end

AccentButton.MouseButton1Click:Connect(function()
    if Settings.AccentName == "Ice" then
        Settings.AccentName = "Mint"
    elseif Settings.AccentName == "Mint" then
        Settings.AccentName = "Violet"
    else
        Settings.AccentName = "Ice"
    end
    AccentButton.Text = Settings.AccentName
    applyAccent()
    addLog("Accent changed to " .. Settings.AccentName .. ".", "ok")
    notify("Accent: " .. Settings.AccentName)
end)

-- Drag from the header.
do
    local dragging = false
    local dragStart = nil
    local startPosition = nil

    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(
                startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local Minimized = false
MinimizeButton.MouseButton1Click:Connect(function()
    Minimized = not Minimized
    Body.Visible = not Minimized
    Main.Size = Minimized and UDim2.fromOffset(760, 70)
        or (Settings.Compact and UDim2.fromOffset(680, 480) or UDim2.fromOffset(760, 520))
    MinimizeButton.Text = Minimized and "+" or "–"
    refreshFrameSampler()
end)

CloseButton.MouseButton1Click:Connect(function()
    Main.Visible = false
    refreshFrameSampler()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if WaitingForKey then
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
            Settings.OpenKey = input.KeyCode
            KeyButton.Text = Settings.OpenKey.Name
            WaitingForKey = false
            addLog("Shortcut changed to " .. Settings.OpenKey.Name .. ".", "ok")
            notify("Shortcut updated")
        end
        return
    end

    if gameProcessed then return end

    if input.KeyCode == Settings.OpenKey then
        if Minimized then
            Minimized = false
            Body.Visible = true
            Main.Size = Settings.Compact and UDim2.fromOffset(680, 480) or UDim2.fromOffset(760, 520)
            MinimizeButton.Text = "–"
        else
            Main.Visible = not Main.Visible
        end
        refreshFrameSampler()
    end
end)

Main:GetPropertyChangedSignal("Visible"):Connect(refreshFrameSampler)

-- Startup
setPage("Overview")
HitboxStatus.Text = string.format("%d tagged test dummy(s) found  •  Tag: %s", countTaggedDummies(), DUMMY_TAG)
addLog("V4ware V22 Studio QA initialized.", "ok")
addLog("Hitbox Lab is visual-only and restricted to tagged NPC test dummies.", "ok")
refreshFrameSampler()

print("[V4ware V22] Studio QA panel ready.")
