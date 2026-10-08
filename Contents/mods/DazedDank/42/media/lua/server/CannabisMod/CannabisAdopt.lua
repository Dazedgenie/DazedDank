-- Crash recovery: a save can keep a bag, bucket, table or grow room panel on the map but lose its farming or room
-- record (the map saves as you play, the records only on a full save); such tiles are rebuilt as their square loads.

if isClient() then return end

require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisFarming"
require "CannabisMod/CannabisGrowBags"
require "CannabisMod/CannabisRooms"
require "CannabisMod/CannabisRegistry"

local Config   = CannabisMod.Config
local Farming  = CannabisMod.Farming

local Adopt = {}
CannabisMod.Adopt = Adopt

Adopt.WAIT_TICKS = 30          -- ticks after a square loads before it is checked, so the farming system has caught up
Adopt.START_TICKS = 120        -- ticks after the game starts before any check runs
Adopt.REDRAW_TICKS = 300       -- how often registered bags with no object on their square are drawn again
Adopt.queue = {}
Adopt.restored = 0
local ticks = 0
local Registry = CannabisMod.Registry

--- Draw back every loaded bag whose plot exists but has no object on its square. Returns how many were drawn.
function Adopt.redrawAll()
    local n = 0
    for key in Registry.eachBag() do
        local x, y, z = key:match("^(-?%d+)_(-?%d+)_(-?%d+)$")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if x and getCell():getGridSquare(x, y, z) then
            local ok, drawn = pcall(CannabisMod.GrowBags.redraw, x, y, z)
            if ok and drawn then n = n + 1 end
        end
    end
    return n
end

--- What a loaded object is to us: "plot" (a bag or bucket shown as a plot), "furniture" (placed, never converted), "panel" or nil.
function Adopt.kindOf(obj)
    local sprite = obj and obj.getSprite and obj:getSprite()
    local name = sprite and sprite:getName()
    if not name then return nil end
    local bag = Config.bagFromSprite(name)
    if bag then return "plot", bag end
    bag = Config.bagFromFurnSprite(name)
    if bag then return "furniture", bag end
    if Config.Rooms and Config.Rooms.PANEL_SPRITES and Config.Rooms.PANEL_SPRITES[name] then return "panel" end
    return nil
end

--- Queue a freshly loaded square if anything on it is ours.
function Adopt.onLoad(square)
    local objects = square and square:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do
        if Adopt.kindOf(objects:get(i)) then
            Adopt.queue[#Adopt.queue + 1] = { x = square:getX(), y = square:getY(), z = square:getZ(), wait = Adopt.WAIT_TICKS }
            return
        end
    end
end

--- Rebuild whatever on the square lost its record. Returns how many tiles were restored.
function Adopt.check(x, y, z)
    local square = getCell() and getCell():getGridSquare(x, y, z)
    local objects = square and square:getObjects()
    if not objects then return 0 end
    local found = {}
    for i = 0, objects:size() - 1 do found[#found + 1] = objects:get(i) end
    local n, tables = 0, false
    for _, obj in ipairs(found) do
        local what, bag = Adopt.kindOf(obj)
        if what == "plot" and not Farming.getVanilla(x, y, z) then
            if CannabisMod.GrowBags.adoptOrphan(square, obj, bag) then
                n = n + 1
                tables = tables or bag == "ebb"
            end
        elseif what == "furniture" and not Farming.getVanilla(x, y, z) then
            if CannabisMod.GrowBags.convertBagAt(x, y, z) then n = n + 1 end
        elseif what == "panel" then
            if CannabisMod.Rooms.adoptPanel(obj) then n = n + 1 end
        end
    end
    if tables then
        CannabisMod.GrowBags.pairOrphanTable(x, y, z)
        if CannabisMod.Hydro then CannabisMod.Hydro.forgetLinks() end
    end
    return n
end

--- Work through the queue once the game has settled.
function Adopt.tick()
    ticks = ticks + 1
    if ticks < Adopt.START_TICKS then return end
    if (ticks - Adopt.START_TICKS) % Adopt.REDRAW_TICKS == 0 then
        local drawn = Adopt.redrawAll()
        if drawn > 0 then print(string.format("[DazedDank] drew back %d grow container(s) that had lost their object", drawn)) end
    end
    if #Adopt.queue == 0 then return end
    local before = Adopt.restored
    for i = #Adopt.queue, 1, -1 do
        local job = Adopt.queue[i]
        job.wait = job.wait - 1
        if job.wait <= 0 then
            table.remove(Adopt.queue, i)
            local ok, n = pcall(Adopt.check, job.x, job.y, job.z)
            if ok then Adopt.restored = Adopt.restored + n end
        end
    end
    if Adopt.restored > before then
        print(string.format("[DazedDank] restored %d grow container(s) or panel(s) that had lost their records", Adopt.restored - before))
    end
end

Events.LoadGridsquare.Add(function(square) pcall(Adopt.onLoad, square) end)
Events.OnTick.Add(Adopt.tick)

return Adopt
