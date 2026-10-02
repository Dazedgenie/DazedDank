-- Teaches every mod recipe to the player when the RecipeMagazine sandbox option is off, so the Grower's Handbook is only needed when the option is on.
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Recipes = {}
CannabisMod.Recipes = Recipes

-- Must match the craftRecipe names in CannabisRecipes.txt and the magazine's LearnedRecipes; a test keeps them in sync.
Recipes.NAMES = {
    "DDMakeGrowBagSmall", "DDMakeGrowBagLarge", "DDMakeSoilSack", "DDMakeDryingRack", "DDMakeDryingFan",
    "DDMakeGrowLampBasic", "DDMakeGrowLampPro", "DDMakeGrowLampLargeBasic", "DDMakeGrowLampLargePro",
    "DDMakeGrowFloodBasic", "DDMakeGrowFloodPro", "DDMakeLightTimer",
    "DDMakeCuringJar", "DDMakeCuringBarrel", "DDSwapPapers",
    "DDMakeDWCBucket", "DDMakeClayPebbles", "DDMakeRDWCSite", "DDMakeRDWCControl",
}

--- Learn every recipe on this player unless the magazine is required; returns how many were newly learned.
function Recipes.learnAll(player)
    if not player or Config.sandbox("RecipeMagazine") then return 0 end
    local count = 0
    for _, name in ipairs(Recipes.NAMES) do
        if not player:isRecipeKnown(name) then
            player:learnRecipe(name)
            count = count + 1
        end
    end
    return count
end

Events.OnCreatePlayer.Add(function(_, player) Recipes.learnAll(player) end)
