local config = require('config')
local TIRE_BONES = { "wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr" }
local wheelClamps = {}

local APPROACH_OFFSETS = {
    wheel_lf = vector3(-0.7, 0.1, 0.6),
    wheel_rf = vector3(0.8, 0.1, 0.6),
    wheel_lr = vector3(-0.7, 0.1, 0.6),
    wheel_rr = vector3(0.8, 0.1, 0.6)
}

local DEFAULT_OFFSET = vector3(-0.7, 0.1, 0.6)

local function getVehicleClampModel(vehicle)
    local vehClass = GetVehicleClass(vehicle)
    if vehClass == 8 then
        return "baspel_wheelclamp_motorcycle"
    elseif vehClass == 2 or vehClass == 9 then
        return "baspel_wheelclamp_suv"
    else
        return "baspel_wheelclamp_normal"
    end
end

local function getClosestTireBoneByPlayer(vehicle)
    local pedPos = GetEntityCoords(cache.ped)
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

local function smoothTurnToCoord(ped, x, y, z, duration)
    TaskTurnPedToFaceCoord(ped, x, y, z, duration)
    Wait(duration)
end

---Walks to a tire and applies an animation.
---@param vehicle number
---@param duration number
---@param bone string
---@param animLabel string
---@return boolean
local function walkToOffsetAndAnimate(vehicle, duration, bone, animLabel)
    if not bone then
        lib.notify({
            title = 'No tire specified.',
            type = 'error'
        })
        return false
    end

    local target, tirePos = getApproachPosForTire(vehicle, bone)
    if not (target and tirePos) then
        lib.notify({
            title = 'Failed to compute approach offset.',
            type = 'error'
        })
        return false
    end

    lib.print.debug(('Walking to approach tire %s'):format(bone))

    TaskGoToCoordAnyMeans(cache.ped, target.x, target.y, target.z, 1.0)

    local arrived = false
    local startTime = GetGameTimer()
    while GetGameTimer() - startTime < 10000 do
        if #(GetEntityCoords(cache.ped) - target) < 0.75 then
            arrived = true
            break
        end
        DisableAllControlActions(0)
        Wait(0)
    end

    lib.print.debug(('Arrived at approach tire %s'):format(bone))

    if not arrived then
        lib.notify({
            title = 'Timed out or path blocked.',
            type = 'error'
        })
        return false
    end

    lib.print.debug(('Smooth turn to tire %s'):format(bone))

    smoothTurnToCoord(cache.ped, tirePos.x, tirePos.y, tirePos.z, 1000)

    Wait(500)

    CreateThread(function()
        lib.progressBar({
            duration = duration,
            label = animLabel,
            disable = { move = true, combat = true },
            useWhileDead = false,
            canCancel = false
        })
    end)

    ExecuteCommand("e mechanic4")
    Wait(duration)
    ExecuteCommand("e c")

    return true
end

---Detaches a clamp from a vehicle.
---@param vehicle number
---@param bone string
local function detachClamp(vehicle, bone)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local key = tostring(netId) .. bone

    if wheelClamps[key] then
        lib.print.debug(('Removing clamp from vehicle %s at bone %s'):format(tostring(netId), bone))
        SetEntityAsMissionEntity(wheelClamps[key], true, true)
        DeleteEntity(wheelClamps[key])
        wheelClamps[key] = nil
    end

    SetVehicleUndriveable(vehicle, false)
end

---Attaches a clamp to a vehicle.
---@param vehicle number
---@param bone string
local function attachClamp(vehicle, bone)
    if not bone or not DoesEntityExist(vehicle) then
        lib.print.error("Attempted to attach clamp to invalid vehicle or bone.")
        return
    end

    lib.print.debug(('Attaching clamp to vehicle %s at bone %s'):format(tostring(NetworkGetNetworkIdFromEntity(vehicle)), bone))

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local key = tostring(netId) .. bone
    local idx = GetEntityBoneIndexByName(vehicle, bone)

    if not idx or idx == -1 then
        lib.notify({
            title = string.format("Invalid bone '%s' for vehicle netID: %s", bone, tostring(netId)),
            type = 'error'
        })
        return
    end

    lib.print.debug(('Getting clamp model for vehicle %s'):format(tostring(netId)))

    local modelName = getVehicleClampModel(vehicle)
    local modelHash = joaat(modelName)
    if not IsModelValid(modelHash) or not IsModelInCdimage(modelHash) then
        lib.notify({
            title = string.format("Clamp model '%s' does not exist.", modelName),
            type = 'error'
        })
        return
    end

    lib.print.debug(('Loading clamp model %s'):format(modelName))

    local start = GetGameTimer()
    while not HasModelLoaded(modelHash) do
        pcall(function()
            lib.requestModel(modelHash)
        end)

        Wait(0)

        if GetGameTimer() - start > 5000 then
            lib.notify({
                title = string.format("Clamp model '%s' failed to load.", modelName),
                type = 'error'
            })
            return
        end
    end

    lib.print.debug(('Getting clamp position for vehicle %s at bone %s'):format(tostring(netId), bone))

    local pos = GetWorldPositionOfEntityBone(vehicle, idx)

    local wheelConfig = config.clampConfig[modelName] or {}
    local offsets = wheelConfig[bone] or { pos = vector3(0, 0, 0), rot = vector3(0, 0, 0) }

    -- If a clamp already exists, reattach it.
    if wheelClamps[key] then
        AttachEntityToEntity(wheelClamps[key], vehicle, idx,
            offsets.pos.x, offsets.pos.y, offsets.pos.z,
            offsets.rot.x, offsets.rot.y, offsets.rot.z,
            false, false, false, false, 1, true)
        return
    end

    -- Otherwise, create a new clamp prop.
    local clampObj = CreateObject(modelHash, pos.x, pos.y, pos.z)
    if not clampObj or clampObj == 0 or not DoesEntityExist(clampObj) then
        lib.notify({
            title = 'Failed to create clamp prop.',
            type = 'error'
        })
        return
    end

    AttachEntityToEntity(clampObj, vehicle, idx,
        offsets.pos.x, offsets.pos.y, offsets.pos.z,
        offsets.rot.x, offsets.rot.y, offsets.rot.z,
        false, false, false, false, 1, true)

    SetEntityCollision(clampObj, false, false)

    wheelClamps[key] = clampObj

    SetVehicleUndriveable(vehicle, true)

    CreateThread(function()
        while DoesEntityExist(vehicle) and DoesEntityExist(clampObj) do
            if cache.vehicle and cache.vehicle == vehicle and cache.seat == -1 then
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end

            Wait(0)
        end
    end)

    CreateThread(function()
        while true do
            if not DoesEntityExist(clampObj) then
                break
            end

            if not DoesEntityExist(vehicle) then
                SetEntityAsMissionEntity(wheelClamps[key], true, true)
                DeleteEntity(clampObj)
                wheelClamps[key] = nil
                break
            end

            Wait(1000)
        end
    end)
end

---Applies a clamp to a vehicle.
---@param data number|OxTargetOption
local function applyClamp(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        lib.notify({
            title = 'No vehicle nearby!',
            type = 'error'
        })
        return
    end

    if exports.ox_inventory:Search('count', config.itemName) <= 0 then
        lib.notify({
            title = 'You do not have a wheel clamp!',
            type = 'error'
        })
        return
    end

    local bone = getClosestTireBoneByPlayer(vehicle)
    if not bone then
        lib.notify({
            title = 'Could not determine target tire.',
            type = 'error'
        })
        return
    end

    local success = walkToOffsetAndAnimate(vehicle, config.times.addClamp, bone, "Applying Parking Boot")

    if not success then
        lib.notify({
            title = 'Failed to complete animation.',
            type = 'error'
        })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local result, err = lib.callback.await('EF-Wheelclamp:Server:ApplyClamp', false, netId, bone)

    if not result then
        lib.notify({
            title = ("Clamp application failed: %s"):format(tostring(err)),
            type = 'error'
        })
        return
    end

    lib.notify({
        title = 'Clamp applied!',
        type = 'success'
    })
end

---Removes a clamp from a vehicle.
---@param data number|OxTargetOption
local function removeClamp(data)
    local vehicle = data.entity
    if not DoesEntityExist(vehicle) then
        lib.notify({
            title = 'No vehicle nearby!',
            type = 'error'
        })
        return
    end

    local bone = Entity(vehicle).state.wheelclamp
    if not bone then
        lib.notify({
            title = 'No clamped tire found.',
            type = 'error'
        })
        return
    end

    local success = walkToOffsetAndAnimate(vehicle, config.times.removeClamp, bone, "Removing Parking Boot")
    if not success then
        lib.notify({
            title = 'Failed to complete animation.',
            type = 'error'
        })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local result, err = lib.callback.await('EF-Wheelclamp:Server:RemoveClamp', false, netId, bone)

    if not result then
        lib.notify({
            title = ("Clamp removal failed: %s"):format(tostring(err)),
            type = 'error'
        })
        return
    end

    lib.notify({
        title = 'Clamp removed!',
        type = 'success'
    })
end

CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            label = "Apply Parking Boot",
            distance = 3.0,
            icon = 'fa-solid fa-road-lock',
            items = { config.itemName },
            groups = config.applyClampAllowedJobs,
            onSelect = applyClamp,
            canInteract = function(entity)
                if Entity(entity).state.wheelclamp then
                    return false
                end

                return true
            end
        },
        {
            label = "Remove Parking Boot",
            distance = 3.0,
            icon = 'fa-solid fa-road-lock',
            groups = config.removeClampAllowedJobs,
            onSelect = removeClamp,
            canInteract = function(entity)
                if not Entity(entity).state.wheelclamp then
                    return false
                end

                return true
            end
        }
    })
end)

AddStateBagChangeHandler("wheelclamp", "", function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)

    if Entity(vehicle).state.wheelclamp then
        detachClamp(vehicle, Entity(vehicle).state.wheelclamp)
        return
    end

    if value == nil then return end

    attachClamp(vehicle, value)
end)

CreateThread(function()
    for _, vehicle in pairs(GetGamePool('CVehicle')) do
        if Entity(vehicle).state.wheelclamp then
            attachClamp(vehicle, Entity(vehicle).state.wheelclamp)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= cache.resource then return end

    for _, clamp in pairs(wheelClamps) do
        if DoesEntityExist(clamp) then
            DeleteEntity(clamp)
        end
    end
end)
