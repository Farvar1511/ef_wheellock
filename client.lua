-- client.lua
-- Assumes config.lua and clampconfig.lua have already been loaded

TIRE_BONES = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }  -- Global tire bones
ITEM_NAME = Config.ItemName or "wheel_clamp"
clientClampedVehicles = clientClampedVehicles or {}  -- Tracks clamp state per vehicle (by netID)
wheelClamps = wheelClamps or {}  -- Stores the actual clamp prop objects

local function dbg(msg)
    if Config.Debug then
        print(string.format("[WHEELCLAMP DEBUG] %s", tostring(msg)))
    end
end

--------------------------------------------------------------------------------
-- Get Player Data & Job via qbx_core Export
--------------------------------------------------------------------------------
local function getPlayerData()
    return exports['qbx_core']:GetPlayerData()
end

local function getPlayerJob()
    local data = getPlayerData()
    if data and data.job and data.job.name then
        return data.job.name:lower(), tonumber(data.job.grade) or 0
    end
    return "", 0
end

--------------------------------------------------------------------------------
-- Check for the clamp item using ox_inventory (client-side)
--------------------------------------------------------------------------------
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
-- canApply / canRemove logic (using Config for job restrictions)
--------------------------------------------------------------------------------
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
-- Clamp Offset Configurations (from clampconfig.lua are already loaded)
-- CLAMP_CONFIG, APPROACH_OFFSETS, and DEFAULT_OFFSET
--------------------------------------------------------------------------------
local APPLY_DURATION = 8000  -- 8 seconds

--------------------------------------------------------------------------------
-- Helper Functions: State Bag, Clamp Attach/Detach, Approach, etc.
--------------------------------------------------------------------------------
local function GetStateBagName(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return "entity:" .. netId
end

local function getServerNetId(vehicle)
    local bagName = GetStateBagName(vehicle)
    if bagName then
        local netIdStr = bagName:match("entity:(%d+)")
        if netIdStr then return tonumber(netIdStr) end
    end
    return NetworkGetNetworkIdFromEntity(vehicle)
end

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
    local netId = getServerNetId(vehicle)
    return clientClampedVehicles[tostring(netId)]
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

--------------------------------------------------------------------------------
-- walkToOffsetAndAnimate: Walk the player to the defined offset then concurrently
-- display a progress bar (with label) and play the mechanic animation.
-- The progress bar and animation are synchronized.
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

    -- Force the player to walk to the target offset (no progress bar for walking)
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

    smoothTurnToCoord(PlayerPedId(), tirePos.x, tirePos.y, tirePos.z, 1000)
    Wait(500)

    -- Start the progress bar concurrently in a new thread so it runs alongside the animation
    Citizen.CreateThread(function()
        exports.ox_lib:progressBar({
            duration = duration,
            label = animLabel,
            disable = { move = true, combat = true },
            useWhileDead = false,
            canCancel = false
        })
    end)
    -- Immediately start the animation
    ExecuteCommand("e mechanic4")
    Wait(duration)
    ExecuteCommand("e c")
    cb(true)
end

--------------------------------------------------------------------------------
-- Clamp Attach/Detach Functions
--------------------------------------------------------------------------------
local function attachClamp(vehicle, bone)
    if not bone or not DoesEntityExist(vehicle) then return end
    local netId = getServerNetId(vehicle)
    local key = tostring(netId) .. bone
    local idx = GetEntityBoneIndexByName(vehicle, bone)
    if not idx or idx == -1 then 
        TriggerEvent("chat:addMessage", { args = { "Error", string.format("Invalid bone '%s' for vehicle netID: %s", bone, tostring(netId)) } })
        return 
    end
    if wheelClamps[key] then
        TriggerEvent("chat:addMessage", { args = { "Error", string.format("Tire '%s' already clamped on vehicle netID: %s", bone, tostring(netId)) } })
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
-- Ox Target Registration: Apply/Remove Options with distinct labels
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
-- Client Event Handlers for Clamp Apply/Remove using walkToOffsetAndAnimate
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
-- State Bag Handlers & Sync
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
    local bagName = ("entity:%d"):format(netId)
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

CreateThread(function()
    while true do
        for key, clampObj in pairs(wheelClamps) do
            local netIdStr, bone = key:match("^(%d+)(.+)$")
            if netIdStr and bone then
                local vehicle = NetworkGetEntityFromNetworkId(tonumber(netIdStr))
                if DoesEntityExist(vehicle) then
                    local idx = GetEntityBoneIndexByName(vehicle, bone)
                    if idx and idx ~= -1 then
                        local pos = GetWorldPositionOfEntityBone(vehicle, bone)
                        local clampPos = GetEntityCoords(clampObj)
                        if #(pos - clampPos) > 0.5 then
                            local modelName = GetVehicleClampModel(vehicle)
                            local config = CLAMP_CONFIG[modelName] or {}
                            local offsets = config[bone] or { pos = vector3(0,0,0), rot = vector3(0,0,0) }
                            AttachEntityToEntity(clampObj, vehicle, idx,
                                offsets.pos.x, offsets.pos.y, offsets.pos.z,
                                offsets.rot.x, offsets.rot.y, offsets.rot.z,
                                false, false, false, false, 1, true)
                        end
                    end
                end
            end
        end
        Wait(5000)
    end
end)
