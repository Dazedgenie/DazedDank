-- Runs each grow room panel tab's render with recording stubs and writes the draw calls as TSV, for tools/render_previews.py.
-- Run: lua tools/preview_tabs.lua <repo> <out_dir>
local repo, out = arg[1], arg[2]
local MOD = repo .. "/Contents/mods/DazedDank/42/media/lua/"
SandboxVars = {}
function isClient() return false end
function isServer() return false end
UIFont = { Small = "S", Medium = "M" }
Events = setmetatable({}, { __index = function() return { Add = function() end } end })
local oldRequire = require
require = function(n) if n:sub(1, 5) == "ISUI/" then return end return pcall(oldRequire, n) and nil or nil end
ISPanel = {}
function ISPanel:derive() local c = {}; c.__index = c; setmetatable(c, { __index = self }); return c end
function ISPanel:new(x, y, w, h) return { x = x, y = y, width = w, height = h } end
function ISPanel:createChildren() end

dofile(MOD .. "shared/CannabisMod/CannabisConfig.lua")
local buttons = {}
CannabisMod.RoomPanel = { choiceButton = function(_, x, y, w, label, active)
    buttons[#buttons + 1] = { x = x, y = y, w = w, label = label, active = active }
    return {}
end }
for _, f in ipairs({ "CannabisRowsTab", "CannabisLightsTab", "CannabisHydroTab", "CannabisPlantsTab", "CannabisClimateTab", "CannabisEquipmentTab", "CannabisLogTab" }) do
    dofile(MOD .. "client/CannabisMod/" .. f .. ".lua")
end

local info = {
    name = "Mother Room", x = 10, y = 10, z = 0, schedule = "12/12", mode = "Flower", tiles = 42, hour = 14, powered = true, now = 500,
    floodTimer = false,
    lamps = {
        { name = "Pro grow lamp", x = 11, y = 11, z = 0, powered = true, lit = true },
        { name = "Pro grow lamp", x = 13, y = 11, z = 0, powered = true, lit = true },
        { name = "Basic grow lamp", x = 15, y = 12, z = 0, powered = true, lit = true },
    },
    openings = { { kind = "window", x = 12, y = 9, covered = true }, { kind = "door", x = 16, y = 12, covered = false } },
    reservoirs = {
        { key = "a", name = "RDWC control", x = 12, y = 13, z = 0, level = 12, cap = 20, strength = 0.8, nutrient = "Bloom", rot = 0, pump = true, age = 30, plants = 4 },
        { key = "b", name = "DWC bucket", x = 14, y = 13, z = 0, level = 6, cap = 15, strength = 0.3, nutrient = "Veg", rot = 1, pump = true, age = 90, plants = 1 },
        { key = "c", name = "Flood reservoir", x = 15, y = 13, z = 0, level = 0, cap = 40, strength = 0, rot = 0, pump = false, age = 10, plants = 6 },
    },
    plants = {
        { x = 12, y = 12, z = 0, name = "Cannabis Plant", type = "Indica", stage = "Flowering", water = "60%", health = "Good", warnings = 0, strain = "Ekron Sour Diesel", sex = "Female" },
        { x = 13, y = 12, z = 0, name = "Cannabis Plant", type = "Hybrid", stage = "Flowering", water = "40%", health = "Fair", warnings = 2, strain = "Shambler Bubba Kush", sex = "Male" },
        { x = 14, y = 12, z = 0, name = "Cannabis Plant", type = "Sativa", stage = "Pre-flower", water = "75%", health = "Good", warnings = 1 },
    },
    equipment = {
        { x = 11, y = 9, z = 0, kind = "exhaust", name = "Exhaust fan", mount = "north wall", powered = true, running = true, mode = "auto" },
        { x = 9, y = 12, z = 0, kind = "intake", name = "Intake fan", mount = "west wall", powered = true, running = true, mode = "auto" },
        { x = 13, y = 9, z = 0, kind = "heater", name = "Heater", mount = "north wall", powered = true, running = false, mode = "off" },
        { x = 9, y = 14, z = 0, kind = "dehumidifier", name = "Dehumidifier", mount = "west wall", powered = true, running = true, mode = "auto" },
        { x = 15, y = 14, z = 0, kind = "humidifier", name = "Humidifier", mount = "floor", powered = false, running = false, mode = "auto" },
    },
    climate = {
        enabled = true, temp = 24.6, hum = 52.3, outT = 11, outH = 58,
        targets = { tLo = 20, tHi = 26, hLo = 40, hHi = 50 },
        present = { exhaust = 1, intake = 1, heater = 1, dehumidifier = 1 },
        running = { exhaust = true, intake = true, dehumidifier = true }, override = { heater = "off" },
        notes = { "Wet plants are drying in a Flower room: set Drying mode" },
    },
    log = {
        { t = 380, text = "Power lost" }, { t = 392, text = "Power restored: 3.5 lit hours lost, 6 flowering plants stressed" },
        { t = 440, text = "Light leak: sunlight through an uncovered window" }, { t = 470, text = "Topped up 3 of 3 reservoirs" },
        { t = 490, text = "Mold risk: 68% humidity with flowering plants" },
    },
}
local actions = {}
local function dump(name, class)
    buttons = {}
    local calls = {}
    local tab = class:new(0, 0, 560, 392, info, actions)
    tab.removeChild = function() end
    tab.drawText = function(_, text, x, y, r, g, b, a, font) calls[#calls + 1] = table.concat({ "T", x, y, r, g, b, tostring(font), text }, "\t") end
    tab.drawRect = function(_, x, y, w, h, a, r, g, b) calls[#calls + 1] = table.concat({ "R", x, y, w, h, r, g, b }, "\t") end
    tab:createChildren()
    tab:render()
    for _, b in ipairs(buttons) do calls[#calls + 1] = table.concat({ "B", b.x, b.y, b.w, b.active and 1 or 0, b.label }, "\t") end
    local f = assert(io.open(out .. "/" .. name .. ".tsv", "w"))
    f:write(table.concat(calls, "\n"), "\n")
    f:close()
end
for _, def in ipairs({ { "lights", CannabisMod.LightsTab }, { "hydro", CannabisMod.HydroTab }, { "plants", CannabisMod.PlantsTab },
    { "climate", CannabisMod.ClimateTab }, { "equipment", CannabisMod.EquipmentTab }, { "log", CannabisMod.LogTab } }) do
    dump(def[1], def[2])
end
print("wrote tab previews to " .. out)
