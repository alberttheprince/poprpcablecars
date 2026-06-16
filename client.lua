local Models  = Config.Models
local T        = Config.Timings
local CLOSED   = 0.95
local OPENADD  = 0.9
local CYCLE    = (2 * T.idle) + (2 * T.travel)
local Seats    = (Config.Seats and #Config.Seats > 0) and Config.Seats or { Config.SeatOffset }

local addTramTarget, createEntities, deleteEntities
local startLoops, boardTram, exitTram, updateSubscription, canExitNow

local timeOffset = 0
local function Now() return GetGameTimer() + timeOffset end

local bestRtt = math.huge
RegisterNetEvent('tramway:syncRes', function(t0, serverNow)
    local t1  = GetGameTimer()
    local rtt = t1 - t0
    if rtt <= bestRtt then
        bestRtt    = rtt
        timeOffset = (serverNow + rtt * 0.5) - t1
    end
end)

CreateThread(function()
    local function ask() TriggerServerEvent('tramway:syncReq', GetGameTimer()) end
    for _ = 1, 8 do ask(); Wait(250) end
    while true do
        Wait(30000)
        bestRtt = bestRtt + 100
        ask()
    end
end)

local Tracks = {}
do
    for index, nodes in pairs(Config.Tracks) do
        local segs, cum = {}, 0.0
        for i = 1, #nodes - 1 do
            local a, b = nodes[i], nodes[i + 1]
            local len  = #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
            segs[i] = { a = a, b = b, len = len, cum = cum }
            cum = cum + len
        end
        Tracks[index] = { nodes = nodes, segments = segs, length = cum }
    end
end

local function clamp01(v) if v < 0.0 then return 0.0 elseif v > 1.0 then return 1.0 end return v end
local function smoothstep(t) t = clamp01(t) return t * t * (3.0 - 2.0 * t) end

local function posAtArc(track, s)
    local nodes = track.nodes
    if s <= 0.0 then return vector3(nodes[1].x, nodes[1].y, nodes[1].z) end
    if s >= track.length then local n = nodes[#nodes] return vector3(n.x, n.y, n.z) end
    for i = 1, #track.segments do
        local seg = track.segments[i]
        if s <= seg.cum + seg.len then
            local lt = (s - seg.cum) / seg.len
            local a, b = seg.a, seg.b
            local px = a.x + (b.x - a.x) * lt
            local py = a.y + (b.y - a.y) * lt
            local pz = a.z + (b.z - a.z) * lt
            if seg.len > Config.SagMinLength then
                pz = pz + (math.abs(lt - 0.5) * 2.0 - 1.0) * Config.SagAmount
            end
            return vector3(px, py, pz)
        end
    end
    local n = nodes[#nodes] return vector3(n.x, n.y, n.z)
end

local function doorOpenAt(tIn, tOut)
    return math.min(clamp01(tIn / T.doorTransition), clamp01(tOut / T.doorTransition))
end

local function getCarState(trackIndex, now)
    local track = Tracks[trackIndex]
    local phase = now % CYCLE
    if phase < T.idle then
        return posAtArc(track, 0.0), 'idle_a', doorOpenAt(phase, T.idle - phase), false
    elseif phase < T.idle + T.travel then
        local p = smoothstep((phase - T.idle) / T.travel)
        return posAtArc(track, p * track.length), 'up', 0.0, true
    elseif phase < (2 * T.idle) + T.travel then
        local tIn = phase - (T.idle + T.travel)
        return posAtArc(track, track.length), 'idle_b', doorOpenAt(tIn, T.idle - tIn), false
    else
        local p = smoothstep((phase - ((2 * T.idle) + T.travel)) / T.travel)
        return posAtArc(track, (1.0 - p) * track.length), 'down', 0.0, true
    end
end

local active      = false
local zoneCount   = 0
local riding      = false
local boarding    = false
local seatedCar   = nil
local seatedSpot  = nil
local cars        = {}
local gen         = 0
local ridersByCar = {}

local function seatOffsetForSpot(spot)
    local s = Seats[spot] or Seats[1]
    return s.x, s.y, s.z
end

local function takenSpots(idx)
    local taken, count = {}, 0
    local myId = PlayerId()
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= myId then
            local st = Player(GetPlayerServerId(pid)).state
            if st.tramCar == idx then
                count = count + 1
                if st.tramSeat then taken[st.tramSeat] = true end
            end
        end
    end
    return taken, count
end

local function carIsFull(idx)
    local _, count = takenSpots(idx)
    return count >= #Seats
end

local function pickFreeSpot(idx)
    local taken = takenSpots(idx)
    for i = 1, #Seats do
        if not taken[i] then return i end
    end
    return nil
end

local function getAnchor(idx)
    local netId = GlobalState['tramAnchor:' .. idx]
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    if e ~= 0 and DoesEntityExist(e) then return e end
    return nil
end

local function requestAudio()
    RequestScriptAudioBank('CABLE_CAR', false, -1)
    RequestScriptAudioBank('CABLE_CAR_SOUNDS', false, -1)
end
local function releaseAudio()
    ReleaseNamedScriptAudioBank('CABLE_CAR')
    ReleaseNamedScriptAudioBank('CABLE_CAR_SOUNDS')
end
local function stopRunningSound(c)
    if c.runningSound then
        StopSound(c.runningSound); ReleaseSoundId(c.runningSound); c.runningSound = nil
    end
end
local function updateCarSound(c, region, traveling)
    if not (c.entity and DoesEntityExist(c.entity)) then return end
    if traveling then
        if not c.runningSound then
            c.runningSound = GetSoundId()
            PlaySoundFromEntity(c.runningSound, 'Running', c.entity, 'CABLE_CAR_SOUNDS', false, 0)
        end
    else
        stopRunningSound(c)
    end
    if c.lastRegion ~= region then
        if region == 'up' or region == 'down' then
            PlaySoundFromEntity(-1, 'Leave_Station', c.entity, 'CABLE_CAR_SOUNDS', false, 0)
            PlaySoundFromEntity(-1, 'DOOR_CLOSE',     c.entity, 'CABLE_CAR_SOUNDS', false, 0)
        else
            PlaySoundFromEntity(-1, 'Arrive_Station', c.entity, 'CABLE_CAR_SOUNDS', false, 0)
            PlaySoundFromEntity(-1, 'DOOR_OPEN',       c.entity, 'CABLE_CAR_SOUNDS', false, 0)
        end
        c.lastRegion = region
    end
end

local function setDoorPos(c, doorPos)
    local e, d = c.entity, c.doors
    if not (e and DoesEntityExist(e)) then return end
    for _, dr in pairs(d) do
        if dr and dr ~= 0 and DoesEntityExist(dr) then DetachEntity(dr, false, false) end
    end
    if d.LL ~= 0 then AttachEntityToEntity(d.LL, e, 0, 0.0, -doorPos, 0.0, 0.0, 0.0,   0.0, false, false, true, false, 2, true) end
    if d.LR ~= 0 then AttachEntityToEntity(d.LR, e, 0, 0.0,  doorPos, 0.0, 0.0, 0.0,   0.0, false, false, true, false, 2, true) end
    if d.RL ~= 0 then AttachEntityToEntity(d.RL, e, 0, 0.0,  doorPos, 0.0, 0.0, 0.0, 180.0, false, false, true, false, 2, true) end
    if d.RR ~= 0 then AttachEntityToEntity(d.RR, e, 0, 0.0, -doorPos, 0.0, 0.0, 0.0, 180.0, false, false, true, false, 2, true) end
end

addTramTarget = function(c)
    c.targetId = ('tramway:%s'):format(c.trackIndex)
    Interaction.Add(c.entity, {
        id       = c.targetId,
        distance = 3.0,
        offset   = Config.InteractOffset,
        options  = {
            {
                name        = 'tramway_board',
                icon        = 'fa-solid fa-cable-car',
                label       = 'Board the tramway',
                canInteract = function()
                    if riding or boarding then return false end
                    if carIsFull(c.trackIndex) then return false end
                    return (c.doorOpen or 0.0) > 0.5
                end,
                onSelect    = function() boardTram(c) end,
            },
            {
                name        = 'tramway_exit',
                icon        = 'fa-solid fa-door-open',
                label       = 'Exit the tramway',
                canInteract = function()
                    if not riding or seatedCar ~= c.trackIndex then return false end
                    return canExitNow(c)
                end,
                onSelect    = function() exitTram(c, false) end,
            },
        },
    })
end

createEntities = function()
    for _, h in ipairs({ Models.car, Models.doorL, Models.doorR }) do RequestModel(h) end
    local started = GetGameTimer()
    while not (HasModelLoaded(Models.car) and HasModelLoaded(Models.doorL) and HasModelLoaded(Models.doorR)) do
        Wait(0)
        if GetGameTimer() - started > 10000 then break end
    end

    local now = Now()

    local function mkObject(model, pos)
        local e = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
        while not DoesEntityExist(e) do Wait(0) end
        SetEntityAsMissionEntity(e, true, true)
        return e
    end

    for index, carCfg in pairs(Config.Cars) do
        local pos, region = getCarState(index, now)
        local e = mkObject(Models.car, pos)
        FreezeEntityPosition(e, true)
        SetEntityRotation(e, 0.0, 0.0, carCfg.heading, 2, true)

        local doors = {
            LL = mkObject(Models.doorL, pos), LR = mkObject(Models.doorR, pos),
            RL = mkObject(Models.doorL, pos), RR = mkObject(Models.doorR, pos),
        }

        local c = {
            entity = e, trackIndex = index, doors = doors,
            region = region, lastRegion = region,
            doorApplied = nil, doorOpen = 0.0, runningSound = nil,
            anchorHandle = nil, nextCtrlReq = 0,
        }
        cars[index] = c
        addTramTarget(c)
    end

    SetModelAsNoLongerNeeded(Models.car)
    SetModelAsNoLongerNeeded(Models.doorL)
    SetModelAsNoLongerNeeded(Models.doorR)
end

deleteEntities = function()
    for _, c in pairs(cars) do
        if c.targetId then Interaction.Remove(c.entity, c.targetId) end
        stopRunningSound(c)
        for _, d in pairs(c.doors) do
            if d and d ~= 0 and DoesEntityExist(d) then DeleteEntity(d) end
        end
        if c.entity and DoesEntityExist(c.entity) then DeleteEntity(c.entity) end
    end
    cars = {}
end

startLoops = function()
    gen = gen + 1
    local myGen = gen

    CreateThread(function()
        while active and myGen == gen do
            local now = Now()
            for idx in pairs(Config.Cars) do
                local detPos, region, doorOpen, traveling = getCarState(idx, now)
                local c = cars[idx]
                if c and c.entity and DoesEntityExist(c.entity) then
                    c.region = region; c.doorOpen = doorOpen
                    local o = Config.Cars[idx].offset
                    local tx, ty, tz = detPos.x + o.x, detPos.y + o.y, detPos.z + o.z

                    local anchor = getAnchor(idx)
                    if anchor ~= c.anchorHandle then
                        c.anchorHandle = anchor
                        if anchor then
                            SetEntityVisible(anchor, false, false)
                            SetEntityCollision(anchor, false, false)
                        end
                    end

                    if anchor then
                        if riding and seatedCar == idx then
                            if NetworkHasControlOfEntity(anchor) then
                                FreezeEntityPosition(anchor, true)
                                SetEntityCoordsNoOffset(anchor, tx, ty, tz, false, false, false)
                                SetEntityHeading(anchor, Config.Cars[idx].heading)
                            elseif now >= c.nextCtrlReq then
                                NetworkRequestControlOfEntity(anchor)
                                c.nextCtrlReq = now + 1000
                            end
                        elseif NetworkHasControlOfEntity(anchor) then
                            FreezeEntityPosition(anchor, true)
                        end
                    end

                    if ridersByCar[idx] and anchor then
                        local ap = GetEntityCoords(anchor)
                        SetEntityCoords(c.entity, ap.x, ap.y, ap.z, false, false, false, false)
                    else
                        SetEntityCoords(c.entity, tx, ty, tz, false, false, false, false)
                    end

                    if not c.doorApplied or math.abs(doorOpen - c.doorApplied) > 0.01 then
                        setDoorPos(c, CLOSED + OPENADD * doorOpen)
                        c.doorApplied = doorOpen
                    end
                    if Config.Sounds then updateCarSound(c, region, traveling) end

                    if idx == seatedCar and riding then
                        local ped = PlayerPedId()
                        if IsEntityDead(ped) then
                            exitTram(c, true)
                        elseif anchor and not IsEntityAttachedToEntity(ped, anchor) then
                            local x, y, z = seatOffsetForSpot(seatedSpot)
                            AttachEntityToEntity(ped, anchor, -1, x, y, z, 0.0, 0.0, 0.0,
                                false, false, false, true, 2, true)
                        end
                    end
                end
            end
            Wait(0)
        end
    end)

    CreateThread(function()
        while active and myGen == gen do
            local riders = {}
            if riding and seatedCar ~= nil then riders[seatedCar] = true end
            local myId = PlayerId()
            for _, pid in ipairs(GetActivePlayers()) do
                if pid ~= myId then
                    local idx = Player(GetPlayerServerId(pid)).state.tramCar
                    if idx ~= nil then riders[idx] = true end
                end
            end
            ridersByCar = riders
            Wait(250)
        end
    end)
end

updateSubscription = function()
    local should = (zoneCount > 0) or riding
    if should and not active then
        active = true
        if Config.Sounds then requestAudio() end
        createEntities()
        startLoops()
    elseif not should and active then
        active = false
        gen = gen + 1
        deleteEntities()
        if Config.Sounds then releaseAudio() end
    end
end

boardTram = function(c)
    if riding or boarding or not (c and c.entity and DoesEntityExist(c.entity)) then return end
    boarding = true
    CreateThread(function()
        local idx = c.trackIndex
        local ped = PlayerPedId()

        local cabinPos = GetEntityCoords(c.entity)
        TriggerServerEvent('tramway:prepareAnchor', idx, cabinPos)

        local ok, anchor = pcall(function()
            return lib.waitFor(function()
                local a = getAnchor(idx)
                if a then return a end
            end, 'tram anchor never streamed in', 5000)
        end)

        if not ok or not anchor then
            boarding = false
            lib.notify({ description = 'The tram isn\'t ready, try again.', type = 'error' })
            return
        end

        local t0 = GetGameTimer()
        while not NetworkHasControlOfEntity(anchor) and GetGameTimer() - t0 < 2000 do
            NetworkRequestControlOfEntity(anchor)
            Wait(50)
        end
        if NetworkHasControlOfEntity(anchor) then
            FreezeEntityPosition(anchor, true)
            SetEntityCoordsNoOffset(anchor, cabinPos.x, cabinPos.y, cabinPos.z, false, false, false)
            SetEntityHeading(anchor, Config.Cars[idx].heading)
        end
        SetEntityVisible(anchor, false, false)
        SetEntityCollision(anchor, false, false)

        seatedSpot = pickFreeSpot(idx)
        if not seatedSpot then
            boarding = false
            lib.notify({ description = 'The tram car is full.', type = 'error' })
            return
        end

        riding = true; seatedCar = idx; boarding = false
        ridersByCar[idx] = true
        LocalPlayer.state:set('tramSeat', seatedSpot, true)

        local x, y, z = seatOffsetForSpot(seatedSpot)
        AttachEntityToEntity(ped, anchor, -1, x, y, z, 0.0, 0.0, 0.0,
            false, false, false, true, 2, true)

        LocalPlayer.state:set('tramCar', idx, true)
        TriggerServerEvent('tramway:riding', true)
        updateSubscription()
    end)
end

canExitNow = function(c)
    if not c then return false end
    return (c.region == 'idle_a' or c.region == 'idle_b') and (c.doorOpen or 0.0) > 0.5
end

exitTram = function(c, force)
    if not riding then return end
    if not force and not canExitNow(c) then
        lib.notify({ description = 'You can only get off at a station.', type = 'inform' })
        return
    end
    local ped = PlayerPedId()
    riding = false; seatedCar = nil; seatedSpot = nil
    DetachEntity(ped, true, true)
    LocalPlayer.state:set('tramCar', nil, true)
    LocalPlayer.state:set('tramSeat', nil, true)
    TriggerServerEvent('tramway:riding', false)
    if c and c.entity and DoesEntityExist(c.entity) then
        local p = GetOffsetFromEntityInWorldCoords(c.entity, 3.5, 0.0, -5.0)
        SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, true)
    end
    updateSubscription()
end

lib.addKeybind({
    name = 'tramway_exit', description = 'Exit the tramway', defaultKey = Config.ExitKey,
    onPressed = function()
        if not riding then return end
        exitTram(seatedCar and cars[seatedCar] or nil, false)
    end,
})

-- /tramseattest (debug only): walk your ped through every Config.Seats spot
if Config.Debug then
    local testing = false
    RegisterCommand('tramseattest', function()
        if testing then return end
        if riding or boarding then
            lib.notify({ description = 'Finish your current ride first.', type = 'error' })
            return
        end
        if not active or next(cars) == nil then
            lib.notify({ description = 'Get near the tramway first (so the cabins spawn).', type = 'error' })
            return
        end

        local ped  = PlayerPedId()
        local here = GetEntityCoords(ped)
        local target, best = nil, math.huge
        for _, c in pairs(cars) do
            if c.entity and DoesEntityExist(c.entity) then
                local d = #(here - GetEntityCoords(c.entity))
                if d < best then best = d; target = c end
            end
        end
        if not target then
            lib.notify({ description = 'No cabin found nearby.', type = 'error' })
            return
        end

        testing = true
        CreateThread(function()
            for i = 1, #Seats do
                local x, y, z = seatOffsetForSpot(i)
                AttachEntityToEntity(ped, target.entity, -1, x, y, z, 0.0, 0.0, 0.0,
                    false, false, false, true, 2, true)
                lib.notify({
                    description = ('Seat %d/%d  (%.2f, %.2f, %.2f)'):format(i, #Seats, x, y, z),
                    type = 'inform',
                })
                Wait(2500)
                if not testing then break end
            end
            DetachEntity(ped, true, true)
            if target.entity and DoesEntityExist(target.entity) then
                local p = GetOffsetFromEntityInWorldCoords(target.entity, 3.5, 0.0, -5.0)
                SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, true)
            end
            testing = false
            lib.notify({ description = 'Seat test finished.', type = 'success' })
        end)
    end, false)
end

local checkedDangle = false
local function checkDangle()
    if checkedDangle then return end
    checkedDangle = true
    TriggerServerEvent('tramway:checkDangle')
end
RegisterNetEvent('QBX:Client:OnPlayerLoaded',    checkDangle)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', checkDangle)

local function resetRiding()
    if riding then DetachEntity(PlayerPedId(), true, true) end
    riding = false; seatedCar = nil; seatedSpot = nil
    LocalPlayer.state:set('tramCar', nil, true)
    LocalPlayer.state:set('tramSeat', nil, true)
end
RegisterNetEvent('QBX:Client:OnPlayerUnload',    resetRiding)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', resetRiding)

RegisterNetEvent('tramway:goToStation', function()
    CreateThread(function()
        local ped = PlayerPedId()

        local returns = Config.LogoutReturns or {}
        local here = GetEntityCoords(ped)
        local r, best = returns[1], math.huge
        for _, p in ipairs(returns) do
            local d = #(here - p)
            if d < best then best = d; r = p end
        end
        if not r then return end

        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < 1000 do
            SetEntityCoords(ped, r.x, r.y, r.z, false, false, false, false)
            Wait(100)
        end
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
    end)
end)

CreateThread(function()
    lib.zones.poly({
        points    = Config.Zone.points,
        thickness = Config.Zone.thickness,
        debug     = Config.Debug,
        onEnter   = function() zoneCount = zoneCount + 1; updateSubscription() end,
        onExit    = function()
            zoneCount = zoneCount - 1
            if zoneCount < 0 then zoneCount = 0 end
            updateSubscription()
        end,
    })
end)

CreateThread(function()
    if not (Config.Blip and Config.Blip.enabled) then return end
    for _, c in ipairs(Config.Blip.coords) do
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, Config.Blip.sprite)
        SetBlipScale(blip, Config.Blip.scale + 0.0)
        SetBlipColour(blip, Config.Blip.color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.Blip.label)
        EndTextCommandSetBlipName(blip)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if riding then DetachEntity(PlayerPedId(), true, true) end
    LocalPlayer.state:set('tramCar', nil, true)
    LocalPlayer.state:set('tramSeat', nil, true)
    deleteEntities()
    lib.hideTextUI()
end)
