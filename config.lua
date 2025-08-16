-- config.lua

Config = {}

-- ==== Phone / comando ====
Config.PhoneNumber = '555-ASSASSIN'   -- integra com o teu phone se quiseres (ver client.lua)
Config.EnableCommandFallback = true   -- permite abrir pelo comando
Config.CommandName = 'assjob'

-- ==== Regras de grupo/convites ====
-- 0 = arranca logo; 1 = pede 1 convite; >1 = pede X convites
Config.RequiredInvites = 1
Config.InviteTimeout = 60             -- segundos para aceitar convite

-- ==== Cooldowns ====
Config.PlayerCooldown = 10 * 60       -- 10 minutos por jogador
Config.SquadCooldown  = 10 * 60       -- 10 minutos por grupo

-- ==== Locais de recolha (dumpsters) ====
Config.Dumpsters = {
  { coords = vec3(-1566.14, -427.58, 36.98), heading = 153.0 },
  { coords = vec3(-1821.20, 803.16, 137.49), heading = 129.1 },
  { coords = vec3(1723.59, 3698.22, 33.47), heading = 286.2 },
--  { coords = vec3(-582.13, -1626.41, 27.01), heading = 140.0 },
  { coords = vec3(885.34, -2171.80, 29.52), heading = 350.0 },
}
-- (Opcional, caso queiras validar modelos no mundo)
Config.DumpsterModels = {
  `prop_recyclebin_04_a`,
  `prop_dumpster_01a`,
  `prop_dumpster_02a`,
  `prop_bin_07d`,
}

-- ==== Modelos dos NPCs (podes trocar aqui) ====
Config.PedModels = {
  vip_primary     = 's_m_m_highsec_01',
  vip_fallback    = 's_m_m_highsec_02',
  guard_primary   = 's_m_y_blackops_01',
  guard_fallback  = 's_m_y_blackops_02',
}

-- ==== Armas por tier ====
Config.Weapons = {
  Tier1 = { `WEAPON_KNIFE`, `WEAPON_BAT`, `WEAPON_BOTTLE` },
  Tier2 = { `WEAPON_SNSPISTOL`, `WEAPON_PISTOL`, `WEAPON_PISTOL_MK2` },
  Tier3 = { `WEAPON_MICROSMG`, `WEAPON_SMG`, `WEAPON_MACHINEPISTOL` },
  Heavy = { `WEAPON_ASSAULTRIFLE`, `WEAPON_CARBINERIFLE`, `WEAPON_COMPACTRIFLE` },
}

-- ==== Tiers ====
Config.Tiers = {
  [1] = {
    name = 'Tier 1',
    vipWeaponPool = Config.Weapons.Tier1,
    guardCount = { min = 0, max = 0 },
    policeCallOnVipDeath = 0.33,      -- 33%
    policeCallOnStart    = 0.0,
    reward = { min = 1000,  max = 2000 },
  },
  [2] = {
    name = 'Tier 2',
    vipWeaponPool = Config.Weapons.Tier2,
    guardCount = { min = 0, max = 0 },
    policeCallOnVipDeath = 0.50,      -- 50%
    policeCallOnStart    = 0.0,
    reward = { min = 2000,  max = 4000 },
  },
  [3] = {
    name = 'Tier 3',
    vipWeaponPool = Config.Weapons.Tier3,
    guardCount = { min = 0, max = 0 },
    policeCallOnVipDeath = 1.00,      -- 100%
    policeCallOnStart    = 0.0,
    reward = { min = 5000,  max = 7000 },
  },
  [4] = {
    name = 'Tier 4',
    vipWeaponPool = Config.Weapons.Heavy,
    guardCount = { min = 3, max = 5 },
    policeCallOnVipDeath = 0.0,
    policeCallOnStart    = 0.50,      -- 50% ao começar
    reward = { min = 10000, max = 15000 },
  },
  [5] = {
    name = 'Tier 5',
    vipWeaponPool = Config.Weapons.Heavy,
    guardCount = { min = 5, max = 10 },
    policeCallOnVipDeath = 0.0,
    policeCallOnStart    = 0.50,
    reward = { min = 15000, max = 20000 },
  },
}

-- ==== Jobs de polícia (NPCs ignoram estes players) ====
Config.PoliceJobs = { 'police' }   -- adiciona aqui 'lspd', 'gndr', etc. se usares

-- ==== Distâncias e AI ====
Config.SpawnDistance = 150.0       -- distância do ponto para spawnar encontro
Config.EngageDistance = 60.0       -- distância a que os guards/vip entram em combate
Config.PedAccuracy = { vip = 25, guard = 20 }
Config.RelationshipGroup = 'ASSJOB'

-- ==== Spots possíveis para encontros ====
Config.EncounterSpots = {
  vec3(-1017.9, -2694.4, 13.97),
  vec3( 455.3,  -1023.7, 28.20),
  vec3(1249.2,   -332.8, 69.10),
  vec3(-1544.8,  -406.5, 41.99),
  vec3( -303.8, -2252.9,  7.30),
  vec3( -705.9,  -915.2, 19.22),
  vec3(  120.7, -1950.3, 20.74),
}

-- ==== Dispatch (hook genérico; integra com ps-dispatch/cd_dispatch no server) ====
Config.Dispatch = {
  Enabled  = true,
  EventName = 'qb_assassination:policeAlert',
  MinCops  = 0,
}

-- ==== UI / limites ====
Config.NotifyTitle = 'Contratante'
Config.MaxActiveSquadsPerTier = 8