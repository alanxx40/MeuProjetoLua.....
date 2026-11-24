-- V4WARE V21.4 - LITE DASHBOARD (base V20.5, preferencias de UI separadas)
-- Este arquivo pressupoe que a tabela global Config ja existe no ambiente que o carrega.
-- Mantenha a configuracao no arquivo/trecho local e hospede este arquivo como Main.lua.
-- =============================================================
-- V4WARE FASTFLAGS: VALORES CONVERTIDOS PARA LUA E APLICACAO VIA EXECUTOR
-- Executado antes dos modulos do V4WARE. Nao consulta lista externa de flags.
-- =============================================================
local env = (type(getgenv) == "function" and getgenv()) or _G

local V4wareFastFlags = {
    ["FFlagAuroraRollbackAttributeChangedSignals"] = false,
    ["DFIntMaxFrameBufferSize"] = 4,
    ["DFIntRenderingThrottleDelayInMS"] = 0,
    ["FFlagGameBasicSettingsFramerateCap5"] = false,
    ["DFIntTaskSchedulerTargetFps"] = 500,
    ["FFlagApplicationFrameRatePolicy3"] = false,
    ["FFlagApplicationFrameRateClampToDisplay"] = false,
    ["FLogApplicationFrameRate"] = 0,
    ["FIntActivatedCountTimerMSGamepad"] = 1,
    ["DFLogAuroraRollback"] = 1,
    ["DFIntAuroraClientInputBufferSize"] = 3,
    ["FFlagAckPaceEnabled"] = false,
    ["FIntAckPaceRttFloorMs"] = 0,
    ["FFlagDebugSkyGray"] = true,
    ["DFIntDebugFRMQualityLevelOverride"] = 1,
    ["FIntDebugForceMSAASamples"] = -1,
    ["DFIntDataSenderRate"] = 220,
    ["DFIntS2PhysicsSenderRate"] = 220,
    ["FIntActivatedCountTimerMSKeyboard"] = 1,
    ["FIntActivatedCountTimerMSMouse"] = 1,
    ["DFIntAuroraInputLatencySmoothTimeMillisecondsDownwards"] = 100,
    ["DFIntAuroraInputFrameCount"] = 3,
    ["DFIntAuroraInputLatencySmoothTimeMillisecondsUpwards"] = 100,
    ["DFIntAngularVelociryLimit"] = 0,
    ["DFIntAccelerationTimeThreshold"] = 0,
    -- AnimationLodThrottleMaxFramesToSkip: nome/tipo e valor ainda nao confirmados.
}

env.V4wareFastFlags = V4wareFastFlags

local fastFlagNames = {}
for flagName in pairs(V4wareFastFlags) do
    table.insert(fastFlagNames, flagName)
end
table.sort(fastFlagNames)

local setFastFlag = env.setfflag
if type(setFastFlag) ~= "function" and type(_G) == "table" then
    setFastFlag = _G.setfflag
end
if type(setFastFlag) ~= "function" and type(setfflag) == "function" then
    setFastFlag = setfflag
end

local getFastFlag = env.getfflag
if type(getFastFlag) ~= "function" and type(_G) == "table" then
    getFastFlag = _G.getfflag
end
if type(getFastFlag) ~= "function" and type(getfflag) == "function" then
    getFastFlag = getfflag
end

local fastFlagStatus = {
    Available = type(setFastFlag) == "function",
    ReadbackAvailable = type(getFastFlag) == "function",
    Total = #fastFlagNames,
    Accepted = 0,
    Verified = 0,
    Unverified = 0,
    Mismatched = 0,
    Rejected = 0,
    NotAttempted = 0,
    Results = {},
}

if fastFlagStatus.Available then
    for _, flagName in ipairs(fastFlagNames) do
        local flagValue = V4wareFastFlags[flagName]
        local expectedValue = string.lower(tostring(flagValue))
        local ok, result = pcall(setFastFlag, flagName, tostring(flagValue))

        if ok and result ~= false then
            fastFlagStatus.Accepted = fastFlagStatus.Accepted + 1
            if fastFlagStatus.ReadbackAvailable then
                local readOk, currentValue = pcall(getFastFlag, flagName)
                if readOk and currentValue ~= nil then
                    if string.lower(tostring(currentValue)) == expectedValue then
                        fastFlagStatus.Verified = fastFlagStatus.Verified + 1
                        fastFlagStatus.Results[flagName] = "VERIFIED"
                    else
                        fastFlagStatus.Mismatched = fastFlagStatus.Mismatched + 1
                        fastFlagStatus.Results[flagName] = "VALUE_MISMATCH: " .. tostring(currentValue)
                    end
                else
                    fastFlagStatus.Unverified = fastFlagStatus.Unverified + 1
                    fastFlagStatus.Results[flagName] = "REQUEST_SENT_UNVERIFIED"
                end
            else
                fastFlagStatus.Unverified = fastFlagStatus.Unverified + 1
                fastFlagStatus.Results[flagName] = "REQUEST_SENT_UNVERIFIED"
            end
        else
            fastFlagStatus.Rejected = fastFlagStatus.Rejected + 1
            fastFlagStatus.Results[flagName] = ok and "REJECTED_BY_EXECUTOR" or ("ERROR: " .. tostring(result))
        end
    end
else
    fastFlagStatus.NotAttempted = fastFlagStatus.Total
    for _, flagName in ipairs(fastFlagNames) do
        fastFlagStatus.Results[flagName] = "SETFFLAG_UNAVAILABLE"
    end
end

env.DHC_FastFlagsStatus = function()
    return fastFlagStatus
end

if not fastFlagStatus.Available then
    warn(string.format("[V4ware FastFlags] setfflag indisponivel. %d flags carregadas em Lua; nenhuma enviada ao cliente.", fastFlagStatus.Total))
else
    print(string.format(
        "[V4ware FastFlags] %d/%d requisicoes aceitas; %d verificadas por leitura; %d sem verificacao; %d rejeitadas. Consulte getgenv().DHC_FastFlagsStatus().",
        fastFlagStatus.Accepted,
        fastFlagStatus.Total,
        fastFlagStatus.Verified,
        fastFlagStatus.Unverified,
        fastFlagStatus.Rejected
    ))
end


-- =============================================================
-- SERVICOS, ESTADO E LIMPEZA DE EXECUCOES ANTERIORES
-- =============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local sessionStartedAt = os.clock()

local oldCfg = env.DHC_Config
if type(env.DHC_Stop) == "function" then
    pcall(env.DHC_Stop)
end
if type(oldCfg) == "table" then
    if oldCfg.Triggerbot and oldCfg.Triggerbot.Whitelist and type(oldCfg.Triggerbot.Whitelist.List) == "table" then
        Config.Triggerbot.Whitelist.List = oldCfg.Triggerbot.Whitelist.List
    end
    if type(oldCfg.IncognitoWhitelist) == "table" then
        Config.IncognitoWhitelist = oldCfg.IncognitoWhitelist
    end
end

env.DHC_Config = Config

-- Normaliza a configuracao do Hitbox Expander para que o painel e o modulo
-- leiam/escrevam exatamente a mesma tabela durante a sessao.
if type(Config.HitboxExpander) ~= "table" then
    Config.HitboxExpander = {}
end
Config.HitboxExpander.Enabled = Config.HitboxExpander.Enabled == true
Config.HitboxExpander.X = tonumber(Config.HitboxExpander.X) or 2
Config.HitboxExpander.Y = tonumber(Config.HitboxExpander.Y) or 2
Config.HitboxExpander.Z = tonumber(Config.HitboxExpander.Z) or 1
Config.HitboxExpander.RefreshTime = math.max(0.05, tonumber(Config.HitboxExpander.RefreshTime) or 1)
Config.HitboxExpander.Visible = Config.HitboxExpander.Visible == true
Config.HitboxExpander.Transparency = math.clamp(tonumber(Config.HitboxExpander.Transparency) or 0.5, 0, 1)
if typeof(Config.HitboxExpander.Color) ~= "Color3" then
    Config.HitboxExpander.Color = Color3.fromRGB(255, 60, 60)
end

-- Intervalo do ESP: padrao de 0.1s (10 atualizacoes por segundo).
-- Pode ser ajustado pela Config.ESP.RefreshTime, respeitando o minimo de 0.05s.
if type(Config.ESP) ~= "table" then
    Config.ESP = {}
end
Config.ESP.RefreshTime = math.clamp(tonumber(Config.ESP.RefreshTime) or 0.1, 0.05, 1)

local spectateTarget = nil
local spectateOldType = nil
local spectateOldSubject = nil
local running = true
local connections = {}
local espObjects = {}
local hitboxOriginal = {}
local spreadOriginal = {} -- [funcao] = { gun="...", values={[indice]=valor_original} }
local spreadPatched = { ["[Double-Barrel SG]"] = 0, ["[TacticalShotgun]"] = 0, ["[Revolver]"] = 0 }
local spreadCandidatesSeen = 0
local spreadAttempted = false
local spreadLastError = nil
local triggerActive = false
-- Weapon Switch: uma tecla executa a sequencia de armas, sem alterar cooldowns do jogo.
local weaponSwitchBusy = false
local weaponSwitchLastStart = -1e9
local weaponSwitchLastResult = "Ainda nao acionado"
local weaponSwitchLastError = nil
local weaponSwitchLastAttempts = 0
local weaponSwitchLastSkipped = 0
local rightMouseHeld = false
local espActive = Config.ESP.Enabled
local camActive = false
local camTarget = nil
local lastShot = 0
local nextESP = 0
local nextHitbox = 0
local nextSpread = 0
local nextReset = 0
local warnedHitbox = false
local warnedSpread = false
local spreadMatches = spreadPatched

local function connectSignal(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function charOf(player)
    return player and player.Character or nil
end

local function humanoidOf(character)
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function rootOf(character)
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function equippedTool()
    local character = charOf(LocalPlayer)
    return character and character:FindFirstChildOfClass("Tool") or nil
end

local function camera()
    return Workspace.CurrentCamera
end

local function pressed(input, key)
    return input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode == Enum.KeyCode[tostring(key)]
end

local function knife(tool)
    if not tool then return false end
    for _, name in ipairs(Config.Triggerbot.KnifeNames) do
        if string.find(string.lower(tool.Name), string.lower(name), 1, true) then
            return true
        end
    end
    return false
end

local function flag(character, name)
    if not character then return false end
    if character:GetAttribute(name) == true then return true end
    local thing = character:FindFirstChild(name, true)
    return thing ~= nil and thing:IsA("BoolValue") and thing.Value == true
end

local function knocked(character)
    return flag(character, "K.O") or flag(character, "Knocked") or flag(character, "KO")
end

local function grabbed(character)
    return flag(character, "Grabbed")
        or (character ~= nil and character:FindFirstChild("GRABBING_CONSTRAINT", true) ~= nil)
end

local function crew(player)
    local folder = player and player:FindFirstChild("DataFolder")
    local info = folder and folder:FindFirstChild("Information")
    local value = info and info:FindFirstChild("Crew")
    if value and value:IsA("StringValue") then return value.Value end
    return nil
end

local function isInList(list, player)
    if type(list) ~= "table" or not player then return false end
    if list[player.Name] == true or list[player.UserId] == true or list[tostring(player.UserId)] == true then
        return true
    end
    for key, value in pairs(list) do
        if (value == true and (tostring(key) == player.Name or tostring(key) == tostring(player.UserId)))
            or (value ~= true and (tostring(value) == player.Name or tostring(value) == tostring(player.UserId))) then
            return true
        end
    end
    return false
end

local function isWhitelisted(player)
    local w = Config.Triggerbot.Whitelist
    return w.Enabled and isInList(w.List, player)
end

local function isIncognito(player)
    return isInList(Config.IncognitoWhitelist, player)
end

-- Whitelist da interface e PROTECAO: jogadores marcados nao viram alvo.
local function onWhitelist(player)
    return not isWhitelisted(player) and not isIncognito(player)
end

local function passes(player, checks, alreadyWhitelisted)
    if not player or player == LocalPlayer or (not alreadyWhitelisted and not onWhitelist(player)) then return false end
    local character = charOf(player)
    local hum = humanoidOf(character)
    if not character or not hum or hum.Health <= 0 then return false end
    checks = checks or {}
    if checks.ForceField and character:FindFirstChildOfClass("ForceField") then return false end
    if checks.Knocked and knocked(character) then return false end
    if checks.Grabbed and grabbed(character) then return false end
    if checks.SelfKnocked and knocked(charOf(LocalPlayer)) then return false end
    if checks.Friend then
        local ok, yes = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
        if ok and yes then return false end
    end
    if checks.Crew then
        local mine, theirs = crew(LocalPlayer), crew(player)
        if mine and mine ~= "" and mine == theirs then return false end
    end
    return true
end

-- RaycastParams compartilhado: evita criar parametros e tabelas a cada frame.
-- O filtro so e atualizado quando o personagem local muda (respawn).
local playerRaycastParams = RaycastParams.new()
playerRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
playerRaycastParams.IgnoreWater = true
local raycastFilterCharacter = nil

local function syncPlayerRaycastFilter()
    local character = charOf(LocalPlayer)
    if character ~= raycastFilterCharacter then
        raycastFilterCharacter = character
        playerRaycastParams.FilterDescendantsInstances = character and { character } or {}
    end
end

local function visible(part, character)
    local cam = camera()
    if not cam or not part then return false end
    local difference = part.Position - cam.CFrame.Position
    if difference.Magnitude < 0.01 then return true end
    syncPlayerRaycastFilter()
    local hit = Workspace:Raycast(cam.CFrame.Position, difference, playerRaycastParams)
    return hit == nil or (character and hit.Instance:IsDescendantOf(character))
end

local function playerFromPart(part)
    local item = part
    while item and item ~= Workspace do
        if item:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(item)
            if player then return player end
        end
        item = item.Parent
    end
    return nil
end

local function aimPart(character)
    local cam = camera()
    if not cam or not character then return nil, math.huge end
    local mousePos = UserInputService:GetMouseLocation()
    local candidate, distance = nil, math.huge
    local names = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }
    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local onScreenPos, onScreen = cam:WorldToViewportPoint(part.Position)
            if onScreen then
                local d = (Vector2.new(onScreenPos.X, onScreenPos.Y) - mousePos).Magnitude
                if d < distance then
                    distance, candidate = d, part
                end
            end
        end
    end
    return candidate, distance
end

-- =============================================================
-- CAMLOCK (CLIENT-SIDE CAMERA)
-- =============================================================
local function findCamTarget()
    local bestPlayer = nil
    local distance = math.max(0, tonumber(Config.Camlock.FOV.Size) or 30)
    for _, player in ipairs(Players:GetPlayers()) do
        if passes(player, { ForceField = true, SelfKnocked = true }) then
            local part, d = aimPart(charOf(player))
            if part and d <= distance then
                if not Config.Camlock.Checks.Wall or visible(part, charOf(player)) then
                    bestPlayer, distance = player, d
                end
            end
        end
    end
    return bestPlayer
end

local function camAllowed()
    if spectateTarget or not Config.Camlock.Enabled or not camActive then return false end
    if Config.Camlock.Checks.RightClicking and not rightMouseHeld then return false end
    if Config.Camlock.Checks.Knife and knife(equippedTool()) then return false end
    local cam = camera()
    local char = charOf(LocalPlayer)
    local head = char and char:FindFirstChild("Head")
    if not cam or not head then return false end
    local fp = (cam.CFrame.Position - head.Position).Magnitude <= 1.6
    if fp and not Config.Camlock.Checks.FirstPerson then return false end
    if not fp and not Config.Camlock.Checks.ThirdPerson then return false end
    return true
end

local function updateCam(dt)
    if not camAllowed() then return end
    if not camTarget or not passes(camTarget) then
        camTarget = findCamTarget()
    end
    if not camTarget then return end
    local character = charOf(camTarget)
    local part = aimPart(character)
    if not part then camTarget = nil return end
    if Config.Camlock.Checks.Wall and not visible(part, character) then
        if not Config.Camlock.Sticky then camTarget = nil end
        return
    end
    local dest = part.Position
    local targetHumanoid = humanoidOf(character)
    local airborne = targetHumanoid and targetHumanoid.FloorMaterial == Enum.Material.Air
    if Config.Camlock.Prediction.Enabled then
        local ahead = airborne and Config.Camlock.Prediction.Air or Config.Camlock.Prediction.Ground
        dest = dest + part.AssemblyLinearVelocity * (tonumber(ahead) or 0)
    end
    local cam = camera()
    if not cam or (dest - cam.CFrame.Position).Magnitude < 0.01 then return end
    local goal = CFrame.lookAt(cam.CFrame.Position, dest)
    if Config.Camlock.Smoothing.Enabled then
        local s = airborne and Config.Camlock.Smoothing.Air or Config.Camlock.Smoothing.Ground
        s = math.clamp((tonumber(s) or 0) * (tonumber(Config.Camlock.Scale) or 1), 0, 1)
        local alpha = 1 - math.pow(1 - s, math.max(dt, 0) * 60)
        cam.CFrame = cam.CFrame:Lerp(goal, alpha)
    else
        cam.CFrame = goal
    end
end

-- =============================================================
-- TRIGGERBOT (TENTA ACIONAR TOOL; NAO IGNORA VALIDACOES DO JOGO)
-- =============================================================
local function attemptShot(tool)
    -- Mantem Tool:Activate e as validacoes/cooldowns naturais do jogo.
    -- Passar a funcao e o self diretamente evita criar uma closure a cada disparo.
    local ok = pcall(tool.Activate, tool)
    if ok then lastShot = os.clock() end
end

local function updateTrigger()
    if weaponSwitchBusy then return end
    if not Config.Triggerbot.Enabled or not triggerActive then return end

    local now = os.clock()
    local clientDelay = math.max(0, tonumber(Config.Triggerbot.FireDelay) or 0)
    if clientDelay > 0 and now - lastShot < clientDelay then return end

    local tool = equippedTool()
    if not tool or knife(tool) then return end

    local range = Config.Triggerbot["Range-Check"]
    local maxDist = range.Data[tool.Name]
    if range.Enabled and maxDist == nil then return end

    local cam = camera()
    if not cam then return end

    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local length = math.clamp(tonumber(maxDist) or 0, 0, math.max(1, tonumber(range.HardCap) or 280))
    if length <= 0 then return end

    syncPlayerRaycastFilter()
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * length, playerRaycastParams)
    if not hit then return end

    local target = playerFromPart(hit.Instance)
    if not target or not onWhitelist(target) then return end

    -- Checagem de distancia sem Magnitude (evita a raiz quadrada).
    local myRoot = rootOf(charOf(LocalPlayer))
    local targetRoot = rootOf(charOf(target))
    if not myRoot or not targetRoot then return end
    local offset = targetRoot.Position - myRoot.Position
    if offset:Dot(offset) > length * length then return end

    -- Combina as validacoes comuns e as opcionais em uma unica passagem.
    -- A whitelist ja foi verificada acima, portanto nao e consultada novamente.
    local checks = Config.Triggerbot.Hitbox.Enabled and Config.Triggerbot.Hitbox.Checks or nil
    if not passes(target, checks, true) then return end

    -- Preserva o filtro Visible original. Os parametros do Raycast ja sao reutilizados.
    if Config.Triggerbot.Hitbox.Checks.Visible and not visible(hit.Instance, charOf(target)) then return end

    attemptShot(tool)
end

-- =============================================================
-- ESP: HIGHLIGHT + NOME, VISUALIZACAO CLIENTE
-- =============================================================
local function clearESP(player)
    local entry = espObjects[player]
    if not entry then return end
    if entry.tag then entry.tag:Destroy() end
    if entry.highlight then entry.highlight:Destroy() end
    espObjects[player] = nil
end

local function refreshESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = charOf(player)
            local head = char and char:FindFirstChild("Head")
            local hum = humanoidOf(char)
            local entry = espObjects[player]
            if not espActive or not Config.ESP.Enabled or isIncognito(player) or not head or not hum or hum.Health <= 0 then
                clearESP(player)
            elseif not entry or entry.character ~= char then
                clearESP(player)
                local h = Instance.new("Highlight")
                h.Name = "DHC_ESP_Highlight"
                h.Adornee = char
                h.FillTransparency = 0.85
                h.OutlineTransparency = 0
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = char

                local gui = Instance.new("BillboardGui")
                gui.Name = "DHC_ESP_Name"
                gui.Adornee = head
                gui.Size = UDim2.fromOffset(180, 28)
                gui.StudsOffset = Vector3.new(0, 2.6, 0)
                gui.AlwaysOnTop = true
                gui.Parent = head

                local label = Instance.new("TextLabel")
                label.Name = "Name"
                label.BackgroundTransparency = 1
                label.Size = UDim2.fromScale(1, 1)
                label.Font = Enum.Font.GothamBold
                label.TextColor3 = Color3.new(1, 1, 1)
                label.TextStrokeTransparency = 0.4
                label.TextSize = tonumber(Config.ESP.Size) or 8
                label.Text = player.DisplayName
                label.Parent = gui
                espObjects[player] = {character = char, highlight = h, tag = gui, label = label}
            else
                entry.label.TextSize = tonumber(Config.ESP.Size) or 8
            end
        end
    end
end

-- =============================================================
-- HITBOX EXPANDER: SOMENTE ALTERACAO LOCAL DO HUMANOIDROOTPART
-- =============================================================
local function restoreHitboxes()
    for part, old in pairs(hitboxOriginal) do
        if part.Parent then
            pcall(function()
                part.Size = old.Size
                part.Transparency = old.Transparency
                part.Color = old.Color
                part.CanCollide = old.CanCollide
            end)
        end
        hitboxOriginal[part] = nil
    end
end

local function updateHitboxes()
    local cfg = Config.HitboxExpander
    if not cfg.Enabled then
        if next(hitboxOriginal) then restoreHitboxes() end
        return
    end
    if cfg.BloodBypass and not warnedHitbox then
        warnedHitbox = true
        warn("[DHC] BloodBypass: flag mantida, mas sem implementacao (logica original oculta).")
    end
    local size = Vector3.new(
        math.clamp(tonumber(cfg.X) or 14, 1, 50),
        math.clamp(tonumber(cfg.Y) or 14, 1, 50),
        math.clamp(tonumber(cfg.Z) or 14, 1, 50)
    )
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local part = rootOf(charOf(player))
            if part and part:IsA("BasePart") then
                if not hitboxOriginal[part] then
                    hitboxOriginal[part] = {
                        Size = part.Size, Color = part.Color,
                        Transparency = part.Transparency, CanCollide = part.CanCollide,
                    }
                end
                pcall(function()
                    part.Size = size
                    part.CanCollide = false
                    part.Color = cfg.Color
                    part.Transparency = cfg.Visible and math.clamp(cfg.Transparency, 0, 1) or 1
                end)
            end
        end
    end
end

-- =============================================================
-- SPREAD V8: REAPLICACAO DINAMICA DOS MULTIPLICADORES CONFIGURADOS
-- =============================================================
-- Mantem os valores originais por funcao. Assim, alterar Config.SpreadModification.Guns
-- durante a execucao reaplica o multiplicador sem depender dos valores ja modificados.
-- A deteccao continua limitada as assinaturas confirmadas no bytecode analisado.
local function isNear(x, target)
    return type(x) == "number" and math.abs(x - target) < 1e-6
end

local function readConsts(fn, getter)
    local ok, vals = pcall(getter, fn)
    if ok and type(vals) == "table" then return vals end
    return nil
end

local function getConstApi()
    local getter = debug and debug.getconstants or getconstants
    local setter = debug and debug.setconstant or setconstant
    if type(getgc) ~= "function" or type(getter) ~= "function" or type(setter) ~= "function" then
        return nil, nil, "Executor sem getgc/debug.getconstants/debug.setconstant"
    end
    return getter, setter, nil
end

local function functionSource(fn)
    local infoApi = debug and debug.getinfo
    if type(infoApi) ~= "function" then return "" end
    local ok, info = pcall(infoApi, fn)
    if not ok or type(info) ~= "table" then return "" end
    return tostring(info.source or info.short_src or "")
end

local function gunFromConsts(vals, fn)
    -- Primeiro tenta identificar a origem da funcao pelo script-fonte.
    -- Isso evita classificar a Double-Barrel como Tactical apenas por constantes compartilhadas.
    local source = functionSource(fn)
    if source:find("DB_GunClient", 1, true)
        or source:find("[Double-Barrel SG]", 1, true) then
        return "[Double-Barrel SG]"
    end
    if source:find("Tactical_GunClient", 1, true)
        or source:find("[TacticalShotgun]", 1, true) then
        return "[TacticalShotgun]"
    end

    local has = {}
    local p03, p06, p015 = false, false, false
    for _, value in pairs(vals) do
        if type(value) == "string" then has[value] = true end
        if isNear(value, 0.03) then p03 = true end
        if isNear(value, 0.06) then p06 = true end
        if isNear(value, 0.015) then p015 = true end
    end

    -- O bytecode exportado de DB_GunClient nao contem a string CTS.
    -- DB usa 0.03/0.06; Tactical tambem apresenta 0.015.
    if not (has.random and has.Vector3 and has.LocalMousePos and has.HandleRayCasting
            and has.Muzzle and has.Unit and has.Range and p03 and p06) then
        return nil
    end
    return p015 and "[TacticalShotgun]" or "[Double-Barrel SG]"
end

local function restoreSpread()
    local _, setter = getConstApi()
    if not setter then return end
    for fn, data in pairs(spreadOriginal) do
        for idx, old in pairs(data.values) do
            pcall(setter, fn, idx, old)
        end
    end
    for fn in pairs(spreadOriginal) do
        spreadOriginal[fn] = nil
    end
    spreadPatched["[Double-Barrel SG]"] = 0
    spreadPatched["[TacticalShotgun]"] = 0
end

local function applySpreadEntry(fn, entry, mult, getter, setter)
    local changed = 0
    for idx, original in pairs(entry.values) do
        local target = original * mult
        local setOk, setErr = pcall(setter, fn, idx, target)
        if setOk then
            local check = readConsts(fn, getter)
            if check and isNear(check[idx], target) then
                changed = changed + 1
            else
                spreadLastError = "setconstant nao confirmou leitura de retorno"
            end
        else
            spreadLastError = tostring(setErr or "setconstant falhou")
        end
    end
    return changed
end

local function updateSpread()
    local cfg = Config.SpreadModification
    if not cfg.Enabled then
        if next(spreadOriginal) then restoreSpread() end
        return
    end

    local supportedSpreadPlaces = {
        [97124701004636] = true,
        [119280064370189] = true,
    }
    if not supportedSpreadPlaces[game.PlaceId] then
        spreadLastError = "PlaceId nao corresponde a uma experiencia analisada"
        if not warnedSpread then
            warnedSpread = true
            warn("[V4ware V20] Experiencia nao corresponde ao Pain Hood analisado; spread nao modificado.")
        end
        return
    end

    local getter, setter, apiError = getConstApi()
    if apiError then
        spreadLastError = apiError
        if not warnedSpread then
            warnedSpread = true
            warn("[V4ware V20] Spread inativo: " .. apiError)
        end
        return
    end

    spreadAttempted = true
    spreadLastError = nil
    spreadPatched["[Double-Barrel SG]"] = 0
    spreadPatched["[TacticalShotgun]"] = 0

    local gcOk, objects = pcall(getgc, true)
    if not gcOk or type(objects) ~= "table" then
        gcOk, objects = pcall(getgc)
    end
    if not gcOk or type(objects) ~= "table" then
        spreadLastError = "getgc nao retornou funcoes"
        warn("[V4ware V20] Spread inativo: " .. spreadLastError)
        return
    end

    local matches, changed = 0, 0
    local seen = {}
    for _, fn in pairs(objects) do
        if type(fn) == "function" then
            local entry = spreadOriginal[fn]
            if entry then
                -- Funcao ja identificada: reaplica usando os valores originais guardados,
                -- mesmo que a constante atual ja seja 0 ou outro multiplicador.
                seen[fn] = true
                matches = matches + 1
                local mult = tonumber(cfg.Guns[entry.gun])
                if mult then
                    local n = applySpreadEntry(fn, entry, mult, getter, setter)
                    spreadPatched[entry.gun] = (spreadPatched[entry.gun] or 0) + n
                    changed = changed + n
                end
            else
                local vals = readConsts(fn, getter)
                if vals then
                    local gun = gunFromConsts(vals, fn)
                    if gun then
                        local entryNew = { gun = gun, values = {} }
                        for idx, value in pairs(vals) do
                            if type(idx) == "number" and
                               (isNear(value, 0.03) or isNear(value, 0.06) or isNear(value, 0.015)) then
                                entryNew.values[idx] = value
                            end
                        end
                        if next(entryNew.values) then
                            spreadOriginal[fn] = entryNew
                            seen[fn] = true
                            matches = matches + 1
                            local mult = tonumber(cfg.Guns[gun])
                            if mult then
                                local n = applySpreadEntry(fn, entryNew, mult, getter, setter)
                                spreadPatched[gun] = (spreadPatched[gun] or 0) + n
                                changed = changed + n
                            end
                        end
                    end
                end
            end
        end
    end

    spreadCandidatesSeen = matches
    if matches == 0 then
        spreadLastError = spreadLastError or "nenhuma funcao correspondeu a assinatura conhecida; bytecode pode ter mudado"
    end

    if not warnedSpread then
        warnedSpread = true
        if changed > 0 then
            warn(("[V4ware V20] %d constantes ajustadas em %d funcao(oes) identificada(s). Resultado visual/servidor ainda precisa de validacao.")
                :format(changed, matches))
        else
            warn("[V4ware V20] Nenhuma constante ativa foi alterada: " .. tostring(spreadLastError or "sem constantes confirmadas"))
        end
        warn(("[V4ware V20] Contagem por arma: DB=%d | Tactical=%d | Revolver=%d")
            :format(spreadPatched["[Double-Barrel SG]"] or 0,
                    spreadPatched["[TacticalShotgun]"] or 0,
                    spreadPatched["[Revolver]"] or 0))
        warn("[V4ware V20] Revolver permanece sem identificacao confirmada no bytecode analisado.")
    end
end

-- =============================================================
-- MOVIMENTO, ORDEM DE ARMAS, TELEPORTES
-- =============================================================
local function sortInventory()
    if not Config.InventorySorter.Enabled then return end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return end
    local list, rank = {}, {}
    for order, name in ipairs(Config.InventorySorter.Order) do rank[name] = order end
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then table.insert(list, item) end
    end
    table.sort(list, function(a, b)
        local aRank, bRank = rank[a.Name] or 9999, rank[b.Name] or 9999
        if aRank ~= bRank then return aRank < bRank end
        return a.Name < b.Name
    end)
    -- Tentativa local de reordenar Backpack (a UI do jogo pode ignorar).
    for _, item in ipairs(list) do item.Parent = nil end
    for _, item in ipairs(list) do item.Parent = backpack end
end

local function autoSwitch()
    if not Config.AutoSwitch.Enabled then return end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local char = charOf(LocalPlayer)
    local hum = humanoidOf(char)
    if not backpack or not char or not hum then return end
    local selected = nil
    for _, name in ipairs(Config.InventorySorter.Order) do
        local item = backpack:FindFirstChild(name)
        if item and item:IsA("Tool") then selected = item break end
    end
    if not selected then selected = backpack:FindFirstChildOfClass("Tool") end
    if selected then hum:EquipTool(selected) end
end

-- =============================================================
-- V4WARE WEAPON SWITCH: UMA TECLA, TRES ARMAS EM SEQUENCIA
-- =============================================================
-- Usa exclusivamente Humanoid:EquipTool e Tool:Activate/Deactivate.
-- Nao modifica recarga, cadencia, eventos remotos ou validacoes do jogo.
-- A chamada Activate confirma uma tentativa, nao o registro do tiro no servidor.
local function weaponSwitchConfig()
    if type(Config.WeaponSwitch) ~= "table" then
        Config.WeaponSwitch = {
            Enabled = true, Key = "V",
            Order = {"[Double-Barrel SG]", "[TacticalShotgun]", "[Revolver]"},
            EquipDelay = 0.20, ShotHold = 0.06, BetweenDelay = 0.12,
            Cooldown = 1.50, RestorePrevious = true, SkipEmpty = true,
        }
    end
    return Config.WeaponSwitch
end

local function findWeapon(name, backpack, character)
    local t = character and character:FindFirstChild(name)
    if not (t and t:IsA("Tool")) then
        t = backpack and backpack:FindFirstChild(name)
    end
    return t and t:IsA("Tool") and t or nil
end

local function weaponAmmoEmpty(tool)
    -- Fica desativavel no Config: algumas armas usam contadores diferentes.
    local ammo = tool:FindFirstChild("Ammo") or tool:FindFirstChild("ClientAmmo")
    return ammo and ammo:IsA("ValueBase") and type(ammo.Value) == "number" and ammo.Value <= 0
end

local function requestWeaponSwitch()
    local cfg = weaponSwitchConfig()
    if not cfg.Enabled or weaponSwitchBusy or not running then return end
    local now = os.clock()
    local cooldown = math.clamp(tonumber(cfg.Cooldown) or 1.5, 0, 30)
    if now - weaponSwitchLastStart < cooldown then return end
    local character = charOf(LocalPlayer)
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local hum = humanoidOf(character)
    if not character or not backpack or not hum or hum.Health <= 0 then
        weaponSwitchLastError = "Personagem/Backpack/Humanoid indisponivel"
        return
    end
    if type(cfg.Order) ~= "table" then
        weaponSwitchLastError = "WeaponSwitch.Order deve ser uma lista"
        return
    end

    weaponSwitchBusy = true
    weaponSwitchLastStart = now
    weaponSwitchLastError = nil
    weaponSwitchLastResult = "Em andamento"
    weaponSwitchLastAttempts = 0
    weaponSwitchLastSkipped = 0

    local original = equippedTool()
    task.spawn(function()
        local ok, err = pcall(function()
            local equipDelay = math.clamp(tonumber(cfg.EquipDelay) or 0.20, 0.05, 2)
            local shotHold = math.clamp(tonumber(cfg.ShotHold) or 0.06, 0, 0.5)
            local between = math.clamp(tonumber(cfg.BetweenDelay) or 0.12, 0, 2)
            for _, name in ipairs(cfg.Order) do
                if not running or charOf(LocalPlayer) ~= character or hum.Health <= 0 then
                    weaponSwitchLastError = "Sequencia interrompida: personagem mudou"
                    break
                end
                local tool = findWeapon(tostring(name), backpack, character)
                if not tool then
                    weaponSwitchLastSkipped = weaponSwitchLastSkipped + 1
                    warn("[V4ware WS] Arma nao encontrada: " .. tostring(name))
                elseif cfg.SkipEmpty and weaponAmmoEmpty(tool) then
                    weaponSwitchLastSkipped = weaponSwitchLastSkipped + 1
                    warn("[V4ware WS] Sem municao: " .. tostring(name))
                else
                    if tool.Parent ~= character then
                        local equipOk = pcall(function() hum:EquipTool(tool) end)
                        if not equipOk then
                            weaponSwitchLastSkipped = weaponSwitchLastSkipped + 1
                            warn("[V4ware WS] Falha ao equipar: " .. tostring(name))
                        end
                    end
                    task.wait(equipDelay)
                    if running and tool.Parent == character then
                        local fireOk, fireErr = pcall(function() tool:Activate() end)
                        if fireOk then
                            weaponSwitchLastAttempts = weaponSwitchLastAttempts + 1
                            print("[V4ware WS] Ativacao solicitada: " .. tostring(name))
                        else
                            weaponSwitchLastSkipped = weaponSwitchLastSkipped + 1
                            weaponSwitchLastError = tostring(fireErr)
                            warn("[V4ware WS] Erro em Activate: " .. tostring(fireErr))
                        end
                        if shotHold > 0 then task.wait(shotHold) end
                        pcall(function() tool:Deactivate() end)
                    else
                        weaponSwitchLastSkipped = weaponSwitchLastSkipped + 1
                        warn("[V4ware WS] A arma nao ficou equipada: " .. tostring(name))
                    end
                    if between > 0 then task.wait(between) end
                end
            end
            if running and cfg.RestorePrevious and original and original.Parent and
                charOf(LocalPlayer) == character and hum.Health > 0 then
                pcall(function() hum:EquipTool(original) end)
            end
        end)
        if not ok then weaponSwitchLastError = tostring(err) end
        weaponSwitchLastResult = ("%d ativacao(oes) solicitada(s); %d ignorada(s)")
            :format(weaponSwitchLastAttempts, weaponSwitchLastSkipped)
        print("[V4ware WS] " .. weaponSwitchLastResult)
        if weaponSwitchLastError then warn("[V4ware WS] " .. weaponSwitchLastError) end
        weaponSwitchBusy = false
    end)
end

local function tp(position)
    local root = rootOf(charOf(LocalPlayer))
    if root then root.CFrame = CFrame.new(position) end
end

local function rageAction(input)
    if not Config.Rage.Enabled then return false end
    local cfg = Config.Rage
    for _, item in pairs(cfg.Teleports) do
        if pressed(input, item.Key) then tp(item.Position) return true end
    end
    if pressed(input, cfg.SkyReset.Key) then
        local root = rootOf(charOf(LocalPlayer))
        if root then tp(root.Position + Vector3.new(0, cfg.SkyReset.SkyHeight, 0)) end
        return true
    end
    if pressed(input, cfg.TeleportToTarget.Key) then
        local target = camTarget or findCamTarget()
        local root = target and rootOf(charOf(target))
        if root then tp(root.Position + Vector3.new(2, 0, 0)) end
        return true
    end
    return false
end

-- =============================================================
-- PULO V14: RESTAURACAO PROATIVA + CONTATO ESTRITO DOS PES
-- =============================================================
-- Um comando de Espaco = no maximo UM pedido de salto.
-- Nada de velocidade adicional, gravidade, CFrame, impulso no ar ou voo.
-- Se apertar Espaco enquanto estiver no ar, esse pedido e DESCARTADO.
-- Nenhum salto e armazenado para executar automaticamente na aterrissagem.
-- Nao remove restricoes que sejam impostas pelo servidor.
local jumpKeyLatched = false
local groundJumpCount = 0
local groundJumpConfirmed = 0
local jumpStateWasDisabled = 0
local restoredJumpPower = 0
local proactivePowerRestores = 0
local proactiveStateRestores = 0
local lastRecoveryReason = "sem bloqueio observado"
local nextNativeRecovery = 0
local recoveryReentry = false
local jumpInputCount = 0
local jumpBufferedCount = 0
local jumpBufferedExecuted = 0
local jumpBufferedExpired = 0
local nativeDeniedCount = 0
local attemptedJumpAt = 0
local attemptedJumpHum = nil
local observedThisAttempt = false
local checkedThisAttempt = true
local baselineHumanoid = nil
local baselinePower = nil
local baselineHeight = nil
local lastJumpResult = "Nenhuma tentativa"
local pendingJumpUntil = 0
local pendingJumpHum = nil
local lastFloorMethod = "nao testado"
local feetContactFrames = 0
local feetStable = false
local feetContactName = "nenhum"
local jumpConsumedThisLanding = false
local hasLeftGroundSinceJump = false
local lastGroundRequestedAt = 0
local airJumpIgnored = 0

local function observeHumanoid(hum)
    if not hum or hum == baselineHumanoid then return end
    baselineHumanoid = hum
    -- Registrar a altura NORMAL da propria sessao. Nunca aumentar acima do inicial.
    local currentPower, currentHeight = hum.JumpPower, hum.JumpHeight
    baselinePower = (currentPower and currentPower > 0) and currentPower or baselinePower
    baselineHeight = (currentHeight and currentHeight > 0) and currentHeight or baselineHeight
    attemptedJumpAt, attemptedJumpHum = 0, nil
    checkedThisAttempt = true
    observedThisAttempt = false
    pendingJumpUntil, pendingJumpHum = 0, nil
    feetContactFrames = 0
    feetStable = false
    feetContactName = "nenhum"
    jumpConsumedThisLanding = false
    hasLeftGroundSinceJump = false
    lastGroundRequestedAt = 0
    local conn = hum.StateChanged:Connect(function(_, newState)
        if not running then return end
        if newState == Enum.HumanoidStateType.Jumping then
            if attemptedJumpHum == hum and not observedThisAttempt then
                observedThisAttempt = true
                groundJumpConfirmed = groundJumpConfirmed + 1
                lastJumpResult = "Salto nativo observado"
            end
        end
    end)
    table.insert(connections, conn)
    -- O cooldown pode reduzir JumpPower para ZERO depois de tres pulos.
    -- Vigiar a propriedade evita depender de outra tecla ou do detector de chao.
    local function onPowerChanged()
        if not running or hum ~= baselineHumanoid or recoveryReentry then return end
        if hum.UseJumpPower and baselinePower and baselinePower > 0 and hum.JumpPower <= 0 then
            recoveryReentry = true
            local ok = pcall(function() hum.JumpPower = baselinePower end)
            recoveryReentry = false
            if ok then
                restoredJumpPower = restoredJumpPower + 1
                proactivePowerRestores = proactivePowerRestores + 1
                lastRecoveryReason = "JumpPower zerado: restaurado ao valor inicial"
            end
        end
    end
    local function onHeightChanged()
        if not running or hum ~= baselineHumanoid or recoveryReentry then return end
        if not hum.UseJumpPower and baselineHeight and baselineHeight > 0 and hum.JumpHeight <= 0 then
            recoveryReentry = true
            local ok = pcall(function() hum.JumpHeight = baselineHeight end)
            recoveryReentry = false
            if ok then
                restoredJumpPower = restoredJumpPower + 1
                proactivePowerRestores = proactivePowerRestores + 1
                lastRecoveryReason = "JumpHeight zerado: restaurado ao valor inicial"
            end
        end
    end
    table.insert(connections, hum:GetPropertyChangedSignal("JumpPower"):Connect(onPowerChanged))
    table.insert(connections, hum:GetPropertyChangedSignal("JumpHeight"):Connect(onHeightChanged))
    -- Nao impomos nem gravidade nem velocidades; somente recuperamos o salto do Humanoid.
    onPowerChanged()
    onHeightChanged()
end

-- A detecao antiga aceitava FloorMaterial (que pode ficar desatualizado)
-- ou um raycast do quadril proximo do solo. Essa verificacao usa as SOLAS.
local function isGrounded(hum)
    lastFloorMethod = "ar / sem apoio dos pes"
    feetContactName = "nenhum"
    if not hum or hum.Health <= 0 or hum.Sit then return false end
    local state = hum:GetState()
    -- Em Jumping, Freefall e outros estados aereos NUNCA tentamos reiniciar salto.
    if state ~= Enum.HumanoidStateType.Running
        and state ~= Enum.HumanoidStateType.RunningNoPhysics
        and state ~= Enum.HumanoidStateType.Landed then
        lastFloorMethod = "estado nao apoiado: " .. tostring(state)
        return false
    end
    local character = hum.Parent
    local root = rootOf(character)
    if not root then return false end
    -- Durante subida ou queda significativa nao ha aterrissagem confirmada.
    local vy = root.AssemblyLinearVelocity.Y
    if vy > 1.25 or vy < -3 then
        lastFloorMethod = "movimento vertical sem pouso: " .. string.format("%.2f", vy)
        return false
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = true
    pcall(function() params.RespectCanCollide = true end)
    local feet
    if hum.RigType == Enum.HumanoidRigType.R15 then
        feet = {"LeftFoot", "RightFoot"}
    else
        feet = {"Left Leg", "Right Leg"}
    end
    local gapLimit = math.clamp(tonumber(Config.Movement.GroundRayTolerance) or 0.10, 0.03, 0.12)
    for _, partName in ipairs(feet) do
        local foot = character:FindFirstChild(partName)
        if foot and foot:IsA("BasePart") then
            -- Altura mais baixa da caixa orientada: considera rotacao da perna/pe.
            local cf, size = foot.CFrame, foot.Size
            local halfVertical = (math.abs(cf.RightVector.Y)*size.X
                + math.abs(cf.UpVector.Y)*size.Y
                + math.abs(cf.LookVector.Y)*size.Z) * 0.5
            local soleY = foot.Position.Y - halfVertical
            local rayStart = foot.Position + Vector3.new(0, 0.15, 0)
            local distance = (rayStart.Y - soleY) + gapLimit
            local hit = Workspace:Raycast(rayStart, Vector3.new(0, -distance, 0), params)
            if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
                local gap = soleY - hit.Position.Y
                -- O pe precisa de fato tocar o piso: nao basta estar perto dele.
                if gap >= -0.08 and gap <= gapLimit then
                    feetContactName = partName
                    lastFloorMethod = "sola apoiada: " .. partName .. " (gap=" .. string.format("%.3f", gap) .. ")"
                    return true
                end
            end
        end
    end
    return false
end

-- Acompanha o pouso antes de autorizar UM novo salto.
-- So rearma quando o personagem realmente saiu do chao e voltou a tocar.
local function updateFootContact()
    local hum = humanoidOf(charOf(LocalPlayer))
    if not hum then
        feetContactFrames, feetStable = 0, false
        return
    end
    observeHumanoid(hum)
    local contact = isGrounded(hum)
    if contact then
        feetContactFrames = math.min(30, feetContactFrames + 1)
        local required = math.clamp(math.floor(tonumber(Config.Movement.GroundStableFrames) or 2), 2, 5)
        feetStable = feetContactFrames >= required
        if jumpConsumedThisLanding and hasLeftGroundSinceJump and feetStable then
            jumpConsumedThisLanding = false
            hasLeftGroundSinceJump = false
        elseif jumpConsumedThisLanding and not hasLeftGroundSinceJump
            and feetStable and os.clock() - lastGroundRequestedAt >= 0.35 then
            -- Pedido rejeitado pelo jogo: permite nova tentativa no chao.
            jumpConsumedThisLanding = false
        end
    else
        feetContactFrames, feetStable = 0, false
        if jumpConsumedThisLanding then hasLeftGroundSinceJump = true end
    end
end

local function maintainNativeJump()
    if not running or not Config.Movement["No Jump Cooldown"] then return end
    local now = os.clock()
    if now < nextNativeRecovery then return end
    nextNativeRecovery = now + 0.06
    local hum = humanoidOf(charOf(LocalPlayer))
    if not hum or hum.Health <= 0 then return end
    observeHumanoid(hum)
    -- O valor normal do pulo pode ser bloqueado tanto por propriedade quanto por estado.
    -- Recuperar somente valores zerados, sem aumento da altura e sem impulso no ar.
    if hum.UseJumpPower and baselinePower and baselinePower > 0 and hum.JumpPower <= 0 then
        if pcall(function() hum.JumpPower = baselinePower end) then
            restoredJumpPower = restoredJumpPower + 1
            proactivePowerRestores = proactivePowerRestores + 1
            lastRecoveryReason = "JumpPower restaurado (verificacao periodica)"
        end
    elseif (not hum.UseJumpPower) and baselineHeight and baselineHeight > 0 and hum.JumpHeight <= 0 then
        if pcall(function() hum.JumpHeight = baselineHeight end) then
            restoredJumpPower = restoredJumpPower + 1
            proactivePowerRestores = proactivePowerRestores + 1
            lastRecoveryReason = "JumpHeight restaurado (verificacao periodica)"
        end
    end
    -- Somente reabilitar Jumping no chao; nunca iniciar um novo salto automaticamente.
    if isGrounded(hum) then
        local ok, enabled = pcall(function()
            return hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        end)
        if ok and enabled == false then
            local restored = pcall(function()
                hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            end)
            if restored then
                jumpStateWasDisabled = jumpStateWasDisabled + 1
                proactiveStateRestores = proactiveStateRestores + 1
                lastRecoveryReason = "Estado Jumping bloqueado: reabilitado no chao"
            end
        end
    end
end

local function nativeJump(hum)
    if not running or not hum or jumpConsumedThisLanding or not feetStable or not isGrounded(hum) then
        return false
    end
    local okEnabled, stateEnabled = pcall(function()
        return hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    end)
    if okEnabled and stateEnabled == false then
        local restored = pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        end)
        if restored then jumpStateWasDisabled = jumpStateWasDisabled + 1 end
    end
    if hum.UseJumpPower and baselinePower and baselinePower > 0 and hum.JumpPower <= 0 then
        local restored = pcall(function() hum.JumpPower = baselinePower end)
        if restored then restoredJumpPower = restoredJumpPower + 1 end
    elseif not hum.UseJumpPower and baselineHeight and baselineHeight > 0 and hum.JumpHeight <= 0 then
        local restored = pcall(function() hum.JumpHeight = baselineHeight end)
        if restored then restoredJumpPower = restoredJumpPower + 1 end
    end
    pendingJumpUntil, pendingJumpHum = 0, nil
    jumpConsumedThisLanding = true
    hasLeftGroundSinceJump = false
    lastGroundRequestedAt = os.clock()
    feetStable = false
    feetContactFrames = 0
    groundJumpCount = groundJumpCount + 1
    attemptedJumpHum = hum
    attemptedJumpAt = os.clock()
    observedThisAttempt = false
    checkedThisAttempt = false
    lastJumpResult = "Pedido de salto nativo enviado no chao"
    -- Nenhuma forca propria: a altura permanece a definida pelo Humanoid.
    hum.Jump = true
    local ok = pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
    if not ok then lastJumpResult = "ChangeState nao aceito pelo cliente" end
    return true
end

local function onJumpRequest()
    if not running or not Config.Movement["No Jump Cooldown"] then return end
    local hum = humanoidOf(charOf(LocalPlayer))
    if not hum then return end
    observeHumanoid(hum)
    jumpInputCount = jumpInputCount + 1
    if feetStable and not jumpConsumedThisLanding and isGrounded(hum) then
        if not nativeJump(hum) then
            lastJumpResult = "Pedido nao aceito: sem apoio confirmado"
        end
    else
        -- IMPORTANTISSIMO: nada de buffer; pedido no ar nao gera salto futuro.
        airJumpIgnored = airJumpIgnored + 1
        lastJumpResult = "Ignorado: pes sem apoio estavel no chao"
    end
end

local function processJumpBuffer()
    -- V14: intencionalmente vazio. Nao agenda nenhum salto automatico.
    if not checkedThisAttempt and attemptedJumpAt > 0
        and os.clock() - attemptedJumpAt > 0.22 then
        checkedThisAttempt = true
        if not observedThisAttempt then
            nativeDeniedCount = nativeDeniedCount + 1
            lastJumpResult = "Salto nao confirmado pelo estado Jumping"
        end
    end
end

-- Deduplicacao: InputBegan e JumpRequest podem chegar no mesmo pressionamento.
local function keyboardJump(input, processed)
    if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local cfg = Config.Movement.InfiniteJump
    if not cfg or not pressed(input, cfg.Key or "Space") or jumpKeyLatched then return end
    jumpKeyLatched = true
    onJumpRequest()
end

local function jumpRequest()
    local cfg = Config.Movement.InfiniteJump
    if cfg and UserInputService.KeyboardEnabled then
        local key = Enum.KeyCode[tostring(cfg.Key or "Space")]
        if key and UserInputService:IsKeyDown(key) then
            if jumpKeyLatched then return end
            jumpKeyLatched = true
        end
    end
    onJumpRequest()
end

connectSignal(LocalPlayer.CharacterAdded, function(ch)
    jumpKeyLatched = false
    local hum = ch:WaitForChild("Humanoid", 10)
    if running and hum then observeHumanoid(hum) end
end)
observeHumanoid(humanoidOf(charOf(LocalPlayer)))

local function updateAutoReset()
    if not Config.AutoReset.Enabled or os.clock() < nextReset then return end
    nextReset = os.clock() + 2
    local character = charOf(LocalPlayer)
    if knocked(character) then
        local hum = humanoidOf(character)
        if hum then pcall(function() hum.Health = 0 end) end
    end
end

-- =============================================================
-- INPUT, LOOP, CONTROLE E STATUS
-- =============================================================
connectSignal(UserInputService.InputBegan, function(input, processed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rightMouseHeld = true
        return
    end
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    keyboardJump(input, processed)
    if Config.Triggerbot.Enabled and pressed(input, Config.Triggerbot.Key) then
        if Config.Triggerbot.Type == "Toggle" then
            triggerActive = not triggerActive
        else
            triggerActive = true
        end
    end
    if rageAction(input) then return end
    if pressed(input, Config.ESP.Key) then
        espActive = not espActive
        refreshESP()
    end
    if pressed(input, Config.Camlock.Key) then
        camActive = not camActive
        camTarget = camActive and findCamTarget() or nil
    end
    local wsCfg = weaponSwitchConfig()
    if wsCfg.Enabled and pressed(input, wsCfg.Key or "V") then
        requestWeaponSwitch()
        return
    end
    if pressed(input, Config.InventorySorter.Key) then sortInventory() end
    if pressed(input, Config.AutoSwitch.Key) then autoSwitch() end
end)

connectSignal(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local cfg = Config.Movement.InfiniteJump
        if cfg and pressed(input, cfg.Key or "Space") then jumpKeyLatched = false end
    end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseHeld = false end
    if pressed(input, Config.Triggerbot.Key) and Config.Triggerbot.Type ~= "Toggle" then
        triggerActive = false
    end
end)

connectSignal(UserInputService.JumpRequest, jumpRequest)
connectSignal(Players.PlayerRemoving, clearESP)

connectSignal(RunService.RenderStepped, function(dt)
    if not running then return end
    updateCam(dt)
    updateTrigger()
end)

connectSignal(RunService.Heartbeat, function()
    if not running then return end
    local now = os.clock()
    if now >= nextESP then
        nextESP = now + Config.ESP.RefreshTime
        -- Evita varrer a lista de jogadores quando o ESP está desligado.
        if espActive and Config.ESP.Enabled then
            refreshESP()
        end
    end
    if now >= nextHitbox then
        nextHitbox = now + math.max(0.05, tonumber(Config.HitboxExpander.RefreshTime) or 1)
        updateHitboxes()
    end
    if now >= nextSpread then
        nextSpread = now + math.max(3, tonumber(Config.SpreadModification.RefreshTime) or 6)
        updateSpread()
    end
    updateFootContact()
    maintainNativeJump()
    processJumpBuffer()
    updateAutoReset()
end)

local function status()
    local localMatches = {}
    for name, count in pairs(spreadMatches) do localMatches[name] = count end
    return {
        Version = 21.3,
        Running = running,
        InfiniteJump = false,
        NoJumpCooldown = Config.Movement["No Jump Cooldown"],
        GroundJumpsRequested = groundJumpCount,
        GroundJumpsStateConfirmed = groundJumpConfirmed,
        JumpStateReenabled = jumpStateWasDisabled,
        JumpPowerBaselineRestored = restoredJumpPower,
        JumpProactivePowerRestores = proactivePowerRestores,
        JumpProactiveStateRestores = proactiveStateRestores,
        JumpRecoveryReason = lastRecoveryReason,
        JumpBaselinePower = baselinePower,
        JumpBaselineHeight = baselineHeight,
        JumpStateEnabled = (function()
            local hum = humanoidOf(charOf(LocalPlayer))
            if not hum then return nil end
            local ok, enabled = pcall(function() return hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) end)
            return ok and enabled or nil
        end)(),
        JumpLastResult = lastJumpResult,
        JumpInputPresses = jumpInputCount,
        JumpBuffered = jumpBufferedCount,
        JumpBufferedExecuted = jumpBufferedExecuted,
        JumpBufferedExpired = jumpBufferedExpired,
        JumpPending = pendingJumpUntil > os.clock(),
        JumpGroundDetection = lastFloorMethod,
        JumpFootContact = feetContactName,
        JumpGroundFrames = feetContactFrames,
        JumpGroundStable = feetStable,
        JumpConsumedThisLanding = jumpConsumedThisLanding,
        JumpAirRequestsIgnored = airJumpIgnored,
        JumpNativeNotConfirmed = nativeDeniedCount,
        JumpCurrentPower = (function()
            local hum = humanoidOf(charOf(LocalPlayer))
            return hum and hum.JumpPower or nil
        end)(),
        JumpCurrentFloor = (function()
            local hum = humanoidOf(charOf(LocalPlayer))
            return hum and tostring(hum.FloorMaterial) or "sem humanoide"
        end)(),
        JumpCurrentState = (function()
            local hum = humanoidOf(charOf(LocalPlayer))
            return hum and tostring(hum:GetState()) or "sem humanoide"
        end)(),
        TriggerFireDelay = Config.Triggerbot.FireDelay,
        TriggerRange = Config.Triggerbot["Range-Check"].Data,
        TriggerMaxRange = Config.Triggerbot["Range-Check"].HardCap,
        Triggerbot = Config.Triggerbot.Enabled and triggerActive,
        ESP = Config.ESP.Enabled and espActive,
        Camlock = Config.Camlock.Enabled and camActive,
        CamTarget = camTarget and camTarget.Name or nil,
        WhitelistCount = (function() local n=0; for _ in pairs(Config.Triggerbot.Whitelist.List) do n=n+1 end; return n end)(),
        Spectating = spectateTarget and spectateTarget.Name or nil,
        HitboxExpander = Config.HitboxExpander.Enabled,
        SpreadConfigured = Config.SpreadModification.Guns,
        SpreadRuntimeConstantsPatched = localMatches,
        SpreadScanAttempted = spreadAttempted,
        SpreadCandidatesSeen = spreadCandidatesSeen,
        SpreadLastError = spreadLastError,
        WeaponSwitchEnabled = weaponSwitchConfig().Enabled,
        WeaponSwitchKey = weaponSwitchConfig().Key,
        WeaponSwitchBusy = weaponSwitchBusy,
        WeaponSwitchLastAttempts = weaponSwitchLastAttempts,
        WeaponSwitchLastSkipped = weaponSwitchLastSkipped,
        WeaponSwitchLastResult = weaponSwitchLastResult,
        WeaponSwitchLastError = weaponSwitchLastError,
        SpreadRealVerified = false, -- validacao de dano/trajetoria do servidor nao foi testada
        FastFlagsAvailable = fastFlagStatus.Available,
        FastFlagsTotal = fastFlagStatus.Total,
        FastFlagsAccepted = fastFlagStatus.Accepted,
        FastFlagsVerified = fastFlagStatus.Verified,
        FastFlagsUnverified = fastFlagStatus.Unverified,
        FastFlagsMismatched = fastFlagStatus.Mismatched,
        FastFlagsRejected = fastFlagStatus.Rejected,
        FastFlagsNotAttempted = fastFlagStatus.NotAttempted,
        FastFlagsResults = fastFlagStatus.Results,
        RemoteHooks = false,
    }
end


-- =============================================================
-- V4WARE V21.4 LITE DASHBOARD
-- Dashboard, telemetria e preferencias visuais; modulos de jogo fora do escopo desta atualizacao.
-- =============================================================
local menuGui, menuPanel, menuPlayers, menuCount, tabWhitelist, tabIncognito, monitorFrame
local activityPage, activityList, activityCountLabel
local panelScale
local selectedTab = "overview"
local selectedPlayerTab = "whitelist"
local menuVisible = false
local menuBodyVisible = true
local fpsCounterConnection = nil
local syncFPSCounter
local renderMenu
local updateSystemMonitor
local refreshDashboard
local monitorValues = {}
local currentFPS = 0
local fpsSampleAt = nil
local fpsFrameCount, fpsElapsed = 0, 0
local monitorEnabled = true
local compactMode = false
local panelKey = Enum.KeyCode.Insert
local panelKeyButton = nil
local capturingPanelKey = false
local uiScaleValue = 1
local pushActivity = nil
local reportProfileSave = nil
local activityRows = {}
local perf = {ping = nil, memory = nil, lastAt = nil}
local accentColor = Color3.fromRGB(160, 190, 222)
local accentChoices = {
    Color3.fromRGB(160, 190, 222),
    Color3.fromRGB(139, 202, 178),
    Color3.fromRGB(180, 166, 225),
}
local accentIndex = 1
local UI_PROFILE_PATH = "V4ware_UI_Profile.json"

local function sanitizeUIPreferences(data)
    if type(data) ~= "table" then return nil end
    local keyName = tostring(data.PanelKey or "Insert")
    local keyCode = Enum.KeyCode.Insert
    local keyOk, resolvedKey = pcall(function() return Enum.KeyCode[keyName] end)
    if keyOk and resolvedKey then keyCode = resolvedKey end
    return {
        AccentIndex = math.clamp(math.floor(tonumber(data.AccentIndex) or 1), 1, #accentChoices),
        CompactMode = data.CompactMode == true,
        MonitorEnabled = data.MonitorEnabled ~= false,
        PanelKey = keyCode,
        UIScale = math.clamp(tonumber(data.UIScale) or 1, 0.85, 1.10),
    }
end

local function loadUIPreferences()
    local stored = nil
    if type(readfile) == "function" then
        local readOk, raw = pcall(readfile, UI_PROFILE_PATH)
        if readOk and type(raw) == "string" then
            local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
            if decodeOk then stored = decoded end
        end
    end
    if type(stored) ~= "table" then stored = env.V4wareUIPrefs end
    local clean = sanitizeUIPreferences(stored)
    if not clean then return false end
    accentIndex = clean.AccentIndex
    compactMode = clean.CompactMode
    monitorEnabled = clean.MonitorEnabled
    panelKey = clean.PanelKey
    uiScaleValue = clean.UIScale
    accentColor = accentChoices[accentIndex]
    return true
end

local function saveUIPreferences()
    local data = {
        Version = 1,
        AccentIndex = accentIndex,
        CompactMode = compactMode,
        MonitorEnabled = monitorEnabled,
        PanelKey = panelKey.Name,
        UIScale = uiScaleValue,
    }
    env.V4wareUIPrefs = data
    if type(writefile) == "function" then
        local encodeOk, encoded = pcall(function() return HttpService:JSONEncode(data) end)
        if not encodeOk then return false, "JSON_ENCODE_FAILED" end
        local writeOk, writeErr = pcall(writefile, UI_PROFILE_PATH, encoded)
        if not writeOk then return false, tostring(writeErr) end
        return true, "FILE"
    end
    return true, "SESSION_ONLY"
end

loadUIPreferences()

local function restoreOwnCamera()
    local cam = camera()
    if not cam then return end
    local char = charOf(LocalPlayer)
    local hum = humanoidOf(char)
    local previous = spectateOldSubject
    if hum then
        cam.CameraType = spectateOldType or Enum.CameraType.Custom
        cam.CameraSubject = (previous and previous.Parent and previous) or hum
    else
        cam.CameraType = Enum.CameraType.Custom
    end
end

local function stopSpectating()
    if not spectateTarget then return end
    spectateTarget = nil
    restoreOwnCamera()
    spectateOldSubject, spectateOldType = nil, nil
end

local function startSpectating(player)
    if spectateTarget == player then
        stopSpectating()
        return
    end
    local targetHum = humanoidOf(charOf(player))
    if not targetHum then
        warn("[V4ware] Jogador sem personagem disponivel para visualizar.")
        return
    end
    if not spectateTarget then
        local cam = camera()
        spectateOldSubject = cam and cam.CameraSubject or nil
        spectateOldType = cam and cam.CameraType or nil
    end
    spectateTarget = player
    local cam = camera()
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = targetHum
    end
end

local function uiNew(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do obj[key] = value end
    obj.Parent = parent
    return obj
end

local function uiText(parent, txt, props)
    local p = {
        Text = txt,
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(229, 237, 247),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BorderSizePixel = 0,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return uiNew("TextLabel", p, parent)
end

-- Native button feedback; no custom hover events or tweens.
local function uiButton(parent, txt, props)
    local p = {
        Text = txt,
        BackgroundColor3 = Color3.fromRGB(23, 37, 55),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Color3.fromRGB(232, 241, 250),
        AutoButtonColor = true,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    local button = uiNew("TextButton", p, parent)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 8)}, button)
    uiNew("UIStroke", {Color = Color3.fromRGB(43, 64, 87), Thickness = 1}, button)
    return button
end

local function uiCard(parent, name, position, size)
    local card = uiNew("Frame", {
        Name = name,
        Position = position,
        Size = size,
        BackgroundColor3 = Color3.fromRGB(20, 32, 49),
        BorderSizePixel = 0,
    }, parent)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 10)}, card)
    uiNew("UIStroke", {Color = Color3.fromRGB(40, 57, 78), Thickness = 1}, card)
    return card
end

local function displayFPS()
    if not monitorEnabled then return "PAUSED" end
    if currentFPS <= 0 or not fpsSampleAt then return "--" end
    if os.clock() - fpsSampleAt > 5 then return "~" .. tostring(currentFPS) end
    return tostring(currentFPS)
end

local function readPingMs()
    local ok, ping = pcall(function()
        return LocalPlayer:GetNetworkPing() * 1000
    end)
    if ok and type(ping) == "number" and ping >= 0 then return ping end
    local okItem, item = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]
    end)
    if okItem and item then
        local okValue, value = pcall(function() return item:GetValue() end)
        if okValue and type(value) == "number" then return value end
        local okText, valueText = pcall(function() return item:GetValueString() end)
        if okText and type(valueText) == "string" then
            local number = tonumber(valueText:match("[%d%.]+"))
            if number then return number end
        end
    end
    return nil
end

local function readMemoryMb()
    local ok, value = pcall(function()
        return Stats:GetTotalMemoryUsageMb()
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

-- V21.4: shared telemetry cache, only populated by the existing FPS sampler.
function perf.text(value, suffix)
    if not monitorEnabled then return "PAUSED" end
    if value == nil then return "--" end
    local prefix = perf.lastAt and os.clock() - perf.lastAt > 5 and "~" or ""
    return prefix .. string.format("%.0f", value) .. (suffix or "")
end

-- Collect only when a visible page needs telemetry; no overlay or history.
function perf.record()
    perf.lastAt = os.clock()
    perf.ping, perf.memory = readPingMs(), readMemoryMb()
end

local function buildMenu()
    local accentElements = {}
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        warn("[V4ware] PlayerGui nao encontrado; menu nao criado")
        return
    end

    local old = playerGui:FindFirstChild("V4ware_ControlPanel")
    if old then old:Destroy() end

    -- Remove any obsolete overlay left by earlier versions.
    local previous = playerGui:FindFirstChild("V4ware_PerformanceOverlay")
    if previous then previous:Destroy() end

    menuGui = uiNew("ScreenGui", {
        Name = "V4ware_ControlPanel",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
        Enabled = false,
        IgnoreGuiInset = false,
    }, playerGui)

    menuPanel = uiNew("Frame", {
        Name = "Panel",
        Size = compactMode and UDim2.fromOffset(820, 550) or UDim2.fromOffset(880, 580),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(10, 16, 27),
        BorderSizePixel = 0,
        Active = true,
    }, menuGui)
    panelScale = uiNew("UIScale", {Scale = uiScaleValue}, menuPanel)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 14)}, menuPanel)
    uiNew("UIStroke", {Color = Color3.fromRGB(38, 58, 81), Thickness = 1}, menuPanel)
    uiNew("UISizeConstraint", {
        MinSize = Vector2.new(660, 74),
        MaxSize = Vector2.new(920, 680),
    }, menuPanel)

    -- Header
    local header = uiNew("Frame", {
        Name = "Header",
        Active = true,
        Size = UDim2.new(1, 0, 0, 74),
        BackgroundColor3 = Color3.fromRGB(15, 24, 39),
        BorderSizePixel = 0,
    }, menuPanel)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 14)}, header)
    uiNew("Frame", {
        Position = UDim2.new(0, 0, 1, -14),
        Size = UDim2.new(1, 0, 0, 14),
        BackgroundColor3 = Color3.fromRGB(15, 24, 39),
        BorderSizePixel = 0,
    }, header)

    local headerAccentDivider = uiNew("Frame", {
        Name = "AccentDivider",
        Position = UDim2.new(0, 20, 1, -1),
        Size = UDim2.new(1, -40, 0, 1),
        BackgroundColor3 = accentColor,
        BackgroundTransparency = 0.24,
        BorderSizePixel = 0,
    }, header)
    table.insert(accentElements, headerAccentDivider)
    local logo = uiCard(header, "LogoMark", UDim2.fromOffset(20, 16), UDim2.fromOffset(42, 42))
    local logoText = uiText(logo, "V4", {
        Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = accentColor,
    })
    uiText(header, "V4WARE", {
        Position = UDim2.fromOffset(74, 12),
        Size = UDim2.fromOffset(190, 27),
        Font = Enum.Font.GothamBold,
        TextSize = 23,
        TextColor3 = Color3.fromRGB(244, 248, 255),
    })
    uiText(header, "LITE EDITION  /  V21.4", {
        Position = UDim2.fromOffset(75, 40),
        Size = UDim2.fromOffset(270, 15),
        Font = Enum.Font.GothamMedium,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })

    local onlinePill = uiNew("Frame", {
        Position = UDim2.new(1, -174, 0, 24),
        Size = UDim2.fromOffset(84, 26),
        BackgroundColor3 = Color3.fromRGB(24, 43, 36),
        BorderSizePixel = 0,
    }, header)
    uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, onlinePill)
    local dot = uiNew("Frame", {
        Position = UDim2.fromOffset(10, 9),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = Color3.fromRGB(111, 207, 151),
        BorderSizePixel = 0,
    }, onlinePill)
    uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)
    uiText(onlinePill, "ONLINE", {
        Position = UDim2.fromOffset(25, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(111, 207, 151),
    })

    local minimize = uiButton(header, "–", {
        Position = UDim2.new(1, -66, 0, 23),
        Size = UDim2.fromOffset(29, 29),
        TextSize = 16,
    })
    local close = uiButton(header, "×", {
        Position = UDim2.new(1, -33, 0, 23),
        Size = UDim2.fromOffset(29, 29),
        TextSize = 17,
    })

    -- Sidebar
    local body = uiNew("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, 74),
        Size = UDim2.new(1, 0, 1, -74),
        BackgroundTransparency = 1,
    }, menuPanel)

    local sidebar = uiNew("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 176, 1, 0),
        BackgroundColor3 = Color3.fromRGB(15, 24, 39),
        BorderSizePixel = 0,
    }, body)
    uiNew("Frame", {
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Color3.fromRGB(38, 58, 81),
        BorderSizePixel = 0,
    }, sidebar)
    uiText(sidebar, "NAVIGATION", {
        Position = UDim2.fromOffset(18, 19),
        Size = UDim2.new(1, -34, 0, 16),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(113, 132, 154),
    })

    local nav = uiNew("Frame", {
        Name = "Navigation",
        Position = UDim2.fromOffset(10, 49),
        Size = UDim2.new(1, -20, 0, 350),
        BackgroundTransparency = 1,
    }, sidebar)
    uiNew("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, nav)

    local footer = uiCard(sidebar, "BuildInfo", UDim2.new(0, 10, 1, -58), UDim2.new(1, -20, 0, 46))
    uiText(footer, "BUILD", {
        Position = UDim2.fromOffset(10, 5),
        Size = UDim2.new(1, -20, 0, 12),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(113, 132, 154),
    })
    uiText(footer, "V21.4  •  LITE", {
        Position = UDim2.fromOffset(10, 22),
        Size = UDim2.new(1, -20, 0, 16),
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(186, 202, 220),
    })

    local content = uiNew("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(176, 0),
        Size = UDim2.new(1, -176, 1, 0),
        BackgroundTransparency = 1,
    }, body)

    local pages, navItems = {}, {}
    local lastRenderedTab = nil
    local function makePage(name)
        local page = uiNew("Frame", {
            Name = name,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Visible = false,
        }, content)
        pages[name] = page
        return page
    end

    local overviewPage = makePage("Overview")
    local playersPage = makePage("Players")
    local systemPage = makePage("System")
    local spreadPage = makePage("Spread")
    local hitboxPage = makePage("Hitbox")
    local settingsPage = makePage("Settings")
    activityPage = makePage("Activity")
    perf.diagnostics = makePage("Diagnostics")

    local function heading(parent, title, subtitle)
        local headingMarker = uiNew("Frame", {
            Position = UDim2.fromOffset(22, 19),
            Size = UDim2.fromOffset(3, 24),
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
        }, parent)
        table.insert(accentElements, headingMarker)
        uiText(parent, title, {
            Position = UDim2.fromOffset(34, 12),
            Size = UDim2.new(1, -58, 0, 29),
            Font = Enum.Font.GothamSemibold,
            TextSize = 24,
            TextColor3 = Color3.fromRGB(244, 248, 255),
        })
        uiText(parent, subtitle, {
            Position = UDim2.fromOffset(35, 45),
            Size = UDim2.new(1, -60, 0, 17),
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = Color3.fromRGB(143, 160, 180),
        })
    end

    local function navItem(name, subtitle, glyph, order)
        local b = uiNew("TextButton", {
            Name = name .. "Nav",
            Size = UDim2.new(1, 0, 0, 39),
            BackgroundColor3 = Color3.fromRGB(15, 24, 39),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
        }, nav)
        uiNew("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
        local bar = uiNew("Frame", {
            Position = UDim2.fromOffset(0, 9),
            Size = UDim2.fromOffset(3, 26),
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
            Visible = false,
        }, b)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
        local icon = uiText(b, glyph, {
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.fromOffset(28, 39),
            TextXAlignment = Enum.TextXAlignment.Center,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Color3.fromRGB(148, 166, 188),
        })
        local title = uiText(b, name, {
            Position = UDim2.fromOffset(44, 3),
            Size = UDim2.new(1, -52, 0, 19),
            Font = Enum.Font.GothamSemibold,
            TextSize = 13,
            TextColor3 = Color3.fromRGB(148, 166, 188),
        })
        uiText(b, subtitle, {
            Position = UDim2.fromOffset(44, 21),
            Size = UDim2.new(1, -52, 0, 13),
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextColor3 = Color3.fromRGB(132, 151, 174),
        })
        local navStroke = uiNew("UIStroke", {
            Color = accentColor,
            Thickness = 1,
            Transparency = 1,
        }, b)
        local navState = {
            button = b, bar = bar, icon = icon, title = title,
            active = false, stroke = navStroke,
        }
        navItems[name] = navState

        return b
    end

    navItem("Overview", "Session summary", "⌂", 1)
    navItem("Players", "Whitelist / Incognito", "◎", 2)
    navItem("Spread", "Weapon tuning", "◌", 3)
    navItem("Hitbox", "Hitbox settings", "▣", 4)
    navItem("System", "Performance", "◫", 5)
    navItem("Settings", "Preferences", "⚙", 6)
    navItem("Activity", "Notifications / history", "◷", 7)
    navItem("Diagnostics", "Startup report", "i", 8)

    -- Overview V21.4: hierarquia visual mais clara, sem alterar os dados exibidos.
    heading(overviewPage, "Overview", "Session overview  /  local telemetry and module status.")
    uiText(overviewPage, "LOCAL TELEMETRY", {
        Position = UDim2.fromOffset(22, 65),
        Size = UDim2.new(1, -44, 0, 12),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(113, 132, 154),
    })
    local dashboardMetrics = {}
    local function dashboardMetric(key, title, column)
        local card = uiCard(overviewPage, "Metric_" .. key,
            UDim2.new(column / 3, 22 - math.floor(column * 32 / 3 + 0.5), 0, 82),
            UDim2.new(1 / 3, -68 / 3, 0, 72))
        uiText(card, title:upper(), {
            Position = UDim2.fromOffset(13, 9),
            Size = UDim2.new(1, -26, 0, 13),
            Font = Enum.Font.GothamBold,
            TextSize = 8,
            TextColor3 = Color3.fromRGB(145, 164, 186),
        })
        dashboardMetrics[key] = uiText(card, "--", {
            Position = UDim2.fromOffset(13, 29),
            Size = UDim2.new(1, -26, 0, 29),
            Font = Enum.Font.GothamSemibold,
            TextSize = 27,
            TextColor3 = Color3.fromRGB(244, 248, 255),
        })
    end
    dashboardMetric("FPS", "Frame rate", 0)
    dashboardMetric("Ping", "Network ping", 1)
    dashboardMetric("Memory", "Client memory", 2)

    uiText(overviewPage, "MODULE STATUS", {
        Position = UDim2.fromOffset(22, 156),
        Size = UDim2.new(1, -44, 0, 12),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(113, 132, 154),
    })

    local featureCards = {}
    local function featureCard(key, title, column, y, cardSize)
        local card = uiCard(
            overviewPage,
            key,
            UDim2.new(column * 0.5, column == 0 and 22 or 6, 0, y),
            cardSize or UDim2.new(0.5, -28, 0, 48)
        )
        local dotFeature = uiNew("Frame", {
            Position = UDim2.fromOffset(15, 21),
            Size = UDim2.fromOffset(7, 7),
            BackgroundColor3 = Color3.fromRGB(105, 113, 124),
            BorderSizePixel = 0,
        }, card)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, dotFeature)
        uiText(card, title, {
            Position = UDim2.fromOffset(34, 0),
            Size = UDim2.new(1, -112, 1, 0),
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextColor3 = Color3.fromRGB(225, 235, 247),
        })
        local value = uiText(card, "OFF", {
            Position = UDim2.new(1, -78, 0, 0),
            Size = UDim2.new(0, 62, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextColor3 = Color3.fromRGB(145, 164, 186),
        })
        featureCards[key] = {value = value, dot = dotFeature}
    end

    featureCard("Triggerbot", "Triggerbot", 0, 174)
    featureCard("InfiniteJump", "Infinite Jump", 1, 174)
    featureCard("ESP", "ESP", 0, 228)
    featureCard("Camlock", "Camlock", 1, 228)
    featureCard("Hitbox", "Hitbox Expander", 0, 282)
    featureCard("Spread", "Spread Modification", 1, 282)
    featureCard("WeaponSwitch", "Weapon Switch", 0, 336, UDim2.new(1, -44, 0, 48))

    local overviewBottom = uiCard(overviewPage, "OverviewSession", UDim2.fromOffset(22, 396), UDim2.new(1, -44, 0, 68))
    uiText(overviewBottom, "SESSION", {
        Position = UDim2.fromOffset(15, 8),
        Size = UDim2.new(1, -30, 0, 13),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(145, 164, 186),
    })
    local overviewSession = uiText(overviewBottom, "ONLINE  •  INSERT TO OPEN / CLOSE", {
        Position = UDim2.fromOffset(15, 26),
        Size = UDim2.new(1, -30, 0, 18),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
        TextColor3 = Color3.fromRGB(231, 236, 244),
    })
    local overviewUptime = uiText(overviewBottom, "Session 00:00:00", {
        Position = UDim2.fromOffset(15, 48),
        Size = UDim2.new(1, -30, 0, 14),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(145, 164, 186),
    })

    local function setFeature(key, enabled, active)
        local item = featureCards[key]
        if not item then return end
        local on = enabled == true
        item.value.Text = not on and "OFF" or (active == false and "READY" or "ON")
        item.value.TextColor3 = on and accentColor or Color3.fromRGB(145, 164, 186)
        item.dot.BackgroundColor3 = on and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(83, 91, 103)
    end

    refreshDashboard = function()
        setFeature("Triggerbot", Config.Triggerbot and Config.Triggerbot.Enabled, true)
        setFeature("InfiniteJump", Config.Movement and Config.Movement.InfiniteJump and Config.Movement.InfiniteJump.Enabled, true)
        setFeature("ESP", Config.ESP and Config.ESP.Enabled, espActive)
        setFeature("Camlock", Config.Camlock and Config.Camlock.Enabled, camActive)
        setFeature("Hitbox", Config.HitboxExpander and Config.HitboxExpander.Enabled, true)
        setFeature("Spread", Config.SpreadModification and Config.SpreadModification.Enabled, true)
        setFeature("WeaponSwitch", weaponSwitchConfig().Enabled, true)
        if monitorEnabled then
            dashboardMetrics.FPS.Text = displayFPS()
            dashboardMetrics.Ping.Text = perf.text(perf.ping, " ms")
            dashboardMetrics.Memory.Text = perf.text(perf.memory, " MB")
        else
            dashboardMetrics.FPS.Text = "PAUSED"
            dashboardMetrics.Ping.Text = "PAUSED"
            dashboardMetrics.Memory.Text = "PAUSED"
        end
        overviewSession.Text = "ONLINE  •  " .. panelKey.Name:upper() .. " TO OPEN / CLOSE"
        overviewUptime.Text = "Session " .. formatDuration(os.clock() - sessionStartedAt)
    end

    -- Players
    heading(playersPage, "Players", "Gerencie as listas e visualize a sessao.")
    tabWhitelist = uiButton(playersPage, "WHITELIST", {
        Position = UDim2.fromOffset(22, 82),
        Size = UDim2.fromOffset(132, 32),
        BackgroundColor3 = Color3.fromRGB(30, 49, 73),
    })
    tabIncognito = uiButton(playersPage, "INCOGNITO", {
        Position = UDim2.fromOffset(164, 82),
        Size = UDim2.fromOffset(132, 32),
    })
    menuPlayers = uiNew("ScrollingFrame", {
        Name = "PlayerList",
        Position = UDim2.fromOffset(22, 126),
        Size = UDim2.new(1, -44, 1, -166),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(89, 119, 151),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, playersPage)
    uiNew("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
    }, menuPlayers)
    menuCount = uiText(playersPage, "WHITELIST  •  0 entries", {
        Position = UDim2.new(0, 23, 1, -30),
        Size = UDim2.new(1, -46, 0, 18),
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })

    -- System: four readouts, one session card, no background visual effects.
    do
        heading(systemPage, "System monitor", "Local measurements  /  updates only while visible.")
        monitorFrame = uiNew("Frame", {
            Name = "SystemMonitor", Position = UDim2.fromOffset(22, 82),
            Size = UDim2.new(1, -44, 1, -104), BackgroundTransparency = 1,
        }, systemPage)
        for i, entry in ipairs({{"FPS", "FRAME RATE"}, {"Ping", "NETWORK PING"},
                {"Memory", "CLIENT MEMORY"}, {"Players", "PLAYERS IN SESSION"}}) do
            local col = (i-1)%2
            local y = math.floor((i-1)/2)*112
            local card = uiCard(monitorFrame, entry[1], UDim2.new(col*0.5, col*6, 0, y), UDim2.new(0.5, -6, 0, 100))
            uiText(card, entry[2], {Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 16),
                TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(145,164,186)})
            monitorValues[entry[1]] = uiText(card, "--", {Position = UDim2.fromOffset(16, 33),
                Size = UDim2.new(1, -32, 0, 45), TextSize = 30, Font = Enum.Font.GothamSemibold})
        end
        local session = uiCard(monitorFrame, "Session", UDim2.fromOffset(0,224), UDim2.new(1,0,0,88))
        uiText(session,"SESSION STATUS",{Position=UDim2.fromOffset(16,10),Size=UDim2.new(1,-32,0,16),TextSize=10,Font=Enum.Font.GothamMedium,TextColor3=Color3.fromRGB(145,164,186)})
        monitorValues.Status = uiText(session,"WARMING UP",{Position=UDim2.fromOffset(16,30),
            Size=UDim2.new(1,-32,0,22),TextSize=14,Font=Enum.Font.GothamSemibold})
        monitorValues.Uptime = uiText(session,"Session 00:00:00",{Position=UDim2.fromOffset(16,57),
            Size=UDim2.new(1,-32,0,17),TextSize=11,TextColor3=Color3.fromRGB(145,164,186)})
        uiText(monitorFrame,"Telemetry sleeps when the panel is closed. ~ indicates a previous sample.",{
            Position=UDim2.fromOffset(0,326),Size=UDim2.new(1,0,0,34),TextWrapped=true,TextSize=11,TextColor3=Color3.fromRGB(145,164,186)})
        updateSystemMonitor = function()
            if not monitorFrame or not monitorFrame.Parent then return end
            monitorValues.FPS.Text = displayFPS()
            monitorValues.Ping.Text = perf.text(perf.ping," ms")
            monitorValues.Memory.Text = perf.text(perf.memory," MB")
            monitorValues.Players.Text = tostring(#Players:GetPlayers())
            monitorValues.Status.Text = not monitorEnabled and "MONITOR PAUSED" or (not fpsSampleAt and "WARMING UP" or (os.clock()-fpsSampleAt>5 and "LAST SAMPLE / REFRESHING" or "LIVE / LOCAL TELEMETRY"))
            monitorValues.Uptime.Text = "Session " .. formatDuration(os.clock()-sessionStartedAt)
        end
    end

    -- Diagnostics: display the existing startup report only; never apply or retry flags here.
    do
        heading(perf.diagnostics,"Diagnostics","Startup report  /  read-only  /  no new flag requests.")
        local report = uiCard(perf.diagnostics,"StartupReport",UDim2.fromOffset(22,78),UDim2.new(1,-44,0,68))
        uiText(report,string.format("%d / %d VERIFIED",fastFlagStatus.Verified,fastFlagStatus.Total),{
            Position=UDim2.fromOffset(12,8),Size=UDim2.new(1,-24,0,20),TextSize=15,Font=Enum.Font.GothamSemibold})
        uiText(report,string.format("Unverified: %d  |  Rejected: %d  |  Mismatch: %d  |  Not attempted: %d",fastFlagStatus.Unverified,fastFlagStatus.Rejected,fastFlagStatus.Mismatched,fastFlagStatus.NotAttempted),{
            Position=UDim2.fromOffset(12,34),Size=UDim2.new(1,-24,0,24),TextSize=10,TextWrapped=true})
        local list = uiNew("ScrollingFrame",{Name="StartupRows",Position=UDim2.fromOffset(22,158),Size=UDim2.new(1,-44,1,-212),
            BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,AutomaticCanvasSize=Enum.AutomaticSize.Y,
            CanvasSize=UDim2.fromOffset(0,0)},perf.diagnostics)
        uiNew("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,5)},list)
        for index,name in ipairs(fastFlagNames) do
            local state = tostring(fastFlagStatus.Results[name] or "UNKNOWN")
            local row=uiCard(list,"Flag"..index,UDim2.new(),UDim2.new(1,-8,0,53))
            row.LayoutOrder=index
            uiText(row,name,{Position=UDim2.fromOffset(10,5),Size=UDim2.new(1,-20,0,18),TextSize=10})
            uiText(row,"Requested: "..tostring(V4wareFastFlags[name]).."  |  "..state,{
                Position=UDim2.fromOffset(10,25),Size=UDim2.new(1,-20,0,24),TextSize=9,TextWrapped=true,
                TextColor3=state=="VERIFIED" and Color3.fromRGB(111,207,151) or Color3.fromRGB(226,185,112)})
        end
        uiText(perf.diagnostics,"Readback does not prove an in-game effect. Results are from startup.",{
            Position=UDim2.new(0,22,1,-48),Size=UDim2.new(1,-44,0,36),TextSize=9,TextWrapped=true,
            TextColor3=Color3.fromRGB(143,160,180)})
    end

    -- Spread tuning panel. Values are written back to the existing Config table.
    local spreadRows = {}
    local spreadNames = {
        {key = "[Double-Barrel SG]", title = "Double-Barrel"},
        {key = "[TacticalShotgun]", title = "Tactical Shotgun"},
        {key = "[Revolver]", title = "Revolver"},
    }
    heading(spreadPage, "Spread settings", "Multipliers: 1.00 = original value  •  0.00 = zero multiplier")
    local spreadStatus = uiText(spreadPage, "EDIT VALUES, THEN APPLY CHANGES", {
        Position = UDim2.fromOffset(24, 67),
        Size = UDim2.new(1, -48, 0, 16),
        Font = Enum.Font.GothamMedium,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local function spreadValue(key)
        if type(Config.SpreadModification) ~= "table" then
            Config.SpreadModification = {Enabled = false, RefreshTime = 6, Guns = {}}
        end
        if type(Config.SpreadModification.Guns) ~= "table" then
            Config.SpreadModification.Guns = {}
        end
        local n = tonumber(Config.SpreadModification.Guns[key])
        return math.clamp(n or 1, 0, 1.5)
    end
    local function updateSpreadRow(key)
        local row = spreadRows[key]
        if not row then return end
        local value = spreadValue(key)
        row.value.Text = string.format("%.2f", value)
        row.fill.Size = UDim2.new(value / 1.5, 0, 1, 0)
    end

    for index, item in ipairs(spreadNames) do
        local weaponKey = item.key
        local weaponTitle = item.title
        local y = 92 + (index - 1) * 96
        local card = uiCard(spreadPage, "Spread_" .. tostring(index), UDim2.fromOffset(22, y), UDim2.new(1, -44, 0, 80))
        uiText(card, weaponTitle, {
            Position = UDim2.fromOffset(15, 11),
            Size = UDim2.new(1, -170, 0, 19),
            Font = Enum.Font.GothamSemibold,
            TextSize = 11,
        })
        local value = uiNew("TextBox", {
            Position = UDim2.new(1, -132, 0, 10),
            Size = UDim2.fromOffset(54, 20),
            BackgroundTransparency = 1,
            Text = "1.00",
            ClearTextOnFocus = false,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = accentColor,
            BorderSizePixel = 0,
        }, card)
        local minus = uiButton(card, "−", {
            Position = UDim2.new(1, -72, 0, 8),
            Size = UDim2.fromOffset(27, 27),
            TextSize = 14,
        })
        local plus = uiButton(card, "+", {
            Position = UDim2.new(1, -39, 0, 8),
            Size = UDim2.fromOffset(27, 27),
            TextSize = 13,
        })
        local track = uiNew("Frame", {
            Position = UDim2.fromOffset(15, 53),
            Size = UDim2.new(1, -30, 0, 8),
            BackgroundColor3 = Color3.fromRGB(40, 57, 78),
            BorderSizePixel = 0,
        }, card)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, track)
        local fill = uiNew("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
        }, track)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)
        spreadRows[weaponKey] = {value = value, fill = fill}
        value.FocusLost:Connect(function()
            local typed = tonumber(value.Text)
            if typed == nil then
                updateSpreadRow(weaponKey)
                return
            end
            Config.SpreadModification.Guns[weaponKey] = math.clamp(typed, 0, 1.5)
            updateSpreadRow(weaponKey)
            spreadStatus.Text = "UNAPPLIED CHANGE  •  CLICK APPLY CHANGES"
            spreadStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
        end)
        local function change(delta)
            Config.SpreadModification.Guns[weaponKey] = math.clamp(spreadValue(weaponKey) + delta, 0, 1.5)
            updateSpreadRow(weaponKey)
            spreadStatus.Text = "UNAPPLIED CHANGE  •  CLICK APPLY CHANGES"
            spreadStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
        end
        minus.Activated:Connect(function() change(-0.05) end)
        plus.Activated:Connect(function() change(0.05) end)
        updateSpreadRow(weaponKey)
    end

    local applySpreadButton = uiButton(spreadPage, "APPLY CHANGES", {
        Position = UDim2.fromOffset(22, 388),
        Size = UDim2.fromOffset(142, 34),
        BackgroundColor3 = Color3.fromRGB(38, 49, 62),
        TextColor3 = Color3.fromRGB(228, 237, 248),
    })
    local resetSpreadButton = uiButton(spreadPage, "RESET DEFAULTS", {
        Position = UDim2.fromOffset(174, 388),
        Size = UDim2.fromOffset(134, 34),
    })
    local spreadInfo = uiText(spreadPage, "Patch status: waiting for scan.", {
        Position = UDim2.fromOffset(24, 424),
        Size = UDim2.new(1, -48, 0, 44),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(143, 160, 180),
        TextWrapped = true,
    })

    local function refreshSpreadStatus()
        local patched = (spreadPatched["[Double-Barrel SG]"] or 0)
            + (spreadPatched["[TacticalShotgun]"] or 0)
            + (spreadPatched["[Revolver]"] or 0)
        local detail = spreadLastError and ("  •  " .. tostring(spreadLastError)) or ""
        spreadInfo.Text = string.format("Matched functions: %d  |  patched constants: %d%s", spreadCandidatesSeen, patched, detail)
    end

    applySpreadButton.Activated:Connect(function()
        if not Config.SpreadModification.Enabled then
            spreadStatus.Text = "SPREAD MODIFICATION IS DISABLED IN CONFIG"
            spreadStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
            return
        end
        local ok, err = pcall(updateSpread)
        refreshSpreadStatus()
        if not ok then
            spreadStatus.Text = "SCAN FAILED  •  " .. tostring(err)
            spreadStatus.TextColor3 = Color3.fromRGB(224, 119, 119)
        elseif spreadLastError then
            spreadStatus.Text = "SCAN FINISHED  •  CHECK DIAGNOSTIC BELOW"
            spreadStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
        else
            spreadStatus.Text = "SCAN FINISHED  •  CHECK PATCH COUNTS BELOW"
            spreadStatus.TextColor3 = Color3.fromRGB(111, 207, 151)
        end
    end)

    resetSpreadButton.Activated:Connect(function()
        Config.SpreadModification.Guns["[Double-Barrel SG]"] = 0.65
        Config.SpreadModification.Guns["[TacticalShotgun]"] = 0.60
        Config.SpreadModification.Guns["[Revolver]"] = 0
        for _, item in ipairs(spreadNames) do updateSpreadRow(item.key) end
        spreadStatus.Text = "DEFAULT VALUES RESTORED  •  CLICK APPLY"
        spreadStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
    end)

    -- Hitbox settings. The controls below write directly to the existing
    -- Config.HitboxExpander table consumed by updateHitboxes().
    local hitboxCfg = Config.HitboxExpander
    local hitboxRows = {}
    local hitboxStatus
    heading(hitboxPage, "Hitbox settings", "Dimensions in studs  •  Transparency: 0 = opaque / 1 = invisible.")

    local hitboxTop = uiCard(hitboxPage, "HitboxModuleCard", UDim2.fromOffset(22, 82), UDim2.new(1, -44, 0, 72))
    uiText(hitboxTop, "HITBOX EXPANDER", {
        Position = UDim2.fromOffset(15, 10),
        Size = UDim2.fromOffset(160, 18),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
    })
    uiText(hitboxTop, "Enable module and choose whether the resized part is visible.", {
        Position = UDim2.fromOffset(15, 34),
        Size = UDim2.new(1, -270, 0, 17),
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })

    local hitboxEnabledButton = uiButton(hitboxTop, hitboxCfg.Enabled and "ON" or "OFF", {
        Position = UDim2.new(1, -194, 0, 20),
        Size = UDim2.fromOffset(82, 32),
        TextSize = 9,
        TextColor3 = hitboxCfg.Enabled and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(154, 171, 192),
    })
    local hitboxVisibleButton = uiButton(hitboxTop, hitboxCfg.Visible and "VISIBLE" or "HIDDEN", {
        Position = UDim2.new(1, -104, 0, 20),
        Size = UDim2.fromOffset(90, 32),
        TextSize = 8,
        TextColor3 = hitboxCfg.Visible and accentColor or Color3.fromRGB(154, 171, 192),
    })

    local function hitboxValue(key, fallback, minimum, maximum)
        local value = tonumber(hitboxCfg[key]) or fallback
        return math.clamp(value, minimum, maximum)
    end

    local function updateHitboxRow(key)
        local row = hitboxRows[key]
        if not row then return end
        local value = hitboxValue(key, row.default, row.minimum, row.maximum)
        row.value.Text = string.format("%.2f", value)
        local fraction = (value - row.minimum) / (row.maximum - row.minimum)
        row.fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
    end

    local function setHitboxValue(key, value)
        local row = hitboxRows[key]
        if not row then return end
        hitboxCfg[key] = math.clamp(value, row.minimum, row.maximum)
        updateHitboxRow(key)
        hitboxStatus.Text = "UNAPPLIED CHANGE  •  CLICK APPLY CHANGES"
        hitboxStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
    end

    local function makeHitboxValueCard(key, title, column, y, minimum, maximum, step, fallback)
        local card = uiCard(hitboxPage, "Hitbox_" .. key,
            UDim2.new(column * 0.5, column == 0 and 22 or 6, 0, y), UDim2.new(0.5, -28, 0, 84))
        uiText(card, title, {
            Position = UDim2.fromOffset(15, 11),
            Size = UDim2.new(1, -164, 0, 19),
            Font = Enum.Font.GothamSemibold,
            TextSize = 10,
        })
        local value = uiNew("TextBox", {
            Position = UDim2.new(1, -130, 0, 10),
            Size = UDim2.fromOffset(52, 20),
            BackgroundTransparency = 1,
            Text = string.format("%.2f", hitboxValue(key, fallback, minimum, maximum)),
            ClearTextOnFocus = false,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = accentColor,
            BorderSizePixel = 0,
        }, card)
        local minus = uiButton(card, "−", {
            Position = UDim2.new(1, -72, 0, 8),
            Size = UDim2.fromOffset(27, 27),
            TextSize = 14,
        })
        local plus = uiButton(card, "+", {
            Position = UDim2.new(1, -40, 0, 8),
            Size = UDim2.fromOffset(27, 27),
            TextSize = 13,
        })
        local track = uiNew("Frame", {
            Position = UDim2.fromOffset(15, 57),
            Size = UDim2.new(1, -30, 0, 8),
            BackgroundColor3 = Color3.fromRGB(40, 57, 78),
            BorderSizePixel = 0,
        }, card)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, track)
        local fill = uiNew("Frame", {
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
        }, track)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)

        hitboxRows[key] = {
            value = value, fill = fill, minimum = minimum,
            maximum = maximum, step = step, default = fallback,
        }

        value.FocusLost:Connect(function()
            local normalizedText = value.Text:gsub(",", ".")
            local typed = tonumber(normalizedText)
            if typed == nil then
                updateHitboxRow(key)
                return
            end
            setHitboxValue(key, typed)
        end)
        minus.Activated:Connect(function()
            setHitboxValue(key, hitboxValue(key, fallback, minimum, maximum) - step)
        end)
        plus.Activated:Connect(function()
            setHitboxValue(key, hitboxValue(key, fallback, minimum, maximum) + step)
        end)
        updateHitboxRow(key)
    end

    makeHitboxValueCard("X", "Size X (studs)", 0, 174, 1, 50, 0.5, 2)
    makeHitboxValueCard("Y", "Size Y (studs)", 1, 174, 1, 50, 0.5, 2)
    makeHitboxValueCard("Z", "Size Z (studs)", 0, 270, 1, 50, 0.5, 1)
    makeHitboxValueCard("Transparency", "Transparency", 1, 270, 0, 1, 0.05, 0.5)

    local applyHitboxButton = uiButton(hitboxPage, "APPLY CHANGES", {
        Position = UDim2.fromOffset(22, 380),
        Size = UDim2.fromOffset(142, 34),
        BackgroundColor3 = Color3.fromRGB(38, 49, 62),
        TextColor3 = Color3.fromRGB(228, 237, 248),
    })
    local resetHitboxButton = uiButton(hitboxPage, "RESET DEFAULTS", {
        Position = UDim2.fromOffset(174, 380),
        Size = UDim2.fromOffset(134, 34),
    })
    hitboxStatus = uiText(hitboxPage, "Module status: waiting for settings.", {
        Position = UDim2.fromOffset(24, 420),
        Size = UDim2.new(1, -48, 0, 50),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(143, 160, 180),
        TextWrapped = true,
    })

    local function refreshHitboxStatus()
        local enabledText = hitboxCfg.Enabled and "ENABLED" or "DISABLED"
        local visibleText = hitboxCfg.Visible and "VISIBLE" or "HIDDEN"
        hitboxStatus.Text = string.format(
            "%s  •  X %.2f / Y %.2f / Z %.2f  •  %s  •  Refresh %.2fs",
            enabledText,
            hitboxValue("X", 2, 1, 50),
            hitboxValue("Y", 2, 1, 50),
            hitboxValue("Z", 1, 1, 50),
            visibleText,
            math.max(0.05, tonumber(hitboxCfg.RefreshTime) or 1)
        )
        hitboxStatus.TextColor3 = hitboxCfg.Enabled and Color3.fromRGB(111, 207, 151)
            or Color3.fromRGB(143, 160, 180)
    end

    local function applyHitboxChanges()
        hitboxCfg.X = hitboxValue("X", 2, 1, 50)
        hitboxCfg.Y = hitboxValue("Y", 2, 1, 50)
        hitboxCfg.Z = hitboxValue("Z", 1, 1, 50)
        hitboxCfg.Transparency = hitboxValue("Transparency", 0.5, 0, 1)
        hitboxCfg.RefreshTime = math.max(0.05, tonumber(hitboxCfg.RefreshTime) or 1)
        for key in pairs(hitboxRows) do updateHitboxRow(key) end

        local ok, err = pcall(updateHitboxes)
        nextHitbox = os.clock() + hitboxCfg.RefreshTime
        refreshDashboard()
        refreshHitboxStatus()
        if ok then
            hitboxStatus.Text = hitboxStatus.Text .. "  •  APPLIED"
            hitboxStatus.TextColor3 = Color3.fromRGB(111, 207, 151)
        else
            hitboxStatus.Text = "APPLY FAILED  •  " .. tostring(err)
            hitboxStatus.TextColor3 = Color3.fromRGB(224, 119, 119)
        end
    end

    hitboxEnabledButton.Activated:Connect(function()
        hitboxCfg.Enabled = not hitboxCfg.Enabled
        hitboxEnabledButton.Text = hitboxCfg.Enabled and "ON" or "OFF"
        hitboxEnabledButton.TextColor3 = hitboxCfg.Enabled and Color3.fromRGB(111, 207, 151)
            or Color3.fromRGB(154, 171, 192)
        applyHitboxChanges()
    end)

    hitboxVisibleButton.Activated:Connect(function()
        hitboxCfg.Visible = not hitboxCfg.Visible
        hitboxVisibleButton.Text = hitboxCfg.Visible and "VISIBLE" or "HIDDEN"
        hitboxVisibleButton.TextColor3 = hitboxCfg.Visible and accentColor or Color3.fromRGB(154, 171, 192)
        applyHitboxChanges()
    end)

    applyHitboxButton.Activated:Connect(applyHitboxChanges)

    resetHitboxButton.Activated:Connect(function()
        hitboxCfg.X = 2
        hitboxCfg.Y = 2
        hitboxCfg.Z = 1
        hitboxCfg.Transparency = 0.5
        for key in pairs(hitboxRows) do updateHitboxRow(key) end
        applyHitboxChanges()
        hitboxStatus.Text = hitboxStatus.Text .. "  •  DEFAULTS RESTORED"
    end)

    -- Settings
    heading(settingsPage, "Settings", "Preferencias leves para o painel.")
    local settingsCard = uiCard(settingsPage, "SettingsCard", UDim2.fromOffset(22, 82), UDim2.new(1, -44, 0, 196))
    uiText(settingsCard, "SYSTEM MONITOR", {
        Position = UDim2.fromOffset(16, 17),
        Size = UDim2.new(1, -160, 0, 20),
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
    })
    uiText(settingsCard, "Live metrics only on Overview and System.", {
        Position = UDim2.fromOffset(16, 40),
        Size = UDim2.new(1, -160, 0, 16),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local monitorToggle = uiButton(settingsCard, monitorEnabled and "ON" or "OFF", {
        Position = UDim2.new(1, -98, 0, 23),
        Size = UDim2.fromOffset(80, 30),
    })
    uiText(settingsCard, "COMPACT PANEL", {
        Position = UDim2.fromOffset(16, 78),
        Size = UDim2.new(1, -160, 0, 20),
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
    })
    uiText(settingsCard, "Reduce the panel footprint.", {
        Position = UDim2.fromOffset(16, 101),
        Size = UDim2.new(1, -160, 0, 16),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local compactToggle = uiButton(settingsCard, compactMode and "ON" or "OFF", {
        Position = UDim2.new(1, -98, 0, 84),
        Size = UDim2.fromOffset(80, 30),
    })
    local panelKeyLabel = uiText(settingsCard, "MENU SHORTCUT", {
        Position = UDim2.fromOffset(16, 139),
        Size = UDim2.new(1, -160, 0, 18),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
    })
    panelKeyButton = uiButton(settingsCard, panelKey.Name:upper(), {
        Position = UDim2.new(1, -98, 0, 145),
        Size = UDim2.fromOffset(80, 30),
        TextSize = 9,
    })
    local accentButton = uiButton(settingsPage, "CHANGE ACCENT", {
        Position = UDim2.fromOffset(22, 290),
        Size = UDim2.fromOffset(148, 34),
    })

    do
        local center = uiButton(settingsPage, "CENTER PANEL", {
            Position = UDim2.fromOffset(180, 290), Size = UDim2.fromOffset(150, 34), TextSize = 10,
        })
        center.Activated:Connect(function()
            menuPanel.Position = UDim2.fromScale(0.5, 0.5)
            if pushActivity then pushActivity("Panel centered", "Window position restored.", "info") end
        end)
        local unload = uiButton(settingsPage, "UNLOAD", {
            Position = UDim2.fromOffset(340, 290), Size = UDim2.fromOffset(150, 34), TextSize = 10,
            TextColor3 = Color3.fromRGB(224, 119, 119),
        })
        local armedAt = nil
        unload.Activated:Connect(function()
            local now = os.clock()
            if armedAt and now - armedAt <= 4 then
                armedAt = nil
                if type(env.DHC_Stop) == "function" then env.DHC_Stop() end
                return
            end
            armedAt = now
            unload.Text = "CONFIRM UNLOAD"
            task.delay(4, function()
                if running and unload.Parent and armedAt == now then
                    armedAt = nil
                    unload.Text = "UNLOAD"
                end
            end)
        end)
    end
    local profileCard = uiCard(settingsPage, "UIProfile", UDim2.fromOffset(22, 334), UDim2.new(1, -44, 0, 116))
    uiText(profileCard, "UI PROFILE", {
        Position = UDim2.fromOffset(15, 8),
        Size = UDim2.new(1, -30, 0, 16),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
    })
    uiText(profileCard, "Saves only panel appearance and interface preferences.", {
        Position = UDim2.fromOffset(15, 25),
        Size = UDim2.new(1, -30, 0, 14),
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local saveProfileButton = uiButton(profileCard, "SAVE", {
        Position = UDim2.fromOffset(15, 48),
        Size = UDim2.fromOffset(88, 28),
    })
    local loadProfileButton = uiButton(profileCard, "LOAD", {
        Position = UDim2.fromOffset(111, 48),
        Size = UDim2.fromOffset(88, 28),
    })
    local resetProfileButton = uiButton(profileCard, "RESET", {
        Position = UDim2.fromOffset(207, 48),
        Size = UDim2.fromOffset(88, 28),
    })
    local scaleLabel = uiText(profileCard, "UI SCALE", {
        Position = UDim2.new(1, -194, 0, 51),
        Size = UDim2.fromOffset(70, 22),
        Font = Enum.Font.GothamSemibold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local scaleValueLabel = uiText(profileCard, string.format("%.2fx", uiScaleValue), {
        Position = UDim2.new(1, -120, 0, 51),
        Size = UDim2.fromOffset(42, 22),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = accentColor,
    })
    local scaleMinus = uiButton(profileCard, "−", {
        Position = UDim2.new(1, -75, 0, 48),
        Size = UDim2.fromOffset(25, 28),
    })
    local scalePlus = uiButton(profileCard, "+", {
        Position = UDim2.new(1, -44, 0, 48),
        Size = UDim2.fromOffset(25, 28),
    })
    local profileStatus = uiText(profileCard, "UI preferences only  •  no gameplay values are stored", {
        Position = UDim2.fromOffset(15, 84),
        Size = UDim2.new(1, -30, 0, 16),
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
    })
    local settingsNote = uiText(settingsPage, "UI scale: 0.85x–1.10x  •  telemetry every 2s, visible pages only", {
        Position = UDim2.fromOffset(24, 454),
        Size = UDim2.new(1, -48, 0, 22),
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(143, 160, 180),
        TextWrapped = true,
    })

    reportProfileSave = function()
        profileStatus.Text = "PENDING  •  SAVING UI PREFERENCES"
        profileStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
        local ok, mode = saveUIPreferences()
        profileStatus.Text = ok and (mode == "FILE" and "SAVED  •  PROFILE ON DISK" or "SAVED  •  SESSION ONLY")
            or ("PENDING  •  SAVE FAILED: " .. tostring(mode))
        profileStatus.TextColor3 = ok and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(224, 119, 119)
        return ok, mode
    end

    -- Activity center: event-driven history, capped at 30 entries.
    heading(activityPage, "Activity center", "Notificacoes e eventos recentes da interface.")
    activityCountLabel = uiText(activityPage, "00 EVENTS", {
        Position = UDim2.fromOffset(24, 72),
        Size = UDim2.fromOffset(110, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = accentColor,
    })
    local clearActivityButton = uiButton(activityPage, "CLEAR HISTORY", {
        Position = UDim2.new(1, -148, 0, 68),
        Size = UDim2.fromOffset(124, 28),
    })
    local activityFilter = "all"
    local activityFilterButtons = {}
    activityList = uiNew("ScrollingFrame", {
        Name = "ActivityList",
        Position = UDim2.fromOffset(22, 146),
        Size = UDim2.new(1, -44, 1, -168),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(89, 119, 151),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, activityPage)
    uiNew("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, activityList)

    local activityEmpty = uiText(activityPage, "No events in this category.", {
        Position = UDim2.fromOffset(22, 162),
        Size = UDim2.new(1, -44, 0, 60),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = Color3.fromRGB(143, 160, 180),
        TextSize = 12,
        Visible = false,
    })
    local function refreshActivityFilter()
        local visibleCount = 0
        for _, row in ipairs(activityRows) do
            if row.Parent then
                row.Visible = activityFilter == "all" or row:GetAttribute("ActivityKind") == activityFilter
                if row.Visible then visibleCount = visibleCount + 1 end
            end
        end
        activityCountLabel.Text = string.format("%02d / %02d EVENTS", visibleCount, #activityRows)
        activityEmpty.Visible = visibleCount == 0
        for name, button in pairs(activityFilterButtons) do
            button.BackgroundColor3 = name == activityFilter and Color3.fromRGB(32, 54, 80) or Color3.fromRGB(23, 37, 55)
        end
    end
    for index, name in ipairs({"all", "info", "success", "error"}) do
        local category = name
        local button = uiButton(activityPage, category:upper(), {
            Position = UDim2.fromOffset(22 + (index - 1) * 86, 106),
            Size = UDim2.fromOffset(78, 28),
            TextSize = 9,
        })
        activityFilterButtons[category] = button
        button.Activated:Connect(function()
            activityFilter = category
            refreshActivityFilter()
        end)
    end
    refreshActivityFilter()

    pushActivity = function(title, detail, kind)
        if not activityList or not activityList.Parent then return end
        local stamp = os.date("%H:%M:%S")
        local row = uiCard(activityList, "ActivityEntry", UDim2.new(), UDim2.new(1, -8, 0, 58))
        row:SetAttribute("ActivityKind", (kind == "success" or kind == "error") and kind or "info")
        table.insert(activityRows, 1, row)
        row.LayoutOrder = 1
        for index, existing in ipairs(activityRows) do
            if existing and existing.Parent then existing.LayoutOrder = index end
        end
        local dotColor = kind == "error" and Color3.fromRGB(224, 119, 119)
            or (kind == "success" and Color3.fromRGB(111, 207, 151) or accentColor)
        local dot = uiNew("Frame", {
            Position = UDim2.fromOffset(13, 25),
            Size = UDim2.fromOffset(7, 7),
            BackgroundColor3 = dotColor,
            BorderSizePixel = 0,
        }, row)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)
        uiText(row, tostring(title or "Event"), {
            Position = UDim2.fromOffset(29, 7),
            Size = UDim2.new(1, -120, 0, 18),
            Font = Enum.Font.GothamSemibold,
            TextSize = 10,
        })
        uiText(row, tostring(detail or ""), {
            Position = UDim2.fromOffset(29, 27),
            Size = UDim2.new(1, -120, 0, 19),
            Font = Enum.Font.Gotham,
            TextSize = 8,
            TextColor3 = Color3.fromRGB(143, 160, 180),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        uiText(row, stamp, {
            Position = UDim2.new(1, -82, 0, 18),
            Size = UDim2.fromOffset(68, 18),
            Font = Enum.Font.GothamMedium,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Color3.fromRGB(143, 160, 180),
        })
        while #activityRows > 30 do
            local oldest = table.remove(activityRows)
            if oldest and oldest.Parent then oldest:Destroy() end
        end
        refreshActivityFilter()
    end
    env.V4wareNotify = function(title, detail, kind)
        if pushActivity then pushActivity(title, detail, kind) end
    end
    clearActivityButton.Activated:Connect(function()
        for _, row in ipairs(activityRows) do
            if row and row.Parent then row:Destroy() end
        end
        table.clear(activityRows)
        refreshActivityFilter()
    end)

    local function applyAccent()
        accentColor = accentChoices[accentIndex]
        for _, element in ipairs(accentElements) do
            element.BackgroundColor3 = accentColor
        end
        logoText.TextColor3 = accentColor
        for _, item in pairs(navItems) do item.bar.BackgroundColor3 = accentColor end
        for _, row in pairs(spreadRows) do row.fill.BackgroundColor3 = accentColor end
        for _, row in pairs(hitboxRows) do
            row.fill.BackgroundColor3 = accentColor
            row.value.TextColor3 = accentColor
        end
        for _, card in pairs(featureCards) do card.value.TextColor3 = accentColor end
        for _, value in pairs(dashboardMetrics) do value.TextColor3 = accentColor end
        if activityCountLabel then activityCountLabel.TextColor3 = accentColor end
        if scaleValueLabel then scaleValueLabel.TextColor3 = accentColor end
    end

    accentButton.Activated:Connect(function()
        accentIndex = accentIndex % #accentChoices + 1
        applyAccent()
        local saved, mode = reportProfileSave()
        if pushActivity then pushActivity("Accent changed", saved and "Interface color updated." or tostring(mode), saved and "success" or "error") end
    end)

    panelKeyButton.Activated:Connect(function()
        capturingPanelKey = true
        panelKeyButton.Text = "PRESS KEY"
        if pushActivity then pushActivity("Shortcut capture", "Press a keyboard key; Escape cancels.", "info") end
    end)

    saveProfileButton.Activated:Connect(function()
        local ok, mode = reportProfileSave()
        if pushActivity then pushActivity(ok and "UI profile saved" or "UI profile pending", tostring(mode), ok and "success" or "error") end
    end)

    loadProfileButton.Activated:Connect(function()
        local loaded = loadUIPreferences()
        if not loaded then
            profileStatus.Text = "NO SAVED UI PROFILE FOUND"
            profileStatus.TextColor3 = Color3.fromRGB(226, 185, 112)
            if pushActivity then pushActivity("UI profile not found", "Save a profile first.", "info") end
            return
        end
        panelScale.Scale = uiScaleValue
        menuPanel.Size = compactMode and UDim2.fromOffset(820, 550) or UDim2.fromOffset(880, 580)
        monitorToggle.Text = monitorEnabled and "ON" or "OFF"
        compactToggle.Text = compactMode and "ON" or "OFF"
        panelKeyButton.Text = panelKey.Name:upper()
        applyAccent()
        scaleValueLabel.Text = string.format("%.2fx", uiScaleValue)
        if updateSystemMonitor then updateSystemMonitor() end
        if syncFPSCounter then syncFPSCounter() end
        if refreshDashboard then refreshDashboard() end
        profileStatus.Text = "UI PROFILE LOADED"
        profileStatus.TextColor3 = Color3.fromRGB(111, 207, 151)
        if pushActivity then pushActivity("UI profile loaded", "Appearance preferences restored.", "success") end
    end)

    resetProfileButton.Activated:Connect(function()
        accentIndex = 1
        accentColor = accentChoices[accentIndex]
        compactMode = false
        monitorEnabled = true
        panelKey = Enum.KeyCode.Insert
        uiScaleValue = 1
        panelScale.Scale = uiScaleValue
        menuPanel.Size = UDim2.fromOffset(880, 580)
        monitorToggle.Text = "ON"
        compactToggle.Text = "OFF"
        panelKeyButton.Text = "INSERT"
        scaleValueLabel.Text = "1.00x"
        applyAccent()
        local saved, mode = reportProfileSave()
        if updateSystemMonitor then updateSystemMonitor() end
        if syncFPSCounter then syncFPSCounter() end
        if saved then profileStatus.Text = "DEFAULTS RESTORED  •  " .. (mode == "FILE" and "SAVED" or "SESSION ONLY") end
        if pushActivity then pushActivity("UI preferences reset", saved and "Default interface settings restored." or tostring(mode), saved and "success" or "error") end
    end)

    local function changeUIScale(delta)
        uiScaleValue = math.clamp(math.floor((uiScaleValue + delta) * 100 + 0.5) / 100, 0.85, 1.10)
        panelScale.Scale = uiScaleValue
        scaleValueLabel.Text = string.format("%.2fx", uiScaleValue)
        reportProfileSave()
    end
    scaleMinus.Activated:Connect(function() changeUIScale(-0.05) end)
    scalePlus.Activated:Connect(function() changeUIScale(0.05) end)

    monitorToggle.Activated:Connect(function()
        monitorEnabled = not monitorEnabled
        monitorToggle.Text = monitorEnabled and "ON" or "OFF"
        monitorToggle.TextColor3 = monitorEnabled and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(160, 166, 176)
        if updateSystemMonitor then updateSystemMonitor() end
        if syncFPSCounter then syncFPSCounter() end
        reportProfileSave()
        if pushActivity then pushActivity("System monitor", monitorEnabled and "Telemetry enabled." or "Telemetry paused.", "info") end
    end)

    compactToggle.Activated:Connect(function()
        compactMode = not compactMode
        compactToggle.Text = compactMode and "ON" or "OFF"
        menuPanel.Size = compactMode and UDim2.fromOffset(820, 550) or UDim2.fromOffset(880, 580)
        reportProfileSave()
        if pushActivity then pushActivity("Panel layout", compactMode and "Compact mode enabled." or "Compact mode disabled.", "info") end
    end)

    -- Render helpers
    local function renderPlayers()
        if not menuPlayers or not menuPlayers.Parent then return end
        for _, child in ipairs(menuPlayers:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
        end

        local roster = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then table.insert(roster, player) end
        end
        table.sort(roster, function(a, b) return a.Name:lower() < b.Name:lower() end)

        local protected = 0
        for index, player in ipairs(roster) do
            local targetPlayer = player
            local list = selectedPlayerTab == "whitelist" and Config.Triggerbot.Whitelist.List or Config.IncognitoWhitelist
            local active = isInList(list, targetPlayer)
            if active then protected = protected + 1 end

            local row = uiCard(menuPlayers, "Player_" .. tostring(targetPlayer.UserId),
                UDim2.new(0, 0, 0, 0), UDim2.new(1, -5, 0, 56))
            row.LayoutOrder = index

            local avatar = uiNew("Frame", {
                Name = "AvatarInitial", Position = UDim2.fromOffset(10,8),
                Size = UDim2.fromOffset(40,40), BackgroundColor3 = Color3.fromRGB(28,44,65), BorderSizePixel = 0,
            }, row)
            uiNew("UICorner", {CornerRadius = UDim.new(0,10)}, avatar)
            uiText(avatar, string.upper(string.sub(targetPlayer.Name,1,1)), {
                Size=UDim2.fromScale(1,1), TextXAlignment=Enum.TextXAlignment.Center,
                TextSize=18, Font=Enum.Font.GothamBold, TextColor3=accentColor,
            })

            uiText(row, targetPlayer.DisplayName, {
                Position = UDim2.fromOffset(62, 8),
                Size = UDim2.new(1, -205, 0, 22),
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Color3.fromRGB(235, 238, 243),
            })
            if targetPlayer.DisplayName ~= targetPlayer.Name then
                uiText(row, "@" .. targetPlayer.Name, {
                    Position = UDim2.fromOffset(62, 29),
                    Size = UDim2.new(1, -205, 0, 15),
                    TextSize = 10,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextColor3 = Color3.fromRGB(143, 148, 157),
                })
            end

            local eye = uiButton(row, "◉", {
                Position = UDim2.new(1, -112, 0, 8),
                Size = UDim2.fromOffset(34, 40),
                BackgroundTransparency = 1,
                TextSize = 17,
                TextColor3 = spectateTarget == targetPlayer and accentColor or Color3.fromRGB(183, 199, 218),
            })
            eye.Activated:Connect(function()
                startSpectating(targetPlayer)
                renderMenu()
            end)

            local toggle = uiButton(row, active and "ON" or "OFF", {
                Position = UDim2.new(1, -70, 0, 10),
                Size = UDim2.fromOffset(56, 36),
                TextSize = 10,
                TextColor3 = active and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(154, 171, 192),
            })
            toggle.Activated:Connect(function()
                local targetList = selectedPlayerTab == "whitelist" and Config.Triggerbot.Whitelist.List or Config.IncognitoWhitelist
                local key = tostring(targetPlayer.UserId)
                if isInList(targetList, targetPlayer) then
                    targetList[key] = nil
                    targetList[targetPlayer.UserId] = nil
                    targetList[targetPlayer.Name] = nil
                    for k, v in pairs(targetList) do
                        if v == targetPlayer.UserId or v == tostring(targetPlayer.UserId) or v == targetPlayer.Name then
                            targetList[k] = nil
                        end
                    end
                else
                    targetList[key] = true
                end
                if camTarget == targetPlayer and not onWhitelist(targetPlayer) then camTarget = nil end
                refreshESP()
                renderMenu()
            end)
        end

        if #roster == 0 then
            local empty = uiCard(menuPlayers, "EmptyRoster", UDim2.new(), UDim2.new(1, -8, 0, 128))
            uiText(empty, "SESSION  /  SOLO", {
                Position = UDim2.fromOffset(12, 16), Size = UDim2.new(1, -24, 0, 20),
                Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = accentColor,
                TextXAlignment = Enum.TextXAlignment.Center,
            })
            uiText(empty, "Nenhum outro jogador na sessao", {
                Position = UDim2.fromOffset(12, 43), Size = UDim2.new(1, -24, 0, 24),
                Font = Enum.Font.GothamSemibold, TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Center,
            })
            uiText(empty, "A lista sera atualizada quando outro jogador entrar.", {
                Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 30),
                TextSize = 10, TextColor3 = Color3.fromRGB(143, 160, 180),
                TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
            })
        end

        local labelText = selectedPlayerTab == "whitelist" and "PROTECTED PLAYERS" or "HIDDEN PLAYERS"
        menuCount.Text = string.format("%s  •  %d entries  •  %s to toggle", labelText, protected, panelKey.Name:upper())
    end

    renderMenu = function()
        for pageName, pageFrame in pairs(pages) do
            pageFrame.Visible = pageName:lower() == selectedTab
        end
        lastRenderedTab = selectedTab

        for name, item in pairs(navItems) do
            local active = name:lower() == selectedTab
            local wasActive = item.active
            item.active = active
            if active then
                item.bar.Visible = true
                if not wasActive then
                    item.bar.Size = UDim2.fromOffset(3, 26)
                end
            else
                item.bar.Visible = false
                item.bar.Size = UDim2.fromOffset(3, 26)
            end
            item.button.BackgroundTransparency = active and 0 or 1
            item.button.BackgroundColor3 = active and Color3.fromRGB(24, 40, 60) or Color3.fromRGB(15, 24, 39)
            item.title.TextColor3 = active and Color3.fromRGB(244, 248, 255) or Color3.fromRGB(148, 166, 188)
            item.icon.TextColor3 = active and accentColor or Color3.fromRGB(148, 166, 188)
            item.stroke.Transparency = active and 0.72 or 1
        end

        if selectedTab == "players" then
            tabWhitelist.BackgroundColor3 = selectedPlayerTab == "whitelist" and Color3.fromRGB(32, 54, 80) or Color3.fromRGB(23, 37, 55)
            tabIncognito.BackgroundColor3 = selectedPlayerTab == "incognito" and Color3.fromRGB(32, 54, 80) or Color3.fromRGB(23, 37, 55)
            renderPlayers()
        elseif selectedTab == "system" then
            updateSystemMonitor()
        elseif selectedTab == "overview" then
            refreshDashboard()
        elseif selectedTab == "activity" then
            refreshActivityFilter()
        elseif selectedTab == "spread" then
            for _, item in ipairs(spreadNames) do updateSpreadRow(item.key) end
            local patched = (spreadPatched["[Double-Barrel SG]"] or 0)
                + (spreadPatched["[TacticalShotgun]"] or 0)
                + (spreadPatched["[Revolver]"] or 0)
            spreadInfo.Text = string.format("Matched functions: %d  |  patched constants: %d", spreadCandidatesSeen, patched)
        elseif selectedTab == "hitbox" then
            for key in pairs(hitboxRows) do updateHitboxRow(key) end
            hitboxEnabledButton.Text = hitboxCfg.Enabled and "ON" or "OFF"
            hitboxVisibleButton.Text = hitboxCfg.Visible and "VISIBLE" or "HIDDEN"
            refreshHitboxStatus()
        end

        if syncFPSCounter then syncFPSCounter() end
    end

    for name, item in pairs(navItems) do
        item.button.Activated:Connect(function()
            selectedTab = name:lower()
            renderMenu()
        end)
    end

    tabWhitelist.Activated:Connect(function()
        selectedPlayerTab = "whitelist"
        renderMenu()
    end)
    tabIncognito.Activated:Connect(function()
        selectedPlayerTab = "incognito"
        renderMenu()
    end)

    local dragging = false
    local dragOrigin, startPosition
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragOrigin = input.Position
            startPosition = menuPanel.Position
        end
    end)
    connectSignal(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragOrigin
            menuPanel.Position = UDim2.new(
                startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
            )
        end
    end)
    connectSignal(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    minimize.Activated:Connect(function()
        body.Visible = not body.Visible
        menuBodyVisible = body.Visible
        menuPanel.Size = body.Visible
            and (compactMode and UDim2.fromOffset(820, 550) or UDim2.fromOffset(880, 580))
            or UDim2.fromOffset(880, 74)
        minimize.Text = body.Visible and "–" or "+"
        if syncFPSCounter then syncFPSCounter() end
        if body.Visible and renderMenu then renderMenu() end
    end)

    close.Activated:Connect(function()
        capturingPanelKey = false
        if panelKeyButton then panelKeyButton.Text = panelKey.Name:upper() end
        dragging = false
        menuVisible = false
        if menuGui then menuGui.Enabled = false end
        if syncFPSCounter then syncFPSCounter() end
    end)

    renderMenu()
end

buildMenu()
if pushActivity then pushActivity("V4WARE V21.4 ready", "Utility dashboard initialized.", "success") end

-- FPS sampler sob demanda: não mantém callback RenderStepped quando o monitor
-- não está visível/ativo. A medição usa uma janela de 2 segundos.
syncFPSCounter = function()
    local shouldSample = running
        and monitorEnabled
        and menuGui ~= nil
        and menuVisible and menuBodyVisible and menuGui.Enabled
        and (selectedTab == "system" or selectedTab == "overview")

    if shouldSample then
        if not fpsCounterConnection then
            fpsFrameCount = 0
            fpsElapsed = 0
            fpsCounterConnection = RunService.RenderStepped:Connect(function(dt)
                if not running then return end
                fpsFrameCount = fpsFrameCount + 1
                fpsElapsed = fpsElapsed + dt
                if fpsElapsed >= 2 then
                    local frames, elapsed = fpsFrameCount, fpsElapsed
                    currentFPS = math.floor((frames / elapsed) + 0.5)
                    fpsSampleAt = os.clock()
                    fpsFrameCount, fpsElapsed = 0, 0
                    -- UI reads are deferred out of RenderStepped.
                    task.defer(function()
                        if not running or not monitorEnabled or not menuVisible or not menuBodyVisible or not menuGui or not menuGui.Enabled then return end
                        if selectedTab ~= "system" and selectedTab ~= "overview" then return end
                        perf.record()
                        if selectedTab == "system" then updateSystemMonitor() else refreshDashboard() end
                    end)
                end
            end)
        end
    elseif fpsCounterConnection then
        pcall(function() fpsCounterConnection:Disconnect() end)
        fpsCounterConnection = nil
        fpsFrameCount = 0
        fpsElapsed = 0
        -- Preserva a ultima amostra; displayFPS sinaliza valores antigos.
    end
end

syncFPSCounter()

connectSignal(UserInputService.InputBegan, function(input, processed)
    if capturingPanelKey and input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Unknown then
            capturingPanelKey = false
            if panelKeyButton then panelKeyButton.Text = panelKey.Name:upper() end
            return
        end
        panelKey = input.KeyCode
        capturingPanelKey = false
        if panelKeyButton then panelKeyButton.Text = panelKey.Name:upper() end
        if reportProfileSave then reportProfileSave() else saveUIPreferences() end
        if pushActivity then pushActivity("Menu shortcut updated", "New shortcut: " .. panelKey.Name, "success") end
        return
    end
    if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == panelKey and menuGui then
        menuVisible = not menuVisible
        menuGui.Enabled = menuVisible
        if menuVisible then
            panelScale.Scale = uiScaleValue
            if renderMenu then renderMenu() end
        end
        if syncFPSCounter then syncFPSCounter() end
    end
end)

connectSignal(Players.PlayerAdded, function()
    if running and menuVisible and menuBodyVisible and renderMenu and menuGui and menuGui.Parent and menuGui.Enabled and selectedTab == "players" then
        renderMenu()
    end
end)

connectSignal(Players.PlayerRemoving, function(player)
    if spectateTarget == player then stopSpectating() end
    task.defer(function()
        if running and menuVisible and menuBodyVisible and renderMenu and menuGui and menuGui.Parent and menuGui.Enabled and selectedTab == "players" then
            renderMenu()
        end
    end)
end)

connectSignal(RunService.Heartbeat, function(dt)
    if spectateTarget and spectateTarget.Parent == Players then
        local hum = humanoidOf(charOf(spectateTarget))
        local cam = camera()
        if hum and cam and cam.CameraSubject ~= hum then
            cam.CameraType = Enum.CameraType.Custom
            cam.CameraSubject = hum
        end
    end
end)

local function stop()
    if not running then return end
    running = false
    if fpsCounterConnection then
        pcall(function() fpsCounterConnection:Disconnect() end)
        fpsCounterConnection = nil
    end
    stopSpectating()
    if menuGui and menuGui.Parent then menuGui:Destroy() end
    menuGui = nil
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    for player in pairs(espObjects) do clearESP(player) end
    restoreHitboxes()
    restoreSpread()
    if env.DHC_Stop == stop then env.DHC_Stop = nil end
    if env.DHC_Status == status then env.DHC_Status = nil end
    if env.V4wareNotify then env.V4wareNotify = nil end
    print("[V4ware V21.4] Parado; interface encerrada e conexoes limpas.")
end

env.DHC_Stop = stop
env.DHC_Status = status
refreshESP()
updateHitboxes()
updateSpread()
print("[V4ware V21.4] Iniciado: painel (Overview / Players / Spread / Hitbox / System / Settings / Activity / Diagnostics) | preferencias visuais separadas")
print("[V4ware V20] Trigger: delay cliente 0 | DB 180 | Revolver 260 | Tactical 180 | limite geral 280 studs")
print("[V4ware V21.4] Menu: atalho configuravel | Status: getgenv().DHC_Status() | Parar: getgenv().DHC_Stop()")
warn("[V4ware V20] Experimento de patch de CONSTANTES especificas. Sem hook FireServer; resultado real nao testado.")
print("[V4ware WS] Weapon Switch ativo: V -> DB / Tactical / Revolver, respeitando cooldowns do jogo")
