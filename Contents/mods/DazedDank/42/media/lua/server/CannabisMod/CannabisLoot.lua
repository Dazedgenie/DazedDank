-- Adds the mod's items to vanilla loot tables: grow gear in garden and hardware stores, and seeds, papers and pipes in the places where people stash them.

require "Items/ProceduralDistributions"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Loot = {}
CannabisMod.Loot = Loot

-- Weights per vanilla distribution list; vanilla weights run from about 0.1 (rare) to 50 (common), and a list's "rolls" decide how many picks it makes.
Loot.TABLE = {
    GardenStoreMisc = {
        ["CannabisMod.CannabisSeed"] = 0.6, ["CannabisMod.SoilSack"] = 4, ["CannabisMod.GrowBagSmallPlaceable"] = 3,
        ["CannabisMod.GrowBagLargePlaceable"] = 2, ["CannabisMod.GrowersHandbook"] = 0.8, ["CannabisMod.LightTimer"] = 3, ["CannabisMod.VegNutrients"] = 2, ["CannabisMod.BloomNutrients"] = 2,
    },
    GardenStoreTools = {
        ["CannabisMod.GrowLampBasic"] = 1.5, ["CannabisMod.GrowLampPro"] = 0.5, ["CannabisMod.GrowLampLargeBasic"] = 0.3,
        ["CannabisMod.DryingFan"] = 0.6, ["CannabisMod.GrowFloodBasic"] = 0.5, ["CannabisMod.GrowFloodPro"] = 0.15, ["CannabisMod.SoilSack"] = 3, ["CannabisMod.VegNutrients"] = 1, ["CannabisMod.BloomNutrients"] = 1,
        ["CannabisMod.RootingGel"] = 0.6, ["CannabisMod.CloningDomeTray"] = 0.4, ["CannabisMod.GrowersHandbook"] = 0.4, ["CannabisMod.LightTimer"] = 3,
    },
    GardenerTools = {
        ["CannabisMod.CannabisSeed"] = 0.3, ["CannabisMod.SoilSack"] = 1, ["CannabisMod.GrowBagSmallPlaceable"] = 1,
        ["CannabisMod.VegNutrients"] = 0.5, ["CannabisMod.RootingGel"] = 0.3,
    },
    CrateFarming = {
        ["CannabisMod.CannabisSeed"] = 0.3, ["CannabisMod.SoilSack"] = 2, ["CannabisMod.GrowBagSmallPlaceable"] = 1,
        ["CannabisMod.GrowBagLargePlaceable"] = 0.6,
    },
    ToolStoreMisc = {
        ["CannabisMod.GrowLampBasic"] = 0.8, ["CannabisMod.GrowLampPro"] = 0.2, ["CannabisMod.DryingFan"] = 0.5,
        ["CannabisMod.GrowFloodBasic"] = 0.4, ["CannabisMod.GrowFloodPro"] = 0.1, ["CannabisMod.LightTimer"] = 4,
    },
    DrugShackMisc = {
        ["CannabisMod.CannabisSeed"] = 4, ["CannabisMod.RollingPapers"] = 6, ["CannabisMod.SmokingPipe"] = 3,
        ["CannabisMod.GrowLampBasic"] = 1, ["CannabisMod.VegNutrients"] = 1, ["CannabisMod.BloomNutrients"] = 1,
        ["CannabisMod.GrowersHandbook"] = 2, ["CannabisMod.LightTimer"] = 3,
    },
    DrugLabSupplies = {
        ["CannabisMod.CannabisSeed"] = 2, ["CannabisMod.GrowLampPro"] = 1, ["CannabisMod.GrowLampLargePro"] = 0.3, ["CannabisMod.GrowFloodPro"] = 0.5,
        ["CannabisMod.VegNutrients"] = 2, ["CannabisMod.BloomNutrients"] = 2, ["CannabisMod.RootingGel"] = 1,
        ["CannabisMod.CloningDomeTray"] = 1, ["CannabisMod.CuringJar"] = 1.5, ["CannabisMod.GrowersHandbook"] = 1.5, ["CannabisMod.LightTimer"] = 3,
    },
    MagazineRackMixed = { ["CannabisMod.GrowersHandbook"] = 1.5 },
    MagazineRackFancy = { ["CannabisMod.GrowersHandbook"] = 0.6 },
    TobaccoStoreAccessories = { ["CannabisMod.RollingPapers"] = 30 },
    StoreCounterTobacco = { ["CannabisMod.RollingPapers"] = 6 },
    TobaccoStorePipes = { ["CannabisMod.SmokingPipe"] = 4 },
    SmokingRoomPipes = { ["CannabisMod.SmokingPipe"] = 1 },
    BedroomDresser = { ["CannabisMod.CannabisSeed"] = 0.05, ["CannabisMod.RollingPapers"] = 0.3, ["CannabisMod.SmokingPipe"] = 0.1 },
}

local done = false

--- Insert every entry of the table into the game's lists, scaled by the LootRarity sandbox option; safe to call twice.
function Loot.apply()
    if done or not (ProceduralDistributions and ProceduralDistributions.list) then return end
    done = true
    local scale = Config.sandbox("LootRarity") or 1
    if scale <= 0 then return end
    for listName, entries in pairs(Loot.TABLE) do
        local list = ProceduralDistributions.list[listName]
        if list and list.items then
            for fullType, weight in pairs(entries) do
                table.insert(list.items, fullType)
                table.insert(list.items, weight * scale)
            end
        end
    end
end

Events.OnPreDistributionMerge.Add(Loot.apply)
