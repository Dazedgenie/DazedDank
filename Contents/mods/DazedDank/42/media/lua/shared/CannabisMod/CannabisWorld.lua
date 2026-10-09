-- Shared world helpers: what each of our sprite names is, and one dispatcher for the square-load and object events,
-- so every square and object is read once however many parts of the mod want to look at it.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local World = CannabisMod.World or {}
CannabisMod.World = World

-- Every sprite of ours starts with this; anything else is rejected with one check.
World.PREFIX = "dazeddank_"

local find = string.find
local PREFIX = World.PREFIX

-- --------------------------------------------------------------------------
-- What a sprite name is
-- --------------------------------------------------------------------------

-- Curtain overlay sprite names as a set.
local CURTAINS = {}
for _, set in pairs(Config.Rooms.CURTAIN_SPRITES) do
    for _, sprite in pairs(set) do CURTAINS[sprite] = true end
end
World.CURTAINS = CURTAINS

-- Sprite name -> info table, or false when the name is ours but means nothing to these events.
local infoCache = {}

--- Work out what a sprite of ours is: overlay, bag, furn, panel, curtain, rack, barrel, lamp, gear, control, flood, drip.
local function buildInfo(name)
    local info, any = {}, false
    if Config.isOverlaySprite(name) then info.overlay = true any = true end
    local bag = Config.bagFromSprite(name)
    if bag then info.bag = bag any = true end
    local furn = Config.bagFromFurnSprite(name)
    if furn then info.furn = furn any = true end
    local panel = Config.Rooms.PANEL_SPRITES[name]
    if panel then info.panel = panel any = true end
    if CURTAINS[name] then info.curtain = true any = true end
    if Config.Drying.RACK_SPRITES[name] then info.rack = true any = true end
    if name == Config.Drying.BARREL_SPRITE then info.barrel = true any = true end
    local lamp = Config.Light.SPRITES[name]
    if lamp then info.lamp = lamp any = true end
    local gear = Config.Rooms.EQUIPMENT[name]
    if gear then info.gear = gear any = true end
    if name == Config.Hydro.CONTROL_SPRITE then info.control = true any = true end
    if name == Config.Hydro.FLOOD_SPRITE then info.flood = true any = true end
    if name == Config.Drip.SPRITE then info.drip = true any = true end
    return any and info or false
end

--- What a sprite name is to the mod (see buildInfo), or nil for anything not ours.
function World.info(name)
    if type(name) ~= "string" or find(name, PREFIX, 1, true) ~= 1 then return nil end
    local info = infoCache[name]
    if info == nil then
        info = buildInfo(name)
        infoCache[name] = info
    end
    return info or nil
end

--- The sprite name of an object, or nil.
function World.spriteName(obj)
    local sprite = obj:getSprite()
    return sprite and sprite:getName()
end
local spriteName = World.spriteName

--- The sprite name of any object, or nil when it has none or reading it fails.
function World.safeSpriteName(obj)
    local ok, name = pcall(spriteName, obj)
    if ok then return name end
    return nil
end

-- --------------------------------------------------------------------------
-- Power and finding objects on squares
-- --------------------------------------------------------------------------

--- True if this square has power for a lamp or pump: the grid, or the building's power indoors.
function World.isPowered(square)
    if square:haveElectricity() then return true end
    return (not square:isOutside()) and getWorld():isHydroPowerOn() or false
end

--- World.isPowered, but false instead of an error when the game API differs.
function World.isPoweredSafe(square)
    local ok, on = pcall(World.isPowered, square)
    return ok and on == true
end

--- The first object on a square whose sprite is `name`, or nil.
function World.findSprite(square, name)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        if sprite and sprite:getName() == name then return obj end
    end
    return nil
end

--- The first object on a square whose sprite name is a key of `set`, with that name and its value; nil when none is.
function World.findIn(square, set)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        local value = name and set[name]
        if value then return obj, name, value end
    end
    return nil
end

--- True if an object with this sprite stands on the tile, false if not, nil when the square isn't loaded.
function World.hasSprite(x, y, z, name)
    local square = getCell():getGridSquare(x, y, z)
    if not square then return nil end
    return World.findSprite(square, name) ~= nil
end

-- --------------------------------------------------------------------------
-- Event dispatcher
-- --------------------------------------------------------------------------

local loadHandlers, addHandlers, anyAddHandlers, removeHandlers, anyRemoveHandlers = {}, {}, {}, {}, {}

local function addHandler(list, label, fn, everySquare)
    list[#list + 1] = { label = label, fn = fn, all = everySquare == true }
end

--- fn(square, hits) runs for each loaded square holding something of ours; with `everySquare` it runs for every square.
--- hits = { n, obj = {}, name = {}, info = {} } is reused between squares, so handlers must not keep it.
function World.onSquareLoad(label, fn, everySquare) addHandler(loadHandlers, label, fn, everySquare) end

--- fn(obj, name, info) runs when an object of ours is added to the world.
function World.onObjectAdded(label, fn) addHandler(addHandlers, label, fn) end

--- fn(obj) runs for every object added, ours or not (keep it cheap).
function World.onAnyObjectAdded(label, fn) addHandler(anyAddHandlers, label, fn) end

--- fn(obj, name, info) runs just before an object of ours leaves the world.
function World.onObjectRemoved(label, fn) addHandler(removeHandlers, label, fn) end

--- fn(obj) runs just before any object leaves the world (keep it cheap).
function World.onAnyObjectRemoved(label, fn) addHandler(anyRemoveHandlers, label, fn) end

local warned = {}
local function failed(label, err)
    if warned[label] then return end
    warned[label] = true
    print("[DazedDank] " .. label .. " failed: " .. tostring(err))
end

local function newHits() return { n = 0, obj = {}, name = {}, info = {} } end

--- Note every object of ours in a square's object list into `hits`; returns how many (run under one pcall per square).
local function collect(objects, hits)
    local n, info = 0, World.info
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local sprite = obj:getSprite()
        local name = sprite and sprite:getName()
        local what = name and info(name)
        if what then
            n = n + 1
            hits.obj[n], hits.name[n], hits.info[n] = obj, name, what
        end
    end
    return n
end
local sharedHits = newHits()
local loading = false

--- Read a freshly loaded square once and hand what is ours on it to every square handler.
function World.dispatchLoad(square)
    local objects = square and square:getObjects()
    if not objects then return end
    -- A handler that loads another square mid-pass gets its own buffer.
    local hits = loading and newHits() or sharedHits
    local outer = loading
    loading = true
    local ok, n = pcall(collect, objects, hits)
    if not ok then
        failed("square read", n)
        n = 0
    end
    hits.n = n
    for _, h in ipairs(loadHandlers) do
        if n > 0 or h.all then
            local ok, err = pcall(h.fn, square, hits)
            if not ok then failed(h.label, err) end
        end
    end
    for i = 1, n do hits.obj[i], hits.name[i], hits.info[i] = nil, nil, nil end
    hits.n = 0
    loading = outer
end

local function dispatchObject(list, anyList, obj)
    if obj == nil then return end
    for _, h in ipairs(anyList) do
        local ok, err = pcall(h.fn, obj)
        if not ok then failed(h.label, err) end
    end
    if #list == 0 then return end
    local ok, name = pcall(spriteName, obj)
    local info = ok and World.info(name)
    if not info then return end
    for _, h in ipairs(list) do
        local fine, err = pcall(h.fn, obj, name, info)
        if not fine then failed(h.label, err) end
    end
end

function World.dispatchAdded(obj) dispatchObject(addHandlers, anyAddHandlers, obj) end
function World.dispatchRemoved(obj) dispatchObject(removeHandlers, anyRemoveHandlers, obj) end

-- One handler per event however many files use it; a reload of this file doesn't add a second.
if Events and not World.hooked then
    World.hooked = true
    if Events.LoadGridsquare then Events.LoadGridsquare.Add(function(square) World.dispatchLoad(square) end) end
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(function(obj) World.dispatchAdded(obj) end) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(function(obj) World.dispatchRemoved(obj) end) end
end

return World
