------------------------------------------------------------
-- server.lua
------------------------------------------------------------
local QBox = exports['qb-core']:GetCoreObject()
local json = json or require("json")

-- Table to track clamped state per vehicle.
-- For each vehicleNetId, this table will contain keys corresponding to tire bone names that are clamped.
local clampedVehicles = {}

-- Check if the player has a wheel clamp in their inventory.
QBox.Functions.CreateCallback("wheelclamp:server:CheckInventory", function(source, cb, itemName)
    local Player = QBox.Functions.GetPlayer(source)
    if Player then
        local item = Player.Functions.GetItemByName(itemName)
        cb(item ~= nil)
    else
        cb(false)
    end
end)

-- Apply Clamp: Remove a clamp item and record clamp state for a specific tire (bone)
RegisterNetEvent("wheelclamp:server:ApplyClamp")
AddEventHandler("wheelclamp:server:ApplyClamp", function(vehicleNetId, bone)
    local src = source
    print("[WheelClamp DEBUG] (Server) Received clamp request for NetID:", vehicleNetId, "bone:", bone, "from source:", src)
    local Player = QBox.Functions.GetPlayer(src)
    if not Player then 
        print("[WheelClamp DEBUG] (Server) ERROR: Player not found for source:", src)
        return 
    end

    clampedVehicles[vehicleNetId] = clampedVehicles[vehicleNetId] or {}
    if clampedVehicles[vehicleNetId][bone] then
        QBox.Functions.Notify(src, "This tire is already clamped.", "error", 5000)
        print("[WheelClamp DEBUG] (Server) Tire already clamped for vehicle NetID:", vehicleNetId, "bone:", bone)
        return
    end

    local removalSuccess = Player.Functions.RemoveItem("wheel_clamp", 1)
    print("[WheelClamp DEBUG] (Server) RemoveItem result for source", src, ":", removalSuccess)
    if not removalSuccess then
        QBox.Functions.Notify(src, "Failed to remove clamp item.", "error", 5000)
        print("[WheelClamp DEBUG] (Server) ERROR: Could not remove clamp item for source:", src)
        return
    end

    clampedVehicles[vehicleNetId][bone] = true
    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = true, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    print("[WheelClamp DEBUG] (Server) Clamp applied for vehicle NetID:", vehicleNetId, "bone:", bone)
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
end)

-- Remove Clamp: Add back a clamp item and remove clamp state for a specific tire (bone)
RegisterNetEvent("wheelclamp:server:RemoveClamp")
AddEventHandler("wheelclamp:server:RemoveClamp", function(vehicleNetId, bone)
    local src = source
    print("[WheelClamp DEBUG] (Server) Received clamp removal request for NetID:", vehicleNetId, "bone:", bone, "from source:", src)
    local Player = QBox.Functions.GetPlayer(src)
    if not Player then return end

    if not (clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId][bone]) then
        QBox.Functions.Notify(src, "This tire is not clamped.", "error", 5000)
        print("[WheelClamp DEBUG] (Server) Tire not clamped for vehicle NetID:", vehicleNetId, "bone:", bone)
        return
    end

    local addSuccess = Player.Functions.AddItem("wheel_clamp", 1)
    print("[WheelClamp DEBUG] (Server) AddItem result for source", src, ":", addSuccess)
    if not addSuccess then
        QBox.Functions.Notify(src, "Failed to add clamp item to inventory.", "error", 5000)
        print("[WheelClamp DEBUG] (Server) ERROR: Could not add clamp item for source:", src)
        return
    end

    clampedVehicles[vehicleNetId][bone] = nil
    if next(clampedVehicles[vehicleNetId]) == nil then
        clampedVehicles[vehicleNetId] = nil
    end

    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = false, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    print("[WheelClamp DEBUG] (Server) Clamp removed for vehicle NetID:", vehicleNetId, "bone:", bone)
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, bone)
end)

-- Sync Clamp: Update clamp state manually for a specific tire.
RegisterNetEvent("wheelclamp:server:SyncClamp")
AddEventHandler("wheelclamp:server:SyncClamp", function(vehicleNetId, clampApplied, bone)
    clampedVehicles[vehicleNetId] = clampedVehicles[vehicleNetId] or {}
    if clampApplied then
        clampedVehicles[vehicleNetId][bone] = true
    else
        clampedVehicles[vehicleNetId][bone] = nil
        if next(clampedVehicles[vehicleNetId]) == nil then
            clampedVehicles[vehicleNetId] = nil
        end
    end
    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = clampApplied, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
end)

-- Restore Clamp: When a vehicle streams in, reapply clamp(s) based on the server table.
RegisterNetEvent("wheelclamp:server:RestoreClamp")
AddEventHandler("wheelclamp:server:RestoreClamp", function(vehicleNetId)
    local bagName = "entity:" .. vehicleNetId
    if clampedVehicles[vehicleNetId] then
        for bone, _ in pairs(clampedVehicles[vehicleNetId]) do
            local stateData = { applied = true, bone = bone }
            SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
            TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
            print("[WheelClamp DEBUG] (Server) Restoring clamp for vehicle NetID:", vehicleNetId, "bone:", bone)
        end
    else
        print("[WheelClamp DEBUG] (Server) No clamp state to restore for vehicle NetID:", vehicleNetId)
    end
end)

-- Check Clamp: Report the clamp status (including bone) to the client.
RegisterNetEvent("wheelclamp:server:CheckClamp")
AddEventHandler("wheelclamp:server:CheckClamp", function(vehicleNetId)
    local src = source
    local bagName = "entity:" .. vehicleNetId
    local state = GetStateBagValue(bagName, "efWheelClamp")
    print("[WheelClamp DEBUG] (Server) CheckClamp: For vehicle", vehicleNetId, "state bag value:", state)
    local status = "NOT clamped"
    if state and type(state) == "string" and state ~= "" then
        local success, data = pcall(json.decode, state)
        if success and type(data) == "table" and data.applied and data.bone then
            status = "CLAMPED on " .. data.bone
        end
    end
    print("[WheelClamp DEBUG] (Server) CheckClamp: Vehicle", vehicleNetId, "is", status)
    TriggerClientEvent("chat:addMessage", src, { args = { "Server Clamp Status", "Vehicle " .. vehicleNetId .. " is " .. status .. "." } })
end)
