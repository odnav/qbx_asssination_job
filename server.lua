-- server.lua

-- Core com fallback (qbx_core -> qb-core)
local QBCore
do
  local ok, obj = pcall(function() return exports['qbx_core']:GetCoreObject() end)
  if ok and obj then
    QBCore = obj
  else
    local ok2, obj2 = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok2 and obj2 then
      QBCore = obj2
    else
      print('^1[assassination] ERRO: não encontrei qbx_core nem qb-core. Verifica o nome da pasta e a ordem de ensure.^7')
      return
    end
  end
end

-- Se não usares locales, podes comentar esta linha para evitar warnings.
lib.locale()

-- =========================
-- Estado / helpers
-- =========================
local ActiveSquads = {}   -- [squadId] = { leader, members = {}, tier, state, startedAt, dumpster, vipDead, paid }
local PlayerSquad = {}    -- [src] = squadId
local PlayerCooldown = {} -- [src] = epoch
local SquadCooldown  = {} -- [squadId] = epoch
local NextSquadId = 1000

local function now() return os.time() end
local function rand(a, b) return math.random(a, b) end
local function pick(t) return t[math.random(1, #t)] end

local function notify(src, msg, typ)
  TriggerClientEvent('ox_lib:notify', src, {
    title = Config.NotifyTitle or 'Contratante',
    description = msg, type = typ or 'inform'
  })
end

local function cooldownLeft(ts)
  local left = ts - now()
  return left > 0 and left or 0
end

local function onCooldownPlayer(src)
  local ts = PlayerCooldown[src]
  if not ts then return 0 end
  return cooldownLeft(ts)
end

local function squadMemberCount(id)
  local s = ActiveSquads[id]; if not s then return 0 end
  local c = 0
  for _ in pairs(s.members) do c = c + 1 end
  return c
end

local function isPolice(src)
  local p = QBCore.Functions.GetPlayer(src)
  if not p then return false end
  local job = p.PlayerData.job and p.PlayerData.job.name or ''
  for _, j in ipairs(Config.PoliceJobs or {'police'}) do
    if job == j then return true end
  end
  return false
end

-- callback para o cliente perguntar se é polícia
lib.callback.register('qbx:server:isPolice', function(source, serverId)
  local sid = serverId or source
  return isPolice(sid)
end)

-- =========================
-- Spots por tier (e dumpsters por tier)
-- =========================
local function _extractVec3(entry)
  if type(entry) == 'vector3' or type(entry) == 'vector4' then
    return vec3(entry.x, entry.y, entry.z)
  elseif type(entry) == 'table' then
    if entry.coords then return entry.coords end
    if entry.x and entry.y and entry.z then return vec3(entry.x, entry.y, entry.z) end
  end
  return nil
end

local function pickSpotForTier(tier)
  local pool = {}
  if Config.EncounterSpotsByTier and Config.EncounterSpotsByTier[tier] then
    for _, e in ipairs(Config.EncounterSpotsByTier[tier]) do
      local v = _extractVec3(e)
      if v then pool[#pool+1] = v end
    end
  end
  if (#pool == 0) and (not Config.EncounterTierStrict) and (Config.EncounterSpots) then
    for _, e in ipairs(Config.EncounterSpots) do
      local v = _extractVec3(e)
      if v then pool[#pool+1] = v end
    end
  end
  if #pool == 0 then return nil end
  return pool[math.random(1, #pool)]
end

local function pickDumpsterForTier(tier)
  local pool = {}
  if Config.DumpstersByTier and Config.DumpstersByTier[tier] then
    for _, e in ipairs(Config.DumpstersByTier[tier]) do
      local v = _extractVec3(e)
      if v then pool[#pool+1] = { coords = v, heading = e.heading or 0.0 } end
    end
  end
  if (#pool == 0) and (not Config.DumpsterTierStrict) and Config.Dumpsters then
    for _, e in ipairs(Config.Dumpsters) do
      local coords = e.coords or _extractVec3(e)
      if coords then pool[#pool+1] = { coords = coords, heading = e.heading or 0.0 } end
    end
  end
  if #pool == 0 then return nil end
  return pool[math.random(1, #pool)]
end

-- =========================
-- Gestão de squads
-- =========================
local function createSquad(leader, tier)
  NextSquadId = NextSquadId + 1
  local id = NextSquadId
  ActiveSquads[id] = {
    leader = leader,
    members = { [leader] = true },
    tier = tier,
    state = 'forming', -- forming -> enroute -> engaged -> completed
    startedAt = now(),
    dumpster = nil,
    vipDead = false,
    paid = false,
  }
  PlayerSquad[leader] = id
  return id
end

local function sendLocationToSquad(squadId, spot)
  local s = ActiveSquads[squadId]; if not s then return end
  for memberSrc, _ in pairs(s.members) do
    TriggerClientEvent('qb_assassination:client:receiveContractLocation', memberSrc, {
      tier = s.tier, coords = spot, squadId = squadId
    })
    notify(memberSrc, 'Localização do VIP enviada no teu mapa.', 'inform')
  end
end

-- =========================
-- Convites
-- =========================
lib.callback.register('qb_assassination:server:invite', function(src, target)
  if type(target) ~= 'number' or not GetPlayerName(target) then
    return false, 'Jogador inválido.'
  end

  local squadId = PlayerSquad[src]
  if not squadId then return false, 'Não tens squad ativa.' end

  local s = ActiveSquads[squadId]; if not s then return false, 'Squad inválida.' end
  if s.state ~= 'forming' then return false, 'O grupo já não está em fase de convite.' end
  if PlayerSquad[target] then return false, 'Esse jogador já está noutra squad.' end
  if target == src then return false, 'Não te podes convidar a ti próprio.' end

  local p = QBCore.Functions.GetPlayer(target)
  if not p then return false, 'Jogador offline ou indisponível.' end

  TriggerClientEvent('qb_assassination:client:invitePrompt', target, {
    from = src,
    fromName = GetPlayerName(src),
    squadId = squadId,
    tier = s.tier,
    timeout = Config.InviteTimeout
  })

  return true
end)

RegisterNetEvent('qb_assassination:server:respondInvite', function(accept, squadId)
  local src = source
  local s = ActiveSquads[squadId]
  if not s or s.state ~= 'forming' then
    notify(src, 'Convite já não é válido.', 'error')
    return
  end

  if not accept then
    notify(src, 'Recusaste o convite.', 'error')
    return
  end

  if PlayerSquad[src] then
    notify(src, 'Já estás noutro grupo.', 'error')
    return
  end

  s.members[src] = true
  PlayerSquad[src] = squadId

  local need = 1 + (Config.RequiredInvites or 0)
  for memberSrc, _ in pairs(s.members) do
    notify(memberSrc, ('%s juntou-se ao grupo (%d/%d).'):format(GetPlayerName(src), squadMemberCount(squadId), need), 'success')
  end

  -- Quando atinge o nº necessário, envia localização
  if (squadMemberCount(squadId) >= need) then
    s.state = 'enroute'

    local spot = pickSpotForTier(s.tier)
    if not spot then
      for memberSrc, _ in pairs(s.members) do
        notify(memberSrc, 'Sem locais configurados para este tier.', 'error')
      end
      -- aborta squad
      for m, _ in pairs(s.members) do PlayerSquad[m] = nil end
      ActiveSquads[squadId] = nil
      return
    end

    local tierCfg = Config.Tiers[s.tier]
    if tierCfg and tierCfg.policeCallOnStart and tierCfg.policeCallOnStart > 0 then
      if math.random() <= tierCfg.policeCallOnStart then
        TriggerEvent(Config.Dispatch.EventName, 'start', spot)
      end
    end

    sendLocationToSquad(squadId, spot)
  end
end)

-- =========================
-- Começar job
-- =========================
lib.callback.register('qb_assassination:server:startJob', function(src, tier)
  if onCooldownPlayer(src) > 0 then
    return false, ('Ainda em cooldown (%ds).'):format(onCooldownPlayer(src))
  end
  if PlayerSquad[src] then
    return false, 'Já tens um job ativo.'
  end
  if not Config.Tiers[tier] then
    return false, 'Tier inválido.'
  end

  -- Limite (simples) por tier
  local activeCount = 0
  for _, s in pairs(ActiveSquads) do
    if s.tier == tier and s.state ~= 'completed' then activeCount = activeCount + 1 end
  end
  if activeCount >= (Config.MaxActiveSquadsPerTier or 8) then
    return false, 'Este tier está demasiado quente. Tenta daqui a pouco.'
  end

  -- Se for arranque imediato, valida já que existe spot
  if (Config.RequiredInvites or 0) <= 0 then
    local spotTest = pickSpotForTier(tier)
    if not spotTest then
      return false, 'Sem locais configurados para este tier.'
    end
  end

  local squadId = createSquad(src, tier)
  local s = ActiveSquads[squadId]
  local tierCfg = Config.Tiers[tier]

  if (Config.RequiredInvites or 0) <= 0 then
    s.state = 'enroute'
    local spot = pickSpotForTier(tier)
    if not spot then
      ActiveSquads[squadId] = nil
      PlayerSquad[src] = nil
      return false, 'Sem locais configurados para este tier.'
    end

    if tierCfg and tierCfg.policeCallOnStart and tierCfg.policeCallOnStart > 0 then
      if math.random() <= tierCfg.policeCallOnStart then
        TriggerEvent(Config.Dispatch.EventName, 'start', spot)
      end
    end

    sendLocationToSquad(squadId, spot)
    notify(src, ('%s iniciado. Vai ao ponto no mapa.'):format(tierCfg.name), 'inform')
  else
    local needed = Config.RequiredInvites
    local msg = (needed == 1)
      and ('Criaste um grupo para %s. Convida %d pessoa focando nela.'):format(tierCfg.name, needed)
      or  ('Criaste um grupo para %s. Convida %d pessoas focando nelas.'):format(tierCfg.name, needed)
    notify(src, msg, 'inform')
  end

  return true, squadId
end)

-- =========================
-- VIP down / pagamento
-- =========================
RegisterNetEvent('qb_assassination:server:vipDown', function(squadId)
  local src = source
  local s = ActiveSquads[squadId]; if not s then return end

  s.vipDead = true
  if s.state ~= 'completed' then
    s.state = 'engaged'
  end

  local cfg = Config.Tiers[s.tier]
  if cfg and cfg.policeCallOnVipDeath and cfg.policeCallOnVipDeath > 0 then
    if math.random() <= cfg.policeCallOnVipDeath then
      TriggerEvent(Config.Dispatch.EventName, 'vip_death', nil)
    end
  end

  for m, _ in pairs(s.members) do
    notify(m, 'O VIP caiu! Vai ao caixote do lixo indicado para recolher o pagamento.', 'success')
  end

  if not s.dumpster then
    local d = pickDumpsterForTier(s.tier)
    if not d then
      for m, _ in pairs(s.members) do
        notify(m, 'Sem dumpsters configurados para este tier.', 'error')
      end
      return
    end
    s.dumpster = d
  end

  for m, _ in pairs(s.members) do
    TriggerClientEvent('qb_assassination:client:assignDumpster', m, {
      coords = s.dumpster.coords, heading = s.dumpster.heading, squadId = squadId
    })
  end
end)

lib.callback.register('qb_assassination:server:claimPayment', function(src)
  local squadId = PlayerSquad[src]
  if not squadId then return false, 'Não estás em nenhum job.' end

  local s = ActiveSquads[squadId]
  if not s then return false, 'Job inválido.' end
  if not s.vipDead then return false, 'O VIP ainda não está abatido.' end
  if s.paid then return false, 'O pagamento já foi levantado.' end

  s.paid = true
  s.state = 'completed'

  local r = Config.Tiers[s.tier].reward
  local amount = rand(r.min, r.max)

  local members = {}
  for m, _ in pairs(s.members) do members[#members+1] = m end
  local share = math.floor(amount / #members)

  for _, m in ipairs(members) do
    local p = QBCore.Functions.GetPlayer(m)
    if p then
      p.Functions.AddMoney('cash', share, 'assassination-job')
      notify(m, ('Recebeste $%d pelo contrato.'):format(share), 'success')
    end
  end

  -- cooldowns e limpeza
  for m, _ in pairs(s.members) do
    PlayerCooldown[m] = now() + (Config.PlayerCooldown or 600)
    PlayerSquad[m] = nil
  end
  SquadCooldown[squadId] = now() + (Config.SquadCooldown or 600)
  ActiveSquads[squadId] = nil

  return true
end)

-- =========================
-- Sair / abortar
-- =========================
RegisterNetEvent('qb_assassination:server:leaveSquad', function()
  local src = source
  local squadId = PlayerSquad[src]
  if not squadId then return end

  local s = ActiveSquads[squadId]
  PlayerSquad[src] = nil
  if s and s.members then
    s.members[src] = nil
    for m, _ in pairs(s.members) do
      notify(m, (GetPlayerName(src) or ('ID '..src)) .. ' saiu do grupo.', 'error')
    end
    if next(s.members) == nil then
      ActiveSquads[squadId] = nil
    end
  end
end)

-- =========================
-- Dispatch genérico
-- =========================
AddEventHandler('qb_assassination:policeAlert', function(kind, coords)
  if not (Config.Dispatch and Config.Dispatch.Enabled) then return end
  for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
    if isPolice(playerId) then
      local msg = (kind == 'start') and 'Atividade suspeita reportada.' or 'Homicídio reportado.'
      TriggerClientEvent('ox_lib:notify', playerId, { title = 'Central', description = msg, type = 'warning' })
      if coords then
        TriggerClientEvent('qb_assassination:client:blipPolice', playerId, coords)
      end
    end
  end
end)

-- =========================
-- Limpeza em disconnect
-- =========================
AddEventHandler('playerDropped', function()
  local src = source
  local squadId = PlayerSquad[src]
  if not squadId then return end

  local s = ActiveSquads[squadId]
  PlayerSquad[src] = nil
  if s and s.members then
    s.members[src] = nil
    if next(s.members) == nil then
      ActiveSquads[squadId] = nil
    end
  end
end)
