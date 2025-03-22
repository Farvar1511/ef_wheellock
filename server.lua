lib.print.debug("[Server] Starting server.lua for ef-wheellock")

local clampedVehicles = {} -- table indexed by network ID

lib.callback.register("wheelclamp:server:check_inventory", function(source, itemName)
    local player = exports.qbx_core:GetPlayer(source)
    if player then
        local item = player.Functions.GetItemByName(itemName)
        return item ~= nil
    end
    return false
end)

lib.callback.register("wheelclamp:server:getClampState", function(source, vehicleNetId)
    vehicleNetId = tonumber(vehicleNetId)
    return clampedVehicles[vehicleNetId] or {}
end)

RegisterNetEvent("wheelclamp:server:clamp_applied", function(vehicleNetId, bone)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    vehicleNetId = tonumber(vehicleNetId)
    if clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId].clamp then
        exports.qbx_core:Notify(src, "This vehicle already has a clamp applied.", "error", 5000)
        return
    end
    local removalSuccess = player.Functions.RemoveItem("wheel_clamp", 1)
    if not removalSuccess then
        exports.qbx_core:Notify(src, "Failed to remove clamp item.", "error", 5000)
        return
    end
    -- Update state: clamp true, record the bone, undriveable always true.
    clampedVehicles[vehicleNetId] = { clamp = true, bone = bone, undriveable = true }
    local bagName = "entity:" .. vehicleNetId
    local stateData = { clamp = true, bone = bone, undriveable = true }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    lib.print.debug(("[Server] Clamp applied on vehicle %d, bone: %s"):format(vehicleNetId, bone))
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, true, bone)
end)

RegisterNetEvent("wheelclamp:server:clamp_removed", function(vehicleNetId, bone)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    vehicleNetId = tonumber(vehicleNetId)
    if not (clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId].clamp) then
        exports.qbx_core:Notify(src, "This vehicle is not clamped.", "error", 5000)
        return
    end
    local addSuccess = player.Functions.AddItem("wheel_clamp", 1)
    if not addSuccess then
        exports.qbx_core:Notify(src, "Failed to add clamp item to inventory.", "error", 5000)
        return
    end
    clampedVehicles[vehicleNetId] = nil
    local bagName = "entity:" .. vehicleNetId
    local stateData = { clamp = false, bone = "", undriveable = false }
    SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
    lib.print.debug(("[Server] Clamp removed from vehicle %d, bone: %s"):format(vehicleNetId, bone))
    TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, bone)
end)

RegisterNetEvent("wheelclamp:server:RestoreClamp")
AddEventHandler("wheelclamp:server:RestoreClamp", function(vehicleNetId)
    vehicleNetId = tonumber(vehicleNetId)
    local bagName = "entity:" .. vehicleNetId
    if clampedVehicles[vehicleNetId] then
        local stateData = clampedVehicles[vehicleNetId]
        SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
        lib.print.debug(("[Server] Restoring clamp state for Vehicle %d, bone: %s, clamp=%s, undriveable=%s"):format(vehicleNetId, stateData.bone, tostring(stateData.clamp), tostring(stateData.undriveable)))
        TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, stateData.clamp, stateData.bone)
    else
        local stateData = { clamp = false, bone = "", undriveable = false }
        SetStateBagValue(bagName, "efWheelClamp", json.encode(stateData), true)
        lib.print.debug(("[Server] Setting default unclamped state for Vehicle %d"):format(vehicleNetId))
        TriggerClientEvent("wheelclamp:client:ForceApplyClamp", -1, vehicleNetId, false, "")
    end
end)

RegisterNetEvent("wheelclamp:server:clamp_checked", function(vehicleNetId)
    local src = source
    vehicleNetId = tonumber(vehicleNetId)
    local status = "NOT clamped"
    if clampedVehicles[vehicleNetId] and clampedVehicles[vehicleNetId].clamp then
        status = "CLAMPED on " .. clampedVehicles[vehicleNetId].bone
    end
    TriggerClientEvent("chat:addMessage", src, { args = { "Server Clamp Status", ("Vehicle %d is %s."):format(vehicleNetId, status) } })
end)

lib.print.debug("[Server] Finished loading server.lua")
