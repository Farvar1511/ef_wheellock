local clampConfig = {
    baspel_wheelclamp_suv = {
        wheel_lf = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(0.07, 0.20,  0.10), rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.06, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(0.07, -0.10, -0.20), rot = vector3(-80.0, 0.0, 0.0) },
    },
    baspel_wheelclamp_normal = {
        wheel_lf = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rf = { pos = vector3(-0.03, 0.20,  0.15), rot = vector3(80.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(-0.03, 0.20, -0.10), rot = vector3(10.0, 0.0, 0.0) },
        wheel_rr = { pos = vector3(-0.06, 0.20,  0.17), rot = vector3(80.0, 0.0, 0.0) },
    },
    baspel_wheelclamp_motorcycle = {
        wheel_lf = { pos = vector3(0.05, 0.0, -0.15), rot = vector3(-25.0, 0.0, 0.0) },
        wheel_lr = { pos = vector3(0.05, 0.0, -0.15), rot = vector3(-25.0, 0.0, 0.0) },
    },
}

return clampConfig
