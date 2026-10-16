-- Debug showcase setups for Workshop screenshots: one command lays a finished grow (or drying corner) out on the free
-- floor around the clicked square, at a chosen stage. Everything goes through the mod's own paths: furniture is put down
-- with vanilla's ISMoveableSpriteProps:placeMoveable (so every placing hook runs), containers become plots the way a
-- placed bag does, plants are sown into them and moved on with Registry.advanceStage, reservoirs are filled with
-- Hydro.debugFillNear and dosed with Hydro.dose. Clients see it through the mod's normal sync.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisStrains"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisServerCommands"
require "CannabisMod/CannabisWorld"
require "CannabisMod/CannabisGrowBags"
require "CannabisMod/CannabisHydro"
require "CannabisMod/CannabisLight"
require "CannabisMod/CannabisDrying"

local Config   = CannabisMod.Config
local Net      = CannabisMod.Net
local Genetics = CannabisMod.Genetics
local Strains  = CannabisMod.Strains
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local World    = CannabisMod.World
local commands = CannabisMod.ServerCommands.handlers
local T        = Config.TYPES
local D        = Config.Drying
local H        = Config.Hydro

local Showcase = {}
CannabisMod.Showcase = Showcase

Showcase.MAX_REACH = 20     -- the clicked square may be this many tiles from the player
Showcase.SEARCH_RADIUS = 8  -- how far the layout's corner may move from the clicked square to find free floor

--- Call a method if the object has it, under pcall. Returns ok, result (ok false when missing or failing).
local function try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, obj, ...)
end

-- --------------------------------------------------------------------------
-- Layouts
-- --------------------------------------------------------------------------
-- Cells are { dx, dy } from the layout's top-left corner. Every piece names the cells it stands on; an aisle is
-- floor kept clear to walk along; exits are the aisle's ends, of which at least one should be open floor.
-- Lamps list the cells to hang over, best first: over the plants, then the aisle.

--- Soil grow: two rows of three bags facing an aisle, a lamp over the middle of each row.
local function soilLayout(bag, lamp)
    return {
        w = 3, h = 3,
        pieces = {
            { kind = "bag", bag = bag, cell = { 0, 0 } }, { kind = "bag", bag = bag, cell = { 1, 0 } },
            { kind = "bag", bag = bag, cell = { 2, 0 } },
            { kind = "bag", bag = bag, cell = { 0, 2 } }, { kind = "bag", bag = bag, cell = { 1, 2 } },
            { kind = "bag", bag = bag, cell = { 2, 2 } },
        },
        lamps = {
            { item = lamp, cells = { { 1, 0 }, { 1, 1 }, { 0, 1 } } },
            { item = lamp, cells = { { 1, 2 }, { 2, 1 }, { 0, 1 } } },
        },
        aisle = { { 0, 1 }, { 1, 1 }, { 2, 1 } },
        exits = { { -1, 1 }, { 3, 1 } },
    }
end

--- Hydro bench: two DWC buckets, an RDWC control with three sites, a flood reservoir and a flood table.
local function hydroLayout()
    return {
        w = 6, h = 3,
        pieces = {
            { kind = "bag", bag = "dwc", cell = { 0, 0 }, stage = "Vegetative" },
            { kind = "bag", bag = "dwc", cell = { 0, 2 }, stage = "Vegetative" },
            { kind = "furniture", item = H.CONTROL_ITEM, cell = { 2, 0 }, label = "an RDWC control bucket" },
            { kind = "bag", bag = "rdwc", cell = { 3, 0 }, stage = "Flowering" },
            { kind = "bag", bag = "rdwc", cell = { 4, 0 }, stage = "Flowering" },
            { kind = "bag", bag = "rdwc", cell = { 5, 0 }, stage = "Flowering" },
            { kind = "furniture", item = H.FLOOD_ITEM, cell = { 2, 2 }, label = "a flood reservoir", flood = true },
            { kind = "table", bag = "ebb", cells = { { 3, 2 }, { 4, 2 } }, stage = "Vegetative" },
        },
        lamps = {
            { item = "CannabisMod.GrowLampPro", cells = { { 0, 0 }, { 0, 1 }, { 1, 1 } } },
            { item = "CannabisMod.GrowLampPro", cells = { { 4, 0 }, { 4, 1 }, { 3, 1 } } },
        },
        aisle = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 } },
        exits = { { -1, 1 }, { 6, 1 } },
    }
end

--- Drying corner: a rack of wet plants with a fan beside it, a jar of curing buds and a curing barrel.
local function dryingLayout()
    return {
        w = 4, h = 3,
        pieces = {
            { kind = "rack", item = D.RACK_ITEM, cells = { { 0, 0 }, { 1, 0 } } },
            { kind = "furniture", item = D.FAN_ITEM, cell = { 3, 0 }, label = "a drying fan" },
            { kind = "jar", cell = { 0, 2 } },
            { kind = "furniture", item = D.BARREL_ITEM, cell = { 3, 2 }, label = "a curing barrel", barrel = true },
        },
        lamps = {},
        aisle = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } },
        exits = { { -1, 1 }, { 4, 1 } },
    }
end

-- Each setup: its layout, the stage its soil plants reach, and how it is described.
Showcase.SETUPS = {
    seedling = { name = "seedlings", stage = "Seedling",
                 layout = function() return soilLayout("small", "CannabisMod.GrowLampBasic") end },
    veg      = { name = "vegetative plants", stage = "Vegetative",
                 layout = function() return soilLayout("large", "CannabisMod.GrowLampBasic") end },
    flower   = { name = "flowering plants", stage = "Flowering",
                 layout = function() return soilLayout("large", "CannabisMod.GrowLampPro") end },
    ripe     = { name = "ripe plants at top quality", stage = "Ripe", maxQuality = true,
                 layout = function() return soilLayout("large", "CannabisMod.GrowLampPro") end },
    hydro    = { name = "a hydro bench", layout = hydroLayout },
    drying   = { name = "a drying and curing corner", layout = dryingLayout },
}

-- --------------------------------------------------------------------------
-- Finding free floor
-- --------------------------------------------------------------------------

-- Object sprites that lie flat on a floor (rugs, floor blends) and leave the square usable.
local FLAT_PREFIXES = { "floors_", "blends_" }

local function isFlat(name)
    if type(name) ~= "string" then return false end
    for _, p in ipairs(FLAT_PREFIXES) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

--- True for an indoor square with a floor and nothing on it: no wall, furniture, plot, water, stairs, item or person.
function Showcase.isFreeFloor(square)
    if not square then return false end
    local ok, free = pcall(function()
        local floor = square:getFloor()
        if not floor then return false end
        if square:isOutside() then return false end
        local okW, water = try(square, "has", IsoFlagType and IsoFlagType.water or "water")
        if okW and water then return false end
        local okS, stairs = try(square, "HasStairs")
        if okS and stairs then return false end
        local okF, isFree = try(square, "isFree", true)
        if okF and isFree == false then return false end
        local okM, moving = try(square, "getMovingObjects")
        if okM and moving and moving:size() > 0 then return false end
        local okV, vehicle = try(square, "isVehicleIntersecting")
        if okV and vehicle then return false end
        if Farming.getVanilla(square:getX(), square:getY(), square:getZ()) then return false end
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj ~= floor and not isFlat(World.safeSpriteName(obj)) then return false end
        end
        local items = square:getWorldObjects()
        if items and items:size() > 0 then return false end
        return true
    end)
    return ok and free == true
end

--- Every cell a layout needs free: the pieces' cells, the lamp cells and the aisle.
local function neededCells(layout)
    local out, seen = {}, {}
    local function add(c)
        local k = c[1] .. "," .. c[2]
        if not seen[k] then seen[k] = true out[#out + 1] = c end
    end
    for _, p in ipairs(layout.pieces) do
        if p.cell then add(p.cell) end
        for _, c in ipairs(p.cells or {}) do add(c) end
    end
    for _, c in ipairs(layout.aisle) do add(c) end
    return out, seen
end

--- True when a wall or door edge stands between two neighbouring squares.
local function blockedBetween(a, b)
    local ok, blocked = try(a, "isBlockedTo", b)
    return ok and blocked == true
end

--- Whether the layout fits with its corner at (ox, oy): every needed cell free floor with no wall between neighbours,
--- and (when `wantExit`) at least one end of the aisle open.
local function fits(layout, cells, set, ox, oy, z, wantExit)
    local cell = getCell()
    local squares = {}
    for _, c in ipairs(cells) do
        local sq = cell:getGridSquare(ox + c[1], oy + c[2], z)
        if not Showcase.isFreeFloor(sq) then return false end
        squares[c[1] .. "," .. c[2]] = sq
    end
    for _, c in ipairs(cells) do
        local here = squares[c[1] .. "," .. c[2]]
        for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
            local there = squares[(c[1] + d[1]) .. "," .. (c[2] + d[2])]
            if there and blockedBetween(here, there) then return false end
        end
    end
    if wantExit and #layout.exits > 0 then
        for _, e in ipairs(layout.exits) do
            local sq = cell:getGridSquare(ox + e[1], oy + e[2], z)
            local inner = squares[(e[1] < 0 and 0 or layout.w - 1) .. "," .. e[2]]
            if Showcase.isFreeFloor(sq) and not (inner and blockedBetween(inner, sq)) then return true end
        end
        return false
    end
    return true
end

--- Corners to try: the layout centred on the clicked square first, then ring by ring outward.
local function cornersAround(cx, cy, layout, radius)
    local bx, by = cx - math.floor(layout.w / 2), cy - math.floor(layout.h / 2)
    local out = { { bx, by } }
    for r = 1, radius do
        for dx = -r, r do out[#out + 1] = { bx + dx, by - r } end
        for dy = -r + 1, r do out[#out + 1] = { bx + r, by + dy } end
        for dx = r - 1, -r, -1 do out[#out + 1] = { bx + dx, by + r } end
        for dy = r - 1, -r + 1, -1 do out[#out + 1] = { bx - r, by + dy } end
    end
    return out
end

--- The top-left corner where the layout fits near (cx, cy, z), or nil. A spot with an open aisle end is preferred.
function Showcase.findSpot(layout, cx, cy, z, radius)
    local cells, set = neededCells(layout)
    local corners = cornersAround(cx, cy, layout, radius or Showcase.SEARCH_RADIUS)
    for _, wantExit in ipairs({ true, false }) do
        for _, c in ipairs(corners) do
            if fits(layout, cells, set, c[1], c[2], z, wantExit) then return c[1], c[2] end
        end
    end
    return nil
end

-- --------------------------------------------------------------------------
-- Placing furniture through vanilla's moveable code
-- --------------------------------------------------------------------------

--- The props to try for a sprite, its own facing first: list of props.
local function facesOf(sprite)
    if not (ISMoveableSpriteProps and ISMoveableSpriteProps.new) then return {} end
    local ok, base = pcall(ISMoveableSpriteProps.new, sprite)
    if not (ok and base and base.isMoveable) then return {} end
    local out = { base }
    local okF, faces = try(base, "getFaces")
    if okF and type(faces) == "table" then
        for _, f in ipairs({ "S", "E", "W", "N" }) do
            local name = faces[f]
            if name and name ~= sprite then
                local okP, p = pcall(ISMoveableSpriteProps.new, name)
                if okP and p and p.isMoveable then out[#out + 1] = p end
            end
        end
    end
    return out
end

--- The squares a piece covers with its anchor on `square`: the sprite grid for a multi-tile piece; nil when unknown.
local function footprint(props, square)
    if not props.isMultiSprite then return { square } end
    local ok, grid = try(props, "getSpriteGridInfo", square, false)
    if not ok or type(grid) ~= "table" or #grid == 0 then return nil end
    local out = {}
    for i, g in ipairs(grid) do
        if not g.square then return nil end
        out[i] = g.square
    end
    return out
end

local function sqKey(sq) return sq:getX() .. "," .. sq:getY() end

--- True when every square of `foot` is one of `allowed` (a set of "x,y").
local function within(foot, allowed)
    for _, s in ipairs(foot) do
        if not allowed[sqKey(s)] then return false end
    end
    return true
end

--- Run fn with vanilla's movables cheat on, so a debug placement never fails on the placer's skill or tools.
local function asCheat(fn)
    local defs = ISMoveableDefinitions
    local was = defs and defs.cheat
    if defs then defs.cheat = true end
    local ok, a, b = pcall(fn)
    if defs then defs.cheat = was end
    if not ok then
        print("[DazedDank] showcase placing failed: " .. tostring(a))
        return nil
    end
    return a, b
end

--- Put one moveable item down with its anchor on one of `anchors` (squares, best first) and its whole footprint inside
--- `allowed` ("x,y" set). Returns the anchor square and the footprint, or nil when it could not be placed.
function Showcase.placeItem(player, fullType, anchors, allowed)
    local inv = player:getInventory()
    local item = inv:AddItem(fullType)
    if not item then return nil end
    local okS, sprite = try(item, "getWorldSprite")
    local faces = okS and type(sprite) == "string" and facesOf(sprite) or {}
    local placedAt, placedFoot = asCheat(function()
        for _, square in ipairs(anchors) do
            for _, props in ipairs(faces) do
                local foot = footprint(props, square)
                if foot and within(foot, allowed) then
                    local fitsHere = true
                    if props.canPlaceMoveable then
                        local okC, can = pcall(props.canPlaceMoveable, props, player, square, item)
                        fitsHere = (not okC) or (can and true or false)
                    end
                    if fitsHere then
                        local ok, err = pcall(props.placeMoveable, props, player, square, sprite)
                        if not ok then print("[DazedDank] showcase: placing " .. fullType .. " failed: " .. tostring(err)) end
                        local okH, still = try(inv, "contains", item)
                        if okH and still == false then return square, foot end
                        -- Without contains(), the piece standing on the square says it landed.
                        if not okH and World.findSprite(square, props.spriteName or sprite) then return square, foot end
                    end
                end
            end
        end
        return nil
    end)
    if placedAt then return placedAt, placedFoot end
    -- Never sent to the client, so it simply goes again.
    pcall(function() inv:Remove(item) end)
    return nil
end

-- --------------------------------------------------------------------------
-- Containers, plants and stations
-- --------------------------------------------------------------------------

--- Make the bag, bucket or table tiles on `squares` into plots: the placed furniture is converted as the placing hook
--- would; if the furniture couldn't be placed, the plots are made directly (and a table's halves paired). Returns the plots.
local function makeContainer(player, kind, squares, allowed)
    local GrowBags = CannabisMod.GrowBags
    local def = Config.GrowBag[kind]
    local placed = Showcase.placeItem(player, def.furnItem, squares, allowed)
    if placed then
        for _, sq in ipairs(squares) do GrowBags.convertBagAt(sq:getX(), sq:getY(), sq:getZ()) end
    end
    local plots = {}
    for _, sq in ipairs(squares) do
        local x, y, z = sq:getX(), sq:getY(), sq:getZ()
        local plot = Farming.getVanilla(x, y, z)
        if not plot then
            CannabisMod.Hydro.clear(x, y, z)
            plot = GrowBags.makePlot(sq, kind)
        end
        if plot then plots[#plots + 1] = plot end
    end
    if kind == "ebb" then
        for _, p in ipairs(plots) do GrowBags.pairOrphanTable(p.x, p.y, p.z) end
    end
    CannabisMod.Hydro.forgetLinks()
    return plots
end

--- Fill a plot's bag with soil, or set a rockwool cube in a hydro net pot, as the fill and add-medium commands do.
local function fillMedium(plot, kind)
    local x, y, z = plot.x, plot.y, plot.z
    local hydro = Config.hydroOf(kind)
    if hydro then CannabisMod.Hydro.get(x, y, z, hydro).medium = "rockwool" end
    Registry.setBagSoiled(x, y, z, true)
    plot:setSpriteName(farming_vegetableconf.getSpriteName(plot))
    plot:setObjectName(farming_vegetableconf.getObjectName(plot))
    plot:saveData()
end

--- Sow a female of `strain` into a ready plot with vanilla's own seeding, register it and grow it on to `stage`.
--- Returns the plant record, or nil when the plot wouldn't take a seed.
function Showcase.sow(plot, strain, stage)
    if not (plot and plot.state == "plow" and type(plot.seed) == "function") then return nil end
    local ok, err = pcall(plot.seed, plot, Config.CROP_TYPE)
    if not ok then print("[DazedDank] showcase: sowing failed: " .. tostring(err)) end
    if plot.state ~= "seeded" or plot.typeOfSeed ~= Config.CROP_TYPE then return nil end
    local seed = Genetics.newSeed(strain)
    seed.sex = Config.SEX.FEMALE
    local plant = Registry.addPlant(plot.x, plot.y, plot.z, seed)
    Farming.onStageChanged(plant)
    local target = Config.STAGE[stage] or Config.STAGE.Seedling
    while plant.stage < target do Registry.advanceStage(plant) end
    return plant
end

--- Top a plant's quality factors out and clear its stress, as debugBoostQuality "max" does.
function Showcase.maxQuality(plant)
    plant.genetics, plant.lightCap, plant.care, plant.stress = 100, 100, 100, 0
end

--- The strains plants are given in turn: indica, sativa and a hybrid cross of the two, round the starters.
local function strainCycle()
    local S = Strains.STARTERS
    local hybrid = Strains.cross(S[1], S[4])
    if Strains.typeOf(hybrid) ~= T.HYBRID then hybrid = Strains.fromType(T.HYBRID, 0) end
    return { S[1], S[4], hybrid, S[2], S[5], hybrid, S[3], S[6] }
end

--- A new inventory item of a type, or nil.
local function newItem(fullType)
    if instanceItem then
        local ok, item = pcall(instanceItem, fullType)
        if ok and item then return item end
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, item = pcall(InventoryItemFactory.CreateItem, fullType)
        if ok and item then return item end
    end
    return nil
end

--- Hang a freshly harvested whole plant of `strain` in a rack's container, carrying a harvest record like a real one.
local function hangWetPlant(container, strain)
    local kind = Strains.typeOf(strain) or T.HYBRID
    local items = container:AddItems(Config.WET_PLANT_ITEMS[kind] or Config.WET_PLANT_ITEMS.Hybrid, 1)
    local item = items and items:size() > 0 and items:get(0)
    if not item then return false end
    local harvest = { type = kind, strain = Strains.copy(strain), quality = 92, budYield = 7, genetics = 100,
                      generation = 0, hermieLineage = false, harvestedAt = Registry.nowHours() }
    item:getModData().CannabisHarvest = harvest
    local name = Strains.plantName(harvest, "Wet")
    if name then item:setName(name) end
    sendAddItemsToContainer(container, items)
    return true
end

--- Fill a container with `count` trimmed buds of `strain`, freshly into their cure. Returns the items list.
local function addBuds(container, strain, count, quality)
    local items = container:AddItems(D.BUD_ITEM, count)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local data = { type = Strains.typeOf(strain) or T.HYBRID, strain = Strains.copy(strain), quality = quality,
                       cureHours = 0, moldy = false, moldBaked = false, moist = false, moisture = 12,
                       seeded = false, genetics = 100 }
        item:getModData()[D.BUD_DATA] = data
        item:setName(CannabisMod.Drying.budName(data))
    end
    return items
end

-- --------------------------------------------------------------------------
-- Building a setup
-- --------------------------------------------------------------------------

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

--- Lay `id` out around (cx, cy, z) for `player`. Returns the summary text (nil for an unknown setup) and a result table.
function Showcase.build(player, id, cx, cy, z)
    local setup = Showcase.SETUPS[id]
    if not setup then return nil end
    local layout = setup.layout()
    local ox, oy = Showcase.findSpot(layout, cx, cy, z)
    local result = { plants = {}, lamps = 0, missing = {}, placed = {} }
    if not ox then
        return "No room for " .. setup.name .. ": it needs about " .. layout.w .. " by " .. layout.h
            .. " tiles of clear indoor floor near where you clicked", result
    end
    local cell = getCell()
    local function at(c) return cell:getGridSquare(ox + c[1], oy + c[2], z) end
    local function setOf(list)
        local s = {}
        for _, c in ipairs(list) do s[(ox + c[1]) .. "," .. (oy + c[2])] = true end
        return s
    end
    local strains, nextStrain = strainCycle(), 0
    local function strain()
        nextStrain = nextStrain % #strains + 1
        return strains[nextStrain]
    end
    local counts = {}
    local function count(label) counts[label] = (counts[label] or 0) + 1 end
    local hydroPlots, stations = {}, {}

    -- Containers and furniture first, so the lamps can hang over them.
    for _, p in ipairs(layout.pieces) do
        if p.kind == "bag" or p.kind == "table" then
            local cells = p.cells or { p.cell }
            local squares = {}
            for _, c in ipairs(cells) do squares[#squares + 1] = at(c) end
            local plots = makeContainer(player, p.bag, squares, setOf(cells))
            if #plots < #cells then result.missing[#result.missing + 1] = Config.GrowBag[p.bag].name end
            for _, plot in ipairs(plots) do
                fillMedium(plot, p.bag)
                local plant = Showcase.sow(plot, strain(), p.stage or setup.stage)
                if plant then
                    if setup.maxQuality then Showcase.maxQuality(plant) end
                    result.plants[#result.plants + 1] = plant
                    if Config.isHydro(p.bag) then hydroPlots[#hydroPlots + 1] = plant end
                else
                    result.missing[#result.missing + 1] = "a plant in a " .. Config.GrowBag[p.bag].name
                end
            end
            if #plots > 0 then count(Config.GrowBag[p.bag].name) end
        elseif p.kind == "furniture" or p.kind == "rack" then
            local cells = p.cells or { p.cell }
            local anchors = {}
            for _, c in ipairs(cells) do anchors[#anchors + 1] = at(c) end
            local sq = Showcase.placeItem(player, p.item, anchors, setOf(cells))
            if sq then
                local x, y = sq:getX(), sq:getY()
                if p.flood then
                    CannabisMod.Hydro.forgetLinks()
                    CannabisMod.Hydro.syncFloodObject(x, y, z)
                end
                stations[#stations + 1] = { piece = p, square = sq }
                result.placed[#result.placed + 1] = p.label or "a drying rack"
            else
                result.missing[#result.missing + 1] = p.label or "a drying rack"
            end
        elseif p.kind == "jar" then
            stations[#stations + 1] = { piece = p, square = at(p.cell) }
        end
    end

    -- Lamps over the plants, or over the aisle where they can't hang there.
    local lampSquares = {}
    for _, lamp in ipairs(layout.lamps) do
        local anchors, allowed = {}, {}
        for _, c in ipairs(lamp.cells) do
            anchors[#anchors + 1] = at(c)
            allowed[(ox + c[1]) .. "," .. (oy + c[2])] = true
        end
        local sq = Showcase.placeItem(player, lamp.item, anchors, allowed)
        if sq then
            CannabisMod.Light.noteLamp(sq:getX(), sq:getY(), z)
            lampSquares[#lampSquares + 1] = sq
            result.lamps = result.lamps + 1
        else
            result.missing[#result.missing + 1] = "a grow lamp"
        end
    end

    -- Drying corner: wet plants on the rack, buds curing in a jar and the barrel.
    local hung, jarred, barrelled = 0, 0, 0
    for _, st in ipairs(stations) do
        local p, sq = st.piece, st.square
        if p.kind == "rack" then
            local racks = CannabisMod.Drying.racksAt(sq)
            local rack = racks[1]
            if not rack then
                -- The rack's container sits on one of its two tiles.
                for _, other in ipairs(CannabisMod.Drying.rackSquares(sq)) do
                    rack = rack or CannabisMod.Drying.racksAt(other)[1]
                end
            end
            if rack then
                for _ = 1, 4 do
                    if hangWetPlant(rack, strain()) then hung = hung + 1 end
                end
            end
        elseif p.barrel then
            local obj = World.findSprite(sq, D.BARREL_SPRITE)
            local container = obj and obj:getContainer()
            if container then
                local items = addBuds(container, strain(), 12, 88)
                sendAddItemsToContainer(container, items)
                barrelled = items:size()
            end
        elseif p.kind == "jar" then
            local jar = newItem(D.JAR_ITEM)
            local inv = jar and jar.getInventory and jar:getInventory()
            if inv then
                -- Filled before it is set down, so the buds travel with it to every client.
                jarred = addBuds(inv, strain(), 8, 94):size()
                local ok = pcall(function() sq:AddWorldInventoryItem(jar, 0.5, 0.5, 0) end)
                if not ok then jarred = 0 end
            end
            if jarred == 0 then result.missing[#result.missing + 1] = "a curing jar" end
        end
    end

    -- Water and food: every pot and reservoir in the layout filled, each reservoir dosed for its plants' stage.
    local notes = {}
    -- Every site links to its reservoir first, so a shared reservoir is filled to what all its sites hold.
    for _, plant in ipairs(hydroPlots) do CannabisMod.Hydro.reservoirOf(plant.x, plant.y, plant.z) end
    if #result.plants > 0 then
        local reach = math.ceil(math.max(layout.w, layout.h) / 2) + 1
        CannabisMod.Hydro.debugFillNear(ox + math.floor(layout.w / 2), oy + math.floor(layout.h / 2), reach)
    end
    local dosed, unpowered = {}, false
    for _, plant in ipairs(hydroPlots) do
        local r = CannabisMod.Hydro.reservoirOf(plant.x, plant.y, plant.z)
        if r and not dosed[r] and plant.stage >= Config.STAGE.Vegetative then
            dosed[r] = true
            if r.kind ~= "ebb" and not CannabisMod.Hydro.pumpState(r) and not unpowered then
                unpowered = true
                notes[#notes + 1] = "the air pumps have no power, so the roots will start to rot"
            end
            CannabisMod.Hydro.dose(r, plant.stage >= Config.STAGE.Flowering and "Bloom" or "Veg")
            if r.kind == "ebb" then
                r.floodTimer = true
                CannabisMod.Hydro.syncFloodObject(r.x, r.y, r.z)
                if CannabisMod.Hydro.flood(r, Registry.nowHours()) == "noPower" then
                    notes[#notes + 1] = "the flood pump has no power"
                end
            end
        end
    end

    -- What was put down.
    local parts = {}
    if #result.plants > 0 then
        local kinds = {}
        for _, plant in ipairs(result.plants) do kinds[plant.type] = (kinds[plant.type] or 0) + 1 end
        local mix = {}
        for _, t in ipairs({ T.INDICA, T.SATIVA, T.HYBRID }) do
            if kinds[t] then mix[#mix + 1] = kinds[t] .. " " .. t end
        end
        parts[#parts + 1] = plural(#result.plants, "plant", "plants") .. " (" .. table.concat(mix, ", ") .. ")"
    end
    local labels = {}
    for label in pairs(counts) do labels[#labels + 1] = label end
    table.sort(labels)
    for _, label in ipairs(labels) do parts[#parts + 1] = counts[label] .. " x " .. label end
    for _, label in ipairs(result.placed) do parts[#parts + 1] = label end
    if result.lamps > 0 then parts[#parts + 1] = plural(result.lamps, "grow lamp", "grow lamps") end
    if hung > 0 then parts[#parts + 1] = hung .. " wet plants on the rack" end
    if jarred > 0 then parts[#parts + 1] = "a jar of " .. jarred .. " curing buds" end
    if barrelled > 0 then parts[#parts + 1] = barrelled .. " buds in the barrel" end
    if result.lamps > 0 and Config.sandbox("LampsNeedPower") and not World.isPoweredSafe(lampSquares[1]) then
        notes[#notes + 1] = "no power here, so the lamps stay dark until the building has power"
    end
    local text = "Showcase " .. id .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "nothing placed")
    if #result.missing > 0 then text = text .. ". Couldn't place: " .. table.concat(result.missing, ", ") end
    if #notes > 0 then text = text .. ". Note: " .. table.concat(notes, "; ") end
    result.text, result.corner = text, { ox, oy, z }
    return text, result
end

--- Spawn a showcase setup. args = { setup, x, y, z }: the clicked square, else the player's own square.
commands.debugShowcase = function(player, args)
    if not Config.debugAllowed(player) then return end
    if not Showcase.SETUPS[args.setup] then return end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) or math.abs(x - px) > Showcase.MAX_REACH or math.abs(y - py) > Showcase.MAX_REACH then
        x, y, z = px, py, pz
    end
    local text = Showcase.build(player, args.setup, math.floor(x), math.floor(y), math.floor(z))
    if text then Net.notify(player, text) end
end

return Showcase
