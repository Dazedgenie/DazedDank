-- Other crops in grow bags and buckets: the plot keeps the pot's sprite and the crop is a separate object raised onto the soil,
-- so one set of vanilla crop sprites serves every pot.

if isClient() then return end

require "Farming/SPlantGlobalObject"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisCrop"

local Config = CannabisMod.Config
local Registry = CannabisMod.Registry
local CROP = Config.CROP_TYPE

local VegBags = {}
CannabisMod.VegBags = VegBags

--- The raised crop object on a square, or nil.
local function overlayOn(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj:getModData().ddVegOverlay then return obj end
    end
    return nil
end

local function lift(square, obj)
    pcall(function() square:transmitRemoveItemFromSquare(obj) end)
    pcall(function() square:RemoveTileObject(obj) end)
end

--- The crop sprite a plot should show above its pot, or nil when it holds cannabis, nothing, or isn't a pot.
function VegBags.wanted(luaObject)
    if not luaObject or luaObject.state == "plow" or luaObject.typeOfSeed == CROP or not luaObject.typeOfSeed then return nil end
    local bag = Registry.getBag(luaObject.x, luaObject.y, luaObject.z)
    if not (bag and Config.VEG_LIFT[bag]) then return nil end
    local ok, sprite = pcall(CannabisMod.vanillaSpriteName, luaObject)
    return ok and sprite or nil, bag
end

--- Make the raised crop object on a plot's square match the plot: add, swap or remove it.
function VegBags.sync(luaObject)
    local square = luaObject and luaObject.getSquare and luaObject:getSquare()
    if not square then return end
    local want, bag = VegBags.wanted(luaObject)
    local current = overlayOn(square)
    local currentName = current and current:getSprite() and current:getSprite():getName()
    if current and currentName == want then return end
    if current then lift(square, current) end
    if not want then return end
    -- A fresh object per change (rather than a re-sprite) so the client always draws the new stage.
    local obj = IsoObject.new(getCell(), square, want)
    obj:getModData().ddVegOverlay = true
    obj:setRenderYOffset(Config.VEG_LIFT[bag])
    square:AddTileObject(obj)
    pcall(function() obj:transmitCompleteItemToClients() end)
end

--- Take the raised crop object off a square (the pot is being picked up).
function VegBags.clear(square)
    local current = square and overlayOn(square)
    if current then lift(square, current) end
end

-- A harvested crop leaves the pot ready to plant again, as cannabis does; done on the next tick, after vanilla's harvest finishes.
local toReset = {}
Events.OnTick.Add(function()
    if #toReset == 0 then return end
    local list = toReset
    toReset = {}
    for _, luaObject in ipairs(list) do
        if luaObject.state == "harvested" and CannabisMod.GrowBags then pcall(CannabisMod.GrowBags.reset, luaObject) end
    end
end)

-- Every sprite change vanilla makes to a plot (sowing, growing, sickness, death, harvest) re-checks the raised crop.
local originalSetSpriteName = SPlantGlobalObject.setSpriteName
function SPlantGlobalObject:setSpriteName(spriteName)
    originalSetSpriteName(self, spriteName)
    if self.state == "harvested" and self.typeOfSeed ~= CROP and Registry.getBag(self.x, self.y, self.z) then
        toReset[#toReset + 1] = self
    end
    local ok, err = pcall(VegBags.sync, self)
    if not ok then print("[DazedDank] crop-in-pot layer failed: " .. tostring(err)) end
end

return VegBags
