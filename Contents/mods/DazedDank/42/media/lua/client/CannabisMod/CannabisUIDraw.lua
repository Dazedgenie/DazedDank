-- Drawing helpers for the dashboard-style windows: rounded cards, pills, and a plant drawn as it stands in its pot.

local Draw = {}
CannabisMod = CannabisMod or {}
CannabisMod.UIDraw = Draw

local TEX = {}
local function tex(name)
    local t = TEX[name]
    if t == nil then
        t = getTexture(name) or false
        TEX[name] = t
    end
    return t or nil
end

--- A texture by its full path, looked up once.
Draw.texture = tex

-- Card corner texture paths, built once instead of per card.
local FILL_TL, FILL_TR = "media/ui/DazedDank/cardfill_tl.png", "media/ui/DazedDank/cardfill_tr.png"
local FILL_BL, FILL_BR = "media/ui/DazedDank/cardfill_bl.png", "media/ui/DazedDank/cardfill_br.png"
local LINE_TL, LINE_TR = "media/ui/DazedDank/cardline_tl.png", "media/ui/DazedDank/cardline_tr.png"
local LINE_BL, LINE_BR = "media/ui/DazedDank/cardline_bl.png", "media/ui/DazedDank/cardline_br.png"
local CIRCLE = "media/ui/DazedDank/circle.png"
-- UI image name -> its full path, so Draw.tex builds each path once.
local PATHS = {}

local R = 8   -- card corner radius, the size of the corner textures

--- One rounded corner of a card: its fill, then its border line when the card has one.
local function corner(el, fillName, lineName, cx, cy, f, b)
    local t = tex(fillName)
    if t then el:drawTextureScaled(t, cx, cy, R, R, 1, f[1], f[2], f[3]) end
    if b then
        local tl = tex(lineName)
        if tl then el:drawTextureScaled(tl, cx, cy, R, R, 1, b[1], b[2], b[3]) end
    end
end

--- A rounded card: fill and a 1 px border, drawn on any ISUIElement `el` in its own coordinates.
function Draw.card(el, x, y, w, h, fill, border)
    local f, b = fill, border
    el:drawRect(x + R, y, w - 2 * R, h, 1, f[1], f[2], f[3])
    el:drawRect(x, y + R, R, h - 2 * R, 1, f[1], f[2], f[3])
    el:drawRect(x + w - R, y + R, R, h - 2 * R, 1, f[1], f[2], f[3])
    local x2, y2 = x + w - R, y + h - R
    corner(el, FILL_TL, LINE_TL, x, y, f, b)
    corner(el, FILL_TR, LINE_TR, x2, y, f, b)
    corner(el, FILL_BL, LINE_BL, x, y2, f, b)
    corner(el, FILL_BR, LINE_BR, x2, y2, f, b)
    if b then
        el:drawRect(x + R, y, w - 2 * R, 1, 1, b[1], b[2], b[3])
        el:drawRect(x + R, y + h - 1, w - 2 * R, 1, 1, b[1], b[2], b[3])
        el:drawRect(x, y + R, 1, h - 2 * R, 1, b[1], b[2], b[3])
        el:drawRect(x + w - 1, y + R, 1, h - 2 * R, 1, b[1], b[2], b[3])
    end
end

--- One of the rendered UI images in media/ui/DazedDank, by name, stretched to the box.
function Draw.tex(el, name, x, y, w, h, a)
    local path = PATHS[name]
    if not path then
        path = "media/ui/DazedDank/" .. name .. ".png"
        PATHS[name] = path
    end
    local t = tex(path)
    if t then el:drawTextureScaled(t, x, y, w, h, a or 1, 1, 1, 1) end
end

--- A pill: a bar with round ends.
function Draw.pill(el, x, y, w, h, color)
    local c = color
    if w <= 0 or h <= 0 then return end
    if w <= h then
        local t = tex(CIRCLE)
        if t then el:drawTextureScaled(t, x, y, w, h, 1, c[1], c[2], c[3]) end
        return
    end
    el:drawRect(x + h / 2, y, w - h, h, 1, c[1], c[2], c[3])
    local t = tex(CIRCLE)
    if t then
        el:drawTextureScaled(t, x, y, h, h, 1, c[1], c[2], c[3])
        el:drawTextureScaled(t, x + w - h, y, h, h, 1, c[1], c[2], c[3])
    else
        el:drawRect(x, y, w, h, 1, c[1], c[2], c[3])
    end
end

--- A plant in a box: its pot (or furrow) and the plant layer raised by `lift` (1x pixels), both scaled to fit the box height.
--- With `fit` the whole raised cell fits the box, so even the tallest plant stays inside it.
function Draw.plant(el, x, y, w, h, sprite, pot, lift, fit)
    -- Tile textures are 128 x 256 at 2x with empty headroom, so by default the cell is scaled a little past the box height.
    local scale = fit and math.min(h / (256 + 2 * (lift or 0)), w / 128) or math.min(h / 220, w / 110)
    local cw, ch = 128 * scale, 256 * scale
    local cx, cy = x + (w - cw) / 2, y + h - ch
    local pt = pot and tex(pot)
    if pt then el:drawTextureScaledAspect(pt, cx, cy, cw, ch, 1, 1, 1, 1) end
    local st = sprite and tex(sprite)
    if st then el:drawTextureScaledAspect(st, cx, cy - (lift or 0) * 2 * scale, cw, ch, 1, 1, 1, 1) end
end

return Draw
