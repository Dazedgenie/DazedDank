-- Timing in one place: CannabisMod.TenMinutes runs the server's ten-minute steps in a fixed order, and
-- CannabisMod.Ticker runs delayed and repeating jobs from a single OnTick handler.

require "CannabisMod/CannabisConfig"

-- --------------------------------------------------------------------------
-- Ten-minute steps
-- --------------------------------------------------------------------------

local TenMinutes = CannabisMod.TenMinutes or { steps = {} }
CannabisMod.TenMinutes = TenMinutes

-- Room shapes first so everything after sees this tick's rooms; the plant tick before the room climate that reads it.
TenMinutes.ORDER = { "roomsRebuild", "timersCleanup", "hydroCleanup", "plants", "vanillaCrops", "roomsTick", "drip", "drying", "domes" }

--- Set the function a named step runs (names from TenMinutes.ORDER).
function TenMinutes.set(name, fn) TenMinutes.steps[name] = fn end

--- Run every step in order; one failing step is reported and the rest still run.
function TenMinutes.run()
    for _, name in ipairs(TenMinutes.ORDER) do
        local fn = TenMinutes.steps[name]
        if fn then
            local ok, err = pcall(fn)
            if not ok then print("[DazedDank] ten-minute step " .. name .. " failed: " .. tostring(err)) end
        end
    end
end

-- --------------------------------------------------------------------------
-- Ticker
-- --------------------------------------------------------------------------

local Ticker = CannabisMod.Ticker or { delayed = {}, repeating = {} }
CannabisMod.Ticker = Ticker

--- Run fn once after `ms` milliseconds. With a key, a newer call for the same key replaces the waiting one and restarts its wait.
function Ticker.after(ms, fn, key)
    local at = getTimestampMs() + ms
    if key then
        for _, job in ipairs(Ticker.delayed) do
            if job.key == key then
                job.at, job.fn = at, fn
                return
            end
        end
    end
    Ticker.delayed[#Ticker.delayed + 1] = { at = at, fn = fn, key = key }
end

--- Run fn every `n` ticks (1 = every tick); `label` names it if it fails.
function Ticker.every(n, fn, label)
    Ticker.repeating[#Ticker.repeating + 1] = { n = math.max(1, n or 1), fn = fn, label = label or "tick job", count = 0 }
end

local warned = {}

--- One game tick: the repeating jobs that are due, then the delayed jobs whose time has come.
function Ticker.tick()
    for _, job in ipairs(Ticker.repeating) do
        job.count = job.count + 1
        if job.count >= job.n then
            job.count = 0
            local ok, err = pcall(job.fn)
            if not ok and not warned[job.label] then
                warned[job.label] = true
                print("[DazedDank] " .. job.label .. " failed: " .. tostring(err))
            end
        end
    end
    local delayed = Ticker.delayed
    if #delayed == 0 then return end
    local now, due = getTimestampMs(), nil
    for i = #delayed, 1, -1 do
        if delayed[i].at <= now then
            due = due or {}
            due[#due + 1] = delayed[i]
            table.remove(delayed, i)
        end
    end
    if not due then return end
    for i = #due, 1, -1 do
        local ok, err = pcall(due[i].fn)
        if not ok then print("[DazedDank] delayed job failed: " .. tostring(err)) end
    end
end

-- One handler per event however many files use them; a reload of this file doesn't add a second.
if Events and not TenMinutes.hooked then
    TenMinutes.hooked = true
    if Events.EveryTenMinutes then Events.EveryTenMinutes.Add(function() TenMinutes.run() end) end
    if Events.OnTick then Events.OnTick.Add(function() Ticker.tick() end) end
end

return TenMinutes
