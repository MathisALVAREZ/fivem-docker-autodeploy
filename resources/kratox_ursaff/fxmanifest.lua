shared_script '@WaveShield/resource/include.lua'

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Evogen RP — Fiscalité'
description 'Déclaration fiscale hebdomadaire (ESX Legacy) — NUI Evogen, dettes, rappels, webhooks.'

shared_scripts {
  'config.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',   -- adapte si tu utilises mysql-async
  'server.lua'
}

client_scripts {
  'client.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/app.js'
}
