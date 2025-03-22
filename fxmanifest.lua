fx_version 'cerulean'
game 'gta5'

author 'Fluxmaster (Script) | Baspel (Props)'
description 'Everfall Parking Boot - Script by Fluxmaster'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua'
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client.lua'
}

server_scripts {
    'server.lua'
}

data_file 'DLC_ITYP_REQUEST' 'stream/baspel_wheelclamp_pack.ytyp'
