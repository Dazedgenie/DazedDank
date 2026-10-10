-- The "Dazed Dank debug" right-click submenu: showcase setups for screenshots, test kits, plant and time skips,
-- water and smoker state. Shown in debug mode or to staff; the server checks again, so showing it grants nothing.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local DebugMenu = {}
CannabisMod.DebugMenu = DebugMenu

-- Showcase setups, spawned around the clicked square (server/CannabisMod/CannabisShowcase.lua).
DebugMenu.SHOWCASES = {
    { "seedling", "Seedlings under lamps" },
    { "veg", "Vegetative under lamps" },
    { "flower", "Flowering under lamps" },
    { "ripe", "Ready to harvest" },
    { "hydro", "Hydro bench (DWC, RDWC, flood table)" },
    { "drying", "Drying and curing" },
}

DebugMenu.KITS = {
    { "debugGiveSeeds", "Test seeds (2 female, 1 male per strain)" },
    { "debugGrowKit", "Grow kit (bags, soil, lamps, nutrients)" },
    { "debugHydroKit", "Hydro kit" },
    { "debugCloningKit", "Cloning kit" },
    { "debugDryingKit", "Drying kit" },
    { "debugSmokeKit", "Smoking kit" },
}

local function send(player, command, args)
    sendClientCommand(player, Config.COMMAND_MODULE, command, args or {})
end

local function at(square, extra)
    local a = { x = square:getX(), y = square:getY(), z = square:getZ() }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

local function submenu(context, parent, label)
    local head = parent:addOption(label)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(head, sub)
    return sub
end

--- Adds the submenu. `plot` is the cannabis plant on the square, if any.
function DebugMenu.add(player, context, square, plot)
    if not Config.debugAllowed(player) then return end
    local menu = submenu(context, context, "Dazed Dank debug")

    local show = submenu(context, menu, "Showcase setup")
    for _, s in ipairs(DebugMenu.SHOWCASES) do
        show:addOption(s[2], player, send, "debugShowcase", at(square, { setup = s[1] }))
    end

    local kits = submenu(context, menu, "Give kit")
    for _, k in ipairs(DebugMenu.KITS) do
        kits:addOption(k[2], player, send, k[1], {})
    end

    if plot then
        local plant = submenu(context, menu, "This plant")
        plant:addOption("Next stage", player, send, "debugNextStage", at(square))
        plant:addOption("Quality +20", player, send, "debugBoostQuality", at(square, { amount = 20 }))
        plant:addOption("Max quality", player, send, "debugBoostQuality", at(square, { amount = "max" }))
    end

    local time = submenu(context, menu, "Skip time")
    time:addOption("Racks and jars: +24 hours", player, send, "debugAdvanceStations", { hours = 24 })
    time:addOption("Finish rooting (cuttings in soil)", player, send, "debugFinishRooting", {})

    menu:addOption("Fill reservoirs and drip tanks, water pots nearby", player, send, "debugFillWater", {})

    local use = submenu(context, menu, "Smoker state")
    use:addOption("Dependent (tolerance 60, dependency 80, 48 h clean)", player, send, "debugUseState", { tol = 60, dep = 80, hoursAgo = 48 })
    use:addOption("Reset tolerance and dependency", player, send, "debugUseState", { tol = 0, dep = 0, hoursAgo = 0 })
end

return DebugMenu
