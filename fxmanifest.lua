fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Popcorn Roleplay & glitchdetector'
description 'Synced Aerial Tramway for FiveM'
version '1.0.0'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_scripts {
    'interaction.lua',
    'client.lua',
}

server_script 'server.lua'