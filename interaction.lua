local OPTION_NAMES = { 'cablecar_board', 'cablecar_exit' }
local Adapters = {}

Adapters.ox_textui = (function()
    local registry = {}
    local started  = false
    local activeEntity, activeOption
    local currentText

    local cfg      = Config.TextUI or {}
    local keyLabel = cfg.keyLabel or cfg.key or 'E'
    local position = cfg.position or 'right-center'

    local function uiOptions(opt)
        return {
            position = position,
            icon     = opt.icon or cfg.icon,
            style    = cfg.style,
        }
    end

    local function hide()
        if currentText then
            lib.hideTextUI()
            currentText  = nil
            activeEntity = nil
            activeOption = nil
        end
    end

    local function startDriver()
        if started then return end
        started = true

        lib.addKeybind({
            name        = 'cablecar_interact',
            description = 'Interact with the cable car',
            defaultKey  = cfg.key or 'E',
            onPressed   = function()
                if activeOption and activeOption.onSelect then
                    activeOption.onSelect(activeEntity)
                end
            end,
        })

        CreateThread(function()
            while true do
                local sleep = 500
                local nextEnt, nextOpt, bestDist = nil, nil, math.huge

                if next(registry) then
                    local pcoords = GetEntityCoords(PlayerPedId())
                    for entity, reg in pairs(registry) do
                        if entity and DoesEntityExist(entity) then
                            local p = reg.offset
                                and GetOffsetFromEntityInWorldCoords(entity, reg.offset.x, reg.offset.y, reg.offset.z)
                                or  GetEntityCoords(entity)
                            local d = #(pcoords - p)
                            if d <= reg.distance and d < bestDist then
                                for _, o in ipairs(reg.options) do
                                    if not o.canInteract or o.canInteract(entity) then
                                        nextEnt, nextOpt, bestDist = entity, o, d
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                if nextOpt then
                    sleep        = 200
                    activeEntity = nextEnt
                    activeOption = nextOpt
                    local text = ('[%s] - %s'):format(keyLabel, nextOpt.label)
                    if text ~= currentText then
                        currentText = text
                        lib.showTextUI(text, uiOptions(nextOpt))
                    end
                else
                    hide()
                end

                Wait(sleep)
            end
        end)
    end

    return {
        Add = function(entity, data)
            registry[entity] = {
                distance = data.distance or 2.5,
                offset   = data.offset,
                options  = data.options,
            }
            startDriver()
        end,
        Remove = function(entity)
            registry[entity] = nil
            if entity == activeEntity then hide() end
        end,
    }
end)()

Adapters.ox_target = {
    Add = function(entity, data)
        local options = {}
        for i, o in ipairs(data.options) do
            options[i] = {
                name        = o.name,
                icon        = o.icon,
                label       = o.label,
                distance    = data.distance or 2.5,
                canInteract = o.canInteract,
                onSelect    = o.onSelect,
            }
        end
        exports.ox_target:addLocalEntity(entity, options)
    end,
    Remove = function(entity)
        exports.ox_target:removeLocalEntity(entity, OPTION_NAMES)
    end,
}

Adapters.custom = {
    Add = function() end,
    Remove = function() end,
}

Interaction = Adapters[Config.Interaction] or Adapters.ox_textui