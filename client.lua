local CLAMP_CONFIG = {
    baspel_wheelclamp_suv = {
        wheel_lf = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(0.07, 0.20, 0.10),  rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(0.07, -0.10, -0.20), rot = vector3(-80.0, 0.0, 0.0) }
    },
    baspel_wheelclamp_normal = {
        wheel_lf = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(-0.03, 0.20, 0.15),  rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(-0.06, 0.20, 0.17), rot = vector3(80.0, 0.0, 0.0) }
    },
    baspel_wheelclamp_motorcycle = {
        wheel_lf = { pos = vector3(0.05, 0.0, -0.15), rot = vector3(-25.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.05, 0.0, -0.15), rot = vector3(-25.0, 0.0, 0.0) }
    }
}

local APPROACH_OFFSETS = {
    wheel_lf = vector3(-0.7, 0.1, 0.6),
    wheel_rf = vector3(0.8, 0.1, 0.6),
    wheel_lr = vector3(-0.7, 0.1, 0.6),
    wheel_rr = vector3(0.8, 0.1, 0.6)
}

local CLAMP_CONES = {} -- keyed by netID..bone
local APPLY_DURATION = 4000
local TIRE_BONES = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }
local DEFAULT_OFFSET = vector3(-0.7, 0.1, 0.6)

local function GetStateBagName(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return "entity:" .. netId
end

local function getServerNetId(vehicle)
    local bagName = GetStateBagName(vehicle)
    if bagName then
        local netIdStr = bagName:match("entity:(%d+)")
        if netIdStr then
            return tonumber(netIdStr)
        end
    end
    return NetworkGetNetworkIdFromEntity(vehicle)
end

local function isVehicleClamped(vehicle)
    local netId = getServerNetId(vehicle)
    local netStr = tostring(netId)
    for _, bone in ipairs(TIRE_BONES) do
        local key = netStr .. bone
        if CLAMP_CONES[key] then
            return true
        end
    end
    return false
end

local function getClosestTireBoneByPlayer(vehicle)
    local pedPos = GetEntityCoords(PlayerPedId())
    local closest, dist = nil, math.huge
    for _, bone in ipairs(TIRE_BONES) do
        local idx = GetEntityBoneIndexByName(vehicle, bone)
        if idx and idx ~= -1 then
            local pos = GetWorldPositionOfEntityBone(vehicle, idx)
            local d = #(pedPos - pos)
            if d < dist then
                dist, closest = d, bone
            end
        end
    end
    return closest
end

local function getClosestClampedTire(vehicle)
    local pedPos = GetEntityCoords(PlayerPedId())
    local netId = getServerNetId(vehicle)
    local keyPrefix = tostring(netId)
    local closest, dist = nil, math.huge
    for _, bone in ipairs(TIRE_BONES) do
        local key = keyPrefix .. bone
        if CLAMP_CONES[key] then
            local idx = GetEntityBoneIndexByName(vehicle, bone)
            if idx and idx ~= -1 then
                local pos = GetWorldPositionOfEntityBone(vehicle, bone)
                local d = #(pedPos - pos)
                if d < dist then
                    dist, closest = d, bone
                end
            end
        end
    end
    return closest
end

local function getApproachPosForTire(vehicle, bone)
    local idx = GetEntityBoneIndexByName(vehicle, bone)
    if not idx or idx == -1 then return nil end
    local tirePos = GetWorldPositionOfEntityBone(vehicle, idx)
    local offset = APPROACH_OFFSETS[bone] or DEFAULT_OFFSET
    local mag = #(offset)
    local norm = (mag > 0) and (offset / mag) or vector3(0, 0, 0)
    local function rotate(off)
        local rot = GetEntityRotation(vehicle, 2) or vector3(0, 0, 0)
        local rad = math.rad(rot.z or 0)
        local rx = off.x * math.cos(rad) - off.y * math.sin(rad)
        local ry = off.x * math.sin(rad) + off.y * math.cos(rad)
        return vector3(rx, ry, off.z)
    end
    return tirePos + rotate(norm), tirePos
end

local function waitUntilClose(target, maxTime, cb)
    local startTime = GetGameTimer()
    while GetGameTimer() - startTime < maxTime do
        if #(GetEntityCoords(PlayerPedId()) - target) < 0.5 then
            return cb(true)
        end
        Wait(100)
    end
    cb(false)
end

local function smoothTurnToCoord(ped, x, y, z, duration)
    TaskTurnPedToFaceCoord(ped, x, y, z, duration)
    Wait(duration)
end

local function walkToOffsetAndAnimate(vehicle, duration, cb, bone, label)
    if not bone then
        TriggerEvent("chat:addMessage", { args = { "Error", "No tire specified." } })
        return cb(false)
    end
    local target, tirePos = getApproachPosForTire(vehicle, bone)
    if not (target and tirePos) then
        TriggerEvent("chat:addMessage", { args = { "Error", "Failed to compute approach offset." } })
        return cb(false)
    end
    TaskFollowNavMeshToCoord(PlayerPedId(), target.x, target.y, target.z, 0.4, 10000, 1.0, false, 0)
    waitUntilClose(target, 15000, function(arrived)
        if not arrived then
            TriggerEvent("chat:addMessage", { args = { "Error", "Timed out or path blocked." } })
            return cb(false)
        end
        smoothTurnToCoord(PlayerPedId(), tirePos.x, tirePos.y, tirePos.z, 1000)
        Wait(500)
        Citizen.CreateThread(function()
            exports.ox_lib:progressBar({
                duration = duration,
                label = label,
                useWhileDead = false,
                canCancel = false,
                disable = { car = true, move = true, combat = true }
            }, function() end)
        end)
        ExecuteCommand("e mechanic4")
        Wait(duration)
        ExecuteCommand("e c")
        cb(true)
    end)
end

local function attachClamp(vehicle, bone)
    if not bone or not DoesEntityExist(vehicle) then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. bone
    local idx = GetEntityBoneIndexByName(vehicle, bone)
    if not idx or idx == -1 then 
        print(string.format("[CLIENT] attachClamp: Invalid bone '%s' for vehicle %d", bone, netId))
        return 
    end
    if CLAMP_CONES[key] then
        TriggerEvent("chat:addMessage", { args = { "Error", "This tire is already clamped." } })
        return
    end
    local vehClass = tonumber(GetVehicleClass(vehicle))
    local modelName = (vehClass == 8 and "baspel_wheelclamp_motorcycle") or
                      ((vehClass == 2 or vehClass == 9) and "baspel_wheelclamp_suv") or
                      "baspel_wheelclamp_normal"
    local modelHash = GetHashKey(modelName)
    if not IsModelInCdimage(modelHash) then
        TriggerEvent("chat:addMessage", { args = { "Error", "Clamp model does not exist." } })
        return
    end
    RequestModel(modelHash)
    local start = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - start > 5000 then
            TriggerEvent("chat:addMessage", { args = { "Error", "Clamp model failed to load." } })
            return
        end
    end
    local pos = GetWorldPositionOfEntityBone(vehicle, idx)
    local cone = CreateObject(modelHash, pos.x, pos.y, pos.z, true, true, false)
    if not cone or cone == 0 then
        TriggerEvent("chat:addMessage", { args = { "Error", "Failed to create clamp prop." } })
        return
    end
    local config = CLAMP_CONFIG[modelName] or {}
    local offsets = config[bone] or { pos = vector3(0, 0, 0), rot = vector3(0, 0, 0) }
    AttachEntityToEntity(cone, vehicle, idx,
        offsets.pos.x, offsets.pos.y, offsets.pos.z,
        offsets.rot.x, offsets.rot.y, offsets.rot.z,
        false, false, false, false, 1, true)
    FreezeEntityPosition(cone, true)
    SetEntityCollision(cone, false, false)
    CLAMP_CONES[key] = cone
    Wait(100)
    -- Mark the vehicle as undriveable when clamped.
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)
    print(string.format("[CLIENT] Attached clamp to Vehicle %d, bone %s", netId, bone))
end

local function detachClamp(vehicle, bone)
    if not bone then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. bone
    if CLAMP_CONES[key] then
        DeleteObject(CLAMP_CONES[key])
        CLAMP_CONES[key] = nil
    end
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineOn(vehicle, true, true, true)
    print(string.format("[CLIENT] Detached clamp from Vehicle %d, bone %s", netId, bone))
end

-- Register the ox_target event with a dynamic label.
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = "toggle_parking_boot",
            icon = "fas fa-wrench",
            label = function(entity)
                local clamped = isVehicleClamped(entity)
                print("[OX_TARGET] isVehicleClamped:", clamped)
                if clamped then
                    return "Remove Parking Boot"
                else
                    return "Apply Parking Boot"
                end
            end,
            distance = 3.0,
            event = "wheelclamp:client:ToggleParkingBoot"
        }
    })
end)

RegisterNetEvent("wheelclamp:client:ToggleParkingBoot")
AddEventHandler("wheelclamp:client:ToggleParkingBoot", function(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        TriggerEvent("chat:addMessage", { args = { "Error", "No vehicle nearby!" } })
        return
    end
    local netId = getServerNetId(vehicle)
    if isVehicleClamped(vehicle) then
        local clampedBone = getClosestClampedTire(vehicle)
        if not clampedBone then
            TriggerEvent("chat:addMessage", { args = { "Error", "No clamped tire found." } })
            return
        end
        walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
            if success then
                TriggerServerEvent("wheelclamp:server:clamp_removed", netId, clampedBone)
            end
        end, clampedBone, "Removing Parking Boot")
    else
        local bone = getClosestTireBoneByPlayer(vehicle)
        if not bone then
            TriggerEvent("chat:addMessage", { args = { "Error", "Could not determine target tire." } })
            return
        end
        walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
            if success then
                -- Call the server event to update state (clamp true, bone, undriveable true)
                TriggerServerEvent("wheelclamp:server:clamp_applied", netId, bone)
            end
        end, bone, "Applying Parking Boot")
    end
end)

-- Listen for state bag changes and restore state if needed.
AddStateBagChangeHandler("efWheelClamp", nil, function(bagName, key, value, reserved, replicated)
    local netIdStr = bagName:match("entity:(%d+)")
    if not netIdStr then return end
    local vehicleNetId = tonumber(netIdStr)
    local valueStr = tostring(value)
    print(string.format("[CLIENT] StateBagChange: Vehicle %d, new state: %s", vehicleNetId, valueStr))
    if valueStr == "" or valueStr == "123" then
        print(string.format("[CLIENT] Invalid state for Vehicle %d, requesting restore.", vehicleNetId))
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    local success, data = pcall(json.decode, valueStr)
    if not (success and type(data) == "table") then
        print(string.format("[CLIENT] Failed to parse state for Vehicle %d, requesting restore.", vehicleNetId))
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    print(string.format("[CLIENT] Parsed state for Vehicle %d: clamp=%s, bone=%s, undriveable=%s", vehicleNetId, tostring(data.clamp), data.bone or "", tostring(data.undriveable)))
    TriggerEvent("wheelclamp:client:ForceApplyClamp", vehicleNetId, data.clamp, data.bone)
end)

RegisterNetEvent("wheelclamp:client:ForceApplyClamp")
AddEventHandler("wheelclamp:client:ForceApplyClamp", function(vehicleNetId, clampApplied, bone)
    print(string.format("[CLIENT] ForceApplyClamp: Vehicle %d, bone %s, clampApplied=%s", vehicleNetId, bone, tostring(clampApplied)))
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then
        print(string.format("[CLIENT] ForceApplyClamp: Vehicle %d does not exist locally.", vehicleNetId))
        return
    end
    if clampApplied then
        attachClamp(vehicle, bone)
    else
        detachClamp(vehicle, bone)
    end
end)

AddEventHandler("entityStreamIn", function(entity)
    if GetEntityType(entity) ~= 2 then return end
    Wait(1000) -- Ensure the entity is fully loaded.
    local netId = getServerNetId(entity)
    local bagName = string.format("entity:%d", netId)
    local state = GetStateBagValue(bagName, "efWheelClamp")
    print(string.format("[CLIENT] StreamIn: Vehicle %d, StateBagValue: %s", netId, tostring(state)))
    if not state or tostring(state) == "" or tostring(state) == "123" then
        print(string.format("[CLIENT] StreamIn: No valid state for Vehicle %d, requesting restore.", netId))
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    local success, data = pcall(json.decode, tostring(state))
    if not (success and type(data) == "table") then
        print(string.format("[CLIENT] StreamIn: Failed to parse state for Vehicle %d, requesting restore.", netId))
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    if data.bone then
        print(string.format("[CLIENT] StreamIn: Forcing clamp apply for Vehicle %d, bone %s, clamp=%s", netId, data.bone, tostring(data.clamp)))
        TriggerEvent("wheelclamp:client:ForceApplyClamp", netId, data.clamp, data.bone)
    end
end)

AddEventHandler("onClientEntityRemove", function(entity)
    local netId = getServerNetId(entity)
    for _, bone in ipairs(TIRE_BONES) do
        local key = tostring(netId) .. bone
        if CLAMP_CONES[key] then
            DeleteObject(CLAMP_CONES[key])
            CLAMP_CONES[key] = nil
        end
    end
end)
