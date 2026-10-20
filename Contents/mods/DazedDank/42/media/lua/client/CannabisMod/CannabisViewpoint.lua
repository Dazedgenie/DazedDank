-- Dazed Dank's 3D models for Project Viewpoint (first-person view). Two model packs ship with the mod (media/dazedviewpoint/):
-- the furniture, lamps and wall units, and the plants and pots. Nothing happens when Viewpoint is not installed.
-- Viewpoint may load after this file, so registering is retried on OnGameBoot and OnGameStart until it takes.

local PACKS = {
    "media/dazedviewpoint/dank/package.properties",
    "media/dazedviewpoint/dankplants/package.properties",
}
local done = {}

local function register()
    if not (Viewpoint and Viewpoint.ModelPacks and Viewpoint.ModelPacks.register) then return end
    for _, path in ipairs(PACKS) do
        if not done[path] then
            local ok, res = pcall(Viewpoint.ModelPacks.register, "DazedDank", path)
            if ok and res then
                done[path] = true
            elseif not ok then
                print("[DazedDank] Viewpoint pack " .. path .. ": " .. tostring(res))
            end
        end
    end
end

register()
Events.OnGameBoot.Add(register)
Events.OnGameStart.Add(register)
