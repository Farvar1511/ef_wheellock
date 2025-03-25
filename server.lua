local config = require('config')

lib.callback.register('EF-Wheelclamp:Server:ApplyClamp', function(source, netId, bone)
    lib.print.debug('applyClamp called for player: ' .. source)

    local player = exports.qbx_core:GetPlayer(source)
    if not player then
        return false, 'Player not found'
    end

    local required = config.applyClampAllowedJobs[player.PlayerData.job.name]

    if not required or player.PlayerData.job.grade.level < required then
        lib.print.debug(('Player %s (job: %s, grade: %d) is not authorized to apply clamp'):format(source, player.PlayerData.job.name, player.PlayerData.job.grade.level))
        return false, 'Not authorized to apply clamp'
    end

    local hasItem = exports.ox_inventory:Search(source, 'count', config.itemName) > 0
    if not hasItem then
        lib.print.debug(('Player %s does not have the clamp item!'):format(source))
        return false, 'Missing clamp item'
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or not DoesEntityExist(vehicle) then
        lib.print.debug(('Vehicle %d does not exist'):format(netId))
        return false, 'Vehicle does not exist'
    end

    local entityState = Entity(vehicle).state

    if entityState.wheelclamp then
        lib.print.debug(('Vehicle %d already clamped'):format(netId))
        return false, 'Vehicle already clamped'
    end

    local result = exports.ox_inventory:RemoveItem(source, config.itemName, 1)
    if not result then
        lib.print.debug(('Failed to remove clamp item for player %s'):format(source))
        return false, 'Failed to remove clamp item'
    end

    entityState:set('wheelclamp', bone, true)

    lib.print.debug(('Clamp applied successfully for vehicle %d by player %s'):format(netId, source))

    return true
end)

lib.callback.register('EF-Wheelclamp:Server:RemoveClamp', function(source, netId)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then
        lib.print.debug('Player data not found for player ' .. source)
        return false, 'Player not found'
    end

    local required = config.removeClampAllowedJobs[player.PlayerData.job.name]
    if not required or player.PlayerData.job.grade.level < required then
        lib.print.debug(('Player %s (job: %s, grade: %d) is not authorized to remove clamp'):format(source, player.PlayerData.job.name, player.PlayerData.job.grade.level))
        return false, 'Not authorized to remove clamp (insufficient grade)'
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or not DoesEntityExist(vehicle) then
        lib.print.debug(('Vehicle %d does not exist'):format(netId))
        return false, 'Vehicle does not exist'
    end

    local entityState = Entity(vehicle).state

    if not entityState.wheelclamp then
        lib.print.debug(('Vehicle %d is not clamped'):format(netId))
        return false, 'Vehicle is not clamped'
    end

    local result = exports.ox_inventory:AddItem(source, config.itemName, 1)
    if not result then
        lib.print.debug(('Failed to add clamp item back to player %s'):format(source))
        return false, 'Failed to add clamp item back to player'
    end

    entityState:set('wheelclamp', nil, true)

    lib.print.debug(('Clamp removed successfully for vehicle %d by player %s'):format(netId, source))

    return true
end)
