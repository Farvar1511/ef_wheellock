_G.Config = {}

-- Debug
Config.Debug = true

-- Base settings (adapt these as needed for your QBox server)
Config.Framework = 2
Config.FrameworkExport = 'qbx_core'
Config.Notify = 2
Config.Target = 2
Config.QBTargetExport = 'qbx-target'
Config.TargetIcon = 'fa-solid fa-podcast'

-- Inventory
Config.ItemName = 'wheel_clamp'

-- Job Permissions:
-- For applying clamps: only SASP is allowed (grade 0 or above).
Config.ApplyClampAllowedJobs = {
    sasp = 0  -- SASP can apply at any grade
}
-- For removing clamps: LSPD ("police") and BCSO ("bcso") require a minimum grade of 3, while SASP may remove at grade 0.
Config.RemoveClampAllowedJobs = {
    police = 3,  -- LSPD must be grade 3 or higher
    bcso   = 3,  -- BCSO must be grade 3 or higher
    sasp   = 0   -- SASP can remove clamp at grade 0
}

-- Animation times (in milliseconds)
Config.Times = {
    addClamp = 7000,
    removeClamp = 7000
}

-- Language / Notifications (optional)
Config.Language = {
    targetLabel = 'Apply/Remove Wheelclamp',
    displayText = 'Press ~INPUT_CONTEXT~ to apply/remove wheel clamp',
    noJob = 'You are not allowed to do that!',
    noItem = 'You do not have a wheel clamp!'
}

print("Config loaded successfully!")
