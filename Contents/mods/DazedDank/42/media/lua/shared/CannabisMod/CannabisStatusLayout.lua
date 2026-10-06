-- Lays out the plant status window as a flat list of draw operations, in the Grow Room dashboard style: cream cards on a
-- dark title bar. It makes no game calls, so the layout can be tested offline; the window class just draws the operations.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Layout = {}
CannabisMod.StatusLayout = Layout

Layout.WIDTH = 420
local M, PAD, GAP = 12, 14, 10        -- window margin, padding inside a card, gap between cards
local HEAD_H = 40

local COLORS = {
    ground = { 0.953, 0.941, 0.918 },
    card   = { 1, 1, 1 },
    line   = { 0.863, 0.839, 0.800 },
    head   = { 0.169, 0.122, 0.239 },
    text   = { 0.149, 0.133, 0.169 },
    muted  = { 0.490, 0.463, 0.518 },
    track  = { 0.925, 0.906, 0.875 },
    photo  = { 0.937, 0.914, 0.969 },
    white  = { 1, 1, 1 },
    purple = { 0.482, 0.247, 0.878 },
    good   = { 0.184, 0.620, 0.310 },
    warn   = { 0.788, 0.541, 0.071 },
    bad    = { 0.800, 0.227, 0.200 },
    water  = { 0.169, 0.482, 0.816 },
    alert  = { 0.992, 0.945, 0.847 },
    Indica = { 0.482, 0.247, 0.878 },
    Sativa = { 0.851, 0.522, 0.122 },
    Hybrid = { 0.184, 0.620, 0.310 },
    plain  = { 0.184, 0.620, 0.310 },
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
    lightLeak = { "Light leak", "bad" }, hungry = { "Hungry", "warn" }, overcut = { "Cut too hard", "bad" },
    roomTemp = { "Room temperature", "warn" }, roomHumid = { "Humid room", "warn" }, outdoorTemp = { "Outdoor temperature", "warn" },
    reservoirDry = { "Reservoir dry", "bad" }, staleReservoir = { "Stale reservoir", "warn" },
    pumpOff = { "Pumps off", "bad" }, rootRot = { "Root rot", "bad" }, noControl = { "No control bucket", "bad" },
    noFlood = { "No flood reservoir", "bad" }, mediumDry = { "Rockwool dry", "bad" },
}

local STAGE_SHORT = { Seedling = "Seed", Vegetative = "Veg", PreFlower = "Pre", Flowering = "Flower", Ripe = "Ripe" }
local STAGE_NAME = { PreFlower = "Pre-flower" }

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
--- @param data the reply from the server (field -> value, plus level, and the plant's sprites when known)
--- @param fontH function(font) -> line height; measure: function(font, text) -> width
--- @return table { width, height, ops, accent }; ops are rect, text, card (rounded box), pill and plant (sprite) operations
function Layout.build(data, fontH, measure)
    local W = Layout.WIDTH
    local ops = {}
    local small, medium = fontH("Small"), fontH("Medium")
    local accent = COLORS[data.type] or COLORS.plain
    local IW = W - 2 * M - 2 * PAD          -- inner width of a card

    local function rect(x, y, w, h, color, a) ops[#ops + 1] = { kind = "rect", x = x, y = y, w = w, h = h, color = color, a = a or 1 } end
    local function pill(x, y, w, h, color) ops[#ops + 1] = { kind = "pill", x = x, y = y, w = w, h = h, color = color } end
    local function text(str, x, y, color, font, align)
        ops[#ops + 1] = { kind = "text", x = x, y = y, text = tostring(str), color = color, font = font or "Small", align = align or "left" }
    end
    local function label(str, x, y) text(string.upper(str), x, y, COLORS.muted) end

    -- Cards are laid out top to bottom; each is opened, filled, then closed once its height is known.
    local y = HEAD_H + M
    local cardOp
    local function openCard()
        cardOp = { kind = "card", x = M, y = y, w = W - 2 * M, h = 0, color = COLORS.card, border = COLORS.line }
        ops[#ops + 1] = cardOp
        return y + PAD
    end
    local function closeCard(bottom)
        cardOp.h = bottom + PAD - cardOp.y
        y = cardOp.y + cardOp.h + GAP
    end
    local L = M + PAD                       -- left edge of card content
    local R = W - M - PAD                   -- right edge of card content

    -- Title bar: the strain (or the plain name), with type and sex tags.
    rect(0, 0, W, HEAD_H, COLORS.head)
    local title = data.strain or data.name or "Cannabis Plant"
    text(title, M, math.floor((HEAD_H - medium) / 2), COLORS.white, "Medium")
    local tx = M + measure("Medium", title) + 10
    for _, tag in ipairs({ data.type, data.sex }) do
        local w = measure("Small", string.upper(tag)) + 16
        if tx + w <= W - 44 then
            local male = tag == "Male" or tag == "Hermaphrodite"
            pill(tx, math.floor((HEAD_H - small - 6) / 2), w, small + 6, (tag == data.type) and accent or (male and COLORS.bad or { 0.29, 0.18, 0.36 }))
            text(string.upper(tag), tx + w / 2, math.floor((HEAD_H - small) / 2), COLORS.white, "Small", "center")
            tx = tx + w + 6
        end
    end

    -- Plant card: the plant itself, its looks, where it grows and how far along it is.
    local top = openCard()
    local photoW, photoH = 118, 150
    ops[#ops + 1] = { kind = "rect", x = L, y = top, w = photoW, h = photoH, color = COLORS.photo, a = 1 }
    if data.sprite then
        ops[#ops + 1] = { kind = "plant", x = L, y = top, w = photoW, h = photoH, sprite = data.sprite, pot = data.potSprite, lift = data.lift or 0 }
    end
    local cx = L + photoW + 12
    local cw = R - cx
    local cy = top + 2
    if data.looks then
        label("Looks", cx, cy); cy = cy + small + 1
        text(data.looks, cx, cy, COLORS.text); cy = cy + small + 8
    end
    if data.container then
        label("Planted in", cx, cy); cy = cy + small + 1
        text(data.container .. (data.generation and ("  ·  Gen " .. data.generation) or ""), cx, cy, COLORS.text); cy = cy + small + 8
    end
    if data.stage and Config.STAGE[data.stage] then
        label("Stage", cx, cy)
        if data.vegHeld then
            text("held in veg", R, cy, COLORS.warn, "Small", "right")
        elseif data.hoursLeft then
            text("next in " .. Layout.formatHours(data.hoursLeft), R, cy, COLORS.muted, "Small", "right")
        end
        cy = cy + small + 3
        local current, count = Config.STAGE[data.stage], #Config.STAGES
        local segW = (cw - (count - 1) * 4) / count
        for i = 1, count do
            local color = i < current and COLORS.good or (i == current and COLORS.purple or COLORS.track)
            pill(cx + (i - 1) * (segW + 4), cy, segW, 7, color)
            local name = STAGE_SHORT[Config.STAGES[i]] or Config.STAGES[i]
            text(name, cx + (i - 1) * (segW + 4) + segW / 2, cy + 10, i <= current and COLORS.text or COLORS.muted, "Small", "center")
        end
        cy = cy + 10 + small + 6
        text(STAGE_NAME[data.stage] or data.stage, cx, cy, COLORS.purple, "Medium"); cy = cy + medium
    elseif data.stageRough then
        label("Growth", cx, cy); cy = cy + small + 1
        text(data.stageRough, cx, cy, COLORS.text, "Medium"); cy = cy + medium
    end
    if data.rooting then cy = cy + 4; text(data.rooting, cx, cy, COLORS.warn); cy = cy + small end
    closeCard(math.max(top + photoH, cy))

    -- Vitals: water (or the reservoir), roots, and the word bands as pill meters.
    local hasBands = data.healthBand or data.stressBand or data.geneticsBand or data.qualityEstimate
    if data.water or data.waterRough or data.reservoir or data.roots or hasBands then
        local vy = openCard()
        label("Vitals", L, vy); vy = vy + small + 6
        local function bar(frac, color, marks)
            rect(L, vy, IW, 8, COLORS.track)
            rect(L, vy, IW * Config.clamp(frac, 0, 1), 8, color)
            for _, m in ipairs(marks or {}) do rect(L + IW * m, vy - 2, 1, 12, COLORS.muted) end
            vy = vy + 8 + 8
        end
        if data.reservoir then
            local r = data.reservoir
            local title2 = r.ebb and "Flood reservoir" or "Shared reservoir"
            text(r.sites and (title2 .. " (" .. r.sites .. " sites)") or "Reservoir", L, vy, COLORS.muted)
            if r.unlinked then
                text("Not connected", R, vy, COLORS.bad, "Small", "right")
                vy = vy + small + 6
            else
                text(r.level .. " / " .. r.cap .. " L" .. (r.stale and "  (stale)" or ""), R, vy, r.stale and COLORS.warn or COLORS.text, "Small", "right")
                vy = vy + small + 3
                bar(r.level / math.max(1, r.cap), r.level > 0 and COLORS.water or COLORS.bad)
                local food = r.nutrient and (r.nutrient .. " " .. r.strength .. "%") or "None"
                local low = r.strength < Config.Hydro.HUNGRY_BELOW * 100
                text("Nutrients", L, vy, COLORS.muted); text(food, R, vy, low and COLORS.warn or COLORS.text, "Small", "right")
                vy = vy + small + 4
                if r.ebb then
                    local wet = r.wetHours and r.wetHours > 0
                    local t2 = r.floodTimer and wet and "Wet (flood timer)" or (wet and ("Wet for " .. Layout.formatHours(r.wetHours)) or "Dry: flood the tables")
                    text("Rockwool", L, vy, COLORS.muted); text(t2, R, vy, wet and COLORS.text or COLORS.bad, "Small", "right")
                    vy = vy + small + 4
                end
            end
        elseif data.water then
            local w = Config.clamp(data.water, 0, 100)
            local color = (w < Config.Water.LOW) and COLORS.warn or ((w > Config.Water.HIGH) and COLORS.bad or COLORS.water)
            text("Water", L, vy, COLORS.muted); text(tostring(data.water) .. "%", R, vy, color, "Small", "right")
            vy = vy + small + 3
            bar(w / 100, color, { Config.Water.LOW / 100, Config.Water.HIGH / 100 })
        elseif data.waterRough then
            text("Watering", L, vy, COLORS.muted); text(data.waterRough, R, vy, data.waterRough == "OK" and COLORS.good or COLORS.warn, "Small", "right")
            vy = vy + small + 6
        end
        if data.roots then
            local color = data.roots == "Healthy" and COLORS.good or (data.roots == "Browning" and COLORS.warn or COLORS.bad)
            if data.rootRot then
                text("Root rot", L, vy, COLORS.muted)
                local right = R
                if data.rootRotTrend then
                    Layout.arrow(ops, right - 7, vy + 3, data.rootRotTrend, data.rootRotTrend > 0 and COLORS.bad
                        or (data.rootRotTrend < 0 and COLORS.good or COLORS.muted))
                    right = right - 12
                end
                text(data.roots .. "  " .. data.rootRot .. "%", right, vy, color, "Small", "right")
                vy = vy + small + 3
                bar(Config.clamp(data.rootRot, 0, 100) / 100, color, { Config.Hydro.ROT_EARLY / 100 })
            else
                text("Roots", L, vy, COLORS.muted); text(data.roots, R, vy, color, "Small", "right")
                vy = vy + small + 6
            end
        end
        -- Bands two to a row: label and word, with a row of pills under them.
        local col, colW = 0, (IW - 16) / 2
        for _, key in ipairs({ "healthBand", "stressBand", "geneticsBand", "qualityEstimate" }) do
            local word, def = data[key], BANDS[key]
            if word then
                local level = #def.words
                for i, candidate in ipairs(def.words) do if candidate == word then level = i end end
                local good = def.good and (level / #def.words) or ((#def.words - level) / (#def.words - 1))
                local color = (good > 0.7) and COLORS.good or ((good > 0.4) and COLORS.warn or COLORS.bad)
                local x = L + col * (colW + 16)
                text(BAND_LABELS[key], x, vy, COLORS.muted)
                text(word, x + colW, vy, color, "Small", "right")
                for i = 1, #def.words do pill(x + (i - 1) * 24, vy + small + 3, 20, 6, i <= level and color or COLORS.track) end
                col = col + 1
                if col == 2 then col = 0; vy = vy + small + 16 end
            end
        end
        if col == 1 then vy = vy + small + 16 end
        closeCard(vy - 6)
    end

    -- Care: plain facts, two to a row, label over value.
    local facts = {}
    local function fact(k, v, color) facts[#facts + 1] = { k, tostring(v), color or COLORS.text } end
    if data.light then fact("Light", data.light, data.light == "None" and COLORS.bad) end
    if data.lightCycle then fact("Light cycle", data.lightCycle, data.lightCycle == "Light leak" and COLORS.bad) end
    if data.topped then fact("Topped", "Yes  (+" .. math.floor(Config.Topping.YIELD_BONUS * 100 + 0.5) .. "% yield)", COLORS.good) end
    if data.extraVeg then fact("Extra veg", Layout.formatHours(data.extraVeg.hours) .. "  (+" .. data.extraVeg.bonus .. "% yield)", COLORS.good) end
    if data.cuttings then
        local c = data.cuttings
        fact("Cuttings ready", c.left .. " of " .. c.max, c.left > 0 and COLORS.text or COLORS.warn)
    end
    if data.lastNutrient then fact("Last fed", data.lastNutrient) end
    if data.harvestWindow then
        fact("Harvest", data.harvestWindow, (data.harvestWindow == "Ready now") and COLORS.good or ((data.harvestWindow == "Overripe") and COLORS.warn))
    end
    if data.pollinated ~= nil then fact("Pollinated", data.pollinated and "Yes" or "No", data.pollinated and COLORS.warn) end
    if data.hermieSigns then fact("Hermie signs", "Yes", COLORS.bad) end
    if #facts > 0 then
        local fy = openCard()
        label("Care", L, fy); fy = fy + small + 6
        local colW = (IW - 16) / 2
        for i, f in ipairs(facts) do
            local x = L + ((i - 1) % 2) * (colW + 16)
            text(f[1], x, fy, COLORS.muted)
            text(f[2], x, fy + small + 1, f[3])
            if i % 2 == 0 or i == #facts then fy = fy + 2 * small + 8 end
        end
        closeCard(fy - 8)
    end

    -- Genetics: the four traits as short bars, with the trait line from CannabisInfo below them.
    if data.traitBars or data.traits then
        local gy = openCard()
        label("Genetics", L, gy)
        gy = gy + small + 6
        if data.traitBars then
            local t = data.traitBars
            local bars = { { "Indica", t.ind / 100, t.ind .. "%", COLORS.purple }, { "Potency", t.pot / 100, t.potText, COLORS.good },
                           { "Yield", t.yld / 100, t.yldText, COLORS.good }, { "Speed", t.flw / 100, t.flwText, COLORS.good } }
            local bw = (IW - 3 * 10) / 4
            for i, b in ipairs(bars) do
                local x = L + (i - 1) * (bw + 10)
                local color = (b[3]:sub(1, 1) == "-") and COLORS.warn or b[4]
                text(b[1], x, gy, COLORS.text)
                text(b[3], x + bw, gy, color, "Small", "right")
                pill(x, gy + small + 3, bw, 5, COLORS.track)
                pill(x, gy + small + 3, bw * Config.clamp(b[2], 0, 1), 5, color)
            end
            gy = gy + small + 14
        elseif data.traits then
            -- Older replies only carry the trait line; wrapped at commas, since it is wider than the card.
            local line = ""
            for part in (data.traits .. ","):gmatch("%s*(.-),") do
                local nxt = line == "" and part or (line .. ", " .. part)
                if line ~= "" and measure("Small", nxt) > IW then
                    text(line .. ",", L, gy, COLORS.muted)
                    gy = gy + small + 2
                    nxt = part
                end
                line = nxt
            end
            text(line, L, gy, COLORS.muted)
            gy = gy + small + 2
        end
        closeCard(gy - 2)
    end

    -- Warnings: an amber strip of chips, as on the Grow Room dashboard.
    if data.warnings and #data.warnings > 0 then
        local chipH = small + 6
        local rowsY, x = y + 8, M + 10
        local chips = {}
        for _, key in ipairs(data.warnings) do
            local def = WARNINGS[key] or { key, "warn" }
            local cw2 = measure("Small", def[1]) + 16
            if x + cw2 > W - M - 10 then x = M + 10; rowsY = rowsY + chipH + 6 end
            chips[#chips + 1] = { x, rowsY, cw2, def }
            x = x + cw2 + 6
        end
        local stripH = rowsY + chipH + 8 - y
        ops[#ops + 1] = { kind = "card", x = M, y = y, w = W - 2 * M, h = stripH, color = COLORS.alert, border = COLORS.warn }
        for _, c in ipairs(chips) do
            pill(c[1], c[2], c[3], chipH, COLORS[c[4][2]])
            text(c[4][1], c[1] + c[3] / 2, c[2] + 3, COLORS.white, "Small", "center")
        end
        y = y + stripH + GAP
    end

    -- Footer: what more Agriculture would show.
    local nextLevel = Layout.nextUnlock(data.level or 0)
    local foot = "Agriculture " .. tostring(data.level or 0)
    if nextLevel then foot = foot .. "  ·  more at level " .. nextLevel end
    text(foot, W - M, y - 2, COLORS.muted, "Small", "right")
    y = y - 2 + small + M

    return { width = W, height = y, ops = ops, accent = accent }
end
