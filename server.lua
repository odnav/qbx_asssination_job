local QBCore = exports['qbx_core']:GetCoreObject()
lib.locale()

-- Estado de squads/instâncias
local ActiveSquads = {}         -- [squadId] = { leader, members = {}, tier, state, startedAt, dumpster, vipDead, paid, cooldownUntil }
local PlayerSquad = {}          -- [src] = squadId
local PlayerCooldown = {}       -- [src] = epoch
local SquadCooldown = {}        -- [squadId] = epoch
local NextSquadId = 1000

local function now() return os.time() end
local function rand(a, b) return math.random(a, b) end
local function pick(t) return t[math.random(1, #t)] end

local function isPolice(src)
  local p = QBCore.Functions.GetPlayer(src)
  if not p then return false end
  local job = p.PlayerData.job and p.PlayerData.job.name or ''
  for _, j in ipairs(Config.PoliceJobs) do
    if job == j then return true end
  end
  return false
end

local function notify(src, msg, typ)
  TriggerClientEvent('ox_lib:notify', src, { title = Config.NotifyTitle, description = msg, type = typ or 'inform' })
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

local function onCooldownSquad(squadId)
  local ts = SquadCooldown[squadId]
  if not ts then return 0 end
  return cooldownLeft(ts)
end

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

local function squadMemberCount(id)
  local s = ActiveSquads[id]; if not s then return 0 end
  local c = 0
  for _ in pairs(s.members) do c = c + 1 end
  return c
end

-- convite a players via focus
lib.callback.register('qb_assassination:server:invite', function(src, target)
  local squadId = PlayerSquad[src]
  if not squadId then
    return false, 'Não tens squad ativa.'
  end
  local s = ActiveSquads[squadId]; if not s then return false, 'Squad inválida.' end
  if s.state ~= 'forming' then
    return false, 'O grupo já não está em fase de convite.'
  end
  if PlayerSquad[target] then
    return false, 'Esse jogador já está noutra squad.'
  end
  if target == src then return false, 'Não te podes convidar a ti próprio.' end

  -- envia pedido ao target
  TriggerClientEvent('qb_assassination:client:invitePrompt', target, { from = src, squadId = squadId, tier = s.tier, timeout = Config.InviteTimeout })
  return true
end)

RegisterNetEvent('qb_assassination:server:respondInvite', function(accept, squadId)
  local src = source
  local s = ActiveSquads[squadId]
  if not s or s.state ~= 'forming' then
    notify(src, 'Convite já não é válido.', 'error')
    return
  end
  if accept then
    if PlayerSquad[src] then
      notify(src, 'Já estás noutro grupo.', 'error')
      return
    end
    s.members[src] = true
    PlayerSquad[src] = squadId
    for memberSrc, _ in pairs(s.members) do
      notify(memberSrc, ('%s juntou-se ao grupo (%d/%d).'):format(GetPlayerName(src), squadMemberCount(squadId), 1 + Config.RequiredInvites), 'success')
    end
    -- Quando atinge o nº necessário, envia localização
    if (squadMemberCount(squadId) >= (1 + Config.RequiredInvites)) then
      s.state = 'enroute'
      local spot = pick(Config.EncounterSpots)
      -- possivelmente dispara alerta de polícia ao começar (Tier 4/5)
      local tierCfg = Config.Tiers[s.tier]
      if tierCfg and tierCfg.policeCallOnStart > 0 then
        if math.random() <= tierCfg.policeCallOnStart then
          TriggerEvent(Config.Dispatch.EventName, 'start', spot)
        end
      end
      -- enviar spot a todos
      for memberSrc, _ in pairs(s.members) do
        TriggerClientEvent('qb_assassination:client:receiveContractLocation', memberSrc, { tier = s.tier, coords = spot, squadId = squadId })
        notify(memberSrc, 'Localização do VIP enviada no teu mapa.', 'inform')
      end
    end
  else
    notify(src, 'Recusaste o convite.', 'error')
  end
end)

-- começa o job: cria squad, checks de cooldown, limitações
lib.callback.register('qb_assassination:server:startJob', function(src, tier)
  if onCooldownPlayer(src) > 0 then
    return false, ('Ainda em cooldown (%ds).'):format(onCooldownPlayer(src))
  end

  if PlayerSquad[src] then
    return false, 'Já tens um job ativo.'
  end

  -- Limite (simples) por tier
  local activeCount = 0
  for _, s in pairs(ActiveSquads) do
    if s.tier == tier and s.state ~= 'completed' then activeCount = activeCount + 1 end
  end
  if activeCount >= Config.MaxActiveSquadsPerTier then
    return false, 'Este tier está demasiado quente. Tenta daqui a pouco.'
  end

  local squadId = createSquad(src, tier)
  notify(src, ('Criaste um grupo para %s. Convida %d membros focando neles.'):format(Config.Tiers[tier].name, Config.RequiredInvites), 'inform')
  return true, squadId
end)

-- marca VIP morto; verifica conclusão
RegisterNetEvent('qb_assassination:server:vipDown', function(squadId)
  local src = source
  local s = ActiveSquads[squadId]; if not s then return end
  s.vipDead = true
  if s.state ~= 'completed' then
    s.state = 'engaged' -- continua até entregar
  end

  -- alerta polícia on VIP death (tiers 1-3)
  local cfg = Config.Tiers[s.tier]
  if cfg and cfg.policeCallOnVipDeath and cfg.policeCallOnVipDeath > 0 then
    if math.random() <= cfg.policeCallOnVipDeath then
      TriggerEvent(Config.Dispatch.EventName, 'vip_death', nil)
    end
  end

  for m, _ in pairs(s.members) do
    notify(m, 'O VIP caiu! Vai ao caixote do lixo indicado para recolher o pagamento.', 'success')
  end

  -- escolhe dumpster para pagamento
  if not s.dumpster then
    s.dumpster = Config.Dumpsters[rand(1, #Config.Dumpsters)]
  end

  -- envia a todos o ponto do dumpster
  for m, _ in pairs(s.members) do
    TriggerClientEvent('qb_assassination:client:assignDumpster', m, { coords = s.dumpster.coords, heading = s.dumpster.heading, squadId = squadId })
  end
end)

-- entrega/pagamento no dumpster (apenas uma vez por squad)
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

  -- paga a todos por igual
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

  -- cooldowns
  for m, _ in pairs(s.members) do
    PlayerCooldown[m] = now() + Config.PlayerCooldown
    PlayerSquad[m] = nil
  end
  SquadCooldown[squadId] = now() + Config.SquadCooldown

  -- limpa
  ActiveSquads[squadId] = nil
  return true
end)

-- sair/abortar
RegisterNetEvent('qb_assassination:server:leaveSquad', function()
  local src = source
  local squadId = PlayerSquad[src]
  if not squadId then return end
  local s = ActiveSquads[squadId]
  PlayerSquad[src] = nil
  if s and s.members then
    s.members[src] = nil
    for m, _ in pairs(s.members) do
      notify(m, GetPlayerName(src) .. ' saiu do grupo.', 'error')
    end
    if next(s.members) == nil then
      ActiveSquads[squadId] = nil
    end
  end
end)

-- Hook de Dispatch (adapta ao teu sistema de polícia/ps-dispatch/etc.)
AddEventHandler('qb_assassination:policeAlert', function(kind, coords)
  if not Config.Dispatch.Enabled then return end
  -- Aqui podes integrar com ps-dispatch, cd_dispatch, etc.
  -- Exemplo genérico: mandar notify a todos os cops
  for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
    if isPolice(playerId) then
      local msg = (kind == 'start') and 'Atividade suspeita reportada.' or 'Homicídio reportado.'
      TriggerClientEvent('ox_lib:notify', playerId, {
        title = 'Central',
        description = msg,
        type = 'warning'
      })
      if coords then
        TriggerClientEvent('qb_assassination:client:blipPolice', playerId, coords)
      end
    end
  end
end)

-- limpeza em disconnect
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
