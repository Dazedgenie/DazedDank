-- Server-side rate limit for Dank's client commands. Self-contained: it does
-- not use Dazed Core. Each player has a token bucket across all commands, and
-- pure request/info commands also have a minimum gap (Config.RateLimit.EVERY).
-- Over-limit commands are dropped silently (one console line per player per
-- minute at most).

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local RL = {}
CannabisMod.RateLimit = RL

local players = {}      -- key -> { tokens, at, seen, lastCmd = {name = ms}, printedAt }
local lastSweep

--- Milliseconds clock. Tests replace it with RL.setClock. Returns nil when no clock exists (then nothing is limited).
local function defaultClock()
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        if ok and type(ms) == "number" then return ms end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" then return t * 1000 end
    end
    return nil
end
RL.clock = defaultClock

--- Replace the clock (a function returning ms); nil restores the default.
function RL.setClock(fn) RL.clock = fn or defaultClock end

--- Stable key for a player: the username, else tostring(player).
function RL.keyOf(player)
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return tostring(player)
end

--- Drop entries not seen for IDLE_MS.
function RL.sweep(now)
    local cfg = Config.RateLimit
    lastSweep = now
    for key, e in pairs(players) do
        if now - e.seen > cfg.IDLE_MS then players[key] = nil end
    end
end

--- Forget one player at once (disconnect).
function RL.forget(player) players[RL.keyOf(player)] = nil end

--- Number of players currently tracked (tests).
function RL.count()
    local n = 0
    for _ in pairs(players) do n = n + 1 end
    return n
end

--- True when this command from this player may run now; records it if so.
function RL.allow(player, command)
    local now = RL.clock()
    if not now then return true end
    local cfg = Config.RateLimit
    if not lastSweep or now < lastSweep or now - lastSweep >= cfg.SWEEP_MS then RL.sweep(now) end
    local key = RL.keyOf(player)
    local e = players[key]
    if not e then
        e = { tokens = cfg.CAPACITY, at = now, seen = now, lastCmd = {} }
        players[key] = e
    end
    local dt = now - e.at
    if dt > 0 then
        e.tokens = math.min(cfg.CAPACITY, e.tokens + dt * cfg.REFILL_PER_SEC / 1000)
    end
    e.at, e.seen = now, now

    local gap = cfg.EVERY[command]
    local prev = gap and e.lastCmd[command]
    local ok = true
    if prev and now >= prev and now - prev < gap then ok = false end
    if ok and e.tokens < 1 then ok = false end
    if ok then
        e.tokens = e.tokens - 1
        if gap then e.lastCmd[command] = now end
        return true
    end
    if not e.printedAt or now < e.printedAt or now - e.printedAt >= cfg.PRINT_MS then
        e.printedAt = now
        print("[DazedDank] rate limit: dropping commands from " .. key .. " (" .. tostring(command) .. ")")
    end
    return false
end

-- Free a player's entry on disconnect where the server offers the event.
pcall(function()
    if Events and Events.OnPlayerDisconnect and Events.OnPlayerDisconnect.Add then
        Events.OnPlayerDisconnect.Add(function(player) if player then RL.forget(player) end end)
    end
end)

return RL
