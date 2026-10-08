-- Character creation: hides Dank's occupations and traits when the "Grower Occupations and Traits" sandbox switch is off.
-- It wraps the screen's own list builders, so vanilla and other mods' entries are untouched.

require "CannabisMod/CannabisTraits"

local Creation = {}
CannabisMod.Creation = Creation

--- The switch as character creation sees it: the sandbox screen's live option first, then SandboxVars.
function Creation.enabled()
    local ok, value = pcall(function()
        return getSandboxOptions():getOptionByName("CannabisMod.TraitsAndOccupations"):getValue()
    end)
    if ok and value ~= nil then return value == true end
    return CannabisMod.Traits.enabled()
end

--- True when a trait or profession type is one of Dank's.
function Creation.isOurs(kind)
    for _, list in ipairs({ DazedDankTraits or {}, DazedDankProfessions or {} }) do
        for _, registered in pairs(list) do
            if kind == registered then return true end
        end
    end
    return false
end

local function install()
    local Screen = CharacterCreationProfession
    if not Screen or Screen.ddWrapped then return end
    Screen.ddWrapped = true
    local isTraitEnabled = Screen.isTraitEnabled
    function Screen:isTraitEnabled(trait)
        local ok, kind = pcall(trait.getType, trait)
        if ok and Creation.isOurs(kind) and not Creation.enabled() then return false end
        return isTraitEnabled(self, trait)
    end
    local populateProfessionList = Screen.populateProfessionList
    function Screen:populateProfessionList(list)
        populateProfessionList(self, list)
        if Creation.enabled() or not list.items then return end
        for i = #list.items, 1, -1 do
            local entry = list.items[i]
            local ok, kind = pcall(function() return entry.item:getType() end)
            if ok and Creation.isOurs(kind) then table.remove(list.items, i) end
        end
    end
end

install()
if Events and Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(install) end

return Creation
