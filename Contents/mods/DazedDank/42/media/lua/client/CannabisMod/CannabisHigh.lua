-- Client side of the high and of withdrawal: applies stat changes to the local player each game minute, and keeps the server's tolerance numbers in sync.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisUse"
require "CannabisMod/CannabisNet"
require "CannabisMod/CannabisTraits"
require "CannabisMod/CannabisHighReport"

local Config = CannabisMod.Config
local Use    = CannabisMod.Use
local Net    = CannabisMod.Net

local High = {}
CannabisMod.High = High

-- states[playerIndex] = { high, withdrawal, tolerance, dependency }, one per split-screen player.
local states = {}

--- The high and withdrawal state of local player `index` (0-3), created on first use.
function High.stateFor(index)
    index = index or 0
    local st = states[index]
    if not st then
        st = { high = nil, withdrawal = 0, lastLog = 0 }
        states[index] = st
    end
    return st
end
-- Player 0's state, kept for readers that only know the first player.
High.state = High.stateFor(0)

--- The local index (0-3) of a player object, or 0 when it can't be read.
local function indexOf(player)
    local ok, n = pcall(function() return player:getPlayerNum() end)
    if ok and type(n) == "number" and n >= 0 and n <= 3 then return n end
    return 0
end
High.indexOf = indexOf

--- The local player a server reply is for, and their index: the player passed in single player, else the one whose online ID the reply names.
function High.targetOf(args, player)
    if player then return player, indexOf(player) end
    local id = args and args.to
    if id ~= nil then
        for i = 0, 3 do
            local p = getSpecificPlayer(i)
            local ok, pid = pcall(function() return p and p:getOnlineID() end)
            if ok and pid == id then return p, i end
        end
    end
    return getSpecificPlayer(0), 0
end

local function worldHours() return getGameTime():getWorldAgeHours() end

local missing = {}

--- Writes a [DazedDank] tracing line to console.txt in debug mode, so effects can be checked from the log.
local function log(text) Config.debugLog(text) end

--- Move one stat by delta and return its value before and after.
local function moveStat(stats, stat, delta)
    local before = stats:get(stat)
    if delta >= 0 then stats:add(stat, delta) else stats:remove(stat, -delta) end
    return before, stats:get(stat)
end

--- Add `delta` to a character stat by name, ignoring stats this game version doesn't have; returns before and after values.
local function applyStat(player, name, delta)
    local stat = CharacterStat and CharacterStat[name]
    if not stat then
        if not missing[name] then missing[name] = true; log("stat " .. name .. " does not exist in this game version, skipped") end
        return nil, nil
    end
    local ok, before, after = pcall(moveStat, player:getStats(), stat, delta)
    if not ok then
        log("stat " .. name .. " failed: " .. tostring(before))
        return nil, nil
    end
    return before, after
end

--- Strength of the current high now, easing in and out.
function High.currentStrength(high, now)
    return CannabisMod.HighReport.strength(high, now)
end

--- One game minute of effects for one player; `index` is their local player number (read from the player when left out).
function High.tickPlayer(player, now, index)
    local state = High.stateFor(index or indexOf(player))
    local step = 1 / 60
    local high = state.high
    local effects
    if high and now < high.endsAt then
        effects = Use.highEffects(high.type, High.currentStrength(high, now), high.moldy, high.strain)
    elseif state.withdrawal > 0 then
        effects = Use.withdrawalEffects(state.withdrawal)
    end
    if high and now >= high.endsAt then
        state.high = nil
        pcall(function() player:getModData().DazedHigh = nil end)
        player:setHaloNote("The high fades")
    end
    if not effects then return end
    -- In debug mode, log a snapshot every ten game minutes: what was asked for and what the stat did.
    local report = (now - state.lastLog) >= (10 / 60) and Config.debugOn()
    local parts = {}
    for stat, perHour in pairs(effects) do
        local before, after = applyStat(player, stat, perHour * step)
        if report and before then parts[#parts + 1] = string.format("%s %.4f->%.4f", stat, before, after) end
    end
    if report then
        state.lastLog = now
        log((high and "high" or "withdrawal") .. " tick: " .. table.concat(parts, ", "))
    end
end

local function eachLocalPlayer(fn)
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then fn(p) end
    end
end

-- Each player is skipped while sober and not craving, which is most of the time.
Events.EveryOneMinute.Add(function()
    local now = nil
    for i = 0, 3 do
        local st = states[i]
        if st and (st.high or st.withdrawal > 0) then
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then
                now = now or worldHours()
                High.tickPlayer(p, now, i)
            end
        end
    end
end)

local function requestState(player)
    sendClientCommand(player, Config.COMMAND_MODULE, "requestUseState", {})
end
Events.EveryHours.Add(function() eachLocalPlayer(requestState) end)

-- Pick the high back up after a reload, and ask for the withdrawal numbers.
Events.OnCreatePlayer.Add(function(index, player)
    local saved = player and player:getModData().DazedHigh
    if saved and saved.endsAt and saved.endsAt > worldHours() then High.stateFor(index).high = saved end
    if not player then return end
    -- A Chronic asks once per character to start hooked; the flag is saved with the character.
    local data = player:getModData()
    if not data.DazedChronicStart and CannabisMod.Traits.has(player, "chronic") then
        data.DazedChronicStart = true
        sendClientCommand(player, Config.COMMAND_MODULE, "chronicStart", {})
        return
    end
    requestState(player)
end)

local FEELINGS = {
    Indica = "A heavy calm settles over you",
    Sativa = "Bright and buzzing",
    Hybrid = "Easy and warm",
}

Net.clientHandlers.smoked = function(args, target)
    local player, index = High.targetOf(args, target)
    if not player then return end
    local state = High.stateFor(index)
    local now = worldHours()
    if Config.debugOn() then
        log(string.format("smoked reply: %s strength %.2f for %.2fh, moldy=%s, tolerance %s, dependency %s", tostring(args.type),
            args.strength or -1, args.hours or -1, tostring(args.moldy), tostring(args.tolerance), tostring(args.dependency)))
    end
    state.high = { type = args.type, strain = CannabisMod.Strains.sanitize(args.strain), moldy = args.moldy,
                   strength = args.strength, startedAt = now, endsAt = now + args.hours }
    pcall(function() player:getModData().DazedHigh = state.high end)
    state.withdrawal = 0
    state.tolerance, state.dependency = args.tolerance, args.dependency
    local msg
    if args.moldy then
        msg = "It's harsh and musty. That was a bad idea"
    elseif args.strength < 0.35 then
        msg = "You barely feel it. Your tolerance is high"
    else
        msg = FEELINGS[args.type] or FEELINGS.Hybrid
    end
    player:setHaloNote(msg)
end

Net.clientHandlers.useState = function(args, target)
    local player, index = High.targetOf(args, target)
    local state = High.stateFor(index)
    local before = state.withdrawal
    state.withdrawal = args.withdrawal or 0
    if Config.debugOn() then
        log(string.format("use state: withdrawal %.2f, tolerance %s, dependency %s", state.withdrawal, tostring(args.tolerance), tostring(args.dependency)))
    end
    if before < 0.1 and state.withdrawal >= 0.1 and not state.high then
        if player then player:setHaloNote("You're craving a smoke") end
    end
    state.tolerance, state.dependency = args.tolerance, args.dependency
end
