Config = {}

-- Draw zone borders in-world and enable the /tramseattest command
Config.Debug = false

-- Play the cable-car audio
Config.Sounds = true

-- Options: 'ox_textui', 'ox_target', 'custom'
Config.Interaction = 'ox_textui'

Config.TextUI = {
    key      = 'E',            -- ox_lib keybind default (rebindable in settings)
    keyLabel = 'E',            -- shown in the prompt, e.g. "[E] - Board the tramway"
    position = 'center',
    icon     = 'cable-car',
    style = {
        borderRadius    = 0,
        backgroundColor = '#48BB78',
        color           = 'white',
    },
}

-- Key to step out while riding (ox_lib keybind)
Config.ExitKey = 'X'

-- Motion / timing (whole cycle derived from these)
Config.Timings = {
    idle           = 30000,  -- ms parked at each station (must be > 2 * doorTransition)
    travel         = 80000,  -- ms to traverse the line one way
    doorTransition = 1500,   -- ms for doors to open / close
}

-- Cable sag: long segments droop slightly in the middle
Config.SagMinLength = 30.0
Config.SagAmount    = 0.25

-- Borders of zone where users  will start to see the cable cars
Config.Zone = {
    points = {
        vec3(-846.6,  5485.65, 450.0),
        vec3(499.52,  5502.42, 450.0),
        vec3(503.06,  5659.14, 450.0),
        vec3(-811.63, 5762.16, 450.0),
    },
    thickness = 900.0,
}

-- Map blips (toggle with enabled)
Config.Blip = {
    enabled = false,
    sprite  = 36,
    color   = 2,
    scale   = 0.8,
    label   = 'Pala Springs Tramway',
    coords  = {
        vec3(-740.911, 5599.341, 47.25),  -- bottom station
        vec3(446.291,  5566.377, 786.75), -- top station
    },
}

Config.Models = {
    car   = `p_cablecar_s`,
    doorL = `p_cablecar_s_door_l`,
    doorR = `p_cablecar_s_door_r`,
}

-- Fallback seat if Config.Seats is empty (offset from cabin origin, z = floor)
Config.SeatOffset = vec3(0.0, 0.0, -5.3)

-- Seat spots (offsets from cabin origin). Entry count = per-car capacity;
-- riders claim the first free spot. Run /tramseattest (Debug) to preview.
Config.Seats = {
    vec3(-0.5,  0.9, -5.3),  -- front-left
    vec3( 0.5,  0.9, -5.3),  -- front-right
    vec3(-0.5,  0.0, -5.3),  -- mid-left
    vec3( 0.5,  0.0, -5.3),  -- mid-right
    vec3(-0.5, -0.9, -5.3),  -- back-left
    vec3( 0.5, -0.9, -5.3),  -- back-right
}

-- Board prompt offset from the cabin (last number = up/down)
Config.InteractOffset = vec3(0.0, 0.0, -5.3)

-- Stations a player logging out mid-ride is set down at (closest one is used)
Config.LogoutReturns = {
    vec3(-745.3, 5595.2, 41.6),   -- bottom station
    vec3(446.3, 5572.0, 781.2),  -- top station
}

-- Cars (one per track): heading + lateral offset to centre on the cable
Config.Cars = {
    [0] = { track = 0, heading = 270.0, offset = vec3(-0.2, 0.0, 0.0) },
    [1] = { track = 1, heading = 90.0,  offset = vec3(-0.2, 0.0, 0.0) },
}

-- Tracks (ordered node lists: [0] bottom->top, [1] top->bottom)
Config.Tracks = {
    [0] = { -- Left skytram (from bottom)
        vec3(-740.911, 5599.341, 47.25),
        vec3(-739.557, 5599.346, 46.997),
        vec3(-581.009, 5596.517, 77.379),
        vec3(-575.717, 5596.388, 79.22),
        vec3(-273.805, 5590.844, 240.795),
        vec3(-268.707, 5590.744, 243.395),
        vec3(6.896,    5585.668, 423.614),
        vec3(11.774,   5585.591, 426.711),
        vec3(236.82,   5581.445, 599.642),
        vec3(241.365,  5581.369, 603.183),
        vec3(412.855,  5578.216, 774.401),
        vec3(417.541,  5578.124, 777.688),
        vec3(444.93,   5577.589, 786.535),
        vec3(446.288,  5577.59,  786.75),
    },
    [1] = { -- Right skytram (from top)
        vec3(446.291,  5566.377, 786.75),
        vec3(444.937,  5566.383, 786.551),
        vec3(417.371,  5567.001, 777.708),
        vec3(412.661,  5567.085, 774.439),
        vec3(241.31,   5570.594, 603.137),
        vec3(236.821,  5570.663, 599.561),
        vec3(11.35,    5575.298, 426.629),
        vec3(6.575,    5575.391, 423.57),
        vec3(-268.965, 5580.996, 243.386),
        vec3(-273.993, 5581.124, 240.808),
        vec3(-575.898, 5587.286, 79.251),
        vec3(-581.321, 5587.4,   77.348),
        vec3(-739.646, 5590.614, 47.006),
        vec3(-740.97,  5590.617, 47.306),
    },
}