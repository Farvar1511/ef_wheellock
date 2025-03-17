------------------------------------------------------------
-- server.lua – Revised Best Practice Following Effective FiveM Lua Guidelines
------------------------------------------------------------
local QBox = exports['qb-core']:GetCoreObject()
local json = json or require("json")

-- Local data: Track clamp state per vehicle (by tire bone)
local clampedVehicles = {}

-- Check if player has a wheel clamp in inventory.
QBox.Functions.CreateCallback("wheelclamp:server:CheckInventory", function(source, cb, itemName)
    local Player = QBox.Functions.GetPlayer(source)
    cb(Player and (Player.Functions.GetItemByName(itemName) ~= nil) or false)
end)

RegisterNetEvent("wheelclamp:server:ApplyClamp")
AddEventHandler("wheelclamp:server:ApplyClamp", function(vehicleNetId, bone)
    local src = source
    print(string.format("[Server] Received clamp request for NetID: %s, bone: %s from source: %s", vehicleNetId, bone, src))
    local Player = QBox.Functions.GetPlayer(src)
    if not Player then
        print(string.format("[Server] ERROR: Player not found for source: %s", src))
        return
    end

    clampedVehicles[vehicleNetId] = clampedVehicles[vehicleNetId] or {}
    if clampedVehicles[vehicleNetId][bone] then
        QBox.Functions.Notify(src, "This tire is already clamped.", "error", 5000)
        print(string.format("[Server] Tire already clamped for vehicle NetID: %s, bone: %s", vehicleNetId, bone))
        return
    end

    local removalSuccess = Player.Functions.RemoveItem("wheel_clamp", 1)
    print(string.format("[Server] RemoveItem result for source %s: %s", src, tostring(removalSuccess)))
    if not removalSuccess then
        QBox.Functions.Notify(src, "Failed to remove clamp item.", "error", 5000)
        print(string.format("[Server] ERROR: Could not remove clamp item for source: %s", src))
        return
    end

    clampedVehicles[vehicleNetId][bone] = true
    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = true, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    print(string.format("[Server] Clamp applied for vehicle NetID: %s, bone: %s", vehicleNetId, bone))
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
end)

RegisterNetEvent("wheelclamp:server:RemoveClamp")
AddEventHandler("wheelclamp:server:RemoveClamp", function(vehicleNetId, bone)
    local src = source
    print(string.format("[Server] Received clamp removal request for NetID: %s, bone: %s from source: %s", vehicleNetId, bone, src))
    local Player = QBox.Functions.GetPlayer(src)
    if not Player then return end

    if not (clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId][bone]) then
        QBox.Functions.Notify(src, "This tire is not clamped.", "error", 5000)
        print(string.format("[Server] Tire not clamped for vehicle NetID: %s, bone: %s", vehicleNetId, bone))
        return
    end

    local addSuccess = Player.Functions.AddItem("wheel_clamp", 1)
    print(string.format("[Server] AddItem result for source %s: %s", src, tostring(addSuccess)))
    if not addSuccess then
        QBox.Functions.Notify(src, "Failed to add clamp item to inventory.", "error", 5000)
        print(string.format("[Server] ERROR: Could not add clamp item for source: %s", src))
        return
    end

    clampedVehicles[vehicleNetId][bone] = nil
    if not next(clampedVehicles[vehicleNetId]) then
        clampedVehicles[vehicleNetId] = nil
    end

    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = false, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    print(string.format("[Server] Clamp removed for vehicle NetID: %s, bone: %s", vehicleNetId, bone))
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, bone)
end)

RegisterNetEvent("wheelclamp:server:SyncClamp")
AddEventHandler("wheelclamp:server:SyncClamp", function(vehicleNetId, clampApplied, bone)
    clampedVehicles[vehicleNetId] = clampedVehicles[vehicleNetId] or {}
    if clampApplied then
        clampedVehicles[vehicleNetId][bone] = true
    else
        clampedVehicles[vehicleNetId][bone] = nil
        if not next(clampedVehicles[vehicleNetId]) then
            clampedVehicles[vehicleNetId] = nil
        end
    end
    local bagName = "entity:" .. vehicleNetId
    local stateData = { applied = clampApplied, bone = bone }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
end)

RegisterNetEvent("wheelclamp:server:RestoreClamp")
AddEventHandler("wheelclamp:server:RestoreClamp", function(vehicleNetId)
    local bagName = "entity:" .. vehicleNetId
    if clampedVehicles[vehicleNetId] then
        for bone, _ in pairs(clampedVehicles[vehicleNetId]) do
            local stateData = { applied = true, bone = bone }
            SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
            TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
            print(string.format("[Server] Restoring clamp for vehicle NetID: %s, bone: %s", vehicleNetId, bone))
        end
    else
        print(string.format("[Server] No clamp state to restore for vehicle NetID: %s", vehicleNetId))
    end
end)

RegisterNetEvent("wheelclamp:server:CheckClamp")
AddEventHandler("wheelclamp:server:CheckClamp", function(vehicleNetId)
    local src = source
    local bagName = "entity:" .. vehicleNetId
    local state = GetStateBagValue(bagName, "efWheelClamp")
    print(string.format("[Server] CheckClamp: For vehicle %s, state bag value: %s", vehicleNetId, tostring(state)))
    local status = "NOT clamped"
    if state and type(state) == "string" and state ~= "" then
        local success, data = pcall(json.decode, state)
        if success and type(data) == "table" and data.applied and data.bone then
            status = "CLAMPED on " .. data.bone
        end
    end
    print(string.format("[Server] CheckClamp: Vehicle %s is %s", vehicleNetId, status))
    TriggerClientEvent("chat:addMessage", src, { args = { "Server Clamp Status", "Vehicle " .. vehicleNetId .. " is " .. status .. "." } })
end)
