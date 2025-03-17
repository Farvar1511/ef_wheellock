_G.Config = {}  -- Force Config to be global

-- Debug
Config.Debug = true

-- Base settings
Config.Framework = 2
Config.FrameworkExport = 'qb-core'
Config.Notify = 2
Config.Target = 2
Config.QBTargetExport = 'qbx-target'
Config.TargetIcon = 'fa-solid fa-podcast'

-- Allowed job (police only)
Config.AllowedJob = "police"

-- Animation times (in milliseconds)
Config.Times = {
    addClamp = 7000,    -- 7 seconds to apply the clamp
    removeClamp = 7000  -- 7 seconds to remove the clamp
}

-- Language / Notifications (optional)
Config.Language = {
    targetLabel = 'Apply/Remove Wheelclamp',
    displayText = 'Press ~INPUT_CONTEXT~ to apply/remove wheel clamp',
    noJob = 'You are not allowed to do that!',
    noItem = 'You do not have a wheel clamp!'
}

-- Inventory
Config.ItemName = 'wheel_clamp'

print("Config loaded successfully!")
