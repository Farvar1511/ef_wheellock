------------------------------------------------------------
-- client.lua
-- Everfall Parking Boot - Example with easy offset config
------------------------------------------------------------
local QBox = exports['qb-core']:GetCoreObject()
local json = json or require("json")

------------------------------------------------------------
-- Clamp Config (Position & Rotation)
------------------------------------------------------------
local clampConfig = {
    ["baspel_wheelclamp_suv"] = {
        -- Front Left (driver)
        wheel_lf = {
            pos = vector3(0.06, 0.20, -0.10),
            rot = vector3(10.0, 0.0, 0.0)
        },
        -- Front Right (passenger)
        wheel_rf = {
            pos = vector3(0.07, 0.20, 0.10),
            rot = vector3(80.0, 0.0, 0.0)
        },
        -- Rear Left (driver)
        wheel_lr = {
            pos = vector3(0.06, 0.20, -0.10),
            rot = vector3(10.0, 0.0, 0.0)
        },
        -- Rear Right (passenger)
        wheel_rr = {
            pos = vector3(0.07, -0.10, -0.20),
            rot = vector3(-80.0, 0.0, 0.0)
        },
    },

    ["baspel_wheelclamp_normal"] = {
        -- Using the same perfect values for normal vehicles:
        wheel_lf = {
            pos = vector3(-0.03, 0.20, -0.10),
            rot = vector3(10.0, 0.0, 0.0)
        },
        wheel_rf = {
            pos = vector3(-0.03, 0.20, 0.15),
            rot = vector3(80.0, 0.0, 0.0)
        },
        wheel_lr = {
            pos = vector3(-0.03, 0.20, -0.10),
            rot = vector3(10.0, 0.0, 0.0)
        },
        wheel_rr = {
            pos = vector3(-0.06, 0.20, 0.17),
            rot = vector3(80.0, 0.0, 0.0)
        },
    },

    ["baspel_wheelclamp_motorcycle"] = {
        -- Bikes have two tires: assume "wheel_lf" is the front tire and "wheel_lr" is the rear tire.
        wheel_lf = {
            pos = vector3(0.05, 0.0, -0.15),
            rot = vector3(-25.0, 0.0, 0.0)
        },
        wheel_lr = {
            pos = vector3(0.05, 0.0, -0.15),
            rot = vector3(-25.0, 0.0, 0.0)
        },
    },
}

------------------------------------------------------------
-- Approach Offsets (NavMesh approach)
------------------------------------------------------------
local approachOffsets = {
    wheel_lf = vector3(-0.7, 0.1, 0.6),
    wheel_rf = vector3(0.8, 0.1, 0.6),
    wheel_lr = vector3(-0.7, 0.1, 0.6),
    wheel_rr = vector3(0.8, 0.1, 0.6)
}

------------------------------------------------------------
-- Local Data
------------------------------------------------------------
local clampCones = {}
local clientClampedVehicles = {}
local applyDuration = 4000 -- ms for progress bar/animation
local tireBones = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }

-- Emote cancel tracking
local emoteCancelled = false
RegisterNetEvent('scully_emotemenu:EmoteCanceled', function()
    emoteCancelled = true
end)

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------
local function GetServerNetId(vehicle)
    return NetworkGetNetworkIdFromEntity(vehicle)
end

local function GetClosestTireBoneByPlayer(vehicle)
    local ped = PlayerPedId()
    local pedPos = GetEntityCoords(ped)
    local closestBone, minDistance = nil, math.huge
    for _, bone in ipairs(tireBones) do
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

local function GetClosestClampedTire(vehicle)
    local ped = PlayerPedId()
    local pedPos = GetEntityCoords(ped)
    local netIdStr = tostring(GetServerNetId(vehicle))
    local closestBone, minDist = nil, math.huge
    for _, bone in ipairs(tireBones) do
        local key = netIdStr .. bone
        if clampCones[key] then
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

------------------------------------------------------------
-- NavMesh approach position for each tire (before the animation).
------------------------------------------------------------
local function GetApproachPosForTire(vehicle, boneName)
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if not boneIndex or boneIndex == -1 then return nil end
    local tirePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    local offset = approachOffsets[boneName] or vector3(-0.7, 0.1, 0.6)
    local mag = #(offset)
    local normalizedOffset = (mag > 0) and (offset / mag) or vector3(0, 0, 0)

    local function RotateOffset(vehicle, off)
       local rot = GetEntityRotation(vehicle, 2) or vector3(0, 0, 0)
       local rad = math.rad(rot.z or 0)
       local rx = off.x * math.cos(rad) - off.y * math.sin(rad)
       local ry = off.x * math.sin(rad) + off.y * math.cos(rad)
       return vector3(rx, ry, off.z)
    end

    local rotatedOffset = RotateOffset(vehicle, normalizedOffset)
    local targetPos = tirePos + rotatedOffset
    return targetPos, tirePos
end

-- Wait until the ped is within a given distance or until timeout.
local function WaitUntilClose(targetPos, maxTime, callback)
    emoteCancelled = false
    local startTime = GetGameTimer()
    while GetGameTimer() - startTime < maxTime do
        if emoteCancelled then
            callback(false)
            return
        end
        local pedPos = GetEntityCoords(PlayerPedId())
        if #(pedPos - targetPos) < 0.5 then
            callback(true)
            return
        end
        Wait(100)
    end
    callback(false)
end

-- Turn ped to face a coordinate
local function SmoothTurnToCoord(ped, x, y, z, duration)
    TaskTurnPedToFaceCoord(ped, x, y, z, duration)
    Wait(duration)
end

------------------------------------------------------------
-- Approach + Animation (with dynamic progress bar label)
------------------------------------------------------------
local function WalkToOffsetAndAnimate(vehicle, duration, callback, boneName, actionLabel)
    if not boneName then
        QBox.Functions.Notify("No tire specified.", "error", 5000)
        if callback then callback(false) end
        return
    end
    local targetPos, tirePos = GetApproachPosForTire(vehicle, boneName)
    if not targetPos or not tirePos then
        QBox.Functions.Notify("Failed to compute approach offset.", "error", 5000)
        if callback then callback(false) end
        return
    end

    local ped = PlayerPedId()
    TaskFollowNavMeshToCoord(ped, targetPos.x, targetPos.y, targetPos.z, 0.4, 10000, 1.0, false, 0)
    WaitUntilClose(targetPos, 15000, function(arrived)
        if not arrived then
            QBox.Functions.Notify("Timed out or path blocked.", "error", 5000)
            if callback then callback(false) end
            return
        end
        SmoothTurnToCoord(ped, tirePos.x, tirePos.y, tirePos.z, 1000)
        Wait(500)
        -- Start progress bar and "mechanic4" animation with custom label
        CreateThread(function()
            exports.ox_lib:progressBar({
                duration = duration,
                label = actionLabel,
                useWhileDead = false,
                canCancel = false,
                disable = { car = true, move = true, combat = true }
            }, function(status) end)
        end)
        ExecuteCommand("e mechanic4")
        Wait(duration)
        ExecuteCommand("e c")
        if callback then callback(true) end
    end)
end

------------------------------------------------------------
-- Attach/Detach Clamp
------------------------------------------------------------
local function AttachClamp(vehicle, boneName)
    if not boneName or not DoesEntityExist(vehicle) then return end
    local netId = GetServerNetId(vehicle)
    local key = tostring(netId) .. boneName
    local boneIndex = GetEntityBoneIndexByName(vehicle, boneName)
    if not boneIndex or boneIndex == -1 then
        print("[DEBUG] Invalid bone index for", boneName)
        return
    end

    -- If already clamped, skip
    if clampCones[key] then
        QBox.Functions.Notify("This tire is already clamped!", "error", 5000)
        return
    end

    -- Choose model name based on vehicle class
    local vehicleClass = tonumber(GetVehicleClass(vehicle))
    local clampModelName
    if vehicleClass == 8 then
        clampModelName = "baspel_wheelclamp_motorcycle"
    elseif vehicleClass == 2 or vehicleClass == 9 then
        clampModelName = "baspel_wheelclamp_suv"
    else
        clampModelName = "baspel_wheelclamp_normal"
    end

    -- Load model
    local modelHash = GetHashKey(clampModelName)
    if not IsModelInCdimage(modelHash) then
        print("[ERROR] Model not in CD image:", clampModelName)
        QBox.Functions.Notify("Clamp model does not exist.", "error", 5000)
        return
    end
    RequestModel(modelHash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - startTime > 5000 then
            print("[DEBUG] Model load timed out for model:", clampModelName)
            QBox.Functions.Notify("Clamp model failed to load.", "error", 5000)
            return
        end
    end

    -- Debug info: bone, offsets, etc.
    print("[DEBUG] ----------------------------")
    print("[DEBUG] Attaching clamp to vehicle NetID:", netId)
    print("[DEBUG] Bone name:", boneName, "Bone index:", boneIndex)
    print("[DEBUG] Model name:", clampModelName)
    
    local tirePos = GetWorldPositionOfEntityBone(vehicle, boneIndex)
    print("[DEBUG] Tire bone world coords:", tirePos)

    -- Create object
    local cone = CreateObject(modelHash, tirePos.x, tirePos.y, tirePos.z, true, true, false)
    if not cone or cone == 0 then
        print("[DEBUG] CreateObject failed for model", clampModelName)
        QBox.Functions.Notify("Failed to create clamp prop.", "error", 5000)
        return
    end

    -- Get offsets from clampConfig
    local configForModel = clampConfig[clampModelName] or {}
    local offsets = configForModel[boneName] or { pos = vector3(0,0,0), rot = vector3(0,0,0) }
    print("[DEBUG] Offsets (pos):", offsets.pos, " (rot):", offsets.rot)

    -- Attach object to vehicle bone with position & rotation
    AttachEntityToEntity(
        cone,
        vehicle,
        boneIndex,
        offsets.pos.x, offsets.pos.y, offsets.pos.z,
        offsets.rot.x, offsets.rot.y, offsets.rot.z,
        false, false, false, false, 1, true
    )
    FreezeEntityPosition(cone, true)
    SetEntityCollision(cone, false, false)
    clampCones[key] = cone

    Wait(100)
    local clampCoords = GetEntityCoords(cone)
    print("[DEBUG] clamp final coords after attach:", clampCoords)

    -- Disable vehicle driving
    Wait(400)
    SetVehicleUndriveable(vehicle, true)

    -- Mark clamp in local table
    clientClampedVehicles[tostring(netId)] = clientClampedVehicles[tostring(netId)] or {}
    clientClampedVehicles[tostring(netId)][boneName] = true

    -- Release model
    SetModelAsNoLongerNeeded(modelHash)
    print("[DEBUG] ----------------------------")
end

local function DetachClamp(vehicle, boneName)
    if not boneName then return end
    local netId = GetServerNetId(vehicle)
    local key = tostring(netId) .. boneName

    if clampCones[key] then
        DeleteObject(clampCones[key])
        clampCones[key] = nil
    end

    -- Re-enable vehicle driving
    SetVehicleUndriveable(vehicle, false)

    if clientClampedVehicles[tostring(netId)] then
        clientClampedVehicles[tostring(netId)][boneName] = nil
        if next(clientClampedVehicles[tostring(netId)]) == nil then
            clientClampedVehicles[tostring(netId)] = nil
        end
    end
end

------------------------------------------------------------
-- OX Target: Two separate targets for Apply and Remove Parking Boot (Police Only)
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
                if not playerData.job or playerData.job.name ~= "police" then
                    return false
                end
                local netId = GetServerNetId(entity)
                -- Only allow if NOT already clamped
                if clientClampedVehicles[tostring(netId)] then
                    return false
                end
                -- Must have a clamp item
                local hasClampItem = false
                local inventory = exports.ox_inventory:GetPlayerItems() or {}
                for slot, item in pairs(inventory) do
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
                if not playerData.job or playerData.job.name ~= "police" then
                    return false
                end
                local netId = GetServerNetId(entity)
                -- Only allow if vehicle is already clamped
                if not clientClampedVehicles[tostring(netId)] then
                    return false
                end
                return true
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
                if not playerData.job or playerData.job.name ~= "police" then
                    return false
                end
                local netId = GetServerNetId(entity)
                if clientClampedVehicles[tostring(netId)] then
                    return false
                end
                local hasClampItem = false
                local inventory = exports.ox_inventory:GetPlayerItems() or {}
                for slot, item in pairs(inventory) do
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
                if not playerData.job or playerData.job.name ~= "police" then
                    return false
                end
                local netId = GetServerNetId(entity)
                if not clientClampedVehicles[tostring(netId)] then
                    return false
                end
                return true
            end
        }
    })
end)

------------------------------------------------------------
-- Toggle Event
------------------------------------------------------------
RegisterNetEvent("wheelclamp:client:ToggleParkingBoot")
AddEventHandler("wheelclamp:client:ToggleParkingBoot", function(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        QBox.Functions.Notify("No vehicle nearby!", "error", 5000)
        return
    end
    local netId = GetServerNetId(vehicle)
    local netIdStr = tostring(netId)

    print("[DEBUG] Toggling clamp. Vehicle NetID:", netIdStr)

    if clientClampedVehicles[netIdStr] then
        -- Remove clamp from the closest clamped tire
        local clampedBone = GetClosestClampedTire(vehicle)
        print("[DEBUG] Found closest clamped bone:", clampedBone or "NONE")
        if not clampedBone then
            QBox.Functions.Notify("No clamped tire found.", "error", 5000)
            return
        end
        WalkToOffsetAndAnimate(vehicle, applyDuration, function(success)
            if success then
                TriggerServerEvent("wheelclamp:server:RemoveClamp", netId, clampedBone)
            end
        end, clampedBone, "Removing Parking Boot")
    else
        -- Apply clamp to the closest tire bone
        QBox.Functions.TriggerCallback("wheelclamp:server:CheckInventory", function(hasItem)
            if not hasItem then
                QBox.Functions.Notify("You do not have a wheel clamp.", "error", 5000)
                return
            end
            local bone = GetClosestTireBoneByPlayer(vehicle)
            print("[DEBUG] Found closest tire bone to attach clamp:", bone or "NONE")
            if not bone then
                QBox.Functions.Notify("Could not determine target tire.", "error", 5000)
                return
            end
            WalkToOffsetAndAnimate(vehicle, applyDuration, function(success)
                if success then
                    TriggerServerEvent("wheelclamp:server:ApplyClamp", netId, bone)
                end
            end, bone, "Applying Parking Boot")
        end, "wheel_clamp")
    end
end)

------------------------------------------------------------
-- State Bag Sync
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
    if not success or type(data) ~= "table" or not data.bone then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    local applied = data.applied
    local bone = data.bone
    TriggerEvent("wheelclamp:client:ForceApplyClamp", vehicleNetId, applied, bone)
end)

RegisterNetEvent("wheelclamp:client:ForceApplyClamp")
AddEventHandler("wheelclamp:client:ForceApplyClamp", function(vehicleNetId, clampApplied, bone)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end
    if clampApplied then
        AttachClamp(vehicle, bone)
    else
        DetachClamp(vehicle, bone)
    end
end)

AddEventHandler("entityStreamIn", function(entity)
    if GetEntityType(entity) ~= 2 then return end
    local netId = GetServerNetId(entity)
    local bagName = ("entity:%d"):format(netId)
    local state = GetStateBagValue(bagName, "efWheelClamp")
    if not state or tostring(state) == "" or tostring(state) == "123" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    local success, data = pcall(json.decode, tostring(state))
    if not success or type(data) ~= "table" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    local applied = data.applied
    local bone = data.bone
    if bone then
        TriggerEvent("wheelclamp:client:ForceApplyClamp", netId, applied, bone)
    end
end)

-- Clean up on entity removal
AddEventHandler("onClientEntityRemove", function(entity)
    local netId = GetServerNetId(entity)
    for _, bone in ipairs(tireBones) do
        local key = tostring(netId) .. bone
        if clampCones[key] then
            DeleteObject(clampCones[key])
            clampCones[key] = nil
        end
    end
end)
