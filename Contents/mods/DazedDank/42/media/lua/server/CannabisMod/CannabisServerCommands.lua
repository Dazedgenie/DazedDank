-- The server's "inbox". Clients never change plant data themselves.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisRegistry"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisSeeds"

local Config = CannabisMod.Config
local Net = CannabisMod.Net
local Info = CannabisMod.Info
local Registry = CannabisMod.Registry

-- How close (in tiles) a player must be to inspect a plant. Stops people
-- reading plants across the map by sending fake coordinates.
local MAX_INSPECT_DISTANCE = 3

--- True if the player is standing close enough to the tile.
local function isNear(player, x, y, z)
    if math.floor(player:getZ()) ~= z then return false end
    local dx = math.abs(player:getX() - x)
    local dy = math.abs(player:getY() - y)
    return dx <= MAX_INSPECT_DISTANCE and dy <= MAX_INSPECT_DISTANCE
end

--- Player's Agriculture level. In code the perk is still called "Farming",
--- even though the game shows it as Agriculture.
local function agricultureLevel(player)
    return player:getPerkLevel(Perks.Farming)
end

-- Table of handlers: commands[name] = function(player, args) Adding a new
-- command later = adding one entry here, or from another server file through
-- CannabisMod.ServerCommands (see CannabisCloning.lua).
local commands = {}

CannabisMod.ServerCommands = {
    handlers         = commands,
    isNear           = isNear,
    agricultureLevel = agricultureLevel,
}

commands.requestPlantInfo = function(player, args)
    -- Validate the arguments are actually numbers.
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) then return end
    if not isNear(player, x, y, z) then return end

    local plant = Registry.getPlant(x, y, z)
    if not plant then
        -- Tell the client so it can close or skip the window.
        Net.toPlayer(player, "plantInfo", { x = x, y = y, z = z, missing = true })
        return
    end

    local data = Info.buildVisible(plant, agricultureLevel(player), Registry.nowHours())
    data.x, data.y, data.z = x, y, z
    -- Timer diagnostics for debug games (shown in console.txt only).
    if isDebugEnabled() then
        data.debugNow  = Registry.nowHours()
        data.debugNext = plant.nextStageAt
        data.debugSpeed = Config.sandbox("GrowthSpeed")
    end
    Net.toPlayer(player, "plantInfo", data)
end

-- --------------------------------------------------------------------------
-- Debug commands
-- --------------------------------------------------------------------------
-- Only work in debug mode (game launched with -debug) or for server admins.
-- The client only SHOWS these options in debug mode, but the server checks
-- again, because a client could send them anyway.

local function isDebugAllowed(player)
    return isDebugEnabled()
        or (player.getAccessLevel and player:getAccessLevel() ~= "None")
end

--- Give the player a test set of seeds with KNOWN data: one female of each
--- type, plus one male of each type for breeding tests.
commands.debugGiveSeeds = function(player, args)
    if not isDebugAllowed(player) then return end
    local T, SEX = Config.TYPES, Config.SEX
    local set = {
        { type = T.INDICA, sex = SEX.FEMALE }, { type = T.SATIVA, sex = SEX.FEMALE },
        { type = T.HYBRID, sex = SEX.FEMALE }, { type = T.INDICA, sex = SEX.MALE },
        { type = T.SATIVA, sex = SEX.MALE },   { type = T.HYBRID, sex = SEX.MALE },
    }
    CannabisMod.Farming.giveItems(player, Config.SEED_ITEM, #set, function(item, n)
        local seed = CannabisMod.Genetics.newSeed(set[n].type)
        seed.sex = set[n].sex
        CannabisMod.Seeds.setData(item, seed)
    end)
    Net.notify(player, "Gave 6 test seeds: 3 female, 3 male (one of each type)")
end

--- Skip the plant on a tile straight to its next stage.
commands.debugNextStage = function(player, args)
    if not isDebugAllowed(player) then return end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if not (x and y and z) then return end
    local plant = Registry.getPlant(x, y, z)
    if not plant then
        Net.notify(player, "No cannabis plant here")
        return
    end
    Registry.advanceStage(plant)
    Net.notify(player, "Now: " .. Config.STAGES[plant.stage])
end

--- Entry point for every client command from every mod. We ignore any command
--- that isn't ours.
local function onClientCommand(module, command, player, args)
    if module ~= Config.COMMAND_MODULE then return end
    local handler = commands[command]
    if handler then
        handler(player, args or {})
    end
end
Events.OnClientCommand.Add(onClientCommand)
