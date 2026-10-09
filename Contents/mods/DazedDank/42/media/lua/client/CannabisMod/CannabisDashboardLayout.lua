-- Lays out the Grow Room Panel dashboard as draw operations plus click regions. It makes no game calls, so it can be tested
-- and previewed offline; the window draws the operations and turns a click on a region into a room action.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisStatusLayout"

local Config = CannabisMod.Config
local C = CannabisMod.StatusLayout.COLORS

local Dash = {}
CannabisMod.DashboardLayout = Dash

Dash.WIDTH, Dash.HEIGHT = 760, 566
Dash.CARD_W, Dash.CARD_GAP = 240, 8          -- plant cards, scrolled sideways
local HEAD_H, M = 40, 12
-- Equipment labels for the narrow tiles a room with every kind of unit gets.
Dash.SHORT_NAMES = { exhaust = "Exhaust", intake = "Intake", cooler = "AC", circfan = "Circ", heater = "Heater",
    dehumidifier = "Dehum", humidifier = "Humid", drip = "Drip" }
local PLANT_Y, PLANT_H = 214, 168
local STAGE_NAME = { Seedling = "Seedling", Vegetative = "Vegetative", PreFlower = "Pre-flower", Flowering = "Flowering", Ripe = "Ripe" }
local TYPE_COLOR = { Indica = C.Indica, Sativa = C.Sativa, Hybrid = C.Hybrid }
Dash.PLANT_AREA = { x = M, y = PLANT_Y, w = 760 - 2 * M, h = PLANT_H }
-- The Cold nights pills of a Flower room, in order: the setting each sends and its label.
Dash.COLD_OPTIONS = { { "off", "Off" }, { "auto", "Late flower" }, { "on", "On" } }

--- The Cold nights status line for the climate strip, and its colour.
function Dash.coldNightsText(cn, temp)
    if not cn or cn.state == "off" then return "Off  |  nights keep the Flower range", C.muted end
    if cn.active then
        if temp then return string.format("On  |  room %d C", math.floor(temp + 0.5)), C.purple end
        return "On", C.purple
    end
    if cn.armed then return string.format("Armed  |  tonight %d to %d C", cn.nightLo or 6, cn.nightHi or 13), C.text end
    return "Waiting for late flower", C.muted
end

--- A plant card's cold night tag as { text, pill or color } (`pill` draws a purple pill), or nil when there is nothing to show.
function Dash.coldTag(cold)
    if not cold then return nil end
    if cold.rolled then
        if cold.purple then return { text = "Purple", pill = true } end
        return { text = "stayed green", color = C.muted }
    end
    if (cold.hours or 0) <= 0 then return nil end
    return { text = string.format("%d/%d h cold", math.floor(cold.hours), cold.need or 12), color = C.purple }
end

--- How far the plant row can scroll, in pixels.
function Dash.maxScroll(info)
    local n = #(info.plants or {})
    return math.max(0, n * (Dash.CARD_W + Dash.CARD_GAP) - Dash.CARD_GAP - Dash.PLANT_AREA.w)
end

--- Build the dashboard for a roomInfo reply. `scroll` is the plant row's offset in pixels.
--- @return table { width, height, ops, hits }; hits are { x, y, w, h, id } click regions, plant regions already scrolled
function Dash.build(info, scroll, fontH, measure)
    local W, H = Dash.WIDTH, Dash.HEIGHT
    local ops, hits = {}, {}
    local small, medium = fontH("Small"), fontH("Medium")
    scroll = scroll or 0

    local function rect(x, y, w, h, color, a) ops[#ops + 1] = { kind = "rect", x = x, y = y, w = w, h = h, color = color, a = a or 1 } end
    local function card(x, y, w, h, color, border) ops[#ops + 1] = { kind = "card", x = x, y = y, w = w, h = h, color = color or C.card, border = border or C.line } end
    local function pill(x, y, w, h, color) ops[#ops + 1] = { kind = "pill", x = x, y = y, w = w, h = h, color = color } end
    local function text(str, x, y, color, font, align)
        ops[#ops + 1] = { kind = "text", x = x, y = y, text = tostring(str), color = color, font = font or "Small", align = align or "left" }
    end
    -- Shorten a string with ".." until it fits `w` pixels.
    local function fit(str, font, w)
        str = tostring(str)
        if measure(font, str) <= w then return str end
        while #str > 1 and measure(font, str .. "..") > w do str = str:sub(1, -2) end
        return str .. ".."
    end
    local function tex(name, x, y, w, h, a) ops[#ops + 1] = { kind = "tex", name = name, x = x, y = y, w = w, h = h, a = a or 1 } end
    -- A section label, with its rendered icon in front when it has one.
    local function label(str, x, y, icon)
        if icon then
            tex(icon, x, y + (small - 16) / 2, 16, 16)
            x = x + 20
        end
        text(string.upper(str), x, y, C.muted)
    end
    local function hit(x, y, w, h, id) hits[#hits + 1] = { x = x, y = y, w = w, h = h, id = id } end
    local function button(x, y, w, h, str, id, filled)
        pill(x, y, w, h, filled and C.purple or C.photo)
        text(str, x + w / 2, y + (h - small) / 2, filled and C.white or C.purple, "Small", "center")
        hit(x, y, w, h, id)
    end
    local climate = info.climate or {}
    -- A Flower room that can run Cold nights gets a strip under the meters; everything below moves down to make room.
    local cn = climate.enabled and climate.coldNights or nil
    local coldH = cn and (2 * small + 28) or 0
    local extra = cn and (coldH + 8) or 0
    H = H + extra

    -- Title bar: room name (click to rename), mode pill (click to change), counts, the time.
    rect(0, 0, W, HEAD_H, C.head)
    local name = info.name or "Grow Room"
    text(name, M, (HEAD_H - medium) / 2, C.white, "Medium")
    local nx = M + measure("Medium", name)
    hit(M, 4, nx - M, HEAD_H - 8, "rename")
    local mode = string.upper(info.mode or "Veg")
    local mw = measure("Small", mode) + 20
    button(nx + 10, (HEAD_H - small - 6) / 2, mw, small + 6, mode, "mode", true)
    local counts = (info.tiles or 0) .. " tiles  |  " .. #(info.lamps or {}) .. " lamps  |  " .. #(info.plants or {}) .. " plants"
    text(counts, nx + mw + 20, (HEAD_H - small) / 2, { 0.79, 0.75, 0.88 })
    -- Refresh asks the server for the room again; the close button sits to its right as a child of the window.
    -- The label shows the last refresh's outcome for a moment ("Updated", "No reply"); the width fits the longest.
    local rw = math.max(measure("Small", "Refresh"), measure("Small", "No reply"), measure("Small", "Updated")) + 20
    button(W - 44 - rw, (HEAD_H - small - 6) / 2, rw, small + 6, info.refreshLabel or "Refresh", "refresh", true)
    text(string.format("%02d:00", info.hour or 0), W - 44 - rw - 10, (HEAD_H - small) / 2, C.white, "Small", "right")

    -- Row 1: lights, temperature, humidity, room seal.
    local y1, h1 = HEAD_H + M, 132
    -- Lights: a 24-hour ring of dots, lit hours in gold, with the hour marked; click to change the schedule.
    card(M, y1, 176, h1 + extra)
    local cx, cy, r = M + 52, y1 + h1 / 2 + 2, 38
    for hr = 0, 23 do
        local a = (hr / 24) * 2 * math.pi - math.pi / 2
        local on = Config.Timer.isOn(info.schedule ~= "24/0" and info.schedule or nil, hr)
        local d = (hr == (info.hour or -1)) and 10 or 7
        pill(cx + r * math.cos(a) - d / 2, cy + r * math.sin(a) - d / 2, d, d,
            hr == (info.hour or -1) and C.bad or (on and { 0.96, 0.77, 0.26 } or C.head))
    end
    text("00", cx, cy - r + 8, C.muted, "Small", "center")
    text("12", cx, cy + r - 8 - small, C.muted, "Small", "center")
    local lx = M + 104
    label("Lights", lx, y1 + 14, "icon_lights")
    text(info.schedule or "24/0", lx, y1 + 14 + small + 4, C.text, "Medium")
    local onH = Config.Timer.SCHEDULES[info.schedule or ""]
    local on = onH and string.format("on %02d to %02d", Config.Timer.ON_HOUR, (Config.Timer.ON_HOUR + onH) % 24) or "always on"
    text(on, lx, y1 + 14 + small + medium + 8, C.muted)
    button(lx, y1 + h1 + extra - small - 20, 62, small + 6, "Change", "schedule")
    hit(M, y1, 176, h1 + extra, "schedule")

    -- Temperature and humidity: the reading, the target band, a marker on it.
    local function meter(x, w, title, icon, value, unit, lo, hi, mn, mx, note)
        card(x, y1, w, h1)
        label(title, x + 14, y1 + 14, icon)
        if not climate.enabled then
            text("Room climate is off", x + 14, y1 + 40, C.muted)
            return
        end
        if not value then
            text("waiting for a reading", x + 14, y1 + 40, C.muted)
            return
        end
        local ok = value >= lo and value <= hi
        local color = ok and C.good or C.warn
        local str = string.format("%.1f", value)
        text(str .. " " .. unit, x + 14, y1 + 36, color, "Large")
        local bw = w - 28
        local by = y1 + 36 + fontH("Large") + 10
        pill(x + 14, by, bw, 8, C.track)
        pill(x + 14 + bw * (lo - mn) / (mx - mn), by, bw * (hi - lo) / (mx - mn), 8, { 0.62, 0.84, 0.66 })
        local mxp = x + 14 + bw * Config.clamp((value - mn) / (mx - mn), 0, 1)
        pill(mxp - 6, by - 3, 12, 14, color)
        text("target " .. lo .. " to " .. hi .. " " .. unit, x + 14, by + 16, C.muted)
        if note then text(note, x + 14, by + 16 + small + 2, ok and C.muted or C.warn) end
    end
    local t = climate.targets or {}
    meter(M + 186, 180, "Temperature", "icon_temp", climate.temp, "C", t.tLo or 20, t.tHi or 26, 5, 40,
        climate.outT and string.format("outdoors %d C", math.floor(climate.outT + 0.5)))
    local humNote = climate.outH and string.format("outdoors %d%%", math.floor(climate.outH + 0.5))
    if climate.hum and t.hHi and climate.hum > t.hHi then humNote = "too humid" elseif climate.hum and t.hLo and climate.hum < t.hLo then humNote = "too dry" end
    meter(M + 376, 180, "Humidity", "icon_humid", climate.hum, "%", t.hLo or 40, t.hHi or 60, 10, 90, humNote)

    -- Cold nights: the three-way setting as pills, styled like the equipment modes, and what it is doing tonight.
    if cn then
        local kx, ky, kw = M + 186, y1 + h1 + 8, 370
        card(kx, ky, kw, coldH)
        label("Cold nights", kx + 14, ky + 10)
        local px = kx + 14 + measure("Small", "COLD NIGHTS") + 12
        for _, opt in ipairs(Dash.COLD_OPTIONS) do
            local pw = measure("Small", opt[2]) + 20
            button(px, ky + 7, pw, small + 6, opt[2], "cold:" .. opt[1], cn.state == opt[1])
            px = px + pw + 6
        end
        local line, lc = Dash.coldNightsText(cn, climate.temp)
        text(fit(line, "Small", kw - 28), kx + 14, ky + 20 + small, lc)
    end

    -- Room seal: power and every door or window, with the uncovered ones in amber.
    local sx = M + 566
    card(sx, y1, W - M - sx, h1 + extra)
    label("Room seal", sx + 14, y1 + 14, "icon_seal")
    local sy = y1 + 14 + small + 8
    local function dot(ok, str)
        pill(sx + 14, sy + (small - 9) / 2, 9, 9, ok and C.good or C.warn)
        text(str, sx + 30, sy, ok and C.text or C.warn)
        sy = sy + small + 6
    end
    dot(info.powered ~= false, info.powered ~= false and "Panel powered" or "Panel has no power")
    local openings = info.openings or {}
    local open = 0
    for i, o in ipairs(openings) do
        if not o.covered then open = open + 1 end
        if i <= 3 then
            local state = o.covered and " covered" or (o.seeps and " seeps (hang a sheet)" or " open")
            dot(o.covered, (o.kind == "door" and "Door " or "Window ") .. o.x .. "," .. o.y .. state)
        end
    end
    if #openings > 3 then text("+" .. (#openings - 3) .. " more", sx + 30, sy, C.muted) end
    if #openings == 0 then text("No doors or windows", sx + 30, sy, C.muted) end

    -- Plants: cards in a row that scrolls sideways; click a card to inspect the plant.
    local A = { x = Dash.PLANT_AREA.x, y = PLANT_Y + extra, w = Dash.PLANT_AREA.w, h = PLANT_H }
    label("Plants", M + 2, A.y - small - 6, "icon_plants")
    local plants = info.plants or {}
    if #plants == 0 then
        card(A.x, A.y, A.w, A.h)
        text("No plants in this room yet.", A.x + A.w / 2, A.y + A.h / 2 - small / 2, C.muted, "Small", "center")
    else
        ops[#ops + 1] = { kind = "clip", x = A.x, y = A.y, w = A.w, h = A.h }
        for i, p in ipairs(plants) do
            local x = A.x + (i - 1) * (Dash.CARD_W + Dash.CARD_GAP) - scroll
            if x + Dash.CARD_W > A.x and x < A.x + A.w then
                local cw = Dash.CARD_W
                card(x, A.y, cw, A.h)
                local title = p.strain or p.name or "Cannabis Plant"
                local tc = TYPE_COLOR[p.type] or C.text
                text(fit(title, "Medium", cw - 24), x + 12, A.y + 10, tc, "Medium")
                tex("photo_tent", x + 8, A.y + 34, 84, A.h - 42)
                if p.sprite then
                    ops[#ops + 1] = { kind = "plant", x = x + 8, y = A.y + 34, w = 84, h = A.h - 42, sprite = p.sprite, pot = p.pot, lift = p.lift or 0, fit = true }
                end
                local tx, ty = x + 102, A.y + 40
                local sub = p.type and (p.type .. (p.looks and ("  |  " .. p.looks) or "")) or p.looks
                if sub then text(fit(sub, "Small", x + cw - 10 - tx), tx, ty, C.muted); ty = ty + small + 2 end
                if p.sex then text(p.sex, tx, ty, (p.sex == "Male" or p.sex == "Hermaphrodite") and C.bad or C.text); ty = ty + small + 2 end
                ty = ty + 4
                text(STAGE_NAME[p.stageKey] or p.stage or "", tx, ty, C.text, "Medium"); ty = ty + medium + 4
                local water = tonumber(tostring(p.water or ""):match("^(%d+)%%"))
                text("Water", tx, ty, C.muted)
                if water then
                    pill(tx + 44, ty + small / 2 - 4, cw - 102 - 56, 8, C.track)
                    pill(tx + 44, ty + small / 2 - 4, (cw - 102 - 56) * Config.clamp(water / 100, 0, 1), 8, C.water)
                else
                    text(tostring(p.water or "?"), x + cw - 12, ty, C.text, "Small", "right")
                end
                ty = ty + small + 4
                if p.health then
                    local hc = (p.health == "Excellent" or p.health == "Good") and C.good or (p.health == "Fair" and C.warn or C.bad)
                    text("Health", tx, ty, C.muted); text(p.health, x + cw - 12, ty, hc, "Small", "right")
                    ty = ty + small + 4
                end
                -- The cold night tag gets the last line of the column: hours so far, then Purple or stayed green.
                local tag = Dash.coldTag(p.cold)
                if tag and tag.pill then
                    local pw = math.min(measure("Small", tag.text) + 12, cw - 114)
                    pill(tx, ty - 1, pw, small + 2, C.purple)
                    text(fit(tag.text, "Small", pw - 6), tx + pw / 2, ty, C.white, "Small", "center")
                elseif tag then
                    text(fit(tag.text, "Small", cw - 114), tx, ty, tag.color)
                end
                -- The warning chip sits on the bottom of the photo, so it never covers the rows beside it.
                local chip = nil
                if (p.warnings or 0) > 0 then
                    chip = { p.warnings .. (p.warnings == 1 and " warning" or " warnings"), C.alert, C.warn }
                elseif p.health then
                    chip = { "all good", { 0.886, 0.957, 0.898 }, C.good }
                end
                if chip then
                    local cwid = math.min(80, measure("Small", chip[1]) + 12)
                    local cy = A.y + A.h - 8 - (small + 6) - 4
                    pill(x + 8 + (84 - cwid) / 2, cy, cwid, small + 6, chip[2])
                    text(fit(chip[1], "Small", cwid - 8), x + 8 + 42, cy + 3, chip[3], "Small", "center")
                end
                local vx, vw = math.max(x, A.x), math.min(x + cw, A.x + A.w) - math.max(x, A.x)
                if vw > 0 then hit(vx, A.y, vw, A.h, "plant:" .. i) end
            end
        end
        ops[#ops + 1] = { kind = "unclip" }
        if Dash.maxScroll(info) > 0 then
            if scroll > 0 then button(A.x - 6, A.y + A.h / 2 - 14, 28, 28, "<", "scrollLeft", true) end
            if scroll < Dash.maxScroll(info) then button(A.x + A.w - 22, A.y + A.h / 2 - 14, 28, 28, ">", "scrollRight", true) end
        end
    end

    -- Reservoirs: tanks with their level, food and roots; click one for its actions.
    local y3, h3 = A.y + PLANT_H + 12, 126
    local rw = 300
    card(M, y3, rw, h3)
    label("Reservoirs", M + 14, y3 + 12, "icon_tank")
    local res = info.reservoirs or {}
    if #res > 0 then
        button(M + rw - 158, y3 + 8, 78, small + 6, "Top up all", "topUpAll", true)
        button(M + rw - 74, y3 + 8, 62, small + 6, "More", "doseAll")
    end
    if #res == 0 then text("No reservoirs in this room.", M + 14, y3 + 40, C.muted) end
    for i, r in ipairs(res) do
        if i > 3 then text("+" .. (#res - 3) .. " more", M + rw - 14, y3 + h3 - small - 8, C.muted, "Small", "right") break end
        local x, y = M + 14 + (i - 1) * 94, y3 + 34
        local frac = Config.clamp((r.level or 0) / math.max(1, r.cap or 1), 0, 1)
        -- The tank is two renders with the water drawn between them, so the glass sits over the water.
        tex("tank_back", x + 22, y - 6, 40, 48)
        if frac > 0 then rect(x + 25, y + 1 + 37 * (1 - frac), 34, 37 * frac, C.water, 0.8) end
        tex("tank_front", x + 22, y - 6, 40, 48)
        local short = (r.name or "Reservoir"):gsub(" control", ""):gsub(" bucket", ""):gsub(" reservoir", "")
        text(short .. " " .. math.floor((r.level or 0) + 0.5) .. "/" .. (r.cap or 0) .. " L", x + 42, y + 44, C.text, "Small", "center")
        local food = r.nutrient and (r.nutrient .. " " .. math.floor((r.strength or 0) * 100 + 0.5) .. "%") or "no food"
        text(food, x + 42, y + 44 + small, C.muted, "Small", "center")
        local state, sc = "healthy", C.good
        if r.pump == false then state, sc = "no power", C.bad
        elseif (r.level or 0) <= 0 then state, sc = "empty", C.bad
        elseif (r.rot or 0) > 0 then state, sc = "rot " .. math.floor(r.rot + 0.5) .. "%", C.warn end
        text(state, x + 42, y + 44 + 2 * small, sc, "Small", "center")
        hit(x, y - 2, 86, 44 + 3 * small, "res:" .. i)
    end

    -- Equipment: one tile per kind, its mode as a tag and whether it runs; click to set Auto, On or Off.
    local ex = M + rw + 10
    local ew = W - M - ex
    card(ex, y3, ew, h3)
    label("Equipment", ex + 14, y3 + 12, "icon_fan")
    local kinds, rows = {}, {}
    for _, e in ipairs(info.equipment or {}) do
        if not rows[e.kind] then rows[e.kind] = {}; kinds[#kinds + 1] = e.kind end
        table.insert(rows[e.kind], e)
    end
    table.sort(kinds, function(a, b)
        local order = {}
        for i, k in ipairs(Config.Rooms.EQUIPMENT_ORDER) do order[k] = i end
        return (order[a] or 9) < (order[b] or 9)
    end)
    if #kinds == 0 then text("No fans or climate units yet.", ex + 14, y3 + 40, C.muted) end
    local override = climate.override or {}
    -- Up to five kinds get full tiles; with more (all seven) the tiles narrow and use short labels so they all fit.
    local n = #kinds
    local gap = n <= 5 and 8 or 6
    local tw = n <= 5 and 74 or math.floor((ew - 28 - (n - 1) * gap) / n)
    local narrow = tw < 70
    for i, kind in ipairs(kinds) do
        local list = rows[kind]
        local x, y = ex + 14 + (i - 1) * (tw + gap), y3 + 30
        card(x, y, tw, 58, C.ground, C.ground)
        ops[#ops + 1] = { kind = "equip", x = x, y = y, w = tw, h = 58, equipKind = kind }
        local m = string.upper(string.sub(override[kind] or "auto", 1, 1)) .. string.sub(override[kind] or "auto", 2)
        if narrow then
            pill(x + 3, y + 3, tw - 6, small + 2, C.purple)
            text(m, x + tw / 2, y + 4, C.white, "Small", "center")
        else
            pill(x + tw - 40, y + 3, 36, small + 2, C.purple)
            text(m, x + tw - 22, y + 4, C.white, "Small", "center")
        end
        local nm = narrow and Dash.SHORT_NAMES[kind] or (Config.Rooms.EQUIPMENT_NAMES[kind] or kind):gsub(" fan", "")
        if #list > 1 then nm = nm .. " x" .. #list end
        text(nm, x + tw / 2, y + 62, C.text, "Small", "center")
        local running, powered = false, false
        for _, e in ipairs(list) do running = running or e.running; powered = powered or e.powered end
        local st, col = running and (narrow and "on" or "running") or "idle", running and C.good or C.muted
        if not powered then st, col = narrow and "no pwr" or "no power", C.bad end
        pill(x + 6, y + 64 + small + 4, 8, 8, col)
        text(st, x + 18, y + 62 + small, col)
        hit(x, y, tw, 64 + 2 * small, "equip:" .. kind)
    end

    -- Bottom strip: the first climate note (or the newest log line), and the full log.
    local by = y3 + h3 + 10
    local note = (climate.notes or {})[1]
    local log = info.log or {}
    local alert = note ~= nil
    card(M, by, W - 2 * M, H - by - M, alert and C.alert or C.card, alert and C.warn or C.line)
    local line = note and ("! " .. note) or (log[#log] and ("Latest: " .. log[#log].text) or "Nothing logged yet")
    text(line, M + 12, by + (H - by - M - small) / 2, alert and C.warn or C.muted)
    button(W - M - 70, by + (H - by - M - small - 6) / 2, 60, small + 6, "Log", "log")

    return { width = W, height = H, ops = ops, hits = hits, plantArea = A }
end

return Dash
