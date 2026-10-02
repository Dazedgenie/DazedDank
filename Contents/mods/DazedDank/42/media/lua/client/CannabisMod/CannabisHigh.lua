-- Client side of the high and of withdrawal: applies stat changes to the local player each game minute, and keeps the server's tolerance numbers in sync.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisUse"
require "CannabisMod/CannabisNet"

local Config = CannabisMod.Config
local Use    = CannabisMod.Use
local Net    = CannabisMod.Net

local High = {}
CannabisMod.High = High

local ONSET_HOURS, COMEDOWN_HOURS = 0.25, 0.5
local state = { high = nil, withdrawal = 0 }
High.state = state

local function worldHours() return getGameTime():getWorldAgeHours() end

local missing = {}
local lastLog = 0

--- Writes a [DazedDank] line to console.txt so effects can be checked from the log.
local function log(text) print("[DazedDank] " .. text) end

--- Add `delta` to a character stat by name, ignoring stats this game version doesn't have; returns before and after values.
local function applyStat(player, name, delta)
    local before, after
    local ok, err = pcall(function()
        local stat = CharacterStat and CharacterStat[name]
        if not stat then
            if not missing[name] then missing[name] = true; log("stat " .. name .. " does not exist in this game version, skipped") end
            return
        end
        local stats = player:getStats()
        before = stats:get(stat)
        if delta >= 0 then stats:add(stat, delta) else stats:remove(stat, -delta) end
        after = stats:get(stat)
    end)
    if not ok then log("stat " .. name .. " failed: " .. tostring(err)) end
    return before, after
end

--- Strength of the current high now, easing in and out.
function High.currentStrength(high, now)
    if not high then return 0 end
    local elapsed, remaining = now - high.startedAt, high.endsAt - now
    if remaining <= 0 then return 0 end
    return high.strength * math.min(1, elapsed / ONSET_HOURS) * math.min(1, remaining / COMEDOWN_HOURS)
end

--- One game minute of effects for one player.
function High.tickPlayer(player, now)
    local step = 1 / 60
    local high = state.high
    local effects
    if high and now < high.endsAt then
        effects = Use.highEffects(high.type, High.currentStrength(high, now), high.moldy)
    elseif state.withdrawal > 0 then
        effects = Use.withdrawalEffects(state.withdrawal)
    end
    if high and now >= high.endsAt then
        state.high = nil
        pcall(function() player:getModData().DazedHigh = nil end)
        player:setHaloNote("The high fades")
    end
    if not effects then return end
    -- Log a snapshot every ten game minutes: what was asked for and what the stat did.
    local report = (now - lastLog) >= (10 / 60)
    local parts = {}
    for stat, perHour in pairs(effects) do
        local before, after = applyStat(player, stat, perHour * step)
        if report and before then parts[#parts + 1] = string.format("%s %.4f->%.4f", stat, before, after) end
    end
    if report then
        lastLog = now
        log((high and "high" or "withdrawal") .. " tick: " .. table.concat(parts, ", "))
    end
end

local function eachLocalPlayer(fn)
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then fn(p) end
    end
end

Events.EveryOneMinute.Add(function()
    local now = worldHours()
    eachLocalPlayer(function(p) High.tickPlayer(p, now) end)
end)

local function requestState(player)
    sendClientCommand(player, Config.COMMAND_MODULE, "requestUseState", {})
end
Events.EveryHours.Add(function() eachLocalPlayer(requestState) end)

-- Pick the high back up after a reload, and ask for the withdrawal numbers.
Events.OnCreatePlayer.Add(function(index, player)
    local saved = player and player:getModData().DazedHigh
    if saved and saved.endsAt and saved.endsAt > worldHours() then state.high = saved end
    if player then requestState(player) end
end)

local FEELINGS = {
    Indica = "A heavy calm settles over you",
    Sativa = "Bright and buzzing",
    Hybrid = "Easy and warm",
}

Net.clientHandlers.smoked = function(args)
    local player = getSpecificPlayer(0)
    if not player then return end
    local now = worldHours()
    log(string.format("smoked reply: %s strength %.2f for %.2fh, moldy=%s, tolerance %s, dependency %s", tostring(args.type),
        args.strength or -1, args.hours or -1, tostring(args.moldy), tostring(args.tolerance), tostring(args.dependency)))
    state.high = { type = args.type, moldy = args.moldy, strength = args.strength,
                   startedAt = now, endsAt = now + args.hours }
    pcall(function() player:getModData().DazedHigh = state.high end)
    state.withdrawal = 0
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

Net.clientHandlers.useState = function(args)
    local before = state.withdrawal
    state.withdrawal = args.withdrawal or 0
    log(string.format("use state: withdrawal %.2f, tolerance %s, dependency %s", state.withdrawal, tostring(args.tolerance), tostring(args.dependency)))
    if before < 0.1 and state.withdrawal >= 0.1 and not state.high then
        local player = getSpecificPlayer(0)
        if player then player:setHaloNote("You're craving a smoke") end
    end
    state.tolerance, state.dependency = args.tolerance, args.dependency
end
