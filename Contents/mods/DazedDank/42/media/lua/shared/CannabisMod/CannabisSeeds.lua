-- Reads and writes the hidden data (type, sex, genetics) stored on seed and
-- cutting items.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisStrains"

local Config = CannabisMod.Config
local Strains = CannabisMod.Strains

local Seeds = {}
CannabisMod.Seeds = Seeds

-- Key inside item:getModData() where our seed data lives.
local MODDATA_KEY = "CannabisSeed"

--- Turn an item ID into a stable pseudo-random number from 0 to 99999. Same
--- input always gives the same output, on every machine.
local function stableRoll(id, salt)
    local n = (math.abs(id) % 1000003) * 7919 + salt * 104729
    return n % 100003 % 100000
end

--- Work out the data for a seed nobody has written data on.
local function deriveFromId(id)
    local typeRoll = stableRoll(id, 1)
    local sexRoll = stableRoll(id, 2) % 100  -- 0-99
    -- Looted seeds are always one of the six starters, picked by the item ID.
    local strain = Strains.starterFor(typeRoll)
    return {
        type          = Strains.typeOf(strain),
        strain        = strain,
        sex           = (sexRoll < Config.sandbox("MaleSeedChance")) and Config.SEX.MALE or Config.SEX.FEMALE,
        genetics      = Config.Genetics.START,
        generation    = 0,
        hermieLineage = false,
    }
end

--- Seeds written before strains existed get a starter of their type, chosen by the item ID.
local function withStrain(stored, id)
    if stored and not stored.strain then
        stored.strain = Strains.fromType(stored.type, stableRoll(id, 1))
    end
    return stored
end

--- Get a seed item's data (type, strain, sex, genetics, generation, hermieLineage).
--- @param item an InventoryItem of type CannabisMod.CannabisSeed
function Seeds.getData(item)
    local stored = item:getModData()[MODDATA_KEY]
    if stored then return withStrain(stored, item:getID()) end
    return deriveFromId(item:getID())
end

--- Write data onto a seed item. Server only, and only BEFORE the item is sent
--- to the player's inventory, so the data goes along with it.
function Seeds.setData(item, data)
    item:getModData()[MODDATA_KEY] = {
        type          = data.type,
        strain        = Strains.copy(data.strain),
        sex           = data.sex,
        genetics      = data.genetics,
        generation    = data.generation or 0,
        hermieLineage = data.hermieLineage == true,
    }
end

-- ==========================================================================
-- Cuttings
-- ==========================================================================
-- Fresh (unrooted) cuttings and rooted cuttings carry their genetics the same
-- way seeds do, under a different key. A cutting taken from a plant always
-- has data written by the server.

local CUTTING_KEY = "CannabisCutting"

local function deriveCuttingFromId(id)
    local d = deriveFromId(id)
    d.sex = Config.SEX.FEMALE
    d.generation = 1
    d.genetics = Config.Genetics.START - (1 + stableRoll(id, 3) % Config.Genetics.DRIFT_MAX)
    d.stress = 0
    d.gel = false
    return d
end

function Seeds.getCuttingData(item)
    local stored = item:getModData()[CUTTING_KEY]
    if stored then return withStrain(stored, item:getID()) end
    return deriveCuttingFromId(item:getID())
end

--- Write data onto a cutting item. Server only, before the item is sent.
function Seeds.setCuttingData(item, data)
    item:getModData()[CUTTING_KEY] = {
        type          = data.type,
        strain        = Strains.copy(data.strain),
        sex           = data.sex,
        genetics      = data.genetics,
        generation    = data.generation or 1,
        hermieLineage = data.hermieLineage == true,
        stress        = data.stress or 0,
        gel           = data.gel == true,
    }
end

-- ==========================================================================
-- Item kinds
-- ==========================================================================

--- "seed", "cutting" (fresh, unrooted), "rooted", or nil for anything else.
function Seeds.kind(item)
    if not item or not item.getFullType then return nil end
    local t = item:getFullType()
    if t == Config.SEED_ITEM then return "seed" end
    if t == Config.CUTTING_ITEM then return "cutting" end
    if t == Config.ROOTED_ITEM then return "rooted" end
    return nil
end

--- Genetics data for any plantable item.
function Seeds.getPlantData(item)
    local kind = Seeds.kind(item)
    if kind == "seed" then return Seeds.getData(item) end
    if kind == "cutting" or kind == "rooted" then return Seeds.getCuttingData(item) end
    return nil
end

--- Hours since a fresh cutting was taken. Cuttings are vanilla "food" items,
--- so their age (in days) is tracked by the game, and fridges slow it.
function Seeds.ageHours(item)
    local ok, days = pcall(function() return item:getAge() end)
    if ok and type(days) == "number" then return days * 24 end
    return 0
end

-- ==========================================================================
-- Tools
-- ==========================================================================

--- True if an item has any of the given vanilla ItemTag names. Each lookup is
--- wrapped so a tag name missing from this game version is just skipped.
-- Tag names resolved to the game's tag objects, once per list of names.
local resolvedTags = {}

local function readTag(name) return ItemTag[name] end
local function itemHasTag(item, tag) return item:hasTag(tag) end

--- The tag objects for a list of tag names, skipping names this game version doesn't have.
local function tagsFor(tagNames)
    local tags = resolvedTags[tagNames]
    if tags then return tags end
    tags = {}
    for _, name in ipairs(tagNames) do
        local ok, tag = pcall(readTag, name)
        if ok and tag ~= nil then tags[#tags + 1] = tag end
    end
    resolvedTags[tagNames] = tags
    return tags
end

local function hasAnyTag(item, tagNames)
    if not item or not item.hasTag or not ItemTag then return false end
    for _, tag in ipairs(tagsFor(tagNames)) do
        local ok, result = pcall(itemHasTag, item, tag)
        if ok and result then return true end
    end
    return false
end
Seeds.hasAnyTag = hasAnyTag

--- Loop over every item a container holds, including inside bags. fn(item)
--- returning true stops the loop and returns that item.
function Seeds.findItem(container, fn)
    if not container then return nil end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if fn(item) then return item end
        if item.getInventory and instanceof and instanceof(item, "InventoryContainer") then
            local found = Seeds.findItem(item:getInventory(), fn)
            if found then return found end
        end
    end
    return nil
end

--- Every item in a container (and its bags) that passes fn.
function Seeds.findAll(container, fn)
    local out = {}
    Seeds.findItem(container, function(item)
        if fn(item) then out[#out + 1] = item end
        return false
    end)
    return out
end

--- The first tool in a player's inventory that can take a cutting.
function Seeds.findCuttingTool(player)
    return Seeds.findItem(player:getInventory(), function(item)
        return hasAnyTag(item, Config.CUTTING_TOOL_TAGS)
    end)
end

--- True if an item is a fresh cutting that can still root.
function Seeds.isUsableCutting(item)
    if Seeds.kind(item) ~= "cutting" then return false end
    local ok, rotten = pcall(function() return item:isRotten() end)
    return not (ok and rotten)
end

-- Exposed for the offline tests.
Seeds._deriveFromId = deriveFromId
Seeds._deriveCuttingFromId = deriveCuttingFromId
