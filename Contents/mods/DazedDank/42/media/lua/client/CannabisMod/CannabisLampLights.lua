-- Makes placed grow lamps actually light the room: a purple glow from the basic lamps and a warm yellow one from the pro lamps.
-- Lights are client-side visuals, rebuilt from the lamps near the player and switched by power and the lamp's timer.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local LampLights = {}
CannabisMod.LampLights = LampLights

-- Light colours by lamp tier: basic lamps run blurple LEDs, pro lamps a warm full-spectrum yellow.
LampLights.COLORS = {
    basic = { 0.70, 0.40, 1.00 },
    pro   = { 1.00, 0.82, 0.45 },
}
LampLights.SCAN_RADIUS = 30   -- tiles around the player that get lamp lights
LampLights.EVERY_TICKS = 60   -- rescan about once a second

local active = {}             -- tileKey -> IsoLightSource
local ticks = 0
local warned = false

--- Print the first failure to console.txt so a changed game API shows up instead of silently giving no light.
local function warnOnce(err)
    if warned then return end
    warned = true
    print("[DazedDank] lamp lights failed: " .. tostring(err))
end

--- Colour tier for a lamp definition: pro-ceiling lamps are yellow, the rest purple.
function LampLights.tier(def)
    return def.cap >= Config.LightCap.GOOD_LAMP and "pro" or "basic"
end

--- Light radius in tiles for a lamp: a little past the area it grows plants in.
function LampLights.radius(def)
    return math.ceil(def.radius) + 2
end

--- True if the lamp on this square should be glowing right now.
local function lampOn(square, obj)
    if Config.sandbox("LampsNeedPower") then
        local ok, powered = pcall(function()
            if square:haveElectricity() then return true end
            return (not square:isOutside()) and getWorld():isHydroPowerOn() or false
        end)
        if not (ok and powered) then return false end
    end
    local schedule = nil
    pcall(function() schedule = obj:getModData().DDTimer end)
    return Config.Timer.isOn(schedule, getGameTime():getHour())
end

local function removeLight(key)
    local light = active[key]
    if light then
        pcall(function() getCell():removeLamppost(light) end)
        active[key] = nil
    end
end

local function addLight(key, x, y, z, def)
    local c = LampLights.COLORS[LampLights.tier(def)]
    local ok, light = pcall(function()
        local l = IsoLightSource.new(x, y, z, c[1], c[2], c[3], LampLights.radius(def))
        getCell():addLamppost(l)
        return l
    end)
    if ok and light then active[key] = light else warnOnce(light) end
end

--- Rescan the lamps around the player and switch their lights on or off to match.
function LampLights.update()
    local player = getPlayer()
    if not player then return end
    local cell = getCell()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    local R = LampLights.SCAN_RADIUS
    local seen = {}
    for x = px - R, px + R do
        for y = py - R, py + R do
            local square = cell:getGridSquare(x, y, pz)
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    local sprite = obj:getSprite()
                    local def = sprite and Config.Light.SPRITES[sprite:getName()]
                    if def then
                        local key = Config.tileKey(x, y, pz)
                        if lampOn(square, obj) then
                            seen[key] = true
                            if not active[key] then addLight(key, x, y, pz, def) end
                        end
                        break
                    end
                end
            end
        end
    end
    -- Anything lit last time but not this time was switched off, picked up or left behind.
    local gone = {}
    for key in pairs(active) do
        if not seen[key] then gone[#gone + 1] = key end
    end
    for _, key in ipairs(gone) do removeLight(key) end
end

Events.OnTick.Add(function()
    ticks = ticks + 1
    if ticks < LampLights.EVERY_TICKS then return end
    ticks = 0
    local ok, err = pcall(LampLights.update)
    if not ok then warnOnce(err) end
end)
