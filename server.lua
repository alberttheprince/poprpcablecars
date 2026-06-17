local riding  = {}        -- [src] = true while that player is on a tram
local anchors = {}        -- [idx] = entity handle

local ANCHOR_MODEL = `prop_cs_cardbox_01`   -- small; rendered invisible client-side

-- One networked anchor per car; riders attach their ped to it and drive it
CreateThread(function()
    Wait(1000)
    for idx in pairs(Config.Cars) do
        local n = Config.Tracks[idx][1]
        local obj = CreateObject(ANCHOR_MODEL, n.x, n.y, n.z, true, true, false)
        local t0 = GetGameTimer()
        while not DoesEntityExist(obj) and GetGameTimer() - t0 < 5000 do Wait(50) end
        if DoesEntityExist(obj) then
            FreezeEntityPosition(obj, true)
            anchors[idx] = obj
            GlobalState['cablecarAnchor:' .. idx] = NetworkGetNetworkIdFromEntity(obj)
        else
            print(('^1[cablecar] failed to create anchor for car %s^7'):format(idx))
        end
    end
end)

-- Move a car's anchor to a boarding rider's cabin so it streams in next to them
RegisterNetEvent('cablecar:prepareAnchor', function(idx, pos)
    if type(pos) ~= 'vector3' then return end
    local obj = anchors[idx]
    if obj and DoesEntityExist(obj) then
        SetEntityCoords(obj, pos.x, pos.y, pos.z, false, false, false, false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for idx, obj in pairs(anchors) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        GlobalState['cablecarAnchor:' .. idx] = nil
    end
end)

-- Shared clock: echo the client's send-time back with our timer for NTP sync
RegisterNetEvent('cablecar:syncReq', function(t0)
    TriggerClientEvent('cablecar:syncRes', source, t0, GetGameTimer())
end)

-- Logout-while-riding rescue
local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. src)
end
local function dangleKey(src)
    return 'cablecar_dangle_' .. (licenseOf(src):gsub('[^%w]', '_'))
end

RegisterNetEvent('cablecar:riding', function(state)
    if state then riding[source] = true else riding[source] = nil end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if riding[src] then
        SetResourceKvpInt(dangleKey(src), 1)
        riding[src] = nil
    end
end)

RegisterNetEvent('cablecar:checkDangle', function()
    local src = source
    local key = dangleKey(src)
    if GetResourceKvpInt(key) == 1 then
        DeleteResourceKvp(key)
        TriggerClientEvent('cablecar:goToStation', src)
    end
end)

-- Switching characters (not a disconnect): forget their riding state
local function clearRiding(src) riding[src or source] = nil end
AddEventHandler('QBCore:Server:OnPlayerUnload', clearRiding)
AddEventHandler('qbx_core:server:onPlayerUnloaded', clearRiding)