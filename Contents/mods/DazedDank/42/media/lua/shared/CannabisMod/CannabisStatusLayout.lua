-- Lays out the plant status window as a flat list of draw operations. It makes no game calls, so the layout can be tested offline; the window class just draws the operations.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Layout = {}
CannabisMod.StatusLayout = Layout

Layout.WIDTH = 340
local PAD, GAP = 12, 8

local COLORS = {
    text   = { 0.92, 0.92, 0.92 },
    muted  = { 0.60, 0.62, 0.64 },
    track  = { 0.20, 0.22, 0.22 },
    good   = { 0.36, 0.76, 0.42 },
    warn   = { 0.92, 0.72, 0.22 },
    bad    = { 0.86, 0.32, 0.30 },
    water  = { 0.35, 0.65, 0.95 },
    Indica = { 0.62, 0.46, 0.86 },
    Sativa = { 0.95, 0.66, 0.26 },
    Hybrid = { 0.46, 0.80, 0.46 },
    plain  = { 0.46, 0.80, 0.46 },
}
Layout.COLORS = COLORS

-- Word bands from CannabisInfo, as levels from 1 (lowest) up; "good" says whether a higher level is better.
local BANDS = {
    healthBand      = { words = { "Poor", "Fair", "Good", "Excellent" }, good = true },
    stressBand      = { words = { "Low", "Moderate", "High", "Severe" }, good = false },
    geneticsBand    = { words = { "Degraded", "Drifting", "Strong" }, good = true },
    qualityEstimate = { words = { "Poor", "Fair", "Good", "Excellent", "Top Shelf" }, good = true },
}
local BAND_LABELS = { healthBand = "Health", stressBand = "Stress", geneticsBand = "Genetics", qualityEstimate = "Est. quality" }

local WARNINGS = {
    nutrientBurn = { "Nutrient burn", "bad" }, wrongNutrient = { "Wrong nutrient", "bad" }, overwatered = { "Overwatered", "bad" },
    underwatered = { "Underwatered", "warn" }, noLight = { "No light", "bad" }, lightInterrupted = { "Light interrupted", "warn" },
    lightLeak = { "Light leak", "bad" }, hungry = { "Hungry", "warn" },
    reservoirDry = { "Reservoir dry", "bad" }, staleReservoir = { "Stale reservoir", "warn" },
    pumpOff = { "Pumps off", "bad" }, rootRot = { "Root rot", "bad" }, noControl = { "No control bucket", "bad" },
    noFlood = { "No flood reservoir", "bad" }, mediumDry = { "Rockwool dry", "bad" },
}

--- "1 d 6 h" style text for a number of hours.
function Layout.formatHours(hours)
    local d, h = math.floor(hours / 24), math.floor(hours % 24)
    if d > 0 then return d .. " d " .. h .. " h" end
    return h .. " h"
end

--- The lowest Agriculture level above `level` that unlocks more info, or nil when everything is visible.
function Layout.nextUnlock(level)
    for _, tier in ipairs(Config.InfoTiers) do
        if tier.level > level then return tier.level end
    end
    return nil
end

--- Add a 7x8 pixel arrow made of rects at (x, y): pointing up for 1, down for -1, a flat dash for 0.
function Layout.arrow(ops, x, y, dir, color)
    if dir == 0 then
        ops[#ops + 1] = { kind = "rect", x = x, y = y + 3, w = 7, h = 2, color = color, a = 1 }
        return
    end
    for i = 0, 3 do
        local row = dir > 0 and i or (7 - i)   -- up: tip on top; down: stem on top, tip at the bottom
        ops[#ops + 1] = { kind = "rect", x = x + 3 - i, y = y + row, w = 1 + 2 * i, h = 1, color = color, a = 1 }
    end
    ops[#ops + 1] = { kind = "rect", x = x + 2, y = dir > 0 and y + 4 or y, w = 3, h = 4, color = color, a = 1 }
end

--- Build the layout for a plant info reply.
--- @param data the reply from the server (field -> value, plus level)
--- @param fontH function(font) -> line height; measure: function(font, text) -> width
--- @return table { width, height, ops, accent }, where each op is rect / text / pill with a position and colour
function Layout.build(data, fontH, measure)
    local W = Layout.WIDTH
    local ops, y = {}, PAD
    local small, medium = fontH("Small"), fontH("Medium")

    local function rect(x, ry, w, h, color, a) ops[#ops + 1] = { kind = "rect", x = x, y = ry, w = w, h = h, color = color, a = a or 1 } end
    local function text(str, x, ty, color, font, align)
        ops[#ops + 1] = { kind = "text", x = x, y = ty, text = str, color = color, font = font or "Small", align = align or "left" }
    end
    local function row(label, value, color)
        text(label, PAD, y, COLORS.muted)
        text(tostring(value), W - PAD, y, color or COLORS.text, "Small", "right")
        y = y + small + 4
    end

    local accent = COLORS[data.type] or COLORS.plain

    -- Header: name and where it grows, with the strain chip on the right.
    rect(0, 0, W, PAD + medium + small + 10, accent, 0.22)
    rect(0, 0, 4, PAD + medium + small + 10, accent, 1)
    text(data.name or "Cannabis Plant", PAD, y, COLORS.text, "Medium")
    if data.type then
        local label = data.type .. (data.sex and (" " .. data.sex) or "")
        local cw = measure("Small", label) + 14
        rect(W - PAD - cw, y + 2, cw, small + 4, accent, 0.9)
        text(label, W - PAD - cw / 2, y + 4, { 0.08, 0.08, 0.08 }, "Small", "center")
    end
    y = y + medium + 2
    text(data.container and ("Planted in: " .. data.container) or "", PAD, y, COLORS.muted)
    y = y + small + 18

    -- Growth: five-step track when the stage is known, a rough word otherwise.
    if data.stage and Config.STAGE[data.stage] then
        local current, count = Config.STAGE[data.stage], #Config.STAGES
        local segW = (W - 2 * PAD - (count - 1) * 3) / count
        for i = 1, count do
            local color = i < current and COLORS.good or (i == current and accent or COLORS.track)
            rect(PAD + (i - 1) * (segW + 3), y, segW, 8, color, i <= current and 1 or 0.9)
        end
        y = y + 8 + 4
        text(data.stage, PAD, y, COLORS.text)
        if data.vegHeld then
            text("held in veg until 12/12", W - PAD, y, COLORS.warn, "Small", "right")
        elseif data.hoursLeft then
            text("next stage in " .. Layout.formatHours(data.hoursLeft), W - PAD, y, COLORS.muted, "Small", "right")
        end
        y = y + small + GAP
    elseif data.stageRough then
        row("Growth", data.stageRough)
    end
    if data.rooting then row("", data.rooting, COLORS.warn) end

    -- Hydro: the reservoir replaces the water bar; an RDWC site shows the shared reservoir of its control bucket.
    if data.reservoir then
        local r = data.reservoir
        local title = r.ebb and "Flood reservoir" or "Shared reservoir"
        text(r.sites and (title .. " (" .. r.sites .. " sites)") or "Reservoir", PAD, y, COLORS.muted)
        if r.unlinked then
            text("Not connected", W - PAD, y, COLORS.bad, "Small", "right")
            y = y + small + GAP
        else
            text(r.level .. " / " .. r.cap .. " L" .. (r.stale and "  (stale)" or ""), W - PAD, y, r.stale and COLORS.warn or COLORS.text, "Small", "right")
            y = y + small + 2
            local bw = W - 2 * PAD
            rect(PAD, y, bw, 8, COLORS.track)
            rect(PAD, y, bw * Config.clamp(r.level / math.max(1, r.cap), 0, 1), 8, r.level > 0 and COLORS.water or COLORS.bad)
            y = y + 8 + GAP
            local food = r.nutrient and (r.nutrient .. " " .. r.strength .. "%") or "None"
            local low = r.strength < Config.Hydro.HUNGRY_BELOW * 100
            row("Nutrients", food, low and COLORS.warn or COLORS.text)
            -- Ebb and Flow: how long the rockwool stays wet, or that a timer keeps it flooded.
            if r.ebb then
                local wet = r.wetHours and r.wetHours > 0
                local text2 = r.floodTimer and wet and "Wet (flood timer)" or (wet and ("Wet for " .. Layout.formatHours(r.wetHours)) or "Dry: flood the tables")
                row("Rockwool", text2, wet and COLORS.text or COLORS.bad)
            end
        end
    end
    if data.roots then
        local color = data.roots == "Healthy" and COLORS.good or (data.roots == "Browning" and COLORS.warn or COLORS.bad)
        if data.rootRot then
            -- Root rot as a bar, with a mark where early (treatable) rot ends.
            text("Root rot", PAD, y, COLORS.muted)
            local right = W - PAD
            if data.rootRotTrend then
                -- Trend arrow at the right edge: red pointing up while rot spreads, green pointing down while it heals.
                Layout.arrow(ops, right - 7, y + 3, data.rootRotTrend, data.rootRotTrend > 0 and COLORS.bad
                    or (data.rootRotTrend < 0 and COLORS.good or COLORS.muted))
                right = right - 12
            end
            text(data.roots .. "  " .. data.rootRot .. "%", right, y, color, "Small", "right")
            y = y + small + 2
            local bw = W - 2 * PAD
            rect(PAD, y, bw, 8, COLORS.track)
            rect(PAD, y, bw * Config.clamp(data.rootRot, 0, 100) / 100, 8, color)
            rect(PAD + bw * Config.Hydro.ROT_EARLY / 100, y - 2, 1, 12, COLORS.muted)
            y = y + 8 + GAP
        else
            row("Roots", data.roots, color)
        end
    end

    -- Water: a bar with the healthy zone marked.
    if data.water and not data.reservoir then
        text("Water", PAD, y, COLORS.muted)
        text(tostring(data.water), W - PAD, y, COLORS.text, "Small", "right")
        y = y + small + 2
        local bw = W - 2 * PAD
        local w = Config.clamp(data.water, 0, 100)
        local color = (w < Config.Water.LOW) and COLORS.warn or ((w > Config.Water.HIGH) and COLORS.bad or COLORS.water)
        rect(PAD, y, bw, 8, COLORS.track)
        rect(PAD, y, bw * w / 100, 8, color)
        rect(PAD + bw * Config.Water.LOW / 100, y - 2, 1, 12, COLORS.muted)
        rect(PAD + bw * Config.Water.HIGH / 100, y - 2, 1, 12, COLORS.muted)
        y = y + 8 + GAP
    elseif data.waterRough then
        local color = (data.waterRough == "OK") and COLORS.good or COLORS.warn
        row("Watering", data.waterRough, color)
    end

    -- Quality-style meters: a row of pills filled to the band's level.
    local shownBand = false
    for _, key in ipairs({ "healthBand", "stressBand", "geneticsBand", "qualityEstimate" }) do
        local word, def = data[key], BANDS[key]
        if word then
            shownBand = true
            local level = #def.words
            for i, candidate in ipairs(def.words) do if candidate == word then level = i end end
            local fraction = level / #def.words
            local good = def.good and fraction or ((#def.words - level) / (#def.words - 1))
            local color = (good > 0.7) and COLORS.good or ((good > 0.4) and COLORS.warn or COLORS.bad)
            text(BAND_LABELS[key], PAD, y, COLORS.muted)
            local pillW, pillGap = 16, 3
            local x = W - PAD - (#def.words * (pillW + pillGap) - pillGap) - measure("Small", word) - 8
            text(word, W - PAD, y, color, "Small", "right")
            for i = 1, #def.words do
                rect(x + (i - 1) * (pillW + pillGap), y + 4, pillW, small - 6, i <= level and color or COLORS.track)
            end
            y = y + small + 4
        end
    end
    if shownBand then y = y + 2 end

    -- Plain facts.
    if data.light then row("Light", data.light, (data.light == "None") and COLORS.bad or COLORS.text) end
    if data.lightCycle then row("Light cycle", data.lightCycle, (data.lightCycle == "Light leak") and COLORS.bad or COLORS.text) end
    if data.extraVeg then
        row("Extra veg", Layout.formatHours(data.extraVeg.hours) .. "  (+" .. data.extraVeg.bonus .. "% yield)", COLORS.good)
    end
    if data.lastNutrient then row("Last nutrient", data.lastNutrient) end
    if data.harvestWindow then
        local color = (data.harvestWindow == "Ready now") and COLORS.good or ((data.harvestWindow == "Overripe") and COLORS.warn or COLORS.text)
        row("Harvest", data.harvestWindow, color)
    end
    if data.pollinated ~= nil then row("Pollinated", data.pollinated and "Yes" or "No", data.pollinated and COLORS.warn or COLORS.text) end
    if data.hermieSigns then row("Hermie signs", "Yes", COLORS.bad) end
    if data.generation then row("Generation", data.generation) end

    -- Warnings as chips.
    if data.warnings and #data.warnings > 0 then
        y = y + 4
        local x = PAD
        for _, key in ipairs(data.warnings) do
            local def = WARNINGS[key] or { key, "warn" }
            local cw = measure("Small", def[1]) + 14
            if x + cw > W - PAD then x = PAD; y = y + small + 8 end
            rect(x, y, cw, small + 4, COLORS[def[2]], 0.85)
            text(def[1], x + cw / 2, y + 2, { 0.08, 0.08, 0.08 }, "Small", "center")
            x = x + cw + 6
        end
        y = y + small + 4 + GAP
    end

    -- Footer: what more Agriculture would show.
    local nextLevel = Layout.nextUnlock(data.level or 0)
    y = y + 2
    rect(PAD, y, W - 2 * PAD, 1, COLORS.track)
    y = y + 6
    local foot = "Agriculture " .. tostring(data.level or 0)
    if nextLevel then foot = foot .. "  -  more detail at level " .. nextLevel end
    text(foot, PAD, y, COLORS.muted)
    y = y + small + PAD

    return { width = W, height = y, ops = ops, accent = accent }
end
