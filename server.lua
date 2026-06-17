---@type table<number, boolean>
local riding = {}        -- [src] = true while that player is on a tram

-- Shared clock: echo the client's send-time back with our timer for NTP sync
RegisterNetEvent('tramway:syncReq', function(t0)
    TriggerClientEvent('tramway:syncRes', source, t0, GetGameTimer())
end)

RegisterNetEvent('tramway:riding', function(state)
    if state then riding[source] = true else riding[source] = nil end
end)

local function onPlayerLeft(src)
    src = src or source
    if riding[src] then
        local citizenid = Player(src).state.citizenid
        if citizenid then
            SetResourceKvpInt('tramway_dangle_' .. citizenid, 1)
        end
        riding[src] = nil
    end
end

AddEventHandler('playerDropped', function() onPlayerLeft(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', onPlayerLeft)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local source = source
    local citizenid = Player(source).state.citizenid
    local key = 'tramway_dangle_' .. citizenid
    if GetResourceKvpInt(key) == 1 then
        DeleteResourceKvp(key)
        TriggerClientEvent('tramway:goToStation', source)
    end
end)
