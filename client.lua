------------------------------------------------------------
-- client.lua – Revised Best Practice Following Effective FiveM Lua Guidelines
------------------------------------------------------------
local QBox = exports['qb-core']:GetCoreObject()
local json = json or require("json")

-- Constants & Configurations
local CLAMP_CONFIG = {
    baspel_wheelclamp_suv = {
        wheel_lf = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(0.07, 0.20, 0.10),  rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(0.07, -0.10, -0.20),rot = vector3(-80.0, 0.0, 0.0) },
    },
    baspel_wheelclamp_normal = {
        wheel_lf = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(-0.03, 0.20, 0.15),  rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(-0.06, 0.20, 0.17),  rot = vector3(80.0, 0.0, 0.0) },
    },
    baspel_wheelclamp_motorcycle = {
        wheel_lf = { pos = vector3(0.05, 0.0, -0.15),  rot = vector3(-25.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.05, 0.0, -0.15),  rot = vector3(-25.0, 0.0, 0.0) },
    },
}

local APPROACH_OFFSETS = {
    wheel_lf = vector3(-0.7, 0.1, 0.6),
    wheel_rf = vector3(0.8, 0.1, 0.6),
    wheel_lr = vector3(-0.7, 0.1, 0.6),
    wheel_rr = vector3(0.8, 0.1, 0.6)
}

local CLAMP_CONES = {}
local CLIENT_CLAMPED_VEHICLES = {}
local APPLY_DURATION = 4000 -- ms for progress bar/animation
local TIRE_BONES = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }
local DEFAULT_OFFSET = vector3(-0.7, 0.1, 0.6)

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------
local DEBUG_ENABLED = true
local function debugPrint(msg, ...)
    if DEBUG_ENABLED then
        print(string.format("[DEBUG] " .. msg, ...))
    end
end

local function getServerNetId(vehicle)
    return NetworkGetNetworkIdFromEntity(vehicle)
end

local function getClosestTireBoneByPlayer(vehicle)
    local ped = PlayerPedId()
    local pedPos = GetEntityCoords(ped)
    local closestBone, minDistance = nil, math.huge
    for _, bone in ipairs(TIRE_BONES) do
        local boneIndex = GetEntityBoneIndexByName(vehicle, bone)
        if boneIndex and boneIndex ~= -1 then
            local bonePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local dist = #(pedPos - bonePos)
            if dist < minDistance then
                minDistance = dist
                closestBone = bone
            end
        end
    end
    return closestBone
end

local function getClosestClampedTire(vehicle)
    local ped = PlayerPedId()
    local pedPos = GetEntityCoords(ped)
    local netIdStr = tostring(getServerNetId(vehicle))
    local closestBone, minDist = nil, math.huge
    for _, bone in ipairs(TIRE_BONES) do
        local key = netIdStr .. bone
        if CLAMP_CONES[key] then
            local boneIndex = GetEntityBoneIndexByName(vehicle, bone)
            if boneIndex and boneIndex ~= -1 then
                local bonePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
                local d = #(pedPos - bonePos)
                if d < minDist then
                    minDist = d
                    closestBone = bone
                end
            end
        end
    end
    return closestBone
end

local function getApproachPosForTire(vehicle, boneName)
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if not boneIndex or boneIndex == -1 then return nil end
    local tirePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    local offset = APPROACH_OFFSETS[boneName] or DEFAULT_OFFSET
    local mag = # (offset)
    local normalizedOffset = (mag > 0) and (offset / mag) or vector3(0, 0, 0)
    local function rotateOffset(off)
       local rot = GetEntityRotation(vehicle, 2) or vector3(0, 0, 0)
       local rad = math.rad(rot.z or 0)
       local rx = off.x * math.cos(rad) - off.y * math.sin(rad)
       local ry = off.x * math.sin(rad) + off.y * math.cos(rad)
       return vector3(rx, ry, off.z)
    end
    local rotatedOffset = rotateOffset(normalizedOffset)
    return tirePos + rotatedOffset, tirePos
end

local function waitUntilClose(targetPos, maxTime, callback)
    local startTime = GetGameTimer()
    while GetGameTimer() - startTime < maxTime do
        if #(GetEntityCoords(PlayerPedId()) - targetPos) < 0.5 then
            return callback(true)
        end
        Wait(100)
    end
    return callback(false)
end

local function smoothTurnToCoord(ped, x, y, z, duration)
    TaskTurnPedToFaceCoord(ped, x, y, z, duration)
    Wait(duration)
end

local function walkToOffsetAndAnimate(vehicle, duration, callback, boneName, actionLabel)
    if not boneName then
        QBox.Functions.Notify("No tire specified.", "error", 5000)
        return callback(false)
    end

    local targetPos, tirePos = getApproachPosForTire(vehicle, boneName)
    if not (targetPos and tirePos) then
        QBox.Functions.Notify("Failed to compute approach offset.", "error", 5000)
        return callback(false)
    end

    local ped = PlayerPedId()
    TaskFollowNavMeshToCoord(ped, targetPos.x, targetPos.y, targetPos.z, 0.4, 10000, 1.0, false, 0)
    waitUntilClose(targetPos, 15000, function(arrived)
        if not arrived then
            QBox.Functions.Notify("Timed out or path blocked.", "error", 5000)
            return callback(false)
        end
        smoothTurnToCoord(ped, tirePos.x, tirePos.y, tirePos.z, 1000)
        Wait(500)
        CreateThread(function()
            exports.ox_lib:progressBar({
                duration = duration,
                label = actionLabel,
                useWhileDead = false,
                canCancel = false,
                disable = { car = true, move = true, combat = true }
            }, function() end)
        end)
        ExecuteCommand("e mechanic4")
        Wait(duration)
        ExecuteCommand("e c")
        callback(true)
    end)
end

local function attachClamp(vehicle, boneName)
    if not boneName or not DoesEntityExist(vehicle) then return end

    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. boneName
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if not boneIndex or boneIndex == -1 then
        debugPrint("Invalid bone index for %s", boneName)
        return
    end
    if CLAMP_CONES[key] then
        QBox.Functions.Notify("This tire is already clamped!", "error", 5000)
        return
    end

    local vehicleClass = tonumber(GetVehicleClass(vehicle))
    local clampModelName = (vehicleClass == 8 and "baspel_wheelclamp_motorcycle") or
                           ((vehicleClass == 2 or vehicleClass == 9) and "baspel_wheelclamp_suv") or
                           "baspel_wheelclamp_normal"

    local modelHash = GetHashKey(clampModelName)
    if not IsModelInCdimage(modelHash) then
        debugPrint("Model not in CD image: %s", clampModelName)
        QBox.Functions.Notify("Clamp model does not exist.", "error", 5000)
        return
    end

    RequestModel(modelHash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - startTime > 5000 then
            debugPrint("Model load timed out for model: %s", clampModelName)
            QBox.Functions.Notify("Clamp model failed to load.", "error", 5000)
            return
        end
    end

    debugPrint("Attaching clamp to vehicle NetID: %s, bone: %s, model: %s", netId, boneName, clampModelName)
    boneIndex = GetEntityBoneIndexByName(vehicle, boneName) -- reusing stored value
    local tirePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    local cone = CreateObject(modelHash, tirePos.x, tirePos.y, tirePos.z, true, true, false)
    if not cone or cone == 0 then
        debugPrint("CreateObject failed for model %s", clampModelName)
        QBox.Functions.Notify("Failed to create clamp prop.", "error", 5000)
        return
    end

    local configForModel = CLAMP_CONFIG[clampModelName] or {}
    local offsets = configForModel[boneName] or { pos = vector3(0, 0, 0), rot = vector3(0, 0, 0) }
    AttachEntityToEntity(
        cone, vehicle, boneIndex,
        offsets.pos.x, offsets.pos.y, offsets.pos.z,
        offsets.rot.x, offsets.rot.y, offsets.rot.z,
        false, false, false, false, 1, true
    )
    FreezeEntityPosition(cone, true)
    SetEntityCollision(cone, false, false)
    CLAMP_CONES[key] = cone

    Wait(100)
    debugPrint("Clamp attached at coords: %s", tostring(GetEntityCoords(cone)))
    Wait(400)
    SetVehicleUndriveable(vehicle, true)
    local netIdStr = tostring(netId)
    CLIENT_CLAMPED_VEHICLES[netIdStr] = CLIENT_CLAMPED_VEHICLES[netIdStr] or {}
    CLIENT_CLAMPED_VEHICLES[netIdStr][boneName] = true
    SetModelAsNoLongerNeeded(modelHash)
end

local function detachClamp(vehicle, boneName)
    if not boneName then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. boneName

    if CLAMP_CONES[key] then
        DeleteObject(CLAMP_CONES[key])
        CLAMP_CONES[key] = nil
    end
    SetVehicleUndriveable(vehicle, false)
    local netIdStr = tostring(netId)
    if CLIENT_CLAMPED_VEHICLES[netIdStr] then
        CLIENT_CLAMPED_VEHICLES[netIdStr][boneName] = nil
        if not next(CLIENT_CLAMPED_VEHICLES[netIdStr]) then
            CLIENT_CLAMPED_VEHICLES[netIdStr] = nil
        end
    end
end

------------------------------------------------------------
-- Target Registration for Parking Boot (Police Only)
------------------------------------------------------------
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = "apply_parking_boot",
            icon = "fas fa-wrench",
            label = "Apply Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:ToggleParkingBoot",
            canInteract = function(entity)
                local playerData = QBox.Functions.GetPlayerData()
                if not (playerData.job and playerData.job.name == "police") then 
                    return false 
                end
                local netId = getServerNetId(entity)
                if CLIENT_CLAMPED_VEHICLES[tostring(netId)] then 
                    return false 
                end
                local hasClampItem = false
                for _, item in pairs(exports.ox_inventory:GetPlayerItems() or {}) do
                    if item.name == "wheel_clamp" and tonumber(item.count) and tonumber(item.count) > 0 then
                        hasClampItem = true
                        break
                    end
                end
                return hasClampItem
            end
        },
        {
            name = "remove_parking_boot",
            icon = "fas fa-wrench",
            label = "Remove Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:ToggleParkingBoot",
            canInteract = function(entity)
                local playerData = QBox.Functions.GetPlayerData()
                if not (playerData.job and playerData.job.name == "police") then 
                    return false 
                end
                local netId = getServerNetId(entity)
                return CLIENT_CLAMPED_VEHICLES[tostring(netId)] and true or false
            end
        }
    })
end)

RegisterNetEvent("QBCore:Client:OnPlayerDataUpdate", function(newData)
    QBox.Functions.SetPlayerData(newData)
    exports.ox_target:removeGlobalVehicle("apply_parking_boot")
    exports.ox_target:removeGlobalVehicle("remove_parking_boot")
    Wait(0)
    exports.ox_target:addGlobalVehicle({
        {
            name = "apply_parking_boot",
            icon = "fas fa-wrench",
            label = "Apply Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:ToggleParkingBoot",
            canInteract = function(entity)
                local playerData = QBox.Functions.GetPlayerData()
                if not (playerData.job and playerData.job.name == "police") then 
                    return false 
                end
                local netId = getServerNetId(entity)
                if CLIENT_CLAMPED_VEHICLES[tostring(netId)] then 
                    return false 
                end
                local hasClampItem = false
                for _, item in pairs(exports.ox_inventory:GetPlayerItems() or {}) do
                    if item.name == "wheel_clamp" and tonumber(item.count) and tonumber(item.count) > 0 then
                        hasClampItem = true
                        break
                    end
                end
                return hasClampItem
            end
        },
        {
            name = "remove_parking_boot",
            icon = "fas fa-wrench",
            label = "Remove Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:ToggleParkingBoot",
            canInteract = function(entity)
                local playerData = QBox.Functions.GetPlayerData()
                if not (playerData.job and playerData.job.name == "police") then 
                    return false 
                end
                local netId = getServerNetId(entity)
                return CLIENT_CLAMPED_VEHICLES[tostring(netId)] and true or false
            end
        }
    })
end)

------------------------------------------------------------
-- Toggle Event for Applying/Removing Parking Boot
------------------------------------------------------------
RegisterNetEvent("wheelclamp:client:ToggleParkingBoot")
AddEventHandler("wheelclamp:client:ToggleParkingBoot", function(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        QBox.Functions.Notify("No vehicle nearby!", "error", 5000)
        return
    end
    local netId = getServerNetId(vehicle)
    local netIdStr = tostring(netId)
    debugPrint("Toggling clamp. Vehicle NetID: %s", netIdStr)

    if CLIENT_CLAMPED_VEHICLES[netIdStr] then
        local clampedBone = getClosestClampedTire(vehicle)
        debugPrint("Found closest clamped bone: %s", clampedBone or "NONE")
        if not clampedBone then
            QBox.Functions.Notify("No clamped tire found.", "error", 5000)
            return
        end
        walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
            if success then
                TriggerServerEvent("wheelclamp:server:RemoveClamp", netId, clampedBone)
            end
        end, clampedBone, "Removing Parking Boot")
    else
        QBox.Functions.TriggerCallback("wheelclamp:server:CheckInventory", function(hasItem)
            if not hasItem then
                QBox.Functions.Notify("You do not have a wheel clamp.", "error", 5000)
                return
            end
            local bone = getClosestTireBoneByPlayer(vehicle)
            debugPrint("Found closest tire bone to attach clamp: %s", bone or "NONE")
            if not bone then
                QBox.Functions.Notify("Could not determine target tire.", "error", 5000)
                return
            end
            walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
                if success then
                    TriggerServerEvent("wheelclamp:server:ApplyClamp", netId, bone)
                end
            end, bone, "Applying Parking Boot")
        end, "wheel_clamp")
    end
end)

------------------------------------------------------------
-- State Bag Sync for Clamp Persistence
------------------------------------------------------------
AddStateBagChangeHandler("efWheelClamp", nil, function(bagName, key, value, reserved, replicated)
    local netIdStr = bagName:match("entity:(%d+)")
    if not netIdStr then return end
    local vehicleNetId = tonumber(netIdStr)
    local valueStr = tostring(value)
    if valueStr == "" or valueStr == "123" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    local success, data = pcall(json.decode, valueStr)
    if not (success and type(data) == "table" and data.bone) then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    TriggerEvent("wheelclamp:client:ForceApplyClamp", vehicleNetId, data.applied, data.bone)
end)

RegisterNetEvent("wheelclamp:client:ForceApplyClamp")
AddEventHandler("wheelclamp:client:ForceApplyClamp", function(vehicleNetId, clampApplied, bone)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end
    if clampApplied then
        attachClamp(vehicle, bone)
    else
        detachClamp(vehicle, bone)
    end
end)

AddEventHandler("entityStreamIn", function(entity)
    if GetEntityType(entity) ~= 2 then return end
    local netId = getServerNetId(entity)
    local bagName = string.format("entity:%d", netId)
    local state = GetStateBagValue(bagName, "efWheelClamp")
    if not state or tostring(state) == "" or tostring(state) == "123" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    local success, data = pcall(json.decode, tostring(state))
    if not (success and type(data) == "table") then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    if data.bone then
        TriggerEvent("wheelclamp:client:ForceApplyClamp", netId, data.applied, data.bone)
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
