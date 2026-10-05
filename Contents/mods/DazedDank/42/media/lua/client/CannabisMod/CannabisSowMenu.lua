-- The Sow Seed menu on a grow bag, bucket or flood table lists only the seeds the player is carrying, not every crop at 0.

require "Farming/ISUI/ISFarmingMenu"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

--- True when a square holds one of our pots or tables (any plot sprite on a Dank sheet that is a bag kind).
local function isPotSquare(square)
    if not square then return false end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local sprite = objects:get(i):getSprite()
        local name = sprite and sprite:getName()
        if name and Config.bagFromSprite(name) then return true end
    end
    return false
end

if ISFarmingMenu and ISFarmingMenu.doSeedMenu and not ISFarmingMenu.ddSowFiltered then
    ISFarmingMenu.ddSowFiltered = true
    local original = ISFarmingMenu.doSeedMenu
    function ISFarmingMenu:doSeedMenu(context, plant, sq, playerObj, ...)
        -- Catch the Sow submenu as vanilla makes it, so its rows can be pruned afterwards.
        local subMenu
        local getNew = context.getNew
        context.getNew = function(c, ...)
            local m = getNew(c, ...)
            subMenu = subMenu or m
            return m
        end
        local ok, err = pcall(original, self, context, plant, sq, playerObj, ...)
        context.getNew = nil
        if not ok then error(err, 0) end
        if not (subMenu and isPotSquare(sq)) then return end
        local empty = {}
        for _, option in ipairs(subMenu.options or {}) do
            if type(option.name) == "string" and option.name:match(" : 0$") then empty[#empty + 1] = option.name end
        end
        for _, name in ipairs(empty) do subMenu:removeOptionByName(name) end
        if subMenu.numOptions <= 1 then
            subMenu:addOption(getText("IGUI_DD_NoSeedsCarried") ~= "IGUI_DD_NoSeedsCarried" and getText("IGUI_DD_NoSeedsCarried") or "No seeds carried", nil, nil).notAvailable = true
        end
    end
end
