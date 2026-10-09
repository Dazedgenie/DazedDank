-- What the drying rack, curing jar and curing barrel will take, enforced by the game's own container check
-- (ItemContainer:isItemAllowed), so every way of moving items respects it: drag and drop, transfer all, other mods.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisWorld"

local Config = CannabisMod.Config
local World = CannabisMod.World

-- The game looks these up by name, so they live in a global table.
DazedDankAccept = DazedDankAccept or {}
local Accept = DazedDankAccept

Accept.RACK = "DazedDankAccept.Rack"
Accept.BUDS = "DazedDankAccept.Buds"

--- Racks hold whole plants only, wet or dried.
function Accept.Rack(container, item)
    return item ~= nil and Config.isHangingPlant(item:getFullType())
end

--- Jars and barrels hold buds only.
function Accept.Buds(container, item)
    return item ~= nil and item:getFullType() == Config.Drying.BUD_ITEM
end

--- The accept function for a sprite name, or nil for anything that isn't a rack or barrel.
function Accept.forName(name)
    if not name then return nil end
    if Config.Drying.RACK_SPRITES[name] then return Accept.RACK end
    if name == Config.Drying.BARREL_SPRITE then return Accept.BUDS end
    return nil
end

--- The accept function a placed object's containers need, by its sprite, or nil for anything else.
function Accept.forObject(obj)
    local sprite = obj and obj.getSprite and obj:getSprite()
    return Accept.forName(sprite and sprite:getName())
end

--- Put an accept function on every container of an object.
local function tagWith(obj, fn)
    if not fn then return false end
    local count = obj.getContainerCount and obj:getContainerCount() or 0
    for i = 0, count - 1 do
        local container = obj:getContainerByIndex(i)
        if container and container:getAcceptItemFunction() ~= fn then container:setAcceptItemFunction(fn) end
    end
    return true
end

--- Put the right accept function on every container of a rack or barrel object (they aren't saved, so this runs on load).
function Accept.tag(obj)
    return tagWith(obj, Accept.forObject(obj))
end

--- Tag the racks and barrels standing on a square.
function Accept.tagSquare(square)
    local objects = square and square:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do Accept.tag(objects:get(i)) end
end

--- Tag the racks and barrels among a loaded square's objects (the shared square pass found them).
function Accept.onLoad(square, hits)
    for i = 1, hits.n do
        local info = hits.info[i]
        if info.rack or info.barrel then tagWith(hits.obj[i], Accept.forName(hits.name[i])) end
    end
end

World.onSquareLoad("rack tagging", Accept.onLoad)
World.onObjectAdded("rack tagging", function(obj, name, info)
    if info.rack or info.barrel then tagWith(obj, Accept.forName(name)) end
end)

return Accept
