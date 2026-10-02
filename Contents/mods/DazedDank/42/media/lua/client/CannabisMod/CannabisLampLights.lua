-- Makes placed grow lamps actually light the room: a purple glow from the basic lamps and a warm yellow one from the pro lamps.
-- Lights are client-side visuals, rebuilt from the lamps near the player and switched by power and the lamp's timer.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local LampLights = {}
CannabisMod.LampLights = LampLights

-- Light colours by lamp tier: basic lamps run blurple LEDs, pro lamps a warm full-spectrum yellow.
LampLights.COLORS = {
    basic = { 0.85, 0.25, 1.00 },
    pro   = { 1.00, 0.82, 0.45 },
}
-- How many light sources each tier stacks on its tile: two for the purple so it reads strongly.
LampLights.LAYERS = { basic = 2, pro = 1 }
LampLights.SCAN_RADIUS = 30   -- tiles around the player that get lamp lights
LampLights.EVERY_TICKS = 60   -- rescan about once a second

local active = {}             -- tileKey -> { x, y, z, lights = { IsoLightSource... } }
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

--- Ask the game to redo its lighting soon, so a light switched off or removed stops showing.
local function refreshLighting()
    pcall(function() IsoGridSquare.setRecalcLightTime(-1) end)
    pcall(function() GameTime.getInstance():setLightSourceUpdate(100) end)
end

--- Switch a lamp's light sources on or off; called on every scan so the game can't leave them in the wrong state.
local function setLit(entry, on)
    local changed = entry.on ~= on
    for _, light in ipairs(entry.lights) do
        pcall(function()
            if light:isActive() ~= on then changed = true end
            light:setActive(on)
            if not on then light:clearInfluence() end
        end)
    end
    entry.on = on
    if changed then refreshLighting() end
end

--- Remove every light source on a lamp tile, trying each way the game offers so none is left glowing.
local function removeLight(key)
    local entry = active[key]
    if not entry then return end
    setLit(entry, false)
    for _, light in ipairs(entry.lights) do
        pcall(function() getCell():removeLamppost(light) end)
    end
    pcall(function() getCell():removeLamppost(entry.x, entry.y, entry.z) end)
    active[key] = nil
    refreshLighting()
end

local function addLight(key, x, y, z, def)
    local tier = LampLights.tier(def)
    local c = LampLights.COLORS[tier]
    local entry = { x = x, y = y, z = z, lights = {}, on = true }
    for _ = 1, LampLights.LAYERS[tier] do
        local ok, light = pcall(function()
            local l = IsoLightSource.new(x, y, z, c[1], c[2], c[3], LampLights.radius(def))
            getCell():addLamppost(l)
            return l
        end)
        if ok and light then entry.lights[#entry.lights + 1] = light else warnOnce(light) end
    end
    if #entry.lights > 0 then active[key] = entry end
    refreshLighting()
end

--- Rescan the lamps around the player and switch their lights on or off to match power and timer.
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
                        seen[key] = true
                        local on = lampOn(square, obj)
                        if not active[key] then
                            if on then addLight(key, x, y, pz, def) end
                        else
                            setLit(active[key], on)
                        end
                        break
                    end
                end
            end
        end
    end
    -- Lamps picked up, or left behind when the player moved away or changed floor.
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
