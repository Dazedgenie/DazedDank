-- Server side of smoking: rolling joints, taking a dose, and each player's tolerance and dependency record.
-- The client applies the stat changes to its own player; the server owns the records and the maths.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisGenetics"
require "CannabisMod/CannabisUse"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisDrying"
require "CannabisMod/CannabisWeather"
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
local Strains  = CannabisMod.Strains
local Use      = CannabisMod.Use
local Seeds    = CannabisMod.Seeds
local Net      = CannabisMod.Net
local Registry = CannabisMod.Registry
local Farming  = CannabisMod.Farming
local Drying   = CannabisMod.Drying
local SC       = CannabisMod.ServerCommands
local commands = SC.handlers
local Smoke    = Config.Smoking

local Smoking = {}
CannabisMod.Smoking = Smoking

-- db.users[username] = { tol, dep, lastUse, at, doses }
-- A joint carries { type, quality, moldy } under Smoke.JOINT_DATA; db.joints[itemId] only holds joints rolled before that.
-- A blunt (or half-smoked blunt) carries the same under JOINT_DATA plus { wrap = "leaf" or "tobacco", hits = sessions left }.
-- Each session swaps the item for a fresh half-smoked one carrying the new count, because later item data changes
-- don't reliably sync in multiplayer.
local db = nil

local function onInitGlobalModData()
    db = ModData.getOrCreate(Config.MODDATA_KEY .. "_Smoking")
    db.users = db.users or {}
    db.joints = db.joints or {}
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)

function Smoking.data() return db end

local function userKey(player)
    local ok, name = pcall(function() return player:getUsername() end)
    return (ok and name) or "player"
end

local function userOf(player)
    local key = userKey(player)
    if not db.users[key] then db.users[key] = Use.new() end
    return db.users[key]
end

--- What a bud is made of: type, final quality and mold, from its record or its own data (a plain bud counts as middling hybrid).
local function budInfo(bud)
    local rec = Drying.budRecord(bud)
    if not rec then return { type = "Hybrid", quality = 50, moldy = false } end
    return { type = rec.type, strain = Strains.copy(rec.strain), purple = rec.purple == true or nil,
             quality = Genetics.curedQuality(rec.quality, rec.cureHours, rec.moldy, rec.moldBaked), moldy = rec.moldy == true }
end

--- What a bud or joint is called: its strain when it has one, else its type, with "Purple" in front for purple buds.
local function strainWord(info)
    return CannabisMod.Weather.purpleName(info, (info.strain and info.strain.name) or tostring(info.type))
end

local function findById(player, id, fullType)
    return Seeds.findItem(player:getInventory(), function(item)
        return item:getID() == id and item:getFullType() == fullType
    end)
end

local function findType(player, fullType)
    return Seeds.findItem(player:getInventory(), function(item) return item:getFullType() == fullType end)
end

local function take(player, item)
    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
end

local function now() return Registry.nowHours() end

commands.rollJoint = function(player, args)
    local id = tonumber(args.id)
    local bud = id and findById(player, id, Config.Drying.BUD_ITEM)
    if not bud then return end
    local paper = findType(player, Smoke.PAPER_ITEM)
    if not paper then
        Net.notify(player, "You need rolling papers")
        return
    end
    local info = budInfo(bud)
    take(player, bud)
    take(player, paper)
    Drying.data().buds[id] = nil
    local name = (info.moldy and "Moldy " or (Config.qualityTier(info.quality) .. " ")) .. strainWord(info) .. " Joint"
    -- The joint carries what it was rolled from; set before the item is sent, so clients get it too.
    Farming.giveItems(player, Smoke.JOINT_ITEM, 1, function(item)
        item:setName(name)
        item:getModData()[Smoke.JOINT_DATA] = info
    end)
    Net.notify(player, "Rolled a " .. name)
end

--- A wrap for a blunt in the player's bag: a cured fan leaf (hemp wrap) or vanilla dried tobacco, as asked
--- (`want` = "leaf" or "tobacco"; nil takes a hemp wrap first). Returns the item and its kind.
local function findWrap(player, want)
    if want ~= "tobacco" then
        local leaf = findType(player, Config.FanLeaves.CURED_ITEM)
        if leaf then return leaf, "leaf" end
        if want == "leaf" then return nil end
    end
    local tobacco = findType(player, Smoke.TOBACCO_WRAP)
    if tobacco then return tobacco, "tobacco" end
    return nil
end

--- The blunt's display name: quality and strain, the wrap, and the sessions left on a half-smoked one.
function Smoking.bluntName(info)
    local wrap = info.wrap == "tobacco" and " Tobacco" or ""
    local base = (info.moldy and "Moldy " or (Config.qualityTier(info.quality) .. " ")) .. strainWord(info) .. wrap .. " Blunt"
    local hits = tonumber(info.hits) or Smoke.BLUNT_HITS
    if hits >= Smoke.BLUNT_HITS then return base end
    return "Half-smoked " .. base .. " (" .. hits .. " hit" .. (hits == 1 and "" or "s") .. " left)"
end

--- Roll a blunt from the bud right-clicked, one more bud and a wrap (hemp wrap or dried tobacco leaf).
commands.rollBlunt = function(player, args)
    local id = tonumber(args.id)
    local bud = id and findById(player, id, Config.Drying.BUD_ITEM)
    if not bud then return end
    -- The second bud: one of the same strain if there is one, else any.
    local first = budInfo(bud)
    local want = first.strain and first.strain.name
    local other = Seeds.findItem(player:getInventory(), function(item)
        if item == bud or item:getFullType() ~= Config.Drying.BUD_ITEM then return false end
        local rec = Drying.budRecord(item)
        return want == nil or (rec and rec.strain and rec.strain.name == want)
    end) or Seeds.findItem(player:getInventory(), function(item)
        return item ~= bud and item:getFullType() == Config.Drying.BUD_ITEM
    end)
    if not other then
        Net.notify(player, "A blunt takes " .. Smoke.BLUNT_BUDS .. " buds")
        return
    end
    local wrap, kind = findWrap(player, args.wrap)
    if not wrap then
        Net.notify(player, "You need a hemp wrap (cured fan leaf) or a dried tobacco leaf")
        return
    end
    local second = budInfo(other)
    local wrapMoldy = kind == "leaf" and Drying.leafData(wrap).moldy == true
    local info = {
        type = first.type, strain = first.strain, purple = first.purple,
        quality = math.floor((first.quality + second.quality) / 2 + 0.5),
        moldy = first.moldy or second.moldy or wrapMoldy,
        wrap = kind, hits = Smoke.BLUNT_HITS,
    }
    take(player, bud)
    take(player, other)
    take(player, wrap)
    Drying.data().buds[id] = nil
    Drying.data().buds[other:getID()] = nil
    local name = Smoking.bluntName(info)
    Farming.giveItems(player, Smoke.BLUNT_ITEM, 1, function(item)
        item:setName(name)
        item:getModData()[Smoke.JOINT_DATA] = info
    end)
    Net.notify(player, "Rolled a " .. name)
end

--- True if the player can light up: a lighter or matches in the bag (vanilla's LIGHTERS list), or an open flame
--- the client found next to them.
local function canLight(player, args)
    if args and args.flame == true then return true end
    local found = Seeds.findItem(player:getInventory(), function(item)
        local t = item:getFullType()
        for _, l in ipairs(Smoke.LIGHTERS) do
            if t == l then
                local ok, uses = pcall(function() return item:getCurrentUsesFloat() end)
                return not ok or uses == nil or uses > 0
            end
        end
        return false
    end)
    return found ~= nil
end

--- Smoke one session of a blunt: the dose, then the rest is put out as a half-smoked blunt (nothing left: gone).
--- args.portion (0.5-1) is how much of the session was smoked before it was put out.
local function smokeBlunt(player, args, id)
    local item = findById(player, id, Smoke.BLUNT_ITEM) or findById(player, id, Smoke.HALF_BLUNT_ITEM)
    if not item then return end
    local half = item:getFullType() == Smoke.HALF_BLUNT_ITEM
    if not canLight(player, args) then
        Net.notify(player, half and "You need a lighter to relight it" or "You need a lighter")
        return
    end
    local info = item:getModData()[Smoke.JOINT_DATA] or { type = "Hybrid", quality = 50, moldy = false }
    local hits = math.max(1, math.floor(tonumber(info.hits) or Smoke.BLUNT_HITS))
    local portion = Config.clamp(tonumber(args.portion) or 1, Smoke.PUT_OUT_COUNTS, 1)
    take(player, item)

    local left = {}
    for k, v in pairs(info) do left[k] = v end
    left.strain = Strains.copy(info.strain)
    left.hits = hits - 1
    if left.hits > 0 then
        local name = Smoking.bluntName(left)
        Farming.giveItems(player, Smoke.HALF_BLUNT_ITEM, 1, function(fresh)
            fresh:setName(name)
            fresh:getModData()[Smoke.JOINT_DATA] = left
        end)
    end

    local user = userOf(player)
    local strength, hours = Use.dose(user, now(), Use.potency(info.quality, info.moldy, info.strain) * portion, "blunt")
    Net.toPlayer(player, "smoked", {
        type = info.type, strain = info.strain, moldy = info.moldy, strength = strength, hours = hours,
        tolerance = user.tol, dependency = user.dep, method = "blunt", to = Net.targetOf(player),
        nicotine = info.wrap == "tobacco" or nil, hitsLeft = left.hits,
    })
end

commands.smoke = function(player, args)
    local id = tonumber(args.id)
    local method = args.method
    Config.debugLog("smoke command: id " .. tostring(id) .. ", method " .. tostring(method))
    if not (id and Smoke.METHODS[method]) then return end
    if method == "blunt" then return smokeBlunt(player, args, id) end
    local item, info
    if method == "joint" then
        item = findById(player, id, Smoke.JOINT_ITEM)
        info = item and (item:getModData()[Smoke.JOINT_DATA] or db.joints[id])
    else
        item = findById(player, id, Config.Drying.BUD_ITEM)
        if item and not findType(player, Smoke.PIPE_ITEM) then
            Net.notify(player, "You need a pipe")
            return
        end
        info = item and budInfo(item)
    end
    if not item then Config.debugLog("smoke: item " .. tostring(id) .. " not found in inventory"); return end
    info = info or { type = "Hybrid", quality = 50, moldy = false }

    take(player, item)
    db.joints[id] = nil
    Drying.data().buds[id] = nil

    local user = userOf(player)
    local strength, hours = Use.dose(user, now(), Use.potency(info.quality, info.moldy, info.strain), method)
    if Config.debugOn() then
        Config.debugLog(string.format("smoke: dose strength %.2f for %.2fh (quality %s)", strength, hours, tostring(info.quality)))
    end
    Net.toPlayer(player, "smoked", {
        type = info.type, strain = info.strain, moldy = info.moldy, strength = strength, hours = hours,
        tolerance = user.tol, dependency = user.dep, method = method, to = Net.targetOf(player),
    })
end

--- The numbers the client needs to show withdrawal.
commands.requestUseState = function(player, args)
    local user = userOf(player)
    Use.decay(user, now())
    Net.toPlayer(player, "useState", {
        withdrawal = Use.withdrawal(user, now()), tolerance = user.tol, dependency = user.dep, to = Net.targetOf(player),
    })
end

-- Debug helpers (debug mode or admins only)

commands.debugSmokeKit = function(player, args)
    if not Config.debugAllowed(player) then return end
    Farming.giveItems(player, Smoke.PAPER_ITEM, 6)
    Farming.giveItems(player, Smoke.PIPE_ITEM, 1)
    Farming.giveItems(player, "Base.Lighter", 1)
    Farming.giveItems(player, Config.FanLeaves.CURED_ITEM, 2, function(item)
        item:getModData()[Config.FanLeaves.DATA] = { moldy = false }
    end)
    Farming.giveItems(player, Smoke.TOBACCO_WRAP, 1)
    for _, kind in ipairs({ "Indica", "Sativa", "Hybrid" }) do
        Farming.giveItems(player, Config.Drying.BUD_ITEM, 3, function(item)
            item:setName("Good " .. kind .. " Bud")
            item:getModData()[Config.Drying.BUD_DATA] = { type = kind, quality = 80, cureHours = 0, moldy = false }
        end)
    end
    Net.notify(player, "Gave papers, a pipe, a lighter, 2 hemp wraps, a tobacco leaf and 9 buds")
end

--- Set the caller's tolerance, dependency and how long ago they last used.
commands.debugUseState = function(player, args)
    if not Config.debugAllowed(player) then return end
    local user = userOf(player)
    user.tol = Config.clamp(tonumber(args.tol) or user.tol, 0, 100)
    user.dep = Config.clamp(tonumber(args.dep) or user.dep, 0, 100)
    if args.hoursAgo then user.lastUse = now() - tonumber(args.hoursAgo) end
    user.at = now()
    Net.notify(player, string.format("Tolerance %d, dependency %d", user.tol, user.dep))
    commands.requestUseState(player, {})
end
