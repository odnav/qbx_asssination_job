fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'qb_assassination_job'
author 'odnavpt + ChatGPT'
description 'Assassination contract job com tiers, convites por focus e pagamento via dumpster.'
version '1.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server.lua'
}

dependencies {
  'qbx_core',
  'ox_lib',
  'ox_target'
  -- opcional: 'qbx_phone' ou 'qb-phone'
}
