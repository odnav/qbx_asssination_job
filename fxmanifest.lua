-- fxmanifest.lua

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qb_assassination_job'
author 'odnavpt + ChatGPT'
description 'Assassination contract (tiers, convites via ox_target, pagamento em dumpster).'
version '1.1.0'

-- OX Lib tem de carregar antes de config/client/server
shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua', -- opcional; remove se não precisares
  'server.lua'
}

-- Dependências diretas usadas no client
dependencies {
  'ox_lib',
  'ox_target'
}
