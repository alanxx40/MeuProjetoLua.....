-- V4WARE V20.4 - ESP 0.1s + UI MONITOR OTIMIZADO (base V20.2 preservada, Config separada)
-- Este arquivo pressupoe que a tabela global Config ja existe no ambiente que o carrega.
-- Mantenha a configuracao no arquivo/trecho local e hospede este arquivo como Main.lua.

-- =============================================================
-- SERVICOS, ESTADO E LIMPEZA DE EXECUCOES ANTERIORES
-- =============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer
local sessionStartedAt = os.clock()
local env = (type(getgenv) == "function" and getgenv()) or _G

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

local function passes(player, checks)
    if not player or player == LocalPlayer or not onWhitelist(player) then return false end
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

local function visible(part, character)
    local cam = camera()
    if not cam or not part then return false end
    local difference = part.Position - cam.CFrame.Position
    if difference.Magnitude < 0.01 then return true end
    local filter = {}
    if charOf(LocalPlayer) then table.insert(filter, charOf(LocalPlayer)) end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = filter
    params.IgnoreWater = true
    local hit = Workspace:Raycast(cam.CFrame.Position, difference, params)
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
    -- Usar o evento natural Tool:Activate para nao depender de codigo remoto.
    -- Alguns jogos so disparam pela entrada real do mouse: nesse caso nao funcionara.
    local ok = pcall(function() tool:Activate() end)
    if ok then lastShot = os.clock() end
end

local function updateTrigger()
    if weaponSwitchBusy then return end -- evita disparos concorrentes durante a sequencia
    if not Config.Triggerbot.Enabled or not triggerActive then return end
    -- FireDelay=0: nenhuma espera artificial antes de tentar Tool:Activate().
    -- Executa a checagem a cada RenderStepped; nao acelera a cadencia imposta pelo jogo.
    local clientDelay = math.max(0, tonumber(Config.Triggerbot.FireDelay) or 0)
    if clientDelay > 0 and os.clock() - lastShot < clientDelay then return end
    local tool = equippedTool()
    if not tool or knife(tool) then return end
    local range = Config.Triggerbot["Range-Check"]
    local maxDist = range.Data[tool.Name]
    if range.Enabled and maxDist == nil then return end
    local cam = camera()
    if not cam then return end
    local mouse = UserInputService:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse.X, mouse.Y)
    local filter = {}
    if charOf(LocalPlayer) then table.insert(filter, charOf(LocalPlayer)) end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = filter
    params.IgnoreWater = true
    -- Limite real: aplica distancia maxima por arma e teto global.
    local length = math.clamp(tonumber(maxDist) or 0, 0, math.max(1, tonumber(range.HardCap) or 280))
    if length <= 0 then return end
    local hit = Workspace:Raycast(ray.Origin, ray.Direction * length, params)
    if not hit then return end
    local target = playerFromPart(hit.Instance)
    if not target or not onWhitelist(target) then return end
    -- Segunda verificacao: distancia entre personagens, nao apenas camera e alvo.
    local myRoot = rootOf(charOf(LocalPlayer))
    local targetRoot = rootOf(charOf(target))
    if not myRoot or not targetRoot then return end
    if (targetRoot.Position - myRoot.Position).Magnitude > length then return end
    if Config.Triggerbot.Hitbox.Enabled and not passes(target, Config.Triggerbot.Hitbox.Checks) then return end
    if not passes(target) then return end
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
        Version = 20.4,
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
        RemoteHooks = false,
    }
end


-- =============================================================
-- V4WARE V20 PREMIUM HUB
-- Interface redesenhada sobre a base V19; modulos principais preservados.
-- =============================================================
local menuGui, menuPanel, menuPlayers, menuCount, tabWhitelist, tabIncognito, tabSystem, monitorFrame
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
local fpsFrameCount, fpsElapsed = 0, 0
local monitorRefreshElapsed = 0
local dashboardRefreshElapsed = 0
local monitorEnabled = true
local compactMode = false
local panelKey = Enum.KeyCode.Insert
local accentColor = Color3.fromRGB(160, 190, 222)
local accentChoices = {
    Color3.fromRGB(160, 190, 222),
    Color3.fromRGB(139, 202, 178),
    Color3.fromRGB(180, 166, 225),
}
local accentIndex = 1

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
        TextColor3 = Color3.fromRGB(224, 229, 237),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BorderSizePixel = 0,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return uiNew("TextLabel", p, parent)
end

-- Hover motion: tweens event-driven (sem loop por frame), com escala e realce discretos.
local HOVER_IN = TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PAGE_IN = TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local function playUiTween(target, info, properties)
    if not target or not target.Parent then return nil end
    local ok, tween = pcall(function()
        return TweenService:Create(target, info, properties)
    end)
    if ok and tween then
        tween:Play()
        return tween
    end
    return nil
end

local function addHoverMotion(guiObject, options)
    options = options or {}
    if not guiObject or not guiObject:IsA("GuiObject") then return end

    local scale = uiNew("UIScale", {Scale = 1}, guiObject)
    local stroke = guiObject:FindFirstChildOfClass("UIStroke")
    local baseBackground = guiObject.BackgroundColor3
    local baseTransparency = guiObject.BackgroundTransparency
    local baseTextColor = guiObject:IsA("TextButton") and guiObject.TextColor3 or nil
    local baseStrokeColor = stroke and stroke.Color or nil
    local baseStrokeThickness = stroke and stroke.Thickness or nil
    local hoverScale = options.Scale or 1.025
    local blend = options.Blend or 0.10

    guiObject.MouseEnter:Connect(function()
        playUiTween(scale, HOVER_IN, {Scale = hoverScale})

        local enterProperties = {}
        if baseTransparency < 1 and options.Background ~= false then
            enterProperties.BackgroundColor3 = baseBackground:Lerp(accentColor, blend)
        end
        if baseTextColor then
            enterProperties.TextColor3 = baseTextColor:Lerp(Color3.fromRGB(255, 255, 255), 0.14)
        end
        if next(enterProperties) then
            playUiTween(guiObject, HOVER_IN, enterProperties)
        end
        if stroke then
            playUiTween(stroke, HOVER_IN, {
                Color = accentColor,
                Thickness = math.max(baseStrokeThickness or 1, 1.35),
            })
        end
    end)

    guiObject.MouseLeave:Connect(function()
        playUiTween(scale, HOVER_OUT, {Scale = 1})

        local leaveProperties = {}
        if baseTransparency < 1 and options.Background ~= false then
            leaveProperties.BackgroundColor3 = baseBackground
        end
        if baseTextColor then
            leaveProperties.TextColor3 = baseTextColor
        end
        if next(leaveProperties) then
            playUiTween(guiObject, HOVER_OUT, leaveProperties)
        end
        if stroke then
            playUiTween(stroke, HOVER_OUT, {
                Color = baseStrokeColor,
                Thickness = baseStrokeThickness,
            })
        end
    end)
end

local function uiButton(parent, txt, props)
    local p = {
        Text = txt,
        BackgroundColor3 = Color3.fromRGB(29, 33, 40),
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        TextColor3 = Color3.fromRGB(226, 231, 239),
        AutoButtonColor = false,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    local button = uiNew("TextButton", p, parent)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 8)}, button)
    uiNew("UIStroke", {Color = Color3.fromRGB(47, 54, 64), Thickness = 1}, button)
    addHoverMotion(button, {Scale = 1.035, Blend = 0.18})
    return button
end

local function uiCard(parent, name, position, size)
    local card = uiNew("Frame", {
        Name = name,
        Position = position,
        Size = size,
        BackgroundColor3 = Color3.fromRGB(23, 27, 33),
        BorderSizePixel = 0,
    }, parent)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 10)}, card)
    uiNew("UIStroke", {Color = Color3.fromRGB(43, 49, 58), Thickness = 1}, card)
    addHoverMotion(card, {Scale = 1.018, Blend = 0.12})
    return card
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

local function buildMenu()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        warn("[V4ware] PlayerGui nao encontrado; menu nao criado")
        return
    end

    local old = playerGui:FindFirstChild("V4ware_ControlPanel")
    if old then old:Destroy() end

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
        Size = UDim2.fromOffset(740, 500),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(12, 14, 18),
        BorderSizePixel = 0,
        Active = true,
    }, menuGui)
    panelScale = uiNew("UIScale", {Scale = 1}, menuPanel)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 14)}, menuPanel)
    uiNew("UIStroke", {Color = Color3.fromRGB(43, 49, 59), Thickness = 1}, menuPanel)
    uiNew("UISizeConstraint", {
        MinSize = Vector2.new(620, 66),
        MaxSize = Vector2.new(900, 620),
    }, menuPanel)

    -- Header
    local header = uiNew("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 66),
        BackgroundColor3 = Color3.fromRGB(17, 20, 25),
        BorderSizePixel = 0,
    }, menuPanel)
    uiNew("UICorner", {CornerRadius = UDim.new(0, 14)}, header)
    uiNew("Frame", {
        Position = UDim2.new(0, 0, 1, -13),
        Size = UDim2.new(1, 0, 0, 13),
        BackgroundColor3 = Color3.fromRGB(17, 20, 25),
        BorderSizePixel = 0,
    }, header)

    local logo = uiCard(header, "LogoMark", UDim2.fromOffset(18, 14), UDim2.fromOffset(38, 38))
    uiText(logo, "V4", {
        Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = accentColor,
    })
    uiText(header, "V4ware", {
        Position = UDim2.fromOffset(66, 12),
        Size = UDim2.fromOffset(170, 24),
        Font = Enum.Font.GothamSemibold,
        TextSize = 18,
        TextColor3 = Color3.fromRGB(241, 244, 249),
    })
    uiText(header, "CLEAN CONTROL CENTER  •  V20.1", {
        Position = UDim2.fromOffset(67, 35),
        Size = UDim2.fromOffset(240, 14),
        Font = Enum.Font.GothamMedium,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(133, 143, 157),
    })

    local onlinePill = uiNew("Frame", {
        Position = UDim2.new(1, -142, 0, 21),
        Size = UDim2.fromOffset(74, 24),
        BackgroundColor3 = Color3.fromRGB(24, 43, 36),
        BorderSizePixel = 0,
    }, header)
    uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, onlinePill)
    local dot = uiNew("Frame", {
        Position = UDim2.fromOffset(9, 8),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = Color3.fromRGB(111, 207, 151),
        BorderSizePixel = 0,
    }, onlinePill)
    uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)
    uiText(onlinePill, "ONLINE", {
        Position = UDim2.fromOffset(22, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(111, 207, 151),
    })

    local minimize = uiButton(header, "–", {
        Position = UDim2.new(1, -61, 0, 19),
        Size = UDim2.fromOffset(27, 27),
        TextSize = 16,
    })
    local close = uiButton(header, "×", {
        Position = UDim2.new(1, -29, 0, 19),
        Size = UDim2.fromOffset(27, 27),
        TextSize = 17,
    })

    -- Sidebar
    local body = uiNew("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, 66),
        Size = UDim2.new(1, 0, 1, -66),
        BackgroundTransparency = 1,
    }, menuPanel)

    local sidebar = uiNew("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 158, 1, 0),
        BackgroundColor3 = Color3.fromRGB(17, 20, 25),
        BorderSizePixel = 0,
    }, body)
    uiNew("Frame", {
        Position = UDim2.new(1, -1, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Color3.fromRGB(43, 49, 59),
        BorderSizePixel = 0,
    }, sidebar)
    uiText(sidebar, "WORKSPACE", {
        Position = UDim2.fromOffset(16, 17),
        Size = UDim2.new(1, -30, 0, 16),
        Font = Enum.Font.GothamBold,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(101, 112, 127),
    })

    local nav = uiNew("Frame", {
        Name = "Navigation",
        Position = UDim2.fromOffset(9, 45),
        Size = UDim2.new(1, -18, 0, 300),
        BackgroundTransparency = 1,
    }, sidebar)
    uiNew("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, nav)

    local footer = uiCard(sidebar, "BuildInfo", UDim2.new(0, 10, 1, -53), UDim2.new(1, -20, 0, 39))
    uiText(footer, "BUILD", {
        Position = UDim2.fromOffset(9, 3),
        Size = UDim2.new(1, -18, 0, 12),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(101, 112, 127),
    })
    uiText(footer, "V20.1  •  PREMIUM", {
        Position = UDim2.fromOffset(9, 17),
        Size = UDim2.new(1, -18, 0, 15),
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(177, 187, 200),
    })

    local content = uiNew("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(158, 0),
        Size = UDim2.new(1, -158, 1, 0),
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

    local function heading(parent, title, subtitle)
        uiText(parent, title, {
            Position = UDim2.fromOffset(22, 15),
            Size = UDim2.new(1, -44, 0, 27),
            Font = Enum.Font.GothamSemibold,
            TextSize = 19,
            TextColor3 = Color3.fromRGB(241, 244, 249),
        })
        uiText(parent, subtitle, {
            Position = UDim2.fromOffset(23, 43),
            Size = UDim2.new(1, -46, 0, 17),
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = Color3.fromRGB(133, 143, 157),
        })
    end

    local function navItem(name, subtitle, glyph, order)
        local b = uiNew("TextButton", {
            Name = name .. "Nav",
            Size = UDim2.new(1, 0, 0, 43),
            BackgroundColor3 = Color3.fromRGB(17, 20, 25),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
        }, nav)
        uiNew("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
        local bar = uiNew("Frame", {
            Position = UDim2.fromOffset(0, 9),
            Size = UDim2.fromOffset(3, 25),
            BackgroundColor3 = accentColor,
            BorderSizePixel = 0,
            Visible = false,
        }, b)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
        local icon = uiText(b, glyph, {
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.fromOffset(22, 42),
            TextXAlignment = Enum.TextXAlignment.Center,
            Font = Enum.Font.GothamSemibold,
            TextSize = 13,
            TextColor3 = Color3.fromRGB(135, 146, 161),
        })
        local title = uiText(b, name, {
            Position = UDim2.fromOffset(39, 5),
            Size = UDim2.new(1, -46, 0, 17),
            Font = Enum.Font.GothamSemibold,
            TextSize = 11,
            TextColor3 = Color3.fromRGB(135, 146, 161),
        })
        uiText(b, subtitle, {
            Position = UDim2.fromOffset(39, 22),
            Size = UDim2.new(1, -46, 0, 13),
            Font = Enum.Font.Gotham,
            TextSize = 8,
            TextColor3 = Color3.fromRGB(97, 108, 123),
        })
        local navScale = uiNew("UIScale", {Scale = 1}, b)
        local navStroke = uiNew("UIStroke", {
            Color = accentColor,
            Thickness = 1,
            Transparency = 1,
        }, b)
        local navState = {
            button = b, bar = bar, icon = icon, title = title,
            active = false, scale = navScale, stroke = navStroke,
        }
        navItems[name] = navState

        b.MouseEnter:Connect(function()
            playUiTween(navScale, HOVER_IN, {Scale = 1.025})
            playUiTween(navStroke, HOVER_IN, {Transparency = 0.55, Color = accentColor})
            if not navState.active then
                playUiTween(b, HOVER_IN, {
                    BackgroundTransparency = 0.42,
                    BackgroundColor3 = Color3.fromRGB(25, 30, 37),
                })
                playUiTween(title, HOVER_IN, {TextColor3 = Color3.fromRGB(226, 232, 241)})
                playUiTween(icon, HOVER_IN, {TextColor3 = accentColor})
            end
        end)
        b.MouseLeave:Connect(function()
            playUiTween(navScale, HOVER_OUT, {Scale = 1})
            playUiTween(navStroke, HOVER_OUT, {Transparency = navState.active and 0.72 or 1})
            if not navState.active then
                playUiTween(b, HOVER_OUT, {BackgroundTransparency = 1})
                playUiTween(title, HOVER_OUT, {TextColor3 = Color3.fromRGB(135, 146, 161)})
                playUiTween(icon, HOVER_OUT, {TextColor3 = Color3.fromRGB(135, 146, 161)})
            end
        end)
        return b
    end

    navItem("Overview", "Session summary", "⌂", 1)
    navItem("Players", "Whitelist / Incognito", "◎", 2)
    navItem("Spread", "Weapon tuning", "◌", 3)
    navItem("Hitbox", "Hitbox settings", "▣", 4)
    navItem("System", "Performance", "◫", 5)
    navItem("Settings", "Preferences", "⚙", 6)

    local function metricCard(parent, key, title, x, y, width)
        local card = uiCard(parent, key, UDim2.fromOffset(x, y), UDim2.fromOffset(width, 82))
        uiText(card, title:upper(), {
            Position = UDim2.fromOffset(12, 9),
            Size = UDim2.new(1, -24, 0, 14),
            Font = Enum.Font.GothamBold,
            TextSize = 8,
            TextColor3 = Color3.fromRGB(132, 143, 158),
        })
        monitorValues[key] = uiText(card, "--", {
            Position = UDim2.fromOffset(12, 30),
            Size = UDim2.new(1, -24, 0, 30),
            Font = Enum.Font.GothamSemibold,
            TextSize = 21,
            TextColor3 = Color3.fromRGB(241, 244, 249),
        })
    end

    -- Overview dashboard: mostra o estado da configuracao, sem criar loops por modulo.
    heading(overviewPage, "Overview", "Status geral da V4ware e da sessao atual.")
    local featureCards = {}
    local function featureCard(key, title, x, y)
        local card = uiCard(overviewPage, key, UDim2.fromOffset(x, y), UDim2.fromOffset(226, 63))
        local dotFeature = uiNew("Frame", {
            Position = UDim2.fromOffset(13, 25),
            Size = UDim2.fromOffset(7, 7),
            BackgroundColor3 = Color3.fromRGB(105, 113, 124),
            BorderSizePixel = 0,
        }, card)
        uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, dotFeature)
        uiText(card, title, {
            Position = UDim2.fromOffset(29, 10),
            Size = UDim2.new(1, -95, 0, 18),
            Font = Enum.Font.GothamMedium,
            TextSize = 10,
            TextColor3 = Color3.fromRGB(220, 226, 235),
        })
        local value = uiText(card, "OFF", {
            Position = UDim2.new(1, -67, 0, 10),
            Size = UDim2.fromOffset(54, 18),
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Color3.fromRGB(132, 143, 158),
        })
        featureCards[key] = {value = value, dot = dotFeature}
    end

    featureCard("Triggerbot", "Triggerbot", 22, 70)
    featureCard("InfiniteJump", "Infinite Jump", 264, 70)
    featureCard("ESP", "ESP", 22, 140)
    featureCard("Camlock", "Camlock", 264, 140)
    featureCard("Hitbox", "Hitbox Expander", 22, 210)
    featureCard("Spread", "Spread Modification", 264, 210)

    featureCard("WeaponSwitch", "Weapon Switch", 22, 280)

    local overviewBottom = uiCard(overviewPage, "OverviewSession", UDim2.fromOffset(22, 354), UDim2.new(1, -44, 0, 66))
    uiText(overviewBottom, "SESSION", {
        Position = UDim2.fromOffset(13, 8),
        Size = UDim2.new(1, -26, 0, 13),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(132, 143, 158),
    })
    local overviewSession = uiText(overviewBottom, "ONLINE  •  INSERT TO OPEN / CLOSE", {
        Position = UDim2.fromOffset(13, 27),
        Size = UDim2.new(1, -26, 0, 17),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
        TextColor3 = Color3.fromRGB(231, 236, 244),
    })
    local overviewUptime = uiText(overviewBottom, "Session 00:00:00", {
        Position = UDim2.fromOffset(13, 45),
        Size = UDim2.new(1, -26, 0, 13),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(132, 143, 158),
    })

    local function setFeature(key, enabled, active)
        local item = featureCards[key]
        if not item then return end
        local on = enabled == true
        item.value.Text = not on and "OFF" or (active == false and "READY" or "ON")
        item.value.TextColor3 = on and accentColor or Color3.fromRGB(132, 143, 158)
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
        overviewUptime.Text = "Session " .. formatDuration(os.clock() - sessionStartedAt)
    end

    -- Players
    heading(playersPage, "Players", "Gerencie as listas e visualize a sessao.")
    tabWhitelist = uiButton(playersPage, "WHITELIST", {
        Position = UDim2.fromOffset(22, 73),
        Size = UDim2.fromOffset(112, 29),
        BackgroundColor3 = Color3.fromRGB(35, 42, 51),
    })
    tabIncognito = uiButton(playersPage, "INCOGNITO", {
        Position = UDim2.fromOffset(142, 73),
        Size = UDim2.fromOffset(112, 29),
    })
    menuPlayers = uiNew("ScrollingFrame", {
        Name = "PlayerList",
        Position = UDim2.fromOffset(22, 112),
        Size = UDim2.new(1, -44, 1, -151),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(88, 97, 110),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
    }, playersPage)
    uiNew("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
    }, menuPlayers)
    menuCount = uiText(playersPage, "WHITELIST  •  0 entries", {
        Position = UDim2.new(0, 23, 1, -29),
        Size = UDim2.new(1, -46, 0, 17),
        Font = Enum.Font.GothamMedium,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
    })

    -- System
    heading(systemPage, "System monitor", "Telemetria local com atualizacao em baixa frequencia.")
    monitorFrame = uiNew("Frame", {
        Name = "SystemMonitor",
        Position = UDim2.fromOffset(22, 76),
        Size = UDim2.new(1, -44, 1, -98),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, systemPage)
    metricCard(monitorFrame, "FPS", "Frame rate", 0, 0, 226)
    metricCard(monitorFrame, "Ping", "Network ping", 242, 0, 226)
    metricCard(monitorFrame, "Memory", "Client memory", 0, 96, 226)
    metricCard(monitorFrame, "Players", "Players in session", 242, 96, 226)
    local systemSession = uiCard(monitorFrame, "SystemSession", UDim2.fromOffset(0, 192), UDim2.new(1, 0, 0, 65))
    uiText(systemSession, "SESSION STATUS", {
        Position = UDim2.fromOffset(13, 8),
        Size = UDim2.new(1, -26, 0, 13),
        Font = Enum.Font.GothamBold,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(132, 143, 158),
    })
    monitorValues.Status = uiText(systemSession, "ONLINE  •  CLIENT MONITOR ACTIVE", {
        Position = UDim2.fromOffset(13, 25),
        Size = UDim2.new(1, -26, 0, 16),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
    })
    monitorValues.Uptime = uiText(systemSession, "Session 00:00:00", {
        Position = UDim2.fromOffset(13, 44),
        Size = UDim2.new(1, -26, 0, 13),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(132, 143, 158),
    })

    updateSystemMonitor = function()
        if not monitorFrame or not monitorFrame.Parent then return end
        monitorValues.FPS.Text = currentFPS > 0 and tostring(currentFPS) or "--"
        local ping = readPingMs()
        monitorValues.Ping.Text = ping and string.format("%.0f ms", ping) or "N/A"
        local memory = readMemoryMb()
        monitorValues.Memory.Text = memory and string.format("%.0f MB", memory) or "N/A"
        monitorValues.Players.Text = tostring(#Players:GetPlayers())
        monitorValues.Status.Text = monitorEnabled and "ONLINE  •  CLIENT MONITOR ACTIVE" or "MONITOR PAUSED"
        monitorValues.Uptime.Text = "Session  " .. formatDuration(os.clock() - sessionStartedAt)
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
        Position = UDim2.fromOffset(23, 62),
        Size = UDim2.new(1, -46, 0, 14),
        Font = Enum.Font.GothamMedium,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(133, 143, 157),
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
        local y = 82 + (index - 1) * 82
        local card = uiCard(spreadPage, "Spread_" .. tostring(index), UDim2.fromOffset(22, y), UDim2.new(1, -44, 0, 70))
        uiText(card, weaponTitle, {
            Position = UDim2.fromOffset(13, 8),
            Size = UDim2.new(1, -160, 0, 17),
            Font = Enum.Font.GothamSemibold,
            TextSize = 11,
        })
        local value = uiNew("TextBox", {
            Position = UDim2.new(1, -125, 0, 7),
            Size = UDim2.fromOffset(50, 18),
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
            Position = UDim2.new(1, -66, 0, 7),
            Size = UDim2.fromOffset(25, 23),
            TextSize = 14,
        })
        local plus = uiButton(card, "+", {
            Position = UDim2.new(1, -35, 0, 7),
            Size = UDim2.fromOffset(25, 23),
            TextSize = 13,
        })
        local track = uiNew("Frame", {
            Position = UDim2.fromOffset(13, 43),
            Size = UDim2.new(1, -26, 0, 7),
            BackgroundColor3 = Color3.fromRGB(43, 49, 58),
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
        Position = UDim2.fromOffset(22, 334),
        Size = UDim2.fromOffset(132, 31),
        BackgroundColor3 = Color3.fromRGB(38, 49, 62),
        TextColor3 = Color3.fromRGB(228, 237, 248),
    })
    local resetSpreadButton = uiButton(spreadPage, "RESET DEFAULTS", {
        Position = UDim2.fromOffset(162, 334),
        Size = UDim2.fromOffset(124, 31),
    })
    local spreadInfo = uiText(spreadPage, "Patch status: waiting for scan.", {
        Position = UDim2.fromOffset(23, 372),
        Size = UDim2.new(1, -46, 0, 34),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
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

    local hitboxTop = uiCard(hitboxPage, "HitboxModuleCard", UDim2.fromOffset(22, 72), UDim2.new(1, -44, 0, 58))
    uiText(hitboxTop, "HITBOX EXPANDER", {
        Position = UDim2.fromOffset(13, 7),
        Size = UDim2.fromOffset(145, 16),
        Font = Enum.Font.GothamSemibold,
        TextSize = 10,
    })
    uiText(hitboxTop, "Enable module and choose whether the resized part is visible.", {
        Position = UDim2.fromOffset(13, 27),
        Size = UDim2.new(1, -260, 0, 15),
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextColor3 = Color3.fromRGB(133, 143, 157),
    })

    local hitboxEnabledButton = uiButton(hitboxTop, hitboxCfg.Enabled and "ON" or "OFF", {
        Position = UDim2.new(1, -178, 0, 14),
        Size = UDim2.fromOffset(70, 30),
        TextSize = 9,
        TextColor3 = hitboxCfg.Enabled and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(143, 151, 163),
    })
    local hitboxVisibleButton = uiButton(hitboxTop, hitboxCfg.Visible and "VISIBLE" or "HIDDEN", {
        Position = UDim2.new(1, -96, 0, 14),
        Size = UDim2.fromOffset(82, 30),
        TextSize = 8,
        TextColor3 = hitboxCfg.Visible and accentColor or Color3.fromRGB(143, 151, 163),
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

    local function makeHitboxValueCard(key, title, x, y, minimum, maximum, step, fallback)
        local card = uiCard(hitboxPage, "Hitbox_" .. key, UDim2.fromOffset(x, y), UDim2.fromOffset(260, 70))
        uiText(card, title, {
            Position = UDim2.fromOffset(13, 8),
            Size = UDim2.new(1, -160, 0, 17),
            Font = Enum.Font.GothamSemibold,
            TextSize = 10,
        })
        local value = uiNew("TextBox", {
            Position = UDim2.new(1, -125, 0, 7),
            Size = UDim2.fromOffset(50, 18),
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
            Position = UDim2.new(1, -66, 0, 7),
            Size = UDim2.fromOffset(25, 23),
            TextSize = 14,
        })
        local plus = uiButton(card, "+", {
            Position = UDim2.new(1, -35, 0, 7),
            Size = UDim2.fromOffset(25, 23),
            TextSize = 13,
        })
        local track = uiNew("Frame", {
            Position = UDim2.fromOffset(13, 43),
            Size = UDim2.new(1, -26, 0, 7),
            BackgroundColor3 = Color3.fromRGB(43, 49, 58),
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

    makeHitboxValueCard("X", "Size X (studs)", 22, 144, 1, 50, 0.5, 2)
    makeHitboxValueCard("Y", "Size Y (studs)", 300, 144, 1, 50, 0.5, 2)
    makeHitboxValueCard("Z", "Size Z (studs)", 22, 226, 1, 50, 0.5, 1)
    makeHitboxValueCard("Transparency", "Transparency", 300, 226, 0, 1, 0.05, 0.5)

    local applyHitboxButton = uiButton(hitboxPage, "APPLY CHANGES", {
        Position = UDim2.fromOffset(22, 310),
        Size = UDim2.fromOffset(132, 31),
        BackgroundColor3 = Color3.fromRGB(38, 49, 62),
        TextColor3 = Color3.fromRGB(228, 237, 248),
    })
    local resetHitboxButton = uiButton(hitboxPage, "RESET DEFAULTS", {
        Position = UDim2.fromOffset(162, 310),
        Size = UDim2.fromOffset(124, 31),
    })
    hitboxStatus = uiText(hitboxPage, "Module status: waiting for settings.", {
        Position = UDim2.fromOffset(23, 350),
        Size = UDim2.new(1, -46, 0, 38),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
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
            or Color3.fromRGB(133, 143, 157)
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
            or Color3.fromRGB(143, 151, 163)
        applyHitboxChanges()
    end)

    hitboxVisibleButton.Activated:Connect(function()
        hitboxCfg.Visible = not hitboxCfg.Visible
        hitboxVisibleButton.Text = hitboxCfg.Visible and "VISIBLE" or "HIDDEN"
        hitboxVisibleButton.TextColor3 = hitboxCfg.Visible and accentColor or Color3.fromRGB(143, 151, 163)
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
    local settingsCard = uiCard(settingsPage, "SettingsCard", UDim2.fromOffset(22, 78), UDim2.new(1, -44, 0, 168))
    uiText(settingsCard, "SYSTEM MONITOR", {
        Position = UDim2.fromOffset(14, 12),
        Size = UDim2.new(1, -145, 0, 18),
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
    })
    uiText(settingsCard, "Pause live metrics when you do not need them.", {
        Position = UDim2.fromOffset(14, 32),
        Size = UDim2.new(1, -145, 0, 15),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
    })
    local monitorToggle = uiButton(settingsCard, "ON", {
        Position = UDim2.new(1, -83, 0, 18),
        Size = UDim2.fromOffset(66, 28),
    })
    uiText(settingsCard, "COMPACT PANEL", {
        Position = UDim2.fromOffset(14, 79),
        Size = UDim2.new(1, -145, 0, 18),
        Font = Enum.Font.GothamSemibold,
        TextSize = 11,
    })
    uiText(settingsCard, "Reduce the panel footprint.", {
        Position = UDim2.fromOffset(14, 99),
        Size = UDim2.new(1, -145, 0, 15),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
    })
    local compactToggle = uiButton(settingsCard, "OFF", {
        Position = UDim2.new(1, -83, 0, 85),
        Size = UDim2.fromOffset(66, 28),
    })
    local accentButton = uiButton(settingsPage, "CHANGE ACCENT", {
        Position = UDim2.fromOffset(22, 262),
        Size = UDim2.fromOffset(132, 30),
    })
    local settingsNote = uiText(settingsPage, "Panel shortcut: INSERT  •  No blur  •  No animated graphs  •  Low-frequency monitor", {
        Position = UDim2.fromOffset(23, 305),
        Size = UDim2.new(1, -46, 0, 34),
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextColor3 = Color3.fromRGB(133, 143, 157),
        TextWrapped = true,
    })

    local function applyAccent()
        accentColor = accentChoices[accentIndex]
        logoText.TextColor3 = accentColor
        for _, item in pairs(navItems) do item.bar.BackgroundColor3 = accentColor end
        for _, row in pairs(spreadRows) do row.fill.BackgroundColor3 = accentColor end
        for _, row in pairs(hitboxRows) do
            row.fill.BackgroundColor3 = accentColor
            row.value.TextColor3 = accentColor
        end
        for _, card in pairs(featureCards) do card.value.TextColor3 = accentColor end
    end

    accentButton.Activated:Connect(function()
        accentIndex = accentIndex % #accentChoices + 1
        applyAccent()
    end)

    monitorToggle.Activated:Connect(function()
        monitorEnabled = not monitorEnabled
        monitorToggle.Text = monitorEnabled and "ON" or "OFF"
        monitorToggle.TextColor3 = monitorEnabled and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(160, 166, 176)
        if updateSystemMonitor then updateSystemMonitor() end
        if syncFPSCounter then syncFPSCounter() end
    end)

    compactToggle.Activated:Connect(function()
        compactMode = not compactMode
        compactToggle.Text = compactMode and "ON" or "OFF"
        menuPanel.Size = compactMode and UDim2.fromOffset(680, 470) or UDim2.fromOffset(740, 500)
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
                UDim2.new(0, 0, 0, 0), UDim2.new(1, -5, 0, 47))
            row.LayoutOrder = index

            local avatar = uiNew("ImageLabel", {
                Name = "Avatar",
                Position = UDim2.fromOffset(8, 6),
                Size = UDim2.fromOffset(35, 35),
                BackgroundColor3 = Color3.fromRGB(36, 41, 49),
                Image = "",
                BorderSizePixel = 0,
            }, row)
            uiNew("UICorner", {CornerRadius = UDim.new(1, 0)}, avatar)
            task.spawn(function()
                local ok, contentImage = pcall(function()
                    return Players:GetUserThumbnailAsync(targetPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                end)
                if ok and avatar.Parent then avatar.Image = contentImage end
            end)

            uiText(row, targetPlayer.DisplayName, {
                Position = UDim2.fromOffset(54, 5),
                Size = UDim2.new(1, -172, 0, 22),
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Color3.fromRGB(235, 238, 243),
            })
            if targetPlayer.DisplayName ~= targetPlayer.Name then
                uiText(row, "@" .. targetPlayer.Name, {
                    Position = UDim2.fromOffset(54, 25),
                    Size = UDim2.new(1, -172, 0, 15),
                    TextSize = 10,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextColor3 = Color3.fromRGB(143, 148, 157),
                })
            end

            local eye = uiButton(row, "◉", {
                Position = UDim2.new(1, -96, 0, 6),
                Size = UDim2.fromOffset(32, 35),
                BackgroundTransparency = 1,
                TextSize = 17,
                TextColor3 = spectateTarget == targetPlayer and accentColor or Color3.fromRGB(165, 174, 187),
            })
            eye.Activated:Connect(function()
                startSpectating(targetPlayer)
                renderMenu()
            end)

            local toggle = uiButton(row, active and "ON" or "OFF", {
                Position = UDim2.new(1, -58, 0, 8),
                Size = UDim2.fromOffset(48, 31),
                TextSize = 10,
                TextColor3 = active and Color3.fromRGB(111, 207, 151) or Color3.fromRGB(143, 151, 163),
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
            uiText(menuPlayers, "Nenhum outro jogador na sessao.", {
                Size = UDim2.new(1, -20, 0, 42),
                TextSize = 12,
                TextColor3 = Color3.fromRGB(145, 150, 159),
                TextXAlignment = Enum.TextXAlignment.Center,
            })
        end

        local labelText = selectedPlayerTab == "whitelist" and "PROTECTED PLAYERS" or "HIDDEN PLAYERS"
        menuCount.Text = string.format("%s  •  %d entries  •  INSERT to toggle", labelText, protected)
    end

    renderMenu = function()
        for pageName, pageFrame in pairs(pages) do
            local activePage = pageName:lower() == selectedTab
            pageFrame.Visible = activePage
            if activePage and lastRenderedTab ~= selectedTab then
                pageFrame.Position = UDim2.fromOffset(8, 0)
                playUiTween(pageFrame, PAGE_IN, {Position = UDim2.fromOffset(0, 0)})
            end
        end
        lastRenderedTab = selectedTab

        for name, item in pairs(navItems) do
            local active = name:lower() == selectedTab
            local wasActive = item.active
            item.active = active
            if active then
                item.bar.Visible = true
                if not wasActive then
                    item.bar.Size = UDim2.fromOffset(3, 0)
                    playUiTween(item.bar, PAGE_IN, {Size = UDim2.fromOffset(3, 25)})
                end
            else
                item.bar.Visible = false
                item.bar.Size = UDim2.fromOffset(3, 0)
            end
            item.button.BackgroundTransparency = active and 0 or 1
            item.button.BackgroundColor3 = active and Color3.fromRGB(25, 30, 37) or Color3.fromRGB(17, 20, 25)
            item.title.TextColor3 = active and Color3.fromRGB(241, 244, 249) or Color3.fromRGB(135, 146, 161)
            item.icon.TextColor3 = active and accentColor or Color3.fromRGB(135, 146, 161)
            item.stroke.Transparency = active and 0.72 or 1
        end

        if selectedTab == "players" then
            tabWhitelist.BackgroundColor3 = selectedPlayerTab == "whitelist" and Color3.fromRGB(38, 47, 58) or Color3.fromRGB(29, 33, 40)
            tabIncognito.BackgroundColor3 = selectedPlayerTab == "incognito" and Color3.fromRGB(38, 47, 58) or Color3.fromRGB(29, 33, 40)
            renderPlayers()
        elseif selectedTab == "system" then
            updateSystemMonitor()
        elseif selectedTab == "overview" then
            refreshDashboard()
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
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
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
            and (compactMode and UDim2.fromOffset(680, 470) or UDim2.fromOffset(740, 500))
            or UDim2.fromOffset(740, 66)
        minimize.Text = body.Visible and "–" or "+"
        if syncFPSCounter then syncFPSCounter() end
        if body.Visible and selectedTab == "system" and monitorEnabled and updateSystemMonitor then
            updateSystemMonitor()
        end
    end)

    close.Activated:Connect(function()
        menuVisible = false
        if menuGui then menuGui.Enabled = false end
        if syncFPSCounter then syncFPSCounter() end
    end)

    renderMenu()
end

buildMenu()

-- FPS sampler sob demanda: não mantém callback RenderStepped quando o monitor
-- não está visível/ativo. A medição continua com janela de 1 segundo.
syncFPSCounter = function()
    local shouldSample = running
        and menuVisible
        and menuBodyVisible
        and menuGui ~= nil
        and menuGui.Enabled
        and selectedTab == "system"
        and monitorEnabled

    if shouldSample then
        if not fpsCounterConnection then
            fpsFrameCount = 0
            fpsElapsed = 0
            fpsCounterConnection = RunService.RenderStepped:Connect(function(dt)
                if not running then return end
                fpsFrameCount = fpsFrameCount + 1
                fpsElapsed = fpsElapsed + dt
                if fpsElapsed >= 1 then
                    currentFPS = math.floor((fpsFrameCount / fpsElapsed) + 0.5)
                    fpsFrameCount = 0
                    fpsElapsed = 0
                end
            end)
        end
    elseif fpsCounterConnection then
        pcall(function() fpsCounterConnection:Disconnect() end)
        fpsCounterConnection = nil
        fpsFrameCount = 0
        fpsElapsed = 0
        currentFPS = 0
    end
end

syncFPSCounter()

connectSignal(UserInputService.InputBegan, function(input, processed)
    if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == panelKey and menuGui then
        menuVisible = not menuVisible
        menuGui.Enabled = menuVisible
        if menuVisible then
            panelScale.Scale = 0.985
            playUiTween(panelScale, PAGE_IN, {Scale = 1})
            if renderMenu then renderMenu() end
        end
        if syncFPSCounter then syncFPSCounter() end
    end
end)

connectSignal(Players.PlayerAdded, function()
    if renderMenu and menuGui and menuGui.Parent and selectedTab == "players" then
        renderMenu()
    end
end)

connectSignal(Players.PlayerRemoving, function(player)
    if spectateTarget == player then stopSpectating() end
    task.defer(function()
        if renderMenu and menuGui and menuGui.Parent and selectedTab == "players" then
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

    if not menuVisible or not menuBodyVisible or not menuGui or not menuGui.Enabled then
        monitorRefreshElapsed = 0
        dashboardRefreshElapsed = 0
        return
    end

    if selectedTab == "system" and monitorEnabled then
        monitorRefreshElapsed = monitorRefreshElapsed + (dt or 0)
        if monitorRefreshElapsed >= 1 then
            monitorRefreshElapsed = 0
            if updateSystemMonitor then updateSystemMonitor() end
        end
    else
        monitorRefreshElapsed = 0
    end

    if selectedTab == "overview" then
        dashboardRefreshElapsed = dashboardRefreshElapsed + (dt or 0)
        if dashboardRefreshElapsed >= 1 then
            dashboardRefreshElapsed = 0
            refreshDashboard()
        end
    else
        dashboardRefreshElapsed = 0
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
    print("[V4ware V20.4] Parado; menu fechado e constantes restauradas onde possivel.")
end

env.DHC_Stop = stop
env.DHC_Status = status
refreshESP()
updateHitboxes()
updateSpread()
print("[V4ware V20.4] Iniciado: INSERT menu (Overview / Players / Spread / Hitbox / System / Settings) | Pulo somente COM OS PES APOIADOS; sem buffer, sem voo e sem cooldown artificial")
print("[V4ware V20] Trigger: delay cliente 0 | DB 180 | Revolver 260 | Tactical 180 | limite geral 280 studs")
print("[V4ware V20.4] Menu: INSERT | Status: getgenv().DHC_Status() | Parar: getgenv().DHC_Stop()")
warn("[V4ware V20] Experimento de patch de CONSTANTES especificas. Sem hook FireServer; resultado real nao testado.")
print("[V4ware WS] Weapon Switch ativo: V -> DB / Tactical / Revolver, respeitando cooldowns do jogo")
