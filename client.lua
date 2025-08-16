-- client.lua

-- NADA de GetCoreObject no cliente
local isInContract = false
local mySquadId = nil
local currentTier = nil
local vipPed, guardPeds = nil, {}
local targetDumpster, dumpsterBlip = nil, nil
local encounterBlip = nil

-- Utils
local function notify(msg, typ)
  lib.notify({ title = Config.NotifyTitle, description = msg, type = typ or 'inform' })
end

local function roll(p) return math.random() <= p end
local function pick(t) return t[math.random(1, #t)] end

-- Phone integration (opcional)
-- AddEventHandler('qbx_phone:client:callIncoming:'..Config.PhoneNumber, function()
--   OpenContractMenu()
-- end)

-- Fallback por comando
if Config.EnableCommandFallback then
  RegisterCommand(Config.CommandName, function()
    OpenContractMenu()
  end)
end

-- =======================
-- MENU DE TIERS
-- =======================
function OpenContractMenu()
  if isInContract then
    notify('Já tens um contrato ativo.', 'error')
    return
  end

  local opts = {}
  for tier, cfg in pairs(Config.Tiers) do
    opts[#opts+1] = {
      title = cfg.name,
      description = ('Recompensa: $%d - $%d'):format(cfg.reward.min, cfg.reward.max),
      icon = 'skull',
      onSelect = function()
        StartTier(tier)
      end
    }
  end
  lib.registerContext({ id = 'assjob_menu', title = 'Contratante', options = opts })
  lib.showContext('assjob_menu')
end

function StartTier(tier)
  local ok, res = lib.callback.await('qb_assassination:server:startJob', 5000, tier)
  if not ok then
    notify(res or 'Não foi possível iniciar o job.', 'error')
    return
  end
  isInContract = true
  currentTier = tier
  mySquadId = res

  local invites = Config.RequiredInvites or 0
  if invites <= 0 then
    -- o servidor vai enviar a localização imediatamente
    notify(('Job %s iniciado. A localização será marcada no mapa.'):format(Config.Tiers[tier].name), 'inform')
  else
    local msg = (invites == 1)
      and ('Job %s criado. Convida %d pessoa focando nela (ox_target).'):format(Config.Tiers[tier].name, invites)
      or  ('Job %s criado. Convida %d pessoas focando nelas (ox_target).'):format(Config.Tiers[tier].name, invites)
    notify(msg, 'inform')
  end
end

-- =======================
-- CONVITES VIA FOCUS (ox_target)
-- =======================
CreateThread(function()
  exports.ox_target:addGlobalPlayer({
    {
      icon = 'fa-solid fa-user-plus',
      label = 'Convidar para o contrato',
      canInteract = function(entity, distance, coords, name, bone)
        if not isInContract or not mySquadId then return false end
        return true
      end,
      onSelect = function(data)
        local target = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))
        if target and target ~= -1 then
          local ok, msg = lib.callback.await('qb_assassination:server:invite', 5000, target)
          if ok then
            notify('Convite enviado.', 'success')
          else
            notify(msg or 'Falha ao enviar convite.', 'error')
          end
        end
      end
    }
  })
end)

-- Recebe o prompt de convite
RegisterNetEvent('qb_assassination:client:invitePrompt', function(payload)
  local from = payload.from
  local squadId = payload.squadId
  local tier = payload.tier
  local timeout = payload.timeout or 60

  local ans = lib.alertDialog({
    header = 'Convite para Contrato',
    content = ('%s convida-te para %s. Aceitas?'):format(GetPlayerName(GetPlayerFromServerId(from)), Config.Tiers[tier].name),
    centered = true,
    cancel = true,
    labels = { confirm = 'Aceitar', cancel = 'Recusar' },
    timeout = timeout * 1000
  })

  local accept = (ans == 'confirm')
  TriggerServerEvent('qb_assassination:server:respondInvite', accept, squadId)
end)

-- =======================
-- RECEBE LOCALIZAÇÃO DO VIP
-- =======================
RegisterNetEvent('qb_assassination:client:receiveContractLocation', function(data)
  mySquadId = data.squadId
  currentTier = data.tier

  if encounterBlip then RemoveBlip(encounterBlip) end
  encounterBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
  SetBlipSprite(encounterBlip, 458) -- skull
  SetBlipColour(encounterBlip, 1)
  SetBlipScale(encounterBlip, 0.9)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Contrato - VIP')
  EndTextCommandSetBlipName(encounterBlip)

  -- gerir spawn quando o player se aproxima
  CreateThread(function()
    while isInContract and mySquadId do
      local p = cache.ped or PlayerPedId()
      local pcoords = GetEntityCoords(p)
      local dist = #(pcoords - data.coords)
      if dist <= Config.SpawnDistance and not vipPed then
        SpawnEncounter(data.coords, currentTier)
        break
      end
      Wait(1000)
    end
  end)
end)

-- =======================
-- SPAWN DE VIP + GUARDS
-- =======================
function SpawnEncounter(coords, tier)
  local cfg = Config.Tiers[tier]
  if not cfg then return end

  -- relationship group
  local relHash = GetHashKey(Config.RelationshipGroup)
  AddRelationshipGroup(Config.RelationshipGroup)

  -- VIP
  local vipModel = `ig_kenny` -- altera se quiseres
  lib.requestModel(vipModel, 5000)
  vipPed = CreatePed(26, vipModel, coords.x, coords.y, coords.z, 0.0, true, true)
  SetEntityAsMissionEntity(vipPed, true, true)
  SetEntityInvincible(vipPed, false)
  SetPedAccuracy(vipPed, Config.PedAccuracy.vip)
  SetPedRelationshipGroupHash(vipPed, relHash)
  GiveWeaponToPed(vipPed, pick(cfg.vipWeaponPool), 250, false, true)

  -- Guards
  guardPeds = {}
  local guardCount = 0
  if cfg.guardCount.max > 0 then
    guardCount = math.random(cfg.guardCount.min, cfg.guardCount.max)
  end

  for i=1, guardCount do
    local guardModel = `csb_mweather`
    lib.requestModel(guardModel, 5000)
    local offset = GetOffsetFromEntityInWorldCoords(vipPed, math.random(-8, 8) * 1.0, math.random(-8, 8) * 1.0, 0.0)
    local ped = CreatePed(26, guardModel, offset.x, offset.y, offset.z, 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedAccuracy(ped, Config.PedAccuracy.guard)
    SetPedRelationshipGroupHash(ped, relHash)
    GiveWeaponToPed(ped, pick(Config.Weapons.Heavy), 250, false, true)
    table.insert(guardPeds, ped)
  end

  -- loop de comportamento (atacar não-polícias quando se aproximam)
  CreateThread(function()
    while vipPed and DoesEntityExist(vipPed) do
      local p = PlayerPedId()
      local dist = #(GetEntityCoords(p) - coords)
      if dist <= Config.EngageDistance then
        local myServerId = GetPlayerServerId(PlayerId())
        local isCop = lib.callback.await('qbx:server:isPolice', false, myServerId)
        if not isCop then
          for _, g in ipairs(guardPeds) do
            if DoesEntityExist(g) and not IsPedDeadOrDying(g, true) then
              TaskCombatPed(g, p, 0, 16)
              SetPedCombatAttributes(g, 46, true)
            end
          end
          if DoesEntityExist(vipPed) and not IsPedDeadOrDying(vipPed, true) then
            TaskCombatPed(vipPed, p, 0, 16)
            SetPedCombatAttributes(vipPed, 46, true)
          end
        end
        break
      end
      Wait(500)
    end
  end)

  -- monitorizar morte do VIP
  CreateThread(function()
    while vipPed and DoesEntityExist(vipPed) do
      if IsPedDeadOrDying(vipPed, true) then
        TriggerServerEvent('qb_assassination:server:vipDown', mySquadId)
        break
      end
      Wait(500)
    end
  end)
end

-- =======================
-- DUMPSTER E PAGAMENTO
-- =======================
RegisterNetEvent('qb_assassination:client:assignDumpster', function(data)
  if dumpsterBlip then RemoveBlip(dumpsterBlip) dumpsterBlip = nil end
  targetDumpster = data

  dumpsterBlip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
  SetBlipSprite(dumpsterBlip, 365)
  SetBlipColour(dumpsterBlip, 2)
  SetBlipScale(dumpsterBlip, 0.9)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Pagamento')
  EndTextCommandSetBlipName(dumpsterBlip)

  -- zona de target para recolher pagamento
  exports.ox_target:addSphereZone({
    coords = vec3(data.coords.x, data.coords.y, data.coords.z),
    radius = 1.5,
    debug = false,
    options = {
      {
        icon = 'fa-solid fa-dumpster',
        label = 'Recolher pagamento',
        onSelect = function()
          if not isInContract or not mySquadId then
            notify('Não tens pagamento para recolher.', 'error')
            return
          end
          local ok, err = lib.callback.await('qb_assassination:server:claimPayment', 5000)
          if ok then
            notify('Pagamento concluído. Bom trabalho.', 'success')
            CleanupEncounter(true)
          else
            notify(err or 'Falha ao recolher pagamento.', 'error')
          end
        end
      }
    }
  })
end)

-- =======================
-- BLIP POLÍCIA
-- =======================
RegisterNetEvent('qb_assassination:client:blipPolice', function(coords)
  local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(blip, 161)
  SetBlipColour(blip, 1)
  SetBlipScale(blip, 1.0)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Relato 911')
  EndTextCommandSetBlipName(blip)
  SetBlipAsShortRange(blip, true)
  SetTimeout(30000, function()
    if blip then RemoveBlip(blip) end
  end)
end)

-- =======================
-- LIMPEZA
-- =======================
function CleanupEncounter(keepContractFlag)
  if vipPed and DoesEntityExist(vipPed) then
    DeletePed(vipPed)
  end
  for _, g in ipairs(guardPeds) do
    if g and DoesEntityExist(g) then DeletePed(g) end
  end
  guardPeds = {}
  vipPed = nil

  if encounterBlip then RemoveBlip(encounterBlip) encounterBlip = nil end
  if dumpsterBlip then RemoveBlip(dumpsterBlip) dumpsterBlip = nil end

  -- termina sempre o contrato localmente
  isInContract = false
  mySquadId = nil
  currentTier = nil
end

RegisterNetEvent('qb_assassination:client:abort', function()
  CleanupEncounter(false)
end)

-- sair manual
RegisterCommand('assleave', function()
  if mySquadId then
    TriggerServerEvent('qb_assassination:server:leaveSquad')
  end
  CleanupEncounter(false)
end)
