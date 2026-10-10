-- Stops a sow action from starting on a pot that is unfilled, not for this crop, or already has a plant in it (the server checks too).

require "CannabisMod/CannabisConfig"
require "Farming/TimedActions/ISSeedActionNew"

local Config = CannabisMod.Config

local Guard = {}
CannabisMod.SowGuard = Guard

--- True if the plot is one of our pots (by its sprite) or the seed is cannabis, so vanilla crops in vanilla furrows are left alone.
function Guard.ours(plant, typeOfSeed)
    if typeOfSeed == Config.CROP_TYPE then return true end
    local sprite = plant and plant.spriteName
    return sprite ~= nil and Config.bagFromSprite(sprite) ~= nil
end

--- True when something is already growing on the plot. Reads the live state every call, since another queued action may have just sown it.
function Guard.occupied(plant, typeOfSeed)
    if not plant or not Guard.ours(plant, typeOfSeed) then return false end
    if plant.updateFromIsoObject then pcall(plant.updateFromIsoObject, plant) end
    return plant.state ~= nil and plant.state ~= "plow"
end

if ISSeedActionNew and ISSeedActionNew.isValid then
    local originalIsValid = ISSeedActionNew.isValid

    --- True if the target plot is a bag or bucket that still needs soil or a medium.
    local function targetUnfilled(target)
        local sq = getCell():getGridSquare(target.x, target.y, target.z)
        local plot = sq and CFarmingSystem.instance:getLuaObjectOnSquare(sq)
        return plot ~= nil and Config.bagIsUnfilled(plot.spriteName) == true
    end

    -- isValid runs every tick of the action, so the soil and cannabis checks are cached once per action; occupancy is re-read each time.
    function ISSeedActionNew:isValid()
        if self.ddUnfilled == nil then
            local ok, unfilled = pcall(targetUnfilled, self.plant)
            self.ddUnfilled = ok and unfilled
        end
        if self.ddUnfilled then return false end
        -- Containers take cannabis, and the vanilla crops Garden Crops allows there.
        if self.ddNotCannabis == nil then
            local p = self.plant
            local sq = p and getCell():getGridSquare(p.x, p.y, p.z)
            local plot = sq and CFarmingSystem.instance:getLuaObjectOnSquare(sq)
            local kind = plot and Config.bagFromSprite(plot.spriteName)
            self.ddNotCannabis = self.typeOfSeed ~= Config.CROP_TYPE and kind ~= nil and not Config.canSowVanilla(self.typeOfSeed, kind)
        end
        if self.ddNotCannabis then return false end
        -- Never sow over a plant that is already there.
        local ok, occupied = pcall(Guard.occupied, self.plant, self.typeOfSeed)
        if ok and occupied then return false end
        return originalIsValid(self)
    end
end
