-- A tall cannabis plant's leaves cover the tiles behind it, so vanilla's watering cursor often lands on an empty furrow ("Furrow needs seeds").
-- If the hovered tile has no planted crop, the cursor looks one or two tiles in front for a planted cannabis plant instead.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local WaterCursor = {}
CannabisMod.WaterCursor = WaterCursor

local function plotOn(sq)
    return sq and CFarmingSystem and CFarmingSystem.instance and CFarmingSystem.instance:getLuaObjectOnSquare(sq) or nil
end

--- The square the watering cursor should act on: the hovered one, or a planted cannabis plant just in front of it.
function WaterCursor.target(sq)
    if not sq then return nil end
    local plot = plotOn(sq)
    if plot and plot.state == "seeded" then return sq end
    for k = 1, 2 do
        local front = getCell():getGridSquare(sq:getX() + k, sq:getY() + k, sq:getZ())
        local p = plotOn(front)
        if p and p.state == "seeded" and p.typeOfSeed == Config.CROP_TYPE then return front end
    end
    return sq
end

--- Wrap vanilla's water cursor check once, after vanilla's farming menu has loaded.
local function guardWaterCursor()
    if not (ISFarmingMenu and ISFarmingMenu.isWaterValid) or ISFarmingMenu.ddWaterGuarded then return end
    ISFarmingMenu.ddWaterGuarded = true
    local original = ISFarmingMenu.isWaterValid
    ISFarmingMenu.isWaterValid = function(self, ...)
        local cursor = ISFarmingMenu.cursor
        if cursor and cursor.sq then cursor.sq = WaterCursor.target(cursor.sq) end
        return original(self, ...)
    end
end
Events.OnGameStart.Add(guardWaterCursor)
