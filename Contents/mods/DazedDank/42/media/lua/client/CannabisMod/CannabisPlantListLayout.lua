-- Lays out the "All plants" window: a sortable table with one row per plant, as draw operations plus click regions.
-- It makes no game calls, so it can be tested offline; the window draws the operations and routes the clicks.

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisStatusLayout"

local Config = CannabisMod.Config
local C = CannabisMod.StatusLayout.COLORS

local PL = {}
CannabisMod.PlantListLayout = PL

PL.WIDTH, PL.HEIGHT = 600, 420
local HEAD_H, M = 40, 12
local STAGE_NAME = { Seedling = "Seedling", Vegetative = "Vegetative", PreFlower = "Pre-flower", Flowering = "Flowering", Ripe = "Ripe" }
local STAGE_RANK = { Seedling = 1, Vegetative = 2, PreFlower = 3, Flowering = 4, Ripe = 5 }
local HEALTH_RANK = { Poor = 1, Fair = 2, Good = 3, Excellent = 4 }
local TYPE_COLOR = { Indica = C.Indica, Sativa = C.Sativa, Hybrid = C.Hybrid }

-- The columns, left to right. Widths add up to the table's inner width.
PL.COLUMNS = {
    { key = "strain", title = "Strain", w = 150 },
    { key = "sex", title = "Sex", w = 90 },
    { key = "stage", title = "Stage", w = 100 },
    { key = "water", title = "Water", w = 60 },
    { key = "health", title = "Health", w = 70 },
    { key = "warnings", title = "Warnings", w = 80 },
}
PL.DEFAULT_SORT = { key = "warnings", asc = false }

--- What a plant sorts by in a column: a number or string, or nil when the plant doesn't show it.
local function sortValue(p, key)
    if key == "strain" then return p.strain and string.lower(p.strain) or nil
    elseif key == "sex" then return p.sex and string.lower(p.sex) or nil
    elseif key == "stage" then return STAGE_RANK[p.stageKey]
    elseif key == "water" then return tonumber(tostring(p.water or ""):match("^(%d+)%%"))
    elseif key == "health" then return HEALTH_RANK[p.health]
    end
    return p.warnings or 0
end

--- The plants' original indexes in display order. Plants with no value for the column come last either way.
--- Ties fall back to strain A to Z, then to the original order.
function PL.order(plants, key, asc)
    local idx = {}
    for i = 1, #plants do idx[i] = i end
    table.sort(idx, function(a, b)
        local va, vb = sortValue(plants[a], key), sortValue(plants[b], key)
        if (va == nil) ~= (vb == nil) then return vb == nil end
        if va ~= nil and va ~= vb then
            if asc then return va < vb else return va > vb end
        end
        local sa, sb = sortValue(plants[a], "strain"), sortValue(plants[b], "strain")
        if (sa == nil) ~= (sb == nil) then return sb == nil end
        if sa ~= sb then return sa < sb end
        return a < b
    end)
    return idx
end

--- The sort after a click on a column header: the same column flips direction, a new one starts ascending.
function PL.nextSort(sort, key)
    if sort and sort.key == key then return { key = key, asc = not sort.asc } end
    return { key = key, asc = true }
end

--- Where the rows sit and how far they can scroll, so the window and the layout agree.
--- @return table { x, y, w, h, rowH, headH, content, maxScroll }; x/y/w/h is the rows area
function PL.metrics(count, fontH)
    local small = fontH("Small")
    local rowH, headH = small + 8, small + 10
    local top = HEAD_H + M + headH + 1
    local h = PL.HEIGHT - M - 4 - top
    local content = count * rowH
    return { x = M, y = top, w = PL.WIDTH - 2 * M, h = h, rowH = rowH, headH = headH, content = content,
        maxScroll = math.max(0, content - h) }
end

--- Build the window for a roomInfo's plants. `sort` is { key, asc } and `scroll` the rows' offset in pixels.
--- @return table { width, height, ops, hits, area, maxScroll, order }; hits are "sort:<column>" and "plant:<index into info.plants>"
function PL.build(info, sort, scroll, fontH, measure)
    local W, H = PL.WIDTH, PL.HEIGHT
    local ops, hits = {}, {}
    local small, medium = fontH("Small"), fontH("Medium")
    local plants = info.plants or {}
    sort = sort or PL.DEFAULT_SORT
    local S = PL.metrics(#plants, fontH)
    scroll = Config.clamp(scroll or 0, 0, S.maxScroll)

    local function text(str, x, y, color, font)
        ops[#ops + 1] = { kind = "text", x = x, y = y, text = tostring(str), color = color, font = font or "Small", align = "left" }
    end
    -- Shorten a string with ".." until it fits `w` pixels.
    local function fit(str, font, w)
        str = tostring(str)
        if measure(font, str) <= w then return str end
        while #str > 1 and measure(font, str .. "..") > w do str = str:sub(1, -2) end
        return str .. ".."
    end

    -- Title bar with the count; the close button sits on it as a child of the window.
    ops[#ops + 1] = { kind = "rect", x = 0, y = 0, w = W, h = HEAD_H, color = C.head, a = 1 }
    text("All plants (" .. #plants .. ")", M, (HEAD_H - medium) / 2, C.white, "Medium")

    local cardY = HEAD_H + M
    ops[#ops + 1] = { kind = "card", x = M, y = cardY, w = W - 2 * M, h = H - M - cardY, color = C.card, border = C.line }

    -- Column header: click a title to sort by it; the sorted one carries ^ (ascending) or v (descending).
    local cx = M + 8
    for _, col in ipairs(PL.COLUMNS) do
        local title = col.title
        local sorted = sort.key == col.key
        if sorted then title = title .. (sort.asc and " ^" or " v") end
        text(fit(title, "Small", col.w - 6), cx, cardY + (S.headH - small) / 2, sorted and C.purple or C.muted)
        hits[#hits + 1] = { x = cx - 4, y = cardY, w = col.w, h = S.headH, id = "sort:" .. col.key }
        cx = cx + col.w
    end
    ops[#ops + 1] = { kind = "rect", x = M + 4, y = S.y - 1, w = W - 2 * M - 8, h = 1, color = C.line, a = 1 }

    local order = PL.order(plants, sort.key, sort.asc)
    if #plants == 0 then
        text("No plants in this room yet.", M + 12, S.y + 10, C.muted)
    end
    ops[#ops + 1] = { kind = "clip", x = S.x, y = S.y, w = S.w, h = S.h }
    for r, i in ipairs(order) do
        local p = plants[i]
        local y = S.y + (r - 1) * S.rowH - scroll
        if y + S.rowH > S.y and y < S.y + S.h then
            local ty = y + (S.rowH - small) / 2
            local x = M + 8
            local function cell(col, str, color)
                text(fit(str, "Small", col.w - 6), x, ty, color)
                x = x + col.w
            end
            local K = PL.COLUMNS
            cell(K[1], p.strain or p.name or "Cannabis Plant", TYPE_COLOR[p.type] or C.text)
            cell(K[2], p.sex or "?", (p.sex == "Male" or p.sex == "Hermaphrodite") and C.bad or C.text)
            cell(K[3], STAGE_NAME[p.stageKey] or p.stage or "?", C.text)
            cell(K[4], p.water or "?", C.text)
            local hc = (p.health == "Excellent" or p.health == "Good") and C.good or (p.health == "Fair" and C.warn or C.bad)
            cell(K[5], p.health or "?", p.health and hc or C.muted)
            local n = p.warnings or 0
            cell(K[6], n, n > 0 and C.warn or C.muted)
            ops[#ops + 1] = { kind = "rect", x = M + 8, y = y + S.rowH - 1, w = W - 2 * M - 16, h = 1, color = C.line, a = 0.6 }
            -- The click region stops at the edges of the rows area, so a half-hidden row can't be hit through the header.
            local top, bottom = math.max(y, S.y), math.min(y + S.rowH, S.y + S.h)
            hits[#hits + 1] = { x = S.x, y = top, w = S.w, h = bottom - top, id = "plant:" .. i }
        end
    end
    ops[#ops + 1] = { kind = "unclip" }
    if S.maxScroll > 0 then
        local th = math.max(12, S.h * S.h / S.content)
        ops[#ops + 1] = { kind = "pill", x = S.x + S.w - 8, y = S.y + (S.h - th) * scroll / S.maxScroll, w = 3, h = th, color = C.muted }
    end
    return { width = W, height = H, ops = ops, hits = hits, area = S, maxScroll = S.maxScroll, order = order }
end

return PL
