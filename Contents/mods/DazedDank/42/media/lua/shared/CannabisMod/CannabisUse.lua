-- The rules for using cannabis: potency, how long a high lasts, what it does, tolerance, dependency and withdrawal. Pure functions, no game calls.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local U = Config.Use

local Use = {}
CannabisMod.Use = Use

--- A fresh record for a player who has never used.
function Use.new()
    return { tol = 0, dep = 0, lastUse = nil, at = nil, doses = 0 }
end

--- Bring a record up to `now` (game hours): tolerance fades, and dependency fades after days off.
function Use.decay(user, now)
    local elapsed = math.max(0, now - (user.at or now))
    user.tol = math.max(0, user.tol - U.TOL_DECAY_PER_DAY * elapsed / 24)
    if user.lastUse and now - user.lastUse > U.DEP_DECAY_AFTER_DAYS * 24 then
        user.dep = math.max(0, user.dep - U.DEP_DECAY_PER_DAY * elapsed / 24)
    end
    user.at = now
end

--- How strong a bud is, 0.4 for poor up to 1.2 for premium and a little more for Top Shelf; mold ruins it.
function Use.potency(quality, moldy)
    if moldy then return U.MOLDY_POTENCY end
    return 0.4 + 0.8 * Config.clamp((quality or 50) / 100, 0, Config.maxQuality(true) / 100)
end

--- Take one dose. Returns strength (after tolerance) and how many game hours it lasts.
function Use.dose(user, now, potency, method)
    Use.decay(user, now)
    local m = Config.Smoking.METHODS[method] or Config.Smoking.METHODS.joint
    local reduction = U.TOL_MAX_REDUCTION * user.tol / 100
    local strength = potency * m.potency * (1 - reduction)
    local hours = Config.Smoking.BASE_HOURS * Config.clamp(strength, 0.3, 1.5)

    local regular = user.lastUse and (now - user.lastUse) <= U.DEP_REGULAR_HOURS
    if Config.sandbox("DependencyEnabled") then
        user.dep = Config.clamp(user.dep + U.DEP_GAIN * Config.sandbox("DependencyRate") * (regular and 1 or U.DEP_OCCASIONAL), 0, 100)
    end
    user.tol = Config.clamp(user.tol + U.TOL_GAIN * Config.sandbox("ToleranceRate") * m.tolerance * Config.clamp(potency, 0.5, 1.2), 0, 100)
    user.lastUse = now
    user.doses = (user.doses or 0) + 1
    return strength, hours
end

--- Withdrawal, 0 (none) to 1 (full), from dependency and time since the last dose.
function Use.withdrawal(user, now)
    if not Config.sandbox("DependencyEnabled") or not user.lastUse or user.dep < U.WITHDRAW_MIN_DEP then return 0 end
    local late = (now - user.lastUse - U.WITHDRAW_AFTER_HOURS) / 24
    return Config.clamp(late, 0, 1) * user.dep / 100
end

--- Per-hour stat changes for a high of `type` at `strength` (a 0-1.5 scale), or the moldy version.
function Use.highEffects(type, strength, moldy)
    local out = {}
    local base = moldy and U.MOLDY_EFFECTS or (U.EFFECTS[type] or U.EFFECTS.Hybrid)
    local scale = Config.sandbox("EffectStrength")
    for stat, perHour in pairs(base) do out[stat] = perHour * scale * (moldy and 1 or strength) end
    if not moldy and strength > U.ANXIETY_ABOVE and type ~= "Indica" then
        out.STRESS = (out.STRESS or 0) + U.ANXIETY_STRESS * (strength - U.ANXIETY_ABOVE) / (1.5 - U.ANXIETY_ABOVE) * scale
    end
    return out
end

--- Per-hour stat changes while withdrawing at `level` (0-1).
function Use.withdrawalEffects(level)
    local out = {}
    local scale = Config.sandbox("EffectStrength")
    for stat, perHour in pairs(U.WITHDRAWAL) do out[stat] = perHour * scale * level end
    return out
end
