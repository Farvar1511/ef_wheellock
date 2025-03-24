-- server.lua
-- This script handles server-side logic for the wheel clamp resource.
-- It manages player data, validates job and inventory requirements,
-- updates clamp state, and synchronizes clamp information with clients.

print("[Server] Starting server.lua for ef_wheellock")

--------------------------------------------------------------------------------
-- Helper: Get Player Data
-- Retrieves player data using the framework export defined in Config.
--------------------------------------------------------------------------------
local function GetPlayerData(src)
    return exports[Config.FrameworkExport]:GetPlayer(src)
end

--------------------------------------------------------------------------------
-- Callback: Return Full Player Data for Debugging
-- Returns player data so that you can verify job and grade.
--------------------------------------------------------------------------------
lib.callback.register("wheelclamp:server:getPlayerData", function(source)
    local data = GetPlayerData(source)
    if data then
        print(string.format("[Server Debug] getPlayerData for %s: job=%s, grade=%s", source, tostring(data.PlayerData.job.name), tostring(data.PlayerData.job.grade)))
    else
        print(string.format("[Server Debug] getPlayerData: No data for source %s", source))
    end
    return data
end)

--------------------------------------------------------------------------------
-- Callback: Return Player's Job (Lowercase)
-- Quickly returns just the player's job name for authorization.
--------------------------------------------------------------------------------
lib.callback.register("wheelclamp:server:getPlayerJob", function(source)
    local playerData = GetPlayerData(source)
    if playerData and playerData.PlayerData and playerData.PlayerData.job then
        local jobName = tostring(playerData.PlayerData.job.name):lower()
        local jobGrade = tonumber(playerData.PlayerData.job.grade) or 0
        print(string.format("[Server Debug] Player %s job: %s | grade: %d", source, jobName, jobGrade))
        return jobName
    end
    return ""
end)

--------------------------------------------------------------------------------
-- Callback: Check if Player Has the Clamp Item
-- Uses ox_inventory to verify that the player has the item defined in Config.
--------------------------------------------------------------------------------
lib.callback.register("wheelclamp:server:hasClampItem", function(source)
    local item = exports.ox_inventory:GetItem(source, Config.ItemName, nil, true)
    print(string.format("[Server Debug] hasClampItem for player %s: %s", source, tostring(item)))
    return item ~= nil
end)

--------------------------------------------------------------------------------
-- Clamp State Storage
-- This table stores clamp state for vehicles. It is synchronized with clients.
--------------------------------------------------------------------------------
local clampedVehicles = {}

--------------------------------------------------------------------------------
-- Callback: Apply Clamp
-- Validates player authorization, removes the clamp item from inventory,
-- updates clamp state, and notifies clients.
--------------------------------------------------------------------------------
lib.callback.register("wheelclamp:server:applyClamp", function(source, vehicleNetId, bone)
    local src = source
    print("[WheelClamp Debug] applyClamp called for player: " .. src)
    
    local playerData = GetPlayerData(src)
    if not playerData then 
        print("[WheelClamp Debug] Player data not found for player " .. src)
        return false, "Player not found"
    end

    local jobName = tostring(playerData.PlayerData.job.name):lower()
    local jobGrade = tonumber(playerData.PlayerData.job.grade) or 0
    local required = Config.ApplyClampAllowedJobs[jobName]
    if not required or jobGrade < required then
        print(string.format("[WheelClamp Debug] Player %s (job: %s, grade: %d) is not authorized to apply clamp", src, jobName, jobGrade))
        return false, "Not authorized to apply clamp"
    end

    local hasItem = exports.ox_inventory:GetItem(src, Config.ItemName, nil, true) ~= nil
    if not hasItem then
        print(string.format("[WheelClamp Debug] Player %s does not have the clamp item!", src))
        return false, "Missing clamp item"
    end

    vehicleNetId = tonumber(vehicleNetId)
    if clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId].clamp then
        print(string.format("[WheelClamp Debug] Vehicle %d already clamped", vehicleNetId))
        return false, "Vehicle already clamped"
    end

    -- Remove the clamp item from the player's inventory.
    local removalSuccess = playerData.Functions.RemoveItem(Config.ItemName, 1)
    if not removalSuccess then
        print(string.format("[WheelClamp Debug] Failed to remove clamp item for player %s", src))
        return false, "Failed to remove clamp item"
    end

    clampedVehicles[vehicleNetId] = { clamp = true, bone = bone, undriveable = true }
    local bagName = "entity:" .. vehicleNetId
    local stateData = { clamp = true, bone = bone, undriveable = true }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
    print(string.format("[WheelClamp Debug] Clamp applied successfully for vehicle %d by player %s", vehicleNetId, src))
    return true
end)

--------------------------------------------------------------------------------
-- Callback: Remove Clamp
-- Validates authorization, returns the clamp item to the player,
-- clears the clamp state, and notifies clients.
--------------------------------------------------------------------------------
lib.callback.register("wheelclamp:server:removeClamp", function(source, vehicleNetId, bone)
    local src = source
    local playerData = GetPlayerData(src)
    if not playerData then 
        print("[WheelClamp Debug] Player data not found for player " .. src)
        return false, "Player not found"
    end

    local jobName = tostring(playerData.PlayerData.job.name):lower()
    local jobGrade = tonumber(playerData.PlayerData.job.grade) or 0
    local required = Config.RemoveClampAllowedJobs[jobName]
    if not required or jobGrade < required then
        print(string.format("[WheelClamp Debug] Player %s (job: %s, grade: %d) is not authorized to remove clamp", src, jobName, jobGrade))
        return false, "Not authorized to remove clamp (insufficient grade)"
    end

    vehicleNetId = tonumber(vehicleNetId)
    if not (clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId].clamp) then
        print(string.format("[WheelClamp Debug] Vehicle %d is not clamped", vehicleNetId))
        return false, "Vehicle is not clamped"
    end

    local addSuccess = playerData.Functions.AddItem(Config.ItemName, 1)
    if not addSuccess then
        print(string.format("[WheelClamp Debug] Failed to add clamp item back to player %s", src))
        return false, "Failed to add clamp item back to player"
    end

    clampedVehicles[vehicleNetId] = nil
    local bagName = "entity:" .. vehicleNetId
    local stateData = { clamp = false, bone = "", undriveable = false }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, bone)
    print(string.format("[WheelClamp Debug] Clamp removed successfully for vehicle %d by player %s", vehicleNetId, src))
    return true
end)

--------------------------------------------------------------------------------
-- Event: Restore Clamp State
-- When a vehicle streams in, restore its clamp state from the stored state.
--------------------------------------------------------------------------------
RegisterNetEvent("wheelclamp:server:RestoreClamp", function(vehicleNetId)
    vehicleNetId = tonumber(vehicleNetId)
    local bagName = "entity:" .. vehicleNetId
    if clampedVehicles[vehicleNetId] then
        local stateData = clampedVehicles[vehicleNetId]
        SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
        TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, stateData.clamp, stateData.bone)
        print(string.format("[WheelClamp Debug] Restored clamp state for vehicle %d: clamp=%s, bone=%s", vehicleNetId, tostring(stateData.clamp), stateData.bone))
    else
        local stateData = { clamp = false, bone = "", undriveable = false }
        SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
        TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, "")
        print(string.format("[WheelClamp Debug] Set default unclamped state for vehicle %d", vehicleNetId))
    end
end)

print("[Server] Finished loading server.lua")
