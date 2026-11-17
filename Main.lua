-- PAIN HOOD V17 - IMPLEMENTACAO REMOTA (separada da configuracao)
-- Este arquivo pressupoe que a tabela global Config ja existe no ambiente que o carrega.
-- Mantenha a configuracao no arquivo/trecho local e hospede este arquivo como Main.lua.

-- =============================================================
-- SERVICOS, ESTADO E LIMPEZA DE EXECUCOES ANTERIORES
-- =============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
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
            warn("[PH V17] Experiencia nao corresponde ao Pain Hood analisado; spread nao modificado.")
        end
        return
    end

    local getter, setter, apiError = getConstApi()
    if apiError then
        spreadLastError = apiError
        if not warnedSpread then
            warnedSpread = true
            warn("[PH V17] Spread inativo: " .. apiError)
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
        warn("[PH V17] Spread inativo: " .. spreadLastError)
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
            warn(("[PH V17] %d constantes ajustadas em %d funcao(oes) identificada(s). Resultado visual/servidor ainda precisa de validacao.")
                :format(changed, matches))
        else
            warn("[PH V17] Nenhuma constante ativa foi alterada: " .. tostring(spreadLastError or "sem constantes confirmadas"))
        end
        warn(("[PH V17] Contagem por arma: DB=%d | Tactical=%d | Revolver=%d")
            :format(spreadPatched["[Double-Barrel SG]"] or 0,
                    spreadPatched["[TacticalShotgun]"] or 0,
                    spreadPatched["[Revolver]"] or 0))
        warn("[PH V17] Revolver permanece sem identificacao confirmada no bytecode analisado.")
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
        nextESP = now + 0.4
        refreshESP()
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
        Version = 17,
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
        SpreadRealVerified = false, -- validacao de dano/trajetoria do servidor nao foi testada
        RemoteHooks = false,
    }
end


-- =============================================================
-- PAINEL INSERT: WHITELIST, INCOGNITO E CAMERA (SPECTATE)
-- Nao altera o patch de spread da V7 nem usa eventos remotos.
-- =============================================================
local menuGui, menuPanel, menuPlayers, menuCount, tabWhitelist, tabIncognito
local selectedTab = "whitelist"
local menuVisible = false
local renderMenu

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
        warn("[PH V8] Jogador sem personagem disponivel para visualizar.")
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
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = parent
    return obj
end

local function uiText(parent, txt, props)
    local p = {
        Text = txt, BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        TextSize = 12, TextColor3 = Color3.fromRGB(217, 217, 217),
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
    }
    for k,v in pairs(props or {}) do p[k] = v end
    return uiNew("TextLabel", p, parent)
end

local function buildMenu()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then
        warn("[PH V8] PlayerGui nao encontrado; menu nao criado")
        return
    end
    local old = playerGui:FindFirstChild("PH_V8_WhitelistMenu")
    if old then old:Destroy() end
    menuGui = uiNew("ScreenGui", {
        Name = "PH_V8_WhitelistMenu", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100,
        Enabled = false, IgnoreGuiInset = false,
    }, playerGui)
    menuPanel = uiNew("Frame", {
        Name="Panel", Size=UDim2.fromOffset(500,426),
        AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
        BackgroundColor3=Color3.fromRGB(8,8,9), BorderSizePixel=0,
        Active=true,
    }, menuGui)
    uiNew("UICorner", {CornerRadius=UDim.new(0,10)}, menuPanel)
    uiNew("UIStroke", {Color=Color3.fromRGB(26,26,28), Thickness=1}, menuPanel)
    uiText(menuPanel, "V4ware", {
        Position=UDim2.fromOffset(20,14), Size=UDim2.fromOffset(50,22),
        Font=Enum.Font.GothamMedium, TextSize=14,
        TextColor3=Color3.fromRGB(40,198,241),
    })
    local close = uiNew("TextButton", {
        Name="Close", Size=UDim2.fromOffset(31,30), Position=UDim2.new(1,-44,0,7),
        BackgroundTransparency=1, Text="×", Font=Enum.Font.Gotham,
        TextColor3=Color3.fromRGB(152,152,158), TextSize=20,
        AutoButtonColor=false,
    }, menuPanel)
    close.Activated:Connect(function()
        menuVisible=false
        if menuGui then menuGui.Enabled=false end
    end)

    tabWhitelist=uiNew("TextButton", {
        Position=UDim2.fromOffset(25,57), Size=UDim2.fromOffset(84,23),
        BackgroundTransparency=1, Font=Enum.Font.Code, Text="whitelist",
        TextColor3=Color3.fromRGB(143,143,149), TextSize=13,
        AutoButtonColor=false,
    },menuPanel)
    tabIncognito=uiNew("TextButton", {
        Position=UDim2.fromOffset(125,57), Size=UDim2.fromOffset(84,23),
        BackgroundTransparency=1, Font=Enum.Font.Code, Text="incognito",
        TextColor3=Color3.fromRGB(143,143,149), TextSize=13,
        AutoButtonColor=false,
    },menuPanel)
    local underline=uiNew("Frame", {
        Name="ActiveTabLine", Position=UDim2.fromOffset(25,82),
        Size=UDim2.fromOffset(84,2), BackgroundColor3=Color3.fromRGB(244,244,244),
        BorderSizePixel=0,
    },menuPanel)
    uiNew("Frame", {
        Position=UDim2.fromOffset(20,85),Size=UDim2.new(1,-40,0,1),
        BackgroundColor3=Color3.fromRGB(24,24,26),BorderSizePixel=0,
    },menuPanel)
    menuPlayers=uiNew("ScrollingFrame", {
        Name="PlayerList", Position=UDim2.fromOffset(20,91),
        Size=UDim2.new(1,-40,1,-133),
        BackgroundTransparency=1,BorderSizePixel=0,
        ScrollBarThickness=3,ScrollBarImageColor3=Color3.fromRGB(75,75,78),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.fromOffset(0,0),
    },menuPanel)
    uiNew("UIListLayout", {
        SortOrder=Enum.SortOrder.LayoutOrder,
        Padding=UDim.new(0,4), HorizontalAlignment=Enum.HorizontalAlignment.Center,
    },menuPlayers)
    menuCount=uiText(menuPanel, "INSERT: abrir/fechar  |  olho: visualizar jogador", {
        Position=UDim2.new(0,24,1,-32),Size=UDim2.new(1,-48,0,22),
        TextSize=10,TextColor3=Color3.fromRGB(110,110,114),
    })

    renderMenu = function()
        if not menuPlayers or not menuPlayers.Parent then return end
        for _, child in ipairs(menuPlayers:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
        end
        local selected = selectedTab == "whitelist" and tabWhitelist or tabIncognito
        underline.Position=selected==tabWhitelist and UDim2.fromOffset(25,82) or UDim2.fromOffset(125,82)
        tabWhitelist.TextColor3 = selected==tabWhitelist and Color3.fromRGB(230,230,234) or Color3.fromRGB(121,121,127)
        tabIncognito.TextColor3 = selected==tabIncognito and Color3.fromRGB(230,230,234) or Color3.fromRGB(121,121,127)

        local roster = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then table.insert(roster, player) end
        end
        table.sort(roster,function(a,b) return a.Name:lower() < b.Name:lower() end)
        local protected = 0
        for index, player in ipairs(roster) do
            local active = selectedTab == "whitelist" and isWhitelisted(player) or isIncognito(player)
            if active then protected=protected+1 end
            local row=uiNew("Frame", {
                Name="Player_"..tostring(player.UserId),LayoutOrder=index,
                Size=UDim2.new(1,-5,0,47),BackgroundColor3=Color3.fromRGB(17,17,18),
                BorderSizePixel=0,
            },menuPlayers)
            uiNew("UICorner",{CornerRadius=UDim.new(0,6)},row)
            local avatar = uiNew("ImageLabel", {
                Name="Avatar",Position=UDim2.fromOffset(8,6), Size=UDim2.fromOffset(35,35),
                BackgroundColor3=Color3.fromRGB(34,34,35),Image="",BorderSizePixel=0,
            },row)
            uiNew("UICorner",{CornerRadius=UDim.new(1,0)},avatar)
            task.spawn(function()
                local ok, content=pcall(function()
                    return Players:GetUserThumbnailAsync(player.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48)
                end)
                if ok and avatar.Parent then avatar.Image=content end
            end)
            uiText(row, player.DisplayName, {
                Position=UDim2.fromOffset(54,5),Size=UDim2.new(1,-172,0,22),
                Font=Enum.Font.GothamMedium,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd,
                TextColor3=Color3.fromRGB(235,235,238),
            })
            if player.DisplayName ~= player.Name then
                uiText(row,"@"..player.Name,{
                    Position=UDim2.fromOffset(54,25), Size=UDim2.new(1,-172,0,15),
                    TextSize=10,TextTruncate=Enum.TextTruncate.AtEnd,
                    TextColor3=Color3.fromRGB(105,105,109),
                })
            end
            local eye=uiNew("TextButton", {
                Name="View",Size=UDim2.fromOffset(32,38),Position=UDim2.new(1,-93,0,4),
                Text="◉",BackgroundTransparency=1,Font=Enum.Font.GothamBold,
                TextSize=19, TextColor3=spectateTarget==player and Color3.fromRGB(45,224,182) or Color3.fromRGB(104,191,234),
                AutoButtonColor=false,
            },row)
            eye.Activated:Connect(function()
                startSpectating(player)
                renderMenu()
            end)
            local toggle=uiNew("TextButton", {
                Name="Toggle",Size=UDim2.fromOffset(52,36),Position=UDim2.new(1,-57,0,5),
                Text=active and "ON" or "OFF",BackgroundTransparency=1,
                TextColor3=active and Color3.fromRGB(76,222,143) or Color3.fromRGB(246,71,78),
                Font=Enum.Font.Code,TextSize=12,AutoButtonColor=false,
            },row)
            toggle.Activated:Connect(function()
                local list=selectedTab=="whitelist" and Config.Triggerbot.Whitelist.List or Config.IncognitoWhitelist
                local key=tostring(player.UserId)
                if isInList(list,player) then
                    list[key]=nil
                    list[player.UserId]=nil
                    list[player.Name]=nil
                    for k,v in pairs(list) do
                        if v == player.UserId or v == tostring(player.UserId) or v == player.Name then list[k]=nil end
                    end
                else
                    list[key]=true
                end
                if camTarget == player and not onWhitelist(player) then camTarget=nil end
                refreshESP()
                renderMenu()
            end)
        end
        if #roster==0 then
            uiText(menuPlayers,"Nenhum outro jogador na sessao",{
                Size=UDim2.new(1,-20,0,42),TextSize=13,
                TextColor3=Color3.fromRGB(134,134,141),
                TextXAlignment=Enum.TextXAlignment.Center,
            })
        end
        local msg=selectedTab=="whitelist" and "Protegidos do Triggerbot/Camlock" or "Ocultos do ESP e protegidos"
        menuCount.Text=string.format("%s: %d  |  INSERT: abrir/fechar  |  ◉: view",msg,protected)
    end
    tabWhitelist.Activated:Connect(function() selectedTab="whitelist" renderMenu() end)
    tabIncognito.Activated:Connect(function() selectedTab="incognito" renderMenu() end)

    -- Arrastar pelo topo, sem depender de APIs especiais do executor.
    local dragging=false
    local dragOrigin, startPosition
    menuPanel.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            local xy=input.Position
            local top=menuPanel.AbsolutePosition.Y
            if xy.Y>=top and xy.Y<=top+52 then
                dragging=true
                dragOrigin=xy
                startPosition=menuPanel.Position
            end
        end
    end)
    connectSignal(UserInputService.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    connectSignal(UserInputService.InputChanged,function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d=input.Position-dragOrigin
            menuPanel.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+d.X,startPosition.Y.Scale,startPosition.Y.Offset+d.Y)
        end
    end)
    renderMenu()
end

buildMenu()
connectSignal(UserInputService.InputBegan,function(input,processed)
    if processed or input.UserInputType~=Enum.UserInputType.Keyboard then return end
    if input.KeyCode==Enum.KeyCode.Insert and menuGui then
        menuVisible=not menuVisible
        menuGui.Enabled=menuVisible
        if menuVisible and renderMenu then renderMenu() end
    end
end)
connectSignal(Players.PlayerAdded,function()
    if renderMenu and menuGui and menuGui.Parent then renderMenu() end
end)
connectSignal(Players.PlayerRemoving,function(player)
    if spectateTarget==player then stopSpectating() end
    task.defer(function()
        if renderMenu and menuGui and menuGui.Parent then renderMenu() end
    end)
end)
connectSignal(RunService.Heartbeat,function()
    if spectateTarget and spectateTarget.Parent==Players then
        local hum=humanoidOf(charOf(spectateTarget))
        local cam=camera()
        if hum and cam and cam.CameraSubject~=hum then
            cam.CameraType=Enum.CameraType.Custom
            cam.CameraSubject=hum
        end
    end
end)

local function stop()
    if not running then return end
    running = false
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
    print("[PH V17] Parado; menu fechado e constantes restauradas onde possivel.")
end

env.DHC_Stop = stop
env.DHC_Status = status
refreshESP()
updateHitboxes()
updateSpread()
print("[PH V17] Iniciado: INSERT menu | Pulo somente COM OS PES APOIADOS; sem buffer, sem voo e sem cooldown artificial")
print("[PH V17] Trigger: delay cliente 0 | DB 180 | Revolver 260 | Tactical 180 | limite geral 280 studs")
print("[PH V17] Menu: INSERT | Status: getgenv().DHC_Status() | Parar: getgenv().DHC_Stop()")
warn("[PH V17] Experimento de patch de CONSTANTES especificas. Sem hook FireServer; resultado real nao testado.")
