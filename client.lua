-- client.lua
-- This script handles client-side functionality for the wheel clamp resource.
-- It requires that config.lua and clampconfig.lua are loaded via fxmanifest.lua.

-- Global definitions:
TIRE_BONES = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }  -- Tire bones for targeting
ITEM_NAME = Config.ItemName or "wheel_clamp"                        -- Clamp item name (from config)
clientClampedVehicles = clientClampedVehicles or {}                -- Tracks vehicles with clamps (by netID)
wheelClamps = wheelClamps or {}                                      -- Stores clamp prop objects attached to vehicles

-- Debug function: Prints debug messages if Config.Debug is true.
local function dbg(msg)
    if Config.Debug then
        print(string.format("[WHEELCLAMP DEBUG] %s", tostring(msg)))
    end
end

--------------------------------------------------------------------------------
-- Player Data Functions
--------------------------------------------------------------------------------
-- Retrieves player data using the qbx_core export.
local function getPlayerData()
    return exports['qbx_core']:GetPlayerData()
end

-- Retrieves the player's job name (lowercase) and grade.
local function getPlayerJob()
    local data = getPlayerData()
    if data and data.job and data.job.name then
        return data.job.name:lower(), tonumber(data.job.grade) or 0
    end
    return "", 0
end

--------------------------------------------------------------------------------
-- Inventory Check
--------------------------------------------------------------------------------
-- Checks whether the player has the clamp item using ox_inventory.
local function hasClampItem()
    local inventory = exports.ox_inventory:GetPlayerItems() or {}
    for _, item in pairs(inventory) do
        dbg(string.format("Inventory item: name=%s, count=%s", tostring(item.name), tostring(item.count)))
        if item.name == ITEM_NAME then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Job Permission Checks
--------------------------------------------------------------------------------
-- Checks if the player meets the requirements for applying or removing clamps.
local function canApply()
    local job, grade = getPlayerJob()
    dbg(string.format("canApply() -> job: %s, grade: %d, hasClampItem: %s", job, grade, tostring(hasClampItem())))
    local required = Config.ApplyClampAllowedJobs[job]
    return required and (grade >= required) and hasClampItem()
end

local function canRemove()
    local job, grade = getPlayerJob()
    local required = Config.RemoveClampAllowedJobs[job]
    return required and (grade >= required)
end

--------------------------------------------------------------------------------
-- Clamp Offset Configurations & Timing
--------------------------------------------------------------------------------
-- These are loaded from clampconfig.lua.
local APPLY_DURATION = 8000  -- Duration (ms) for the mechanic animation/progress bar

--------------------------------------------------------------------------------
-- Helper Functions: Positioning & State Bag
--------------------------------------------------------------------------------
-- Constructs a state bag name using the entity's network ID.
local function GetStateBagName(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return "entity:" .. netId
end

-- Returns the server network ID for a vehicle.
local function getServerNetId(vehicle)
    local bagName = GetStateBagName(vehicle)
    if bagName then
        local netIdStr = bagName:match("entity:(%d+)")
        if netIdStr then return tonumber(netIdStr) end
    end
    return NetworkGetNetworkIdFromEntity(vehicle)
end

-- Chooses the clamp model name based on the vehicle class.
local function GetVehicleClampModel(vehicle)
    local vehClass = tonumber(GetVehicleClass(vehicle))
    if vehClass == 8 then
        return "baspel_wheelclamp_motorcycle"
    elseif vehClass == 2 or vehClass == 9 then
        return "baspel_wheelclamp_suv"
    else
        return "baspel_wheelclamp_normal"
    end
end

-- Returns the name of the closest tire bone to the player's position.
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

-- Returns the bone that currently has a clamp attached.
local function getClosestClampedTire(vehicle)
    local netId = getServerNetId(vehicle)
    return clientClampedVehicles[tostring(netId)]
end

-- Computes the approach position for the specified tire bone.
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

-- Waits until the player is within a certain distance of a target coordinate.
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

-- Rotates the player smoothly to face a coordinate.
local function smoothTurnToCoord(ped, x, y, z, duration)
    TaskTurnPedToFaceCoord(ped, x, y, z, duration)
    Wait(duration)
end

--------------------------------------------------------------------------------
-- walkToOffsetAndAnimate
-- Forces the player to walk to the target offset, turns them to face the tire,
-- then concurrently displays a progress bar (with label) while playing the mechanic animation.
-- Both the progress bar and the animation run for the same duration.
--------------------------------------------------------------------------------
local function walkToOffsetAndAnimate(vehicle, duration, cb, bone, animLabel)
    if not bone then
        TriggerEvent("chat:addMessage", { args = { "Error", "No tire specified." } })
        return cb(false)
    end

    local target, tirePos = getApproachPosForTire(vehicle, bone)
    if not (target and tirePos) then
        TriggerEvent("chat:addMessage", { args = { "Error", "Failed to compute approach offset." } })
        return cb(false)
    end

    -- Force the player to walk to the target offset (no progress bar here).
    TaskFollowNavMeshToCoord(PlayerPedId(), target.x, target.y, target.z, 0.4, 10000, 1.0, false, 0)
    local arrived = false
    local startTime = GetGameTimer()
    while GetGameTimer() - startTime < 10000 do
        if #(GetEntityCoords(PlayerPedId()) - target) < 0.5 then
            arrived = true
            break
        end
        DisableAllControlActions(0)
        Wait(100)
    end

    if not arrived then
        TriggerEvent("chat:addMessage", { args = { "Error", "Timed out or path blocked." } })
        return cb(false)
    end

    -- Turn the player to face the tire.
    smoothTurnToCoord(PlayerPedId(), tirePos.x, tirePos.y, tirePos.z, 1000)
    Wait(500)

    -- Start the progress bar concurrently in a new thread so it runs alongside the animation.
    Citizen.CreateThread(function()
        exports.ox_lib:progressBar({
            duration = duration,
            label = animLabel,
            disable = { move = true, combat = true },
            useWhileDead = false,
            canCancel = false
        })
    end)

    -- Start the mechanic animation.
    ExecuteCommand("e mechanic4")
    Wait(duration)
    ExecuteCommand("e c")
    cb(true)
end

--------------------------------------------------------------------------------
-- Clamp Prop Attachment Functions
--------------------------------------------------------------------------------
-- Attaches a clamp prop to the specified tire bone of a vehicle.
-- If a clamp already exists for this bone, it will be reattached.
local function attachClamp(vehicle, bone)
    if not bone or not DoesEntityExist(vehicle) then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. bone
    local idx = GetEntityBoneIndexByName(vehicle, bone)
    if not idx or idx == -1 then 
        TriggerEvent("chat:addMessage", { args = { "Error", string.format("Invalid bone '%s' for vehicle netID: %s", bone, tostring(netId)) } })
        return 
    end

    local vehClass = tonumber(GetVehicleClass(vehicle))
    local modelName = (vehClass == 8 and "baspel_wheelclamp_motorcycle")
                      or ((vehClass == 2 or vehClass == 9) and "baspel_wheelclamp_suv")
                      or "baspel_wheelclamp_normal"
    local modelHash = joaat(modelName)
    if not IsModelInCdimage(modelHash) then
        TriggerEvent("chat:addMessage", { args = { "Error", string.format("Clamp model '%s' does not exist.", modelName) } })
        return
    end
    RequestModel(modelHash)
    local start = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        Wait(10)
        if GetGameTimer() - start > 5000 then
            TriggerEvent("chat:addMessage", { args = { "Error", string.format("Clamp model '%s' failed to load.", modelName) } })
            return
        end
    end
    local pos = GetWorldPositionOfEntityBone(vehicle, idx)
    
    -- If a clamp already exists, reattach it.
    if wheelClamps[key] then
        local config = CLAMP_CONFIG[modelName] or {}
        local offsets = config[bone] or { pos = vector3(0, 0, 0), rot = vector3(0, 0, 0) }
        AttachEntityToEntity(wheelClamps[key], vehicle, idx,
            offsets.pos.x, offsets.pos.y, offsets.pos.z,
            offsets.rot.x, offsets.rot.y, offsets.rot.z,
            false, false, false, false, 1, true)
        return
    end

    -- Otherwise, create a new clamp prop.
    local clampObj = CreateObject(modelHash, pos.x, pos.y, pos.z, true, true, false)
    if not clampObj or clampObj == 0 then
        TriggerEvent("chat:addMessage", { args = { "Error", "Failed to create clamp prop." } })
        return
    end
    local config = CLAMP_CONFIG[modelName] or {}
    local offsets = config[bone] or { pos = vector3(0, 0, 0), rot = vector3(0, 0, 0) }
    AttachEntityToEntity(clampObj, vehicle, idx,
        offsets.pos.x, offsets.pos.y, offsets.pos.z,
        offsets.rot.x, offsets.rot.y, offsets.rot.z,
        false, false, false, false, 1, true)
    FreezeEntityPosition(clampObj, true)
    SetEntityCollision(clampObj, false, false)
    wheelClamps[key] = clampObj
    Wait(100)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)
end

-- Detaches and deletes the clamp prop from the vehicle.
local function detachClamp(vehicle, bone)
    if not bone then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. bone
    if wheelClamps[key] then
        DeleteObject(wheelClamps[key])
        wheelClamps[key] = nil
    end
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineOn(vehicle, false, true, true)
end

--------------------------------------------------------------------------------
-- Ox Target Registration
-- Registers two target options:
--   1. "Apply Parking Boot" if no clamp is applied.
--   2. "Remove Parking Boot" if a clamp is applied.
--------------------------------------------------------------------------------
CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = "apply_parking_boot",
            icon = "",  -- No icon
            label = "Apply Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:ApplyClamp",
            canInteract = function(entity)
                local playerData = getPlayerData()
                if not playerData or not playerData.job then return false end
                local job = playerData.job.name:lower()
                local grade = tonumber(playerData.job.grade) or 0
                local required = Config.ApplyClampAllowedJobs[job]
                if not required or grade < required then
                    return false
                end
                local netId = getServerNetId(entity)
                if clientClampedVehicles[tostring(netId)] then
                    return false
                end
                local inventory = exports.ox_inventory:GetPlayerItems() or {}
                for _, item in pairs(inventory) do
                    if item.name == ITEM_NAME then
                        return true
                    end
                end
                return false
            end
        },
        {
            name = "remove_parking_boot",
            icon = "",  -- No icon
            label = "Remove Parking Boot",
            distance = 3.0,
            event = "wheelclamp:client:RemoveClamp",
            canInteract = function(entity)
                local playerData = getPlayerData()
                if not playerData or not playerData.job then return false end
                local job = playerData.job.name:lower()
                local grade = tonumber(playerData.job.grade) or 0
                local required = Config.RemoveClampAllowedJobs[job]
                if not required or grade < required then
                    return false
                end
                local netId = getServerNetId(entity)
                if not clientClampedVehicles[tostring(netId)] then
                    return false
                end
                return true
            end
        }
    })
end)

--------------------------------------------------------------------------------
-- Client Event Handlers for Clamp Apply/Remove
--------------------------------------------------------------------------------
RegisterNetEvent("wheelclamp:client:ApplyClamp")
AddEventHandler("wheelclamp:client:ApplyClamp", function(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        TriggerEvent("chat:addMessage", { args = { "Error", "No vehicle nearby!" } })
        return
    end
    if not hasClampItem() then
        TriggerEvent("chat:addMessage", { args = { "Error", Config.Language.noItem } })
        return
    end
    local bone = getClosestTireBoneByPlayer(vehicle)
    if not bone then
        TriggerEvent("chat:addMessage", { args = { "Error", "Could not determine target tire." } })
        return
    end
    walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
        if not success then
            TriggerEvent("chat:addMessage", { args = { "Error", "Failed to complete animation." } })
            return
        end
        local netId = getServerNetId(vehicle)
        local result, err = lib.callback.await('wheelclamp:server:applyClamp', false, netId, bone)
        if not result then
            TriggerEvent("chat:addMessage", { args = { "Error", string.format("Clamp application failed: %s", tostring(err)) } })
        else
            TriggerEvent("chat:addMessage", { args = { "Success", "Clamp applied!" } })
        end
    end, bone, "Applying Parking Boot")
end)

RegisterNetEvent("wheelclamp:client:RemoveClamp")
AddEventHandler("wheelclamp:client:RemoveClamp", function(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        TriggerEvent("chat:addMessage", { args = { "Error", "No vehicle nearby!" } })
        return
    end
    local bone = getClosestClampedTire(vehicle)
    if not bone then
        TriggerEvent("chat:addMessage", { args = { "Error", "No clamped tire found." } })
        return
    end
    walkToOffsetAndAnimate(vehicle, APPLY_DURATION, function(success)
        if not success then
            TriggerEvent("chat:addMessage", { args = { "Error", "Failed to complete animation." } })
            return
        end
        local netId = getServerNetId(vehicle)
        local result, err = lib.callback.await('wheelclamp:server:removeClamp', false, netId, bone)
        if not result then
            TriggerEvent("chat:addMessage", { args = { "Error", string.format("Clamp removal failed: %s", tostring(err)) } })
        else
            TriggerEvent("chat:addMessage", { args = { "Success", "Clamp removed!" } })
        end
    end, bone, "Removing Parking Boot")
end)

--------------------------------------------------------------------------------
-- State Bag Handlers & Synchronization
--------------------------------------------------------------------------------
RegisterNetEvent("wheelclamp:client:ForceApplyClamp")
AddEventHandler("wheelclamp:client:ForceApplyClamp", function(vehicleNetId, clampApplied, bone)
    if not NetworkDoesEntityExistWithNetworkId(vehicleNetId) then return end
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end
    if clampApplied then
        clientClampedVehicles[tostring(vehicleNetId)] = bone
        SetVehicleUndriveable(vehicle, true)
        SetVehicleEngineOn(vehicle, false, true, true)
        attachClamp(vehicle, bone)
    else
        clientClampedVehicles[tostring(vehicleNetId)] = nil
        detachClamp(vehicle, bone)
    end
end)

AddStateBagChangeHandler("efWheelClamp", nil, function(bagName, key, value, reserved, replicated)
    local netIdStr = bagName:match("entity:(%d+)")
    if not netIdStr then return end
    local vehicleNetId = tonumber(netIdStr)
    local s = tostring(value or "")
    if s == "" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    local success, data = pcall(json.decode, s)
    if not (success and type(data) == "table") then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", vehicleNetId)
        return
    end
    TriggerEvent("wheelclamp:client:ForceApplyClamp", vehicleNetId, data.clamp, data.bone)
end)

AddEventHandler("entityStreamIn", function(entity)
    if GetEntityType(entity) ~= 2 then return end
    Wait(1000)
    local netId = getServerNetId(entity)
    local bagName = string.format("entity:%d", netId)
    local state = GetStateBagValue(bagName, "efWheelClamp")
    if not state or state == "" then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    local success, data = pcall(json.decode, tostring(state))
    if not (success and type(data) == "table") then
        TriggerServerEvent("wheelclamp:server:RestoreClamp", netId)
        return
    end
    if data.bone then
        TriggerEvent("wheelclamp:client:ForceApplyClamp", netId, data.clamp, data.bone)
    end
end)

AddEventHandler("onClientEntityRemove", function(entity)
    local netId = getServerNetId(entity)
    clientClampedVehicles[tostring(netId)] = nil
end)
