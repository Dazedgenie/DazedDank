-- The grow room climate model: how warm and humid a room gets and when its equipment runs.
-- Pure functions of plain numbers, so the Rooms module feeds them what it finds and tests can feed them anything.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local K = Config.Climate

local Climate = {}
CannabisMod.Climate = Climate

--- The comfortable ranges for a room mode. `young` picks the humid range for seedlings and clones.
function Climate.targets(mode, young)
    local t = K.TARGETS[mode] or K.TARGETS.Veg
    local hLo, hHi = t.hLo, t.hHi
    if young then hLo, hHi = t.youngLo, t.youngHi end
    return { tLo = t.tLo, tHi = t.tHi, hLo = hLo, hHi = hHi }
end

--- A machine count: `true` means one running, a number means that many, anything else none.
local function count(v)
    if v == true then return 1 end
    return tonumber(v) or 0
end

--- Where the room would settle with these inputs, as temperature and humidity.
--- Inputs: outT, outH (outdoors), lampHeat and moisture (gains), exhaust and intake (effective fan sums), heater, humidifier, dehumidifier,
--- cooler and circfan (how many are running).
function Climate.balance(i)
    local vent = K.BASE_VENT + i.exhaust + i.intake
    local t = i.outT + math.min(K.MAX_RISE, (i.lampHeat + count(i.heater) * K.HEATER_C) / vent)
    -- Cooling works whatever the weather: ACs pull heat out (down to a floor), circulation fans take the edge off.
    t = t - math.min(K.CIRC_FAN_MAX_C, count(i.circfan) * K.CIRC_FAN_C)
    local coolers = count(i.cooler)
    if coolers > 0 and t > K.COOLER_FLOOR_C then t = math.max(K.COOLER_FLOOR_C, t - coolers * K.COOLER_C) end
    local h = i.outH + i.moisture / vent
    h = h + count(i.humidifier) * K.HUMIDIFIER - count(i.dehumidifier) * K.DEHUMIDIFIER - coolers * K.COOLER_DRY
    return t, Config.clamp(h, 5, 100)
end

--- Move the room's temperature and humidity part of the way toward where it would settle.
function Climate.step(room, inputs)
    local t, h = Climate.balance(inputs)
    local nowT = room.temp or inputs.outT
    local nowH = room.hum or inputs.outH
    room.temp = nowT + (t - nowT) * K.RELAX
    room.hum = nowH + (h - nowH) * K.RELAX
end

--- Decide which equipment runs. `present` says which kinds the room has, `override` maps a kind to "on" or "off" (anything else is automatic).
--- The automatic state lives in room.auto so a heater or fan doesn't flick on and off around its limit. Returns the running kinds as a set.
function Climate.control(room, targets, present, override)
    local auto = room.auto or {}
    room.auto = auto
    local T, H = room.temp, room.hum
    local mid = (targets.hLo + targets.hHi) / 2
    if present.heater then
        if T < targets.tLo then auto.heater = true elseif T >= targets.tLo + 1.5 then auto.heater = false end
    end
    if present.exhaust or present.intake then
        if T > targets.tHi or H > targets.hHi then auto.exhaust = true
        elseif T <= targets.tHi - 1 and H <= targets.hHi - 3 then auto.exhaust = false end
        auto.intake = auto.exhaust
    end
    -- The AC runs above the room's top temperature and rests 2 C under it; fans start a little earlier. Neither fights the heater.
    local heating = auto.heater or (override and override.heater == "on")
    if present.cooler then
        if T > targets.tHi then auto.cooler = true elseif T <= targets.tHi - 2 then auto.cooler = false end
        if heating then auto.cooler = false end
    end
    if present.circfan then
        if T > targets.tHi - 1 then auto.circfan = true elseif T <= targets.tHi - 2.5 then auto.circfan = false end
        if heating then auto.circfan = false end
    end
    if present.dehumidifier then
        if H > targets.hHi then auto.dehumidifier = true elseif H <= mid then auto.dehumidifier = false end
    end
    if present.humidifier then
        if H < targets.hLo then auto.humidifier = true elseif H >= mid then auto.humidifier = false end
    end
    local on = {}
    for _, kind in ipairs(Config.Rooms.EQUIPMENT_ORDER) do
        if present[kind] then
            local forced = override and override[kind]
            if forced == "on" then on[kind] = true
            elseif forced == "off" then on[kind] = false
            else on[kind] = auto[kind] == true end
        end
    end
    return on
end

--- Stress per ten minutes a plant takes from the room's air, and which warnings apply: returns stress, tempWarning, humidWarning.
function Climate.plantStress(temp, hum, flowering)
    local stress, hot, wet = 0, false, false
    if temp < K.TEMP_STRESS_BELOW or temp > K.TEMP_STRESS_ABOVE then
        stress = stress + K.TEMP_STRESS_PER_HOUR / 6
        hot = true
    end
    if flowering and hum > K.FLOWER_MOLD_ABOVE then
        stress = stress + K.MOLD_STRESS_PER_HOUR / 6
        wet = true
    end
    return stress, hot, wet
end

--- How much faster (above 1) or slower (below 1) wet plants dry in air of this humidity.
function Climate.dryFactor(hum)
    return Config.clamp(1 + (K.MOLD_REF_HUMIDITY - hum) * K.DRY_PER_HUMIDITY, 0.5, 1.5)
end

--- How much more (above 1) or less (below 1) likely mold is in air of this humidity.
function Climate.moldFactor(hum)
    return Config.clamp(1 + (hum - K.MOLD_REF_HUMIDITY) * K.MOLD_PER_HUMIDITY, 0.3, 4)
end
