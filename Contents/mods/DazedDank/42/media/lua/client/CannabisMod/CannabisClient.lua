-- Everything the player's own game does: right-click options, asking the
-- server for plant info, and showing replies. This file only sends requests
-- and displays answers.

require "Farming/farming_vegetableconf"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisDomeContainer"
require "CannabisMod/CannabisInfo"
require "CannabisMod/CannabisSeeds"
require "CannabisMod/CannabisNet"
require "CannabisMod/ISTakeCannabisCuttingAction"
require "CannabisMod/ISGrowBagAction"
require "CannabisMod/ISCannabisSmokeAction"
require "CannabisMod/CannabisHigh"
require "CannabisMod/CannabisStatusWindow"
require "CannabisMod/ISCannabisItemAction"
require "Farming/TimedActions/ISSeedActionNew"

local Config = CannabisMod.Config
local Info   = CannabisMod.Info
local Seeds  = CannabisMod.Seeds
local Net    = CannabisMod.Net

local Client = {}
CannabisMod.Client = Client

local function send(player, command, args)
    sendClientCommand(player, Config.COMMAND_MODULE, command, args or {})
end

local function squareArgs(square)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

-- --------------------------------------------------------------------------
-- Showing replies
-- --------------------------------------------------------------------------

-- Fixed display order so lines don't jump around. Fields the player hasn't
-- unlocked are simply missing from the reply, so they're skipped.
local DISPLAY_ORDER = {
    "name", "container", "stageRough", "rooting", "stage", "hoursLeft", "waterRough", "water",
    "lastNutrient", "type", "sex", "light", "healthBand", "stressBand",
    "warnings", "harvestWindow", "pollinated", "hermieSigns",
    "generation", "geneticsBand", "qualityEstimate",
}

-- Readable labels for the window.
local LABELS = {
    name = "Plant", container = "Planted in", stageRough = "Growth", stage = "Stage", hoursLeft = "Next stage in",
    waterRough = "Watering", water = "Water", lastNutrient = "Last nutrient",
    type = "Type", sex = "Sex", light = "Light", healthBand = "Health",
    stressBand = "Stress", warnings = "Warnings", harvestWindow = "Harvest window",
    pollinated = "Pollinated", hermieSigns = "Hermie signs", generation = "Generation",
    geneticsBand = "Genetics", qualityEstimate = "Est. quality", rooting = "Rooting",
}

local function formatInfo(data)
    local lines = {}
    for _, field in ipairs(DISPLAY_ORDER) do
        local value = data[field]
        if value ~= nil then
            if type(value) == "table" then
                value = (#value > 0) and table.concat(value, ", ") or "none"
            end
            if field == "hoursLeft" and type(value) == "number" then
                -- show days and hours, e.g. "1 d 6 h"
                local d, h = math.floor(value / 24), value % 24
                value = (d > 0) and (d .. " d " .. h .. " h") or (h .. " h")
            end
            lines[#lines + 1] = { (LABELS[field] or field), tostring(value) }
        end
    end
    return lines
end

-- Plain text status window, kept as the fallback if the styled one fails.
-- Any failure here falls back to floating text so inspect never breaks.
local function openWindow(lines, level)
    local text = ""
    for _, l in ipairs(lines) do
        text = text .. "<LEFT> " .. l[1] .. ": <RGB:1,1,0.6> " .. l[2] .. " <RGB:1,1,1> <LINE> "
    end
    local w, h = 340, 60 + #lines * 20
    local win = ISCollapsableWindow:new(200, 200, w, h + 24)
    win:initialise()
    win:setTitle("Cannabis Plant (Agriculture " .. tostring(level) .. ")")
    win.resizable = false
    local panel = ISRichTextPanel:new(0, 16, w, h)
    panel:initialise()
    panel.autosetheight = false
    panel.clip = true
    panel:setText(text)
    panel:paginate()
    win:addChild(panel)
    win:addToUIManager()
    win:setVisible(true)
    return win
end

local currentWindow = nil

function Client.showPlantInfo(data)
    local player = getPlayer()
    if not player then return end
    if data.missing then
        player:setHaloNote("No cannabis plant data here")
        return
    end
    local lines = formatInfo(data)
    print("[DazedDank] Plant info (Agriculture " .. tostring(data.level) .. "):")
    for _, l in ipairs(lines) do
        print("  " .. l[1] .. ": " .. l[2])
    end
    if data.debugNow then
        print("  [debug] worldHours=" .. tostring(data.debugNow) .. " nextStageAt="
            .. tostring(data.debugNext) .. " growthSpeed=" .. tostring(data.debugSpeed))
    end
    if currentWindow then
        pcall(function() currentWindow:removeFromUIManager() end)
        currentWindow = nil
    end
    local ok, result = pcall(CannabisMod.StatusWindow.open, data)
    if not ok then
        print("[DazedDank] WARNING: styled status window failed: " .. tostring(result))
        ok, result = pcall(openWindow, lines, data.level)
    end
    if ok then
        currentWindow = result
    else
        print("[DazedDank] WARNING: status window failed: " .. tostring(result))
        local flat = {}
        for _, l in ipairs(lines) do flat[#flat + 1] = l[1] .. ": " .. l[2] end
        player:setHaloNote(table.concat(flat, " | "))
    end
end

function Client.notify(args)
    local player = getPlayer()
    if player and args.text then
        player:setHaloNote(args.text)
    end
end

-- Register handlers in one table. Net.toPlayer calls these directly in single
-- player; in multiplayer they're reached through OnServerCommand.
Net.clientHandlers.plantInfo = Client.showPlantInfo
Net.clientHandlers.notify    = Client.notify

local function onServerCommand(module, command, args)
    if module ~= Config.COMMAND_MODULE then return end
    local handler = Net.clientHandlers[command]
    if handler then handler(args or {}) end
end
Events.OnServerCommand.Add(onServerCommand)

-- --------------------------------------------------------------------------
-- Right-click on the ground / a plot
-- --------------------------------------------------------------------------

-- Vanilla growth numbers that mean veg or pre-flower (see
-- Config.STAGE_TO_NBOFGROW), the stages you can take cuttings in.
local CLONEABLE_NBOFGROW = {}
for stageName in pairs(Config.CLONEABLE_STAGES) do
    CLONEABLE_NBOFGROW[Config.STAGE_TO_NBOFGROW[stageName]] = true
end

--- The vanilla client plot on this square, if it's a cannabis plant. pcall: a
--- renamed function in a future B42 patch then logs a warning instead of
--- breaking every right-click menu in the game.
local function getAnyPlot(square)
    if not CFarmingSystem or not CFarmingSystem.instance then return nil end
    local ok, plot = pcall(function()
        return CFarmingSystem.instance:getLuaObjectOnSquare(square)
    end)
    return ok and plot or nil
end

local function getCannabisPlot(square)
    if not CFarmingSystem or not CFarmingSystem.instance then return nil end
    local ok, plot = pcall(function()
        return CFarmingSystem.instance:getLuaObjectOnSquare(square)
    end)
    if not ok then
        print("[DazedDank] WARNING: farming lookup failed: " .. tostring(plot))
        return nil
    end
    if plot and plot.typeOfSeed == Config.CROP_TYPE and plot:isAlive() then
        return plot
    end
    return nil
end

local addDomeOptions
local addStationOptions
local addHydroOptions

--- A water or tainted-water container with something in it, or nil.
local function hasWater(player)
    return Seeds.findItem(player:getInventory(), function(i)
        local ok, yes = pcall(function()
            local fc = i:getFluidContainer()
            if not fc or fc:getAmount() <= 0 or not fc:getPrimaryFluid() then return false end
            local t = fc:getPrimaryFluid():getFluidTypeString()
            return t == "Water" or t == "TaintedWater"
        end)
        return ok and yes
    end) ~= nil
end

--- A bleach bottle with some left, or nil.
local function hasBleach(player)
    return Seeds.findItem(player:getInventory(), function(i)
        local ok, yes = pcall(function()
            local fc = i:getFluidContainer()
            return fc and fc:getPrimaryFluid() and fc:getPrimaryFluid():getFluidTypeString() == "Bleach" and fc:getAmount() > 0
        end)
        return ok and yes
    end) ~= nil
end

--- Grey out an option with a short reason.
local function needs(option, ok, why)
    if ok then return end
    option.notAvailable = true
    local tip = ISInventoryPaneContextMenu.addToolTip()
    tip.description = why
    option.toolTip = tip
end

--- Reservoir, medium and root options on a hydro plot.
function addHydroOptions(player, context, plot, kind, action)
    local inv = player:getInventory()
    if plot.state == "plow" and Config.bagIsUnfilled(plot.spriteName) then
        local rw = context:addOption("Add Rockwool Cube", player, function() action("hydroAddMedium", { medium = "rockwool" }) end)
        needs(rw, inv:containsTypeRecurse(Config.Hydro.MEDIUM_ITEMS.rockwool), "Needs a rockwool cube. Best for starting seeds.")
        local cp = context:addOption("Fill With Clay Pebbles", player, function() action("hydroAddMedium", { medium = "pebbles" }) end)
        needs(cp, inv:containsTypeRecurse(Config.Hydro.MEDIUM_ITEMS.pebbles), "Needs clay pebbles. Reusable; some seeds sown straight in fail.")
    end
    local parent = context:addOption("Reservoir", player, nil)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)
    sub:addOption("Check Reservoir", player, function() action("hydroCheck") end)
    local water = hasWater(player)
    needs(sub:addOption("Top Up Reservoir", player, function() action("hydroTopUp") end), water, "Needs water in a bottle, pot or bucket.")
    needs(sub:addOption("Change Reservoir", player, function() action("hydroChange") end), water, "Drains the old water and refills it. Needs water.")
    needs(sub:addOption("Treat Roots With Bleach", player, function() action("hydroBleach") end), hasBleach(player),
        "Cures early root rot after a reservoir change. Needs bleach.")
end
local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or not worldObjects or #worldObjects == 0 then return end
    local square = worldObjects[1]:getSquare()
    if not square then return end

    -- Grow bags. A bag plot is recognised by its sprite (the server keeps the
    -- real registry).
    local anyPlot = getAnyPlot(square)
    local bagSize = anyPlot and Config.bagFromSprite(anyPlot.spriteName) or nil
    local function bagAction(command, extra)
        if luautils.walkAdj(player, square) then
            ISTimedActionQueue.add(ISGrowBagAction:new(player, square, command, extra))
        end
    end
    if bagSize then
        if Config.isHydro(bagSize) then
            addHydroOptions(player, context, anyPlot, bagSize, bagAction)
        end
        if anyPlot.state == "plow" and Config.bagIsUnfilled(anyPlot.spriteName) and not Config.isHydro(bagSize) then
            -- A new bag needs soil once before anything can be sown in it.
            local need = Config.GrowBag[bagSize].soil
            local have = #Seeds.findAll(player:getInventory(), function(i)
                return Config.isSoilItem(i:getFullType())
            end)
            local opt = context:addOption("Fill " .. Config.GrowBag[bagSize].name .. " with Soil", player, function()
                bagAction("fillGrowBag")
            end)
            if have < need then
                opt.notAvailable = true
                local tip = ISInventoryPaneContextMenu.addToolTip()
                tip.description = "Needs " .. need .. " sack" .. (need > 1 and "s" or "") .. " of soil (you have " .. have .. ")"
                opt.toolTip = tip
            end
        end
        if anyPlot.state == "plow" then
            context:addOption("Pick Up " .. Config.GrowBag[bagSize].name, player, function()
                bagAction("pickUpGrowBag")
            end)
        elseif not anyPlot:isAlive() or anyPlot.state == "dead" or anyPlot.state == "rotten"
                or anyPlot.state == "destroyed" or anyPlot.state == "harvested" then
            context:addOption("Empty " .. Config.GrowBag[bagSize].name, player, function()
                bagAction("emptyGrowBag")
            end)
        end
    end

    -- Placed grow lamp: install, set or remove a light timer.
    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        local sprite = obj:getSprite()
        if sprite and Config.Light.SPRITES[sprite:getName()] then
            local schedule = obj:getModData().DDTimer
            if not schedule then
                local opt = context:addOption("Install Light Timer", player, function() bagAction("installTimer") end)
                if not player:getInventory():containsTypeRecurse(Config.Timer.ITEM) then
                    opt.notAvailable = true
                    local tip = ISInventoryPaneContextMenu.addToolTip()
                    tip.description = "Needs a light timer. Without one this lamp runs 24/0, so plants under it stay in veg."
                    opt.toolTip = tip
                end
            else
                local parent = context:addOption("Light Timer: " .. schedule, player, nil)
                local sub = ISContextMenu:getNew(context)
                context:addSubMenu(parent, sub)
                local labels = { ["18/6"] = "Set to 18/6 (veg)", ["12/12"] = "Set to 12/12 (flower)" }
                for _, s in ipairs(Config.Timer.ORDER) do
                    if s ~= schedule then
                        sub:addOption(labels[s], player, function() bagAction("setTimer", { schedule = s }) end)
                    end
                end
                sub:addOption("Remove Light Timer", player, function() bagAction("removeTimer") end)
            end
            break
        end
    end

    -- Placed curing barrel.
    for i = 0, square:getObjects():size() - 1 do
        local sprite = square:getObjects():get(i):getSprite()
        if sprite and sprite:getName() == Config.Drying.BARREL_SPRITE then
            context:addOption("Check Curing Barrel", player, function(p) send(p, "checkBarrel", squareArgs(square)) end)
            context:addOption("Burp Barrel", player, function(p) send(p, "burpBarrel", squareArgs(square)) end)
            break
        end
    end

    -- Placed drying rack (either of its two tiles).
    for i = 0, square:getObjects():size() - 1 do
        local sprite = square:getObjects():get(i):getSprite()
        if sprite and Config.Drying.RACK_SPRITES[sprite:getName()] then
            context:addOption("Check Drying Rack", player, function(p) send(p, "checkRack", squareArgs(square)) end)
            break
        end
    end

    local plot = getCannabisPlot(square)
    if plot then
        context:addOption("Inspect Cannabis Plant", player, function(p)
            send(p, "requestPlantInfo", squareArgs(square))
        end)

        -- Feed: one nutrient bottle per feeding. Shown whenever there is a
        -- plant; greyed out without the bottle.
        for _, nutrient in ipairs({ "Veg", "Bloom" }) do
            local itemType = Config.NUTRIENT_ITEMS[nutrient]
            local has = Seeds.findItem(player:getInventory(), function(i)
                return i:getFullType() == itemType
            end)
            local option = context:addOption("Feed " .. nutrient .. " Nutrients", player, function(p)
                local a = squareArgs(square)
                a.nutrient = nutrient
                send(p, "feedPlant", a)
            end)
            if not has then option.notAvailable = true end
        end

        -- Take Cutting: only in veg or pre-flower. The client reads the stage
        -- from vanilla's growth number (CLONEABLE_NBOFGROW); the server
        -- checks the real stage again.
        if CLONEABLE_NBOFGROW[plot.nbOfGrow] then
            local option = context:addOption("Take Cutting", player, function(p)
                if ISFarmingMenu.walkToPlant(p, square) then
                    ISTimedActionQueue.add(ISTakeCannabisCuttingAction:new(p, plot, square))
                end
            end)
            if not Seeds.findCuttingTool(player) then
                option.notAvailable = true
                local tip = ISToolTip:new()
                tip:initialise()
                tip:setVisible(false)
                tip.description = "Needs scissors, a sharp knife or another plant-cutting tool"
                option.toolTip = tip
            end
        end
    end

    -- A cloning dome sitting in the world (on a table or the floor).
    for _, obj in ipairs(worldObjects) do
        local ok, item = pcall(function()
            return instanceof(obj, "IsoWorldInventoryObject") and obj:getItem() or nil
        end)
        if ok and item and item:getFullType() == Config.DOME_ITEM then
            addDomeOptions(player, context, item)
        elseif ok and item then
            addStationOptions(player, context, item)
        end
    end

    -- Debug-mode helpers. The server re-checks debug/admin, so showing these
    -- grants nothing by itself.
    if isDebugEnabled() then
        context:addOption("[Debug] Give cannabis test seeds", player, function(p)
            send(p, "debugGiveSeeds")
        end)
        context:addOption("[Debug] Give cloning kit", player, function(p)
            send(p, "debugCloningKit")
        end)
        context:addOption("[Debug] Give grow kit", player, function(p)
            send(p, "debugGrowKit")
        end)
        context:addOption("[Debug] Give hydro kit", player, function(p)
            send(p, "debugHydroKit", {})
        end)
        context:addOption("[Debug] Give drying kit", player, function(p)
            send(p, "debugDryingKit")
        end)
        context:addOption("[Debug] Give smoking kit", player, function(p)
            send(p, "debugSmokeKit")
        end)
        context:addOption("[Debug] Dependent: tolerance 60, dependency 80, 48h clean", player, function(p)
            send(p, "debugUseState", { tol = 60, dep = 80, hoursAgo = 48 })
        end)
        context:addOption("[Debug] Reset tolerance and dependency", player, function(p)
            send(p, "debugUseState", { tol = 0, dep = 0, hoursAgo = 0 })
        end)
        context:addOption("[Debug] Racks and jars: +24 hours", player, function(p)
            send(p, "debugAdvanceStations", { hours = 24 })
        end)
        if plot then
            context:addOption("[Debug] Cannabis: next stage", player, function(p)
                send(p, "debugNextStage", squareArgs(square))
            end)
            context:addOption("[Debug] Cannabis: finish rooting", player, function(p)
                send(p, "debugFinishRooting")
            end)
        end
    end
end
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- --------------------------------------------------------------------------
-- Right-click on a seed in the inventory
-- --------------------------------------------------------------------------

--- Inventory menus pass either items or stacks ({ items = {...} }).
local function firstItem(entry)
    if type(entry) == "table" and entry.items then
        return entry.items[1]
    end
    return entry
end

--- Agriculture-gated description of a seed or cutting.
local function describePlantable(item, level)
    local kind = Seeds.kind(item)
    local data = Seeds.getPlantData(item)
    if kind == "seed" then
        return Info.seedLabel(data, level)
    end
    local name = (kind == "rooted") and "Rooted cutting" or "Cutting"
    local parts = {}
    if level >= Config.SEED_INSPECT_LEVEL then
        parts[#parts + 1] = data.type
    end
    if level >= 9 then
        parts[#parts + 1] = "generation " .. tostring(data.generation)
    end
    if kind == "cutting" then
        parts[#parts + 1] = data.gel and "dipped in gel" or "no gel"
        parts[#parts + 1] = string.format("cut %dh ago", math.floor(Seeds.ageHours(item)))
    end
    if #parts == 0 then return name end
    return name .. " (" .. table.concat(parts, ", ") .. ")"
end

--- Check / take options for a cloning dome, wherever it is (inventory or
--- placed on a table). The server finds it again from its ID and square.
function addDomeOptions(player, context, dome)
    local args = CannabisMod.DomeContainer.squareArgs(dome, player)
    args.domeId = dome:getID()
    context:addOption("Check Cuttings", player, function(p)
        send(p, "domeCheck", args)
    end)
    context:addOption("Take Rooted Cuttings", player, function(p)
        send(p, "domeTake", args)
    end)
    if isDebugEnabled() then
        context:addOption("[Debug] Finish rooting now", player, function(p)
            send(p, "debugFinishRooting", args)
        end)
    end
end

--- Burp / check options for a curing jar, wherever it is.
function addStationOptions(player, context, item)
    if item:getFullType() ~= Config.Drying.JAR_ITEM then return end
    local args = CannabisMod.DomeContainer.squareArgs(item, player)
    args.id = item:getID()
    context:addOption("Check Curing Jar", player, function(p) send(p, "checkJar", args) end)
    context:addOption("Burp Jar", player, function(p) send(p, "burpJar", args) end)
end

--- A lighter with fuel left in the player's bag, or nil.
local function findLighter(player)
    local inv = player:getInventory()
    for _, itemType in ipairs(Config.Smoking.LIGHTERS) do
        local lighter = inv:getFirstTypeEvalRecurse(itemType, function(i) return i:getCurrentUsesFloat() > 0 end)
        if lighter then return lighter end
    end
    return nil
end

--- Is there anything to light a smoke with: an open flame nearby or a lighter.
local function canLight(player)
    local ok, flame = pcall(function() return ISInventoryPaneContextMenu.hasOpenFlame(player) end)
    return (ok and flame) and true or findLighter(player) ~= nil
end

--- Smoking menu options for a bud or a joint.
local function addSmokingOptions(player, context, item)
    local fullType = item:getFullType()
    local S = Config.Smoking
    local function needs(opt, text)
        opt.notAvailable = true
        local tip = ISToolTip:new()
        tip:initialise()
        tip:setVisible(false)
        tip.description = text
        opt.toolTip = tip
    end
    local function smoke(method)
        local flame = (ISInventoryPaneContextMenu.hasOpenFlame(player)) and nil or findLighter(player)
        ISTimedActionQueue.add(ISCannabisSmokeAction:new(player, item, method, flame))
    end
    if fullType == Config.Drying.BUD_ITEM then
        local paper = Seeds.findItem(player:getInventory(), function(i) return i:getFullType() == S.PAPER_ITEM end)
        local roll = context:addOption("Roll Joint", player, function(p)
            ISTimedActionQueue.add(ISCannabisItemAction:new(p, item, "rollJoint", 120))
        end)
        if not paper then needs(roll, "Needs rolling papers") end

        local pipe = Seeds.findItem(player:getInventory(), function(i) return i:getFullType() == S.PIPE_ITEM end)
        local opt = context:addOption("Smoke in Pipe", player, function() smoke("pipe") end)
        if not pipe then needs(opt, "Needs a smoking pipe")
        elseif not canLight(player) then needs(opt, "Needs a lighter or an open flame") end
    elseif fullType == S.JOINT_ITEM then
        local opt = context:addOption("Smoke Joint", player, function() smoke("joint") end)
        if not canLight(player) then needs(opt, "Needs a lighter or an open flame") end
    end
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or not items then return end
    local inv = player:getInventory()

    for _, entry in ipairs(items) do
        local item = firstItem(entry)
        if item and item.getFullType then
            local fullType = item:getFullType()
            local kind = Seeds.kind(item)

            -- Seeds and cuttings: inspect
            if kind then
                context:addOption(kind == "seed" and "Inspect Seed" or "Inspect Cutting", player, function(p)
                    p:setHaloNote(describePlantable(item, p:getPerkLevel(Perks.Farming)))
                end)
            end

            -- Fresh cutting: dip in rooting gel
            if kind == "cutting" and not Seeds.getCuttingData(item).gel then
                local hasGel = Seeds.findItem(inv, function(i)
                    return i:getFullType() == Config.GEL_ITEM
                end)
                local option = context:addOption("Dip in Rooting Gel", player, function(p)
                    send(p, "dipInGel", { id = item:getID() })
                end)
                if not hasGel then option.notAvailable = true end
            end

            -- Wet whole plant: trim into buds (needs scissors or a sharp knife)
            if Config.isHangingPlant(fullType) then
                local opt = context:addOption("Trim Plant", player, function(p)
                    ISTimedActionQueue.add(ISCannabisItemAction:new(p, item, "trimPlant", 200))
                end)
                if not Seeds.findCuttingTool(player) then
                    opt.notAvailable = true
                    local tip = ISToolTip:new()
                    tip:initialise()
                    tip:setVisible(false)
                    tip.description = "Needs scissors, a sharp knife or another plant-cutting tool"
                    opt.toolTip = tip
                end
            end

            -- Bud: what is it worth?
            if fullType == Config.Drying.BUD_ITEM then
                context:addOption("Inspect Bud", player, function(p) send(p, "inspectBud", { id = item:getID() }) end)
            end

            -- Rack / jar
            addStationOptions(player, context, item)

            -- Buds and joints can be smoked
            addSmokingOptions(player, context, item)

            -- Cloning dome (a container: drag cuttings in). Check / take.
            if fullType == Config.DOME_ITEM then
                addDomeOptions(player, context, item)
            end
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)


-- Sowing into a bag that has no soil yet is refused (the server checks too;
-- this just stops the action from starting). The plot's sprite tells us.
if ISSeedActionNew and ISSeedActionNew.isValid then
    local originalIsValid = ISSeedActionNew.isValid
    function ISSeedActionNew:isValid()
        local ok, unfilled = pcall(function()
            local sq = getCell():getGridSquare(self.plant.x, self.plant.y, self.plant.z)
            local plot = sq and getAnyPlot(sq)
            return plot and Config.bagIsUnfilled(plot.spriteName)
        end)
        if ok and unfilled then return false end
        return originalIsValid(self)
    end
end


-- Vanilla's farming info window assumes every plot has a crop entry and throws every frame for a plot without one, such as a soil-only bag. These guards show "Unknown" for those plots instead.
local function guardFarmingInfo()
    if not (ISFarmingInfo and farming_vegetableconf and farming_vegetableconf.props) then return end
    if ISFarmingInfo.ddGuarded then return end
    ISFarmingInfo.ddGuarded = true
    for _, name in ipairs({ "getCurrentGrowingPhase", "getNextGrowingPhase" }) do
        local original = ISFarmingInfo[name]
        if original then
            ISFarmingInfo[name] = function(info, ...)
                local plant = info and info.plant
                if plant and not farming_vegetableconf.props[plant.typeOfSeed] then
                    return getText("UI_FriendState_Unknown")
                end
                return original(info, ...)
            end
        end
    end
end
-- The info window also stays open after a harvest empties the plot, and its debug pest loop then fails every frame. Skipping the draw for a plot with no crop entry stops that.
local function guardFarmingInfoRender()
    if not (ISFarmingInfo and ISFarmingInfo.render and farming_vegetableconf and farming_vegetableconf.props) then return end
    if ISFarmingInfo.ddRenderGuarded then return end
    ISFarmingInfo.ddRenderGuarded = true
    local original = ISFarmingInfo.render
    ISFarmingInfo.render = function(self, ...)
        local plant = self and self.plant
        if plant and not farming_vegetableconf.props[plant.typeOfSeed] then return end
        return original(self, ...)
    end
end
Events.OnGameStart.Add(guardFarmingInfo)
Events.OnGameStart.Add(guardFarmingInfoRender)

-- The same missing entry breaks vanilla's phase text, which also feeds the plot's hover name.
local vanillaGetObjectPhase = farming_vegetableconf and farming_vegetableconf.getObjectPhase
if vanillaGetObjectPhase then
    farming_vegetableconf.getObjectPhase = function(plant)
        if plant and not farming_vegetableconf.props[plant.typeOfSeed] then
            return getText("Farming_Plowed_Land")
        end
        return vanillaGetObjectPhase(plant)
    end
end
