-- client.lua (assassination job) — comandos + convite por focus

-- =======================
-- Estado local
-- =======================
local isInContract = false
local mySquadId = nil
local currentTier = nil
local vipPed, guardPeds = nil, {}
local encounterBlip = nil
local dumpsterBlip, dumpsterZoneId = nil, nil
local lastInvite = nil  -- para /assaccept /assdecline

-- =======================
-- Utils
-- =======================
local function notify(msg, typ)
  lib.notify({ title = Config.NotifyTitle or 'Contratante', description = msg, type = typ or 'inform' })
end

local function pick(t)
  return t[math.random(1, #t)]
end

-- Fallback de modelos seguro
local function toHash(model) return type(model) == 'string' and GetHashKey(model) or model end
local function loadModelOrFallback(primary, fallback)
  local p = toHash(primary)
  if IsModelInCdimage(p) and IsModelValid(p) then
    lib.requestModel(p, 5000); return p
  end
  local f = toHash(fallback)
  if IsModelInCdimage(f) and IsModelValid(f) then
    lib.requestModel(f, 5000); return f
  end
  return nil
end

-- Cache simples de "é polícia?" (30s)
local policeCache = {} -- [serverId] = { val = true/false, ts = <ms> }
local function isPoliceCached(serverId)
  local now = GetGameTimer()
  local e = policeCache[serverId]
  if e and (now - e.ts) < 30000 then
    return e.val
  end
  local ok, res = pcall(function()
    return lib.callback.await('qbx:server:isPolice', false, serverId)
  end)
  local val = ok and res or false
  policeCache[serverId] = { val = val, ts = now }
  return val
end

-- Helper: obter o serverId a partir do ped de um jogador (focus)
local function getServerIdFromEntity(ent)
  if not ent or ent == 0 then return nil end
  local idx = NetworkGetPlayerIndexFromPed(ent)
  if not idx or idx == -1 then return nil end
  return GetPlayerServerId(idx)
end

-- =======================
-- Menu de tiers
-- =======================
function OpenContractMenu()
  if isInContract then
    notify('Já tens um contrato ativo.', 'error'); return
  end

  local opts = {}
  for tier, cfg in pairs(Config.Tiers) do
    opts[#opts+1] = {
      title = cfg.name,
      description = ('Recompensa: $%d - $%d'):format(cfg.reward.min, cfg.reward.max),
      icon = 'skull',
      onSelect = function() StartTier(tier) end
    }
  end

  lib.registerContext({ id = 'assjob_menu', title = 'Contratante', options = opts })
  lib.showContext('assjob_menu')
end

function StartTier(tier)
  if type(tier) ~= 'number' or not Config.Tiers[tier] then
    notify('Tier inválido.', 'error'); return
  end
  if isInContract then
    notify('Já tens um contrato ativo.', 'error'); return
  end

  local ok, res = lib.callback.await('qb_assassination:server:startJob', 5000, tier)
  if not ok then
    notify(res or 'Não foi possível iniciar o job.', 'error'); return
  end

  isInContract = true
  currentTier = tier
  mySquadId = res

  local invites = Config.RequiredInvites or 0
  if invites <= 0 then
    notify(('Job %s iniciado. A localização será marcada no mapa.'):format(Config.Tiers[tier].name), 'inform')
  else
    local msg = (invites == 1)
      and ('Job %s criado. Convida %d pessoa com /assinvite <id> ou por focus.'):format(Config.Tiers[tier].name, invites)
      or  ('Job %s criado. Convida %d pessoas com /assinvite <id> ou por focus.'):format(Config.Tiers[tier].name, invites)
    notify(msg, 'inform')
  end
end

-- =======================
-- Comandos
-- =======================
RegisterCommand('assjob', function()
  OpenContractMenu()
end, false)

RegisterCommand('asstier', function(_, args)
  local tier = tonumber(args[1])
  StartTier(tier)
end, false)

RegisterCommand('assinvite', function(_, args)
  if not isInContract or not mySquadId then
    notify('Não tens grupo para convidar.', 'error'); return
  end
  local target = tonumber(args[1] or '')
  if not target then
    notify('Uso: /assinvite <serverId>', 'error'); return
  end
  if target == GetPlayerServerId(PlayerId()) then
    notify('Não te podes convidar a ti próprio.', 'error'); return
  end
  local ok, msg = lib.callback.await('qb_assassination:server:invite', 5000, target)
  if ok then notify(('Convite enviado para ID %d.'):format(target), 'success')
  else notify(msg or 'Falha ao enviar convite.', 'error') end
end, false)

RegisterCommand('assaccept', function()
  if not lastInvite or GetGameTimer() > lastInvite.expire then
    notify('Nenhum convite pendente.', 'error'); return
  end
  TriggerServerEvent('qb_assassination:server:respondInvite', true, lastInvite.squadId)
  lastInvite = nil
end, false)

RegisterCommand('assdecline', function()
  if not lastInvite or GetGameTimer() > lastInvite.expire then
    notify('Nenhum convite pendente.', 'error'); return
  end
  TriggerServerEvent('qb_assassination:server:respondInvite', false, lastInvite.squadId)
  lastInvite = nil
end, false)

RegisterCommand('assstatus', function()
  local txt = ('Estado: %s | Tier: %s | Squad: %s')
    :format(isInContract and 'ATIVO' or 'livre', tostring(currentTier or '-'), tostring(mySquadId or '-'))
  notify(txt, 'inform'); print('[assstatus] '..txt)
end, false)

RegisterCommand('assleave', function()
  if mySquadId then TriggerServerEvent('qb_assassination:server:leaveSquad') end
  CleanupEncounter()
end, false)

-- Dicas no chat
CreateThread(function()
  TriggerEvent('chat:addSuggestion', '/assjob', 'Abrir o menu de contratos.')
  TriggerEvent('chat:addSuggestion', '/asstier', 'Começar um contrato diretamente pelo tier.', { { name='tier', help='1-5' } })
  TriggerEvent('chat:addSuggestion', '/assinvite', 'Convidar jogador para o contrato.', { { name='serverId', help='ID do jogador (F9/scoreboard)' } })
  TriggerEvent('chat:addSuggestion', '/assaccept', 'Aceitar o último convite recebido.')
  TriggerEvent('chat:addSuggestion', '/assdecline', 'Recusar o último convite recebido.')
  TriggerEvent('chat:addSuggestion', '/assstatus', 'Mostrar estado atual do contrato.')
  TriggerEvent('chat:addSuggestion', '/assleave', 'Sair do grupo/contrato e limpar local.')
end)

-- =======================
-- Convite por focus (ox_target)
-- =======================
CreateThread(function()
  if not (Config.EnableFocusInvite ~= false and pcall(function() return exports.ox_target end)) then
    return
  end

  exports.ox_target:addGlobalPlayer({
    {
      icon  = 'fa-solid fa-user-plus',
      label = Config.FocusInviteLabel or 'Convidar para o contrato',
      canInteract = function(entity)
        return isInContract and mySquadId ~= nil and entity ~= 0
      end,
      onSelect = function(data)
        local target = getServerIdFromEntity(data.entity)
        if not target then
          notify('Não consegui identificar o jogador (aproxima-te mais).', 'error'); return
        end
        if target == GetPlayerServerId(PlayerId()) then
          notify('Não te podes convidar a ti próprio.', 'error'); return
        end

        local ok, msg = lib.callback.await('qb_assassination:server:invite', 5000, target)
        if ok then
          notify(('Convite enviado para ID %d.'):format(target), 'success')
        else
          notify(msg or 'Falha ao enviar convite.', 'error')
        end
      end
    }
  })
end)

-- =======================
-- Receção de convite
-- =======================
RegisterNetEvent('qb_assassination:client:invitePrompt', function(payload)
  lastInvite = { squadId = payload.squadId, expire = GetGameTimer() + (payload.timeout or 60) * 1000 }

  local fromName = payload.fromName or ('ID '..tostring(payload.from))
  local tier = payload.tier
  local timeout = (payload.timeout or 60) * 1000

  local ans = lib.alertDialog({
    header = 'Convite para Contrato',
    content = ('%s convida-te para %s. Aceitas?'):format(fromName, Config.Tiers[tier].name),
    centered = true,
    cancel = true,
    labels = { confirm = 'Aceitar', cancel = 'Recusar' },
    timeout = timeout
  })

  if ans == 'confirm' then
    TriggerServerEvent('qb_assassination:server:respondInvite', true, payload.squadId)
    lastInvite = nil
  elseif ans == 'cancel' then
    TriggerServerEvent('qb_assassination:server:respondInvite', false, payload.squadId)
    lastInvite = nil
  end
end)

-- =======================
-- Recebe localização do VIP
-- =======================
RegisterNetEvent('qb_assassination:client:receiveContractLocation', function(data)
  mySquadId = data.squadId
  currentTier = data.tier

  if encounterBlip then RemoveBlip(encounterBlip) end
  encounterBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
  SetBlipSprite(encounterBlip, 458); SetBlipColour(encounterBlip, 1); SetBlipScale(encounterBlip, 0.9)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Contrato - VIP'); EndTextCommandSetBlipName(encounterBlip)

  -- Spawn quando te aproximas
  CreateThread(function()
    while isInContract and mySquadId do
      local p = cache and cache.ped or PlayerPedId()
      local dist = #(GetEntityCoords(p) - data.coords)
      if dist <= (Config.SpawnDistance or 150.0) and not vipPed then
        SpawnEncounter(data.coords, currentTier)
        break
      end
      Wait(1000)
    end
  end)
end)

-- =======================
-- Spawn de VIP + guards
-- =======================
function SpawnEncounter(coords, tier)
  local cfg = Config.Tiers[tier]; if not cfg then return end

  local pedCfg = Config.PedModels or {
    vip_primary = 's_m_m_highsec_01',   vip_fallback = 's_m_m_highsec_02',
    guard_primary = 's_m_y_blackops_01', guard_fallback = 's_m_y_blackops_02'
  }

  AddRelationshipGroup(Config.RelationshipGroup or 'ASSJOB')
  local relHash = GetHashKey(Config.RelationshipGroup or 'ASSJOB')

  -- VIP
  local vipModel = loadModelOrFallback(pedCfg.vip_primary, pedCfg.vip_fallback)
  if not vipModel then notify('Falha ao carregar modelo do VIP.', 'error'); return end

  vipPed = CreatePed(26, vipModel, coords.x, coords.y, coords.z, 0.0, true, true)
  SetEntityAsMissionEntity(vipPed, true, true)
  SetEntityInvincible(vipPed, false)
  SetPedAccuracy(vipPed, (Config.PedAccuracy and Config.PedAccuracy.vip) or 25)
  SetPedRelationshipGroupHash(vipPed, relHash)
  SetPedDropsWeaponsWhenDead(vipPed, false)
  GiveWeaponToPed(vipPed, pick(cfg.vipWeaponPool), 250, false, true)

  -- Guards
  guardPeds = {}
  local guardCount = 0
  if cfg.guardCount and cfg.guardCount.max and cfg.guardCount.max > 0 then
    guardCount = math.random(cfg.guardCount.min, cfg.guardCount.max)
  end

  local guardModel = loadModelOrFallback(pedCfg.guard_primary, pedCfg.guard_fallback)
  if guardCount > 0 and not guardModel then
    notify('Falha ao carregar modelo dos seguranças.', 'error'); return
  end

  for i = 1, guardCount do
    local offset = vec3(coords.x, coords.y, coords.z) + GetEntityForwardVector(vipPed) * (2.0 + i)
    local ped = CreatePed(26, guardModel, offset.x + math.random(-6,6), offset.y + math.random(-6,6), coords.z, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedAccuracy(ped, (Config.PedAccuracy and Config.PedAccuracy.guard) or 20)
    SetPedRelationshipGroupHash(ped, relHash)
    SetPedDropsWeaponsWhenDead(ped, false)
    GiveWeaponToPed(ped, pick(Config.Weapons.Heavy), 250, false, true)
    table.insert(guardPeds, ped)
  end

  -- IA: atacar apenas jogadores NÃO-polícia que se aproximem
  CreateThread(function()
    local engageDist = (Config.EngageDistance or 60.0)
    while vipPed and DoesEntityExist(vipPed) do
      local players = GetActivePlayers()
      local targetPed, bestDist = nil, engageDist + 1.0

      for _, pid in ipairs(players) do
        local ped = GetPlayerPed(pid)
        if ped ~= 0 and not IsPedDeadOrDying(ped, true) then
          local dist = #(GetEntityCoords(ped) - coords)
          if dist <= engageDist then
            local sid = GetPlayerServerId(pid)
            if not isPoliceCached(sid) and dist < bestDist then
              bestDist, targetPed = dist, ped
            end
          end
        end
      end

      if targetPed then
        if DoesEntityExist(vipPed) and not IsPedDeadOrDying(vipPed, true) then
          TaskCombatPed(vipPed, targetPed, 0, 16); SetPedCombatAttributes(vipPed, 46, true)
        end
        for _, g in ipairs(guardPeds) do
          if g and DoesEntityExist(g) and not IsPedDeadOrDying(g, true) then
            TaskCombatPed(g, targetPed, 0, 16); SetPedCombatAttributes(g, 46, true)
          end
        end
        break
      end

      Wait(1500)
    end
  end)

  -- Monitorizar morte do VIP
  CreateThread(function()
    while vipPed and DoesEntityExist(vipPed) do
      if IsPedDeadOrDying(vipPed, true) then
        TriggerServerEvent('qb_assassination:server:vipDown', mySquadId)
        break
      end
      Wait(400)
    end
  end)
end

-- =======================
-- Dumpster e pagamento
-- =======================
RegisterNetEvent('qb_assassination:client:assignDumpster', function(data)
  if dumpsterBlip then RemoveBlip(dumpsterBlip) dumpsterBlip = nil end
  if dumpsterZoneId then exports.ox_target:removeZone(dumpsterZoneId) dumpsterZoneId = nil end

  dumpsterBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
  SetBlipSprite(dumpsterBlip, 365); SetBlipColour(dumpsterBlip, 2); SetBlipScale(dumpsterBlip, 0.9)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Pagamento'); EndTextCommandSetBlipName(dumpsterBlip)

  dumpsterZoneId = exports.ox_target:addSphereZone({
    coords = vec3(data.coords.x, data.coords.y, data.coords.z),
    radius = 1.5,
    debug = false,
    options = { {
      icon = 'fa-solid fa-dumpster',
      label = 'Recolher pagamento',
      onSelect = function()
        if not isInContract or not mySquadId then
          notify('Não tens pagamento para recolher.', 'error'); return
        end
        local ok, err = lib.callback.await('qb_assassination:server:claimPayment', 5000)
        if ok then
          notify('Pagamento concluído. Bom trabalho.', 'success')
          CleanupEncounter()
        else
          notify(err or 'Falha ao recolher pagamento.', 'error')
        end
      end
    } }
  })
end)

-- =======================
-- Blip polícia
-- =======================
RegisterNetEvent('qb_assassination:client:blipPolice', function(coords)
  local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(blip, 161); SetBlipColour(blip, 1); SetBlipScale(blip, 1.0)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Relato 911'); EndTextCommandSetBlipName(blip)
  SetBlipAsShortRange(blip, true)
  SetTimeout(30000, function() if blip then RemoveBlip(blip) end end)
end)

-- =======================
-- Limpeza
-- =======================
function CleanupEncounter()
  if vipPed and DoesEntityExist(vipPed) then DeletePed(vipPed) end
  for _, g in ipairs(guardPeds) do if g and DoesEntityExist(g) then DeletePed(g) end end
  guardPeds = {}; vipPed = nil

  if encounterBlip then RemoveBlip(encounterBlip) encounterBlip = nil end
  if dumpsterBlip then RemoveBlip(dumpsterBlip) dumpsterBlip = nil end
  if dumpsterZoneId then exports.ox_target:removeZone(dumpsterZoneId) dumpsterZoneId = nil end

  isInContract = false
  mySquadId = nil
  currentTier = nil
end

RegisterNetEvent('qb_assassination:client:abort', function()
  CleanupEncounter()
end)
