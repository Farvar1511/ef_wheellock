fx_version 'cerulean'
game 'gta5'

author 'Fluxmaster (Script) | Baspel (Props)'
description 'Everfall Parking Boot - Script by Fluxmaster, using props by Baspel'
version '1.0.0'

shared_scripts {
  'config.lua'
}

client_scripts {
  '@qbx_core/modules/playerdata.lua',
  'client.lua'
}

server_scripts {
  'server.lua'
}

data_file 'DLC_ITYP_REQUEST' 'stream/baspel_wheelclamp_pack.ytyp'
