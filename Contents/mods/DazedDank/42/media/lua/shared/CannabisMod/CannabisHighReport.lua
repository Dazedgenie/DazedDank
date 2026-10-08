-- What the High Tracker window shows: the current high or withdrawal, tolerance and dependency, and the stat changes
-- being applied each hour. Pure functions over the client's high state, so the offline tests can check them.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisUse"

local Config = CannabisMod.Config
local Use = CannabisMod.Use

local Report = {}
CannabisMod.HighReport = Report

Report.ONSET_HOURS, Report.COMEDOWN_HOURS = 0.25, 0.5

-- Stats in the order shown, with how each is displayed: percent of a 0-1 bar, or points on a 0-100 bar.
Report.STATS = {
    { key = "STRESS", label = "Stress", scale = 100 },
    { key = "UNHAPPINESS", label = "Unhappiness", scale = 1 },
    { key = "BOREDOM", label = "Boredom", scale = 1 },
    { key = "FATIGUE", label = "Fatigue", scale = 100 },
    { key = "HUNGER", label = "Hunger", scale = 100 },
    { key = "THIRST", label = "Thirst", scale = 100 },
}

--- Strength of a high at `now`, easing in over the onset and out over the comedown.
function Report.strength(high, now)
    if not high then return 0 end
    local elapsed, remaining = now - high.startedAt, high.endsAt - now
    if remaining <= 0 then return 0 end
    return high.strength * math.min(1, elapsed / Report.ONSET_HOURS) * math.min(1, remaining / Report.COMEDOWN_HOURS)
end

--- "Coming up", "Peak" or "Coming down" for a high still running at `now`.
function Report.phase(high, now)
    if now - high.startedAt < Report.ONSET_HOURS then return "Coming up" end
    if high.endsAt - now < Report.COMEDOWN_HOURS then return "Coming down" end
    return "Peak"
end

--- Game hours as "1h 25m".
function Report.duration(hours)
    local minutes = math.max(0, math.floor(hours * 60 + 0.5))
    local h, m = math.floor(minutes / 60), minutes % 60
    if h == 0 then return m .. "m" end
    return h .. "h " .. string.format("%02dm", m)
end

--- One stat change per game hour, signed, in that stat's display units.
function Report.rate(stat, perHour)
    local v = perHour * stat.scale
    return string.format("%+.1f%s / h", v, stat.scale == 100 and "%" or "")
end

--- The tracker's rows for `state` (CannabisMod.High.state) at `now`: a list of { label, value } and a heading.
--- `current` (optional) maps stat keys to the player's current values, shown next to each rate.
function Report.build(state, now, current)
    local rows = {}
    local function row(label, value) rows[#rows + 1] = { label, value } end
    local high = state.high
    local effects, heading
    if high and now < high.endsAt then
        local s = Report.strength(high, now)
        local strain = high.strain and high.strain.name
        heading = "High"
        row("Smoked", (high.moldy and "Moldy " or "") .. (strain and (strain .. " (" .. tostring(high.type) .. ")") or tostring(high.type)))
        row("Phase", Report.phase(high, now))
        row("Strength", string.format("%.2f now, %.2f peak", s, high.strength))
        row("Time left", Report.duration(high.endsAt - now))
        if not high.moldy and s > Config.Use.ANXIETY_ABOVE and (not high.strain or (high.strain.ind or 50) < CannabisMod.Strains.INDICA_MIN) then
            row("Anxious", "yes: too strong for a racy strain")
        end
        effects = Use.highEffects(high.type, s, high.moldy, high.strain)
    elseif (state.withdrawal or 0) > 0 then
        heading = "Withdrawal"
        row("Withdrawal", string.format("%d%%", math.floor(state.withdrawal * 100 + 0.5)))
        effects = Use.withdrawalEffects(state.withdrawal)
    else
        heading = "Sober"
    end
    row("Tolerance", state.tolerance and string.format("%d / 100", math.floor(state.tolerance + 0.5)) or "?")
    row("Dependency", state.dependency and string.format("%d / 100", math.floor(state.dependency + 0.5)) or "?")
    if effects then
        for _, stat in ipairs(Report.STATS) do
            local perHour = effects[stat.key]
            if perHour and perHour ~= 0 then
                local text = Report.rate(stat, perHour)
                local now = current and current[stat.key]
                if now then text = text .. string.format("  (now %.0f%s)", now * stat.scale, stat.scale == 100 and "%" or "") end
                row(stat.label, text)
            end
        end
    end
    return heading, rows
end

return Report
