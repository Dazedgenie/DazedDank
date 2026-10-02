-- Keeps the Cloning Dome to cuttings, the Drying Rack to wet plants and the Curing Jar to buds by wrapping
-- the item-transfer action.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisSeeds"
require "TimedActions/ISInventoryTransferAction"

local Config = CannabisMod.Config
local Seeds  = CannabisMod.Seeds

local Dome = {}
CannabisMod.DomeContainer = Dome

--- The dome item that owns this container, or nil if it isn't a dome.
function Dome.itemOf(container)
    if not container or not container.getContainingItem then return nil end
    local ok, owner = pcall(function() return container:getContainingItem() end)
    if ok and owner and owner:getFullType() == Config.DOME_ITEM then
        return owner
    end
    return nil
end

--- Which kind of station (rack or jar) this container belongs to, or nil.
local function stationOwner(container)
    if not container then return nil end
    local ok, kind = pcall(function()
        local owner = container.getContainingItem and container:getContainingItem()
        if owner and owner:getFullType() == Config.Drying.JAR_ITEM then return "jar" end
        local parent = container.getParent and container:getParent()
        local sprite = parent and parent.getSprite and parent:getSprite()
        if sprite and Config.Drying.RACK_SPRITES[sprite:getName()] then return "rack" end
        return nil
    end)
    return ok and kind or nil
end

--- Why `item` can't go into a rack or jar, or nil if it can.
local function stationRefusal(container, item, ownerType)
    local D = Config.Drying
    local isRack = ownerType == "rack"
    local ok = isRack and Config.isHangingPlant(item:getFullType()) or (not isRack and item:getFullType() == D.BUD_ITEM)
    if not ok then return isRack and "The rack only holds whole plants" or "The jar only holds buds" end
    if item:getContainer() == container then return nil end
    local cap = isRack and D.RACK_CAPACITY or D.JAR_CAPACITY
    if container:getItems():size() >= cap then
        return (isRack and "This side of the rack is full (" or "The jar is full (") .. cap .. ")"
    end
    return nil
end

--- Why `item` can't go into `container`, or nil if it can.
function Dome.refusal(container, item)
    local owner = stationOwner(container)
    if owner then return stationRefusal(container, item, owner) end
    local dome = Dome.itemOf(container)
    if not dome then return nil end
    local kind = Seeds.kind(item)
    if kind ~= "cutting" and kind ~= "rooted" then
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

function ISInventoryTransferAction:isValid()
    local why = Dome.refusal(self.destContainer, self.item)
    if why then
        if not self.dazedDankWarned and self.character and self.character.setHaloNote then
            self.dazedDankWarned = true
            self.character:setHaloNote(why)
        end
        return false
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
