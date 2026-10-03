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
require "CannabisMod/CannabisServerCommands"

local Config   = CannabisMod.Config
local Genetics = CannabisMod.Genetics
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
    return { type = rec.type, quality = Genetics.curedQuality(rec.quality, rec.cureHours, rec.moldy, rec.moldBaked),
             moldy = rec.moldy == true }
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
    local name = (info.moldy and "Moldy " or (Config.qualityTier(info.quality) .. " ")) .. info.type .. " Joint"
    -- The joint carries what it was rolled from; set before the item is sent, so clients get it too.
    Farming.giveItems(player, Smoke.JOINT_ITEM, 1, function(item)
        item:setName(name)
        item:getModData()[Smoke.JOINT_DATA] = info
    end)
    Net.notify(player, "Rolled a " .. name)
end

commands.smoke = function(player, args)
    local id = tonumber(args.id)
    local method = args.method
    Config.debugLog("smoke command: id " .. tostring(id) .. ", method " .. tostring(method))
    if not (id and Smoke.METHODS[method]) then return end
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
    local strength, hours = Use.dose(user, now(), Use.potency(info.quality, info.moldy), method)
    if Config.debugOn() then
        Config.debugLog(string.format("smoke: dose strength %.2f for %.2fh (quality %s)", strength, hours, tostring(info.quality)))
    end
    Net.toPlayer(player, "smoked", {
        type = info.type, moldy = info.moldy, strength = strength, hours = hours,
        tolerance = user.tol, dependency = user.dep, method = method,
    })
end

--- The numbers the client needs to show withdrawal.
commands.requestUseState = function(player, args)
    local user = userOf(player)
    Use.decay(user, now())
    Net.toPlayer(player, "useState", {
        withdrawal = Use.withdrawal(user, now()), tolerance = user.tol, dependency = user.dep,
    })
end

-- Debug helpers (debug mode or admins only)

local function debugAllowed(player)
    return isDebugEnabled() or (player.getAccessLevel and player:getAccessLevel() ~= "None")
end

commands.debugSmokeKit = function(player, args)
    if not debugAllowed(player) then return end
    Farming.giveItems(player, Smoke.PAPER_ITEM, 6)
    Farming.giveItems(player, Smoke.PIPE_ITEM, 1)
    Farming.giveItems(player, "Base.Lighter", 1)
    for _, kind in ipairs({ "Indica", "Sativa", "Hybrid" }) do
        Farming.giveItems(player, Config.Drying.BUD_ITEM, 3, function(item)
            item:setName("Good " .. kind .. " Bud")
            item:getModData()[Config.Drying.BUD_DATA] = { type = kind, quality = 80, cureHours = 0, moldy = false }
        end)
    end
    Net.notify(player, "Gave papers, a pipe, a lighter and 9 buds")
end

--- Set the caller's tolerance, dependency and how long ago they last used.
commands.debugUseState = function(player, args)
    if not debugAllowed(player) then return end
    local user = userOf(player)
    user.tol = Config.clamp(tonumber(args.tol) or user.tol, 0, 100)
    user.dep = Config.clamp(tonumber(args.dep) or user.dep, 0, 100)
    if args.hoursAgo then user.lastUse = now() - tonumber(args.hoursAgo) end
    user.at = now()
    Net.notify(player, string.format("Tolerance %d, dependency %d", user.tol, user.dep))
    commands.requestUseState(player, {})
end
