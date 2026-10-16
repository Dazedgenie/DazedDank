-- Temperatures from DazedCore's shared climate lookup when it is loaded, else from the game's climate manager.
-- Dazed Climate feeds DazedCore real room and outdoor temperatures; without it everything here still works.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config
local W = Config.Weather

local Weather = {}
CannabisMod.Weather = Weather

--- DazedCore's climate lookup, or nil when DazedCore (1.3.0 or later) isn't loaded.
function Weather.core()
    local core = DazedCore and DazedCore.Climate
    if type(core) == "table" and core.temperatureAt and core.outdoor then return core end
    return nil
end

--- The outdoor temperature in C, or nil when nothing can tell.
function Weather.outdoor()
    local core = Weather.core()
    if core then
        local ok, v = pcall(core.outdoor)
        if ok and type(v) == "number" then return v end
    end
    local ok, v = pcall(function() return getClimateManager():getTemperature() end)
    if ok and type(v) == "number" then return v end
    return nil
end

--- The air temperature in C at a square (its room's when indoors and Dazed Climate tracks rooms), or `fallback`.
function Weather.tempAt(square, fallback)
    if not square then return fallback end
    local core = Weather.core()
    if core then
        local ok, v = pcall(core.temperatureAt, square)
        if ok and type(v) == "number" then return v end
    end
    local ok, v = pcall(function() return getClimateManager():getAirTemperatureForSquare(square) end)
    if ok and type(v) == "number" then return v end
    return fallback
end

--- A temperature in C in the player's unit: the number and "C" or "F". Dazed Core's Temperatures option (Core 1.6.0+)
--  decides when Core is loaded, else the game's own Display > Temperature display option.
function Weather.display(t)
    local core = Weather.core()
    if core and core.display then
        local ok, v, unit = pcall(core.display, t)
        if ok and type(v) == "number" and unit then return v, unit end
    end
    local ok, celsius = pcall(function() return getCore():getOptionDisplayAsCelsius() end)
    if ok and celsius == false then return t * 9 / 5 + 32, "F" end
    return t, "C"
end

--- A temperature in C as text in the player's unit, with `decimals` places (default none): "23 C" or "73 F".
function Weather.tempText(t, decimals)
    local v, unit = Weather.display(t)
    if decimals and decimals > 0 then return string.format("%." .. decimals .. "f %s", v, unit) end
    return string.format("%d %s", math.floor(v + 0.5), unit)
end

--- A temperature the server writes into a room log line, kept in C so each player reads it in their own unit.
function Weather.logTemp(t)
    return string.format("{temp:%.1f}", t)
end

--- Log text with every temperature written by logTemp shown in the player's unit.
function Weather.localize(text)
    return (tostring(text):gsub("{temp:(%-?[%d%.]+)}", function(v) return Weather.tempText(tonumber(v) or 0) end))
end

--- True between NIGHT_FROM and NIGHT_TO game hours.
function Weather.isNight(hour)
    return hour >= W.NIGHT_FROM or hour < W.NIGHT_TO
end

--- How far outdoor growth slows at this temperature: 0 at 15 C and up, 0.5 at 10 C, 1 (stalled) at 5 C and below.
function Weather.slowdown(temp)
    if not temp then return 0 end
    return Config.clamp((W.SLOW_BELOW - temp) / (W.SLOW_BELOW - W.STALL_AT), 0, 1)
end

--- The chance (0-1) a plant turns purple after its cold nights: sativa-leaning rarely, indica-leaning often.
function Weather.purpleChance(strain)
    local lean = Config.clamp(((strain and strain.ind) or 50) / 100, 0, 1)
    return W.PURPLE_BASE + W.PURPLE_PER_INDICA * lean
end

--- A plant colour blended toward purple.
function Weather.purpleTint(r, g, b)
    local t, k = W.PURPLE_TINT, W.PURPLE_BLEND
    return r + (t[1] - r) * k, g + (t[2] - g) * k, b + (t[3] - b) * k
end

--- A purple plant's or bud's name with "Purple" in front; unchanged when not purple or the name already says purple.
function Weather.purpleName(data, word)
    word = tostring(word)
    if not (data and data.purple) or string.find(string.lower(word), "purple", 1, true) then return word end
    return Weather.purplePrefix() .. word
end

--- The word put before a purple strain name, with its trailing space.
function Weather.purplePrefix()
    local key = "Tooltip_DD_PurplePrefix"
    if getText then
        local ok, text = pcall(getText, key)
        if ok and type(text) == "string" and text ~= "" and text ~= key then return text .. " " end
    end
    return "Purple "
end

--- How fast buds cure at this temperature: full at 15-21 C, easing to half at 10 and 25 C, half beyond.
function Weather.cureSpeed(temp)
    if not temp or not Config.sandbox("CuringTemperature") then return 1 end
    if temp >= W.CURE_BEST_LO and temp <= W.CURE_BEST_HI then return 1 end
    local slow = W.CURE_SLOW
    if temp < W.CURE_BEST_LO then
        return 1 - (1 - slow) * Config.clamp((W.CURE_BEST_LO - temp) / (W.CURE_BEST_LO - W.CURE_OK_LO), 0, 1)
    end
    return 1 - (1 - slow) * Config.clamp((temp - W.CURE_BEST_HI) / (W.CURE_OK_HI - W.CURE_BEST_HI), 0, 1)
end

--- How much more often a missed burp molds at this temperature (1.5 above 25 C).
function Weather.cureMoldFactor(temp)
    if not temp or not Config.sandbox("CuringTemperature") then return 1 end
    if temp > W.CURE_OK_HI then return W.CURE_WARM_MOLD end
    return 1
end
