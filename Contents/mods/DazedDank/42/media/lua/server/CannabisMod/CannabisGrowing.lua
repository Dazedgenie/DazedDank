-- Player actions for plant care: feeding nutrients, plus the debug grow kit.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Net      = CannabisMod.Net
local Seeds    = CannabisMod.Seeds
local Registry = CannabisMod.Registry
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers

local FEED_MESSAGES = {
    good  = "The plant looks happier",
    wrong = "That's the wrong food for this stage",
    burn  = "Nutrient burn! Once per stage is plenty",
}

commands.feedPlant = function(player, args)
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    local itemType = Config.NUTRIENT_ITEMS[args.nutrient]
    if not (x and y and z and itemType) or not SC.isNear(player, x, y, z) then return end

    local plant = Registry.getPlant(x, y, z)
    if not plant or plant.dead or plant.rooting then
        Net.notify(player, "There's nothing here to feed")
        return
    end
    -- Seedlings are too young; ripe plants are flushed (no food).
    if plant.stage <= Config.STAGE.Seedling or plant.stage >= Config.STAGE.Ripe then
        Net.notify(player, "This plant doesn't need feeding right now")
        return
    end

    local bottle = Seeds.findItem(player:getInventory(), function(item)
        return item:getFullType() == itemType
    end)
    if not bottle then
        Net.notify(player, "You have no " .. args.nutrient .. " nutrients")
        return
    end

    -- One bottle is one feeding.
    local container = bottle:getContainer()
    if container then
        container:Remove(bottle)
        sendRemoveItemFromContainer(container, bottle)
    end

    local result = Registry.feed(plant, args.nutrient)
    Net.notify(player, FEED_MESSAGES[result] or "Fed the plant")
end

commands.debugGrowKit = function(player, args)
    if not (isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")) then
        return
    end
    local give = CannabisMod.Farming.giveItems
    give(player, Config.NUTRIENT_ITEMS.Veg, 2)
    give(player, Config.NUTRIENT_ITEMS.Bloom, 2)
    for _, lamp in ipairs({ "GrowLampBasic", "GrowLampPro", "GrowLampLargeBasic", "GrowLampLargePro", "GrowFloodBasic", "GrowFloodPro" }) do
        give(player, "CannabisMod." .. lamp, 1)
    end
    give(player, Config.Timer.ITEM, 2)
    give(player, Config.GrowBag.small.furnItem, 2)
    give(player, Config.GrowBag.large.furnItem, 2)
    give(player, "CannabisMod.SoilSack", 6)
    Net.notify(player, "Gave 2 veg, 2 bloom, all 6 grow lamps, 2 light timers, 2 small and 2 large bags, 6 soil sacks")
end
