-- Keeps the Cloning Dome to cuttings, the Drying Rack to wet plants and the Curing Jar and Barrel to buds by wrapping
-- the item-transfer action.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSeeds"
require "TimedActions/ISInventoryTransferAction"

local Config = CannabisMod.Config
local Seeds  = CannabisMod.Seeds

local Dome = {}
CannabisMod.DomeContainer = Dome

--- The item that holds this container (a dome or a jar), or nil.
local function holderOf(container)
    return container:getContainingItem()
end

--- The dome item that owns this container, or nil if it isn't a dome.
function Dome.itemOf(container)
    if not container or not container.getContainingItem then return nil end
    local ok, owner = pcall(holderOf, container)
    if ok and owner and owner:getFullType() == Config.DOME_ITEM then
        return owner
    end
    return nil
end

--- Read which kind of special container this is: "jar", "dome", "rack", "barrel", or false.
local function readKind(container)
    local owner = container.getContainingItem and container:getContainingItem()
    if owner then
        local fullType = owner:getFullType()
        if fullType == Config.Drying.JAR_ITEM then return "jar" end
        if fullType == Config.DOME_ITEM then return "dome" end
    end
    local parent = container.getParent and container:getParent()
    local sprite = parent and parent.getSprite and parent:getSprite()
    local name = sprite and sprite:getName()
    if name and Config.Drying.RACK_SPRITES[name] then return "rack" end
    if name and name == Config.Drying.BARREL_SPRITE then return "barrel" end
    return false
end

--- Which kind of station or dome this container belongs to, or false for any other container.
function Dome.kindOf(container)
    if not container then return false end
    local ok, kind = pcall(readKind, container)
    return ok and kind or false
end

--- Why `item` can't go into a rack, jar or barrel, or nil if it can.
local function stationRefusal(container, item, ownerType)
    local D = Config.Drying
    local isRack = ownerType == "rack"
    local name = (ownerType == "barrel") and "barrel" or "jar"
    local ok = isRack and Config.isHangingPlant(item:getFullType()) or (not isRack and item:getFullType() == D.BUD_ITEM)
    if not ok then return isRack and "The rack only holds whole plants" or ("The " .. name .. " only holds buds") end
    if item:getContainer() == container then return nil end
    local cap = isRack and D.RACK_CAPACITY or (ownerType == "barrel" and D.BARREL_CAPACITY or D.JAR_CAPACITY)
    if container:getItems():size() >= cap then
        return (isRack and "This side of the rack is full (" or ("The " .. name .. " is full (")) .. cap .. ")"
    end
    return nil
end

--- Why `item` can't go into `container`, or nil if it can. Pass the container's kind when it is already known.
function Dome.refusal(container, item, kind)
    if kind == nil then kind = Dome.kindOf(container) end
    if not kind then return nil end
    if kind ~= "dome" then return stationRefusal(container, item, kind) end
    local seedKind = Seeds.kind(item)
    if seedKind ~= "cutting" and seedKind ~= "rooted" then
        return "The dome only holds cuttings"
    end
    -- Already inside this dome (moving it around): no count check.
    if item:getContainer() == container then return nil end
    if container:getItems():size() >= Config.Rooting.DOME_CAPACITY then
        return "The dome is full (" .. Config.Rooting.DOME_CAPACITY .. " cuttings)"
    end
    return nil
end

-- --------------------------------------------------------------------------
-- Hook the transfer action
-- --------------------------------------------------------------------------

local originalIsValid = ISInventoryTransferAction.isValid

-- isValid runs every tick of a transfer, so the destination's kind is worked out once per action.
function ISInventoryTransferAction:isValid()
    local dest = self.destContainer
    if self.dazedDankDest ~= dest then
        self.dazedDankDest = dest
        self.dazedDankKind = Dome.kindOf(dest)
    end
    local kind = self.dazedDankKind
    if kind then
        local why = Dome.refusal(dest, self.item, kind)
        if why then
            if not self.dazedDankWarned and self.character and self.character.setHaloNote then
                self.dazedDankWarned = true
                self.character:setHaloNote(why)
            end
            return false
        end
    end
    return originalIsValid(self)
end

-- Where a dome is: its own square when placed, else the player's.
function Dome.squareArgs(dome, player)
    local x, y, z = player:getX(), player:getY(), player:getZ()
    pcall(function()
        local wo = dome:getWorldItem()
        if wo and wo:getSquare() then
            local sq = wo:getSquare()
            x, y, z = sq:getX(), sq:getY(), sq:getZ()
        end
    end)
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

local originalPerform = ISInventoryTransferAction.perform
local pending = nil  -- { player, domeId, args, ticks }

function ISInventoryTransferAction:perform()
    local dome = Dome.itemOf(self.destContainer)
    local result = originalPerform(self)
    if dome and self.character then
        local args = Dome.squareArgs(dome, self.character)
        args.domeId = dome:getID()
        pending = { player = self.character, args = args, ticks = 90 }
    end
    return result
end

-- Give the item move a moment to reach the server, then ask it to start the
-- rooting clock for whatever is in the dome.
Events.OnTick.Add(function()
    if not pending then return end
    pending.ticks = pending.ticks - 1
    if pending.ticks <= 0 then
        sendClientCommand(pending.player, Config.COMMAND_MODULE, "domeSync", pending.args)
        pending = nil
    end
end)
