Config = {}

-- Número do "contratante" no telemóvel (se tiveres qb-phone/qbx_phone)
Config.PhoneNumber = '555-ASSASSIN'  -- string que irá abrir o menu de tiers

-- Se não tiveres phone, podes usar /assjob para abrir o menu
Config.EnableCommandFallback = true
Config.CommandName = 'assjob'

-- Número mínimo de membros (além do iniciador) que tens de convidar por focus
Config.RequiredInvites = 0  -- conforme pediste; podes mudar aqui

-- Tempo para aceitar convite (segundos)
Config.InviteTimeout = 60

-- Cooldown por jogador/por equipa (segundos)
Config.PlayerCooldown = 10 * 60      -- 10 minutos
Config.SquadCooldown  = 10 * 60

-- Dumpsters (locais de recolha de prémio) - define pontos no mapa
-- Podes adicionar quantos quiseres
Config.Dumpsters = {
  {coords = vec3(45.87, -1748.22, 29.61), heading = 50.0},
  {coords = vec3(207.34, -1466.51, 29.15), heading = 130.0},
  {coords = vec3(-312.64, -1531.23, 27.54), heading = 230.0},
  {coords = vec3(-582.13, -1626.41, 27.01), heading = 140.0},
  {coords = vec3(877.92, -2165.67, 32.29), heading = 175.0},
}

-- Modelos de caixotes (para validação visual/target opcional)
Config.DumpsterModels = {
  `prop_recyclebin_04_a`,
  `prop_dumpster_01a`,
  `prop_dumpster_02a`,
  `prop_bin_07d`
}

-- Armas por tier
Config.Weapons = {
  Tier1 = { `WEAPON_KNIFE`, `WEAPON_BAT`, `WEAPON_BOTTLE` },
  Tier2 = { `WEAPON_SNSPISTOL`, `WEAPON_PISTOL`, `WEAPON_PISTOL_MK2` },
  Tier3 = { `WEAPON_MICROSMG`, `WEAPON_SMG`, `WEAPON_MACHINEPISTOL` },
  Heavy = { `WEAPON_ASSAULTRIFLE`, `WEAPON_CARBINERIFLE`, `WEAPON_COMPACTRIFLE` },
}

-- Definição dos Tiers
Config.Tiers = {
  [1] = {
    name = 'Tier 1',
    vipWeaponPool = Config.Weapons.Tier1,
    guardCount = {min = 0, max = 0},
    policeCallOnVipDeath = 0.33,  -- 33%
    policeCallOnStart = 0.0,
    reward = {min = 1000, max = 2000}
  },
  [2] = {
    name = 'Tier 2',
    vipWeaponPool = Config.Weapons.Tier2,
    guardCount = {min = 0, max = 0},
    policeCallOnVipDeath = 0.50,
    policeCallOnStart = 0.0,
    reward = {min = 2000, max = 4000}
  },
  [3] = {
    name = 'Tier 3',
    vipWeaponPool = Config.Weapons.Tier3,
    guardCount = {min = 0, max = 0},
    policeCallOnVipDeath = 1.0,   -- 100%
    policeCallOnStart = 0.0,
    reward = {min = 5000, max = 7000}
  },
  [4] = {
    name = 'Tier 4',
    vipWeaponPool = Config.Weapons.Heavy,
    guardCount = {min = 3, max = 5},
    policeCallOnVipDeath = 0.0,
    policeCallOnStart = 0.50,
    reward = {min = 10000, max = 15000}
  },
  [5] = {
    name = 'Tier 5',
    vipWeaponPool = Config.Weapons.Heavy,
    guardCount = {min = 5, max = 10},
    policeCallOnVipDeath = 0.0,
    policeCallOnStart = 0.50,
    reward = {min = 15000, max = 20000}
  },
}

-- NPCs não atacam players com job de polícia ('police', 'lspd', etc.)
Config.PoliceJobs = { 'police' }

-- Distância de spawn e comportamento
Config.SpawnDistance = 150.0     -- distância do jogador para spawnar o encontro
Config.EngageDistance = 60.0     -- quando se aproximam, os guards entram em alerta
Config.PedAccuracy = {vip = 25, guard = 20}
Config.RelationshipGroup = 'ASSJOB'

-- Lista de possíveis zonas para encontros (VIP + guards). Acrescenta quantas quiseres.
Config.EncounterSpots = {
  vec3(-1017.9, -2694.4, 13.97),
  vec3(455.3, -1023.7, 28.2),
  vec3(1249.2, -332.8, 69.1),
  vec3(-1544.8, -406.5, 41.99),
  vec3(-303.8, -2252.9, 7.3),
}

-- Dispatch: adapta ao teu sistema (aqui ficam eventos genéricos para integrares)
Config.Dispatch = {
  Enabled = true,
  EventName = 'qb_assassination:policeAlert', -- o server propaga este evento
  MinCops = 0
}

-- Notificações
Config.NotifyTitle = 'Contratante'

-- Proteções básicas
Config.MaxActiveSquadsPerTier = 8
