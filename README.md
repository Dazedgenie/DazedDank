# Dazed Dank (Project Zomboid B42)

Realistic cannabis growing: strains and breeding, five growth stages, sexed seeds, cloning, grow lights and bags, three hydro systems, drying, trimming, curing and smoking. Cannabis is a
vanilla farm crop: plow a plot, sow a seed, water it, and harvest it when
ripe. Our server clock drives the 5 stages; vanilla handles watering,
pests and health. Each plant type has its own sprites.

## Install

This zip uses the Steam Workshop layout. Extract it into
`C:\Users\<you>\Zomboid\Workshop\` so you end up with:

    Zomboid\Workshop\DazedDank\Contents\mods\DazedDank\mod.info
    Zomboid\Workshop\DazedDank\Contents\mods\DazedDank\42\mod.info

Delete any older DazedDank folder first. Then enable "Dazed Dank" in the
Mods menu.

## In-game test (launch with -debug)

1. Right-click the ground: **[Debug] Give cannabis test seeds**. You get 6
   seeds: 3 female and 3 male, one of each type.
2. Right-click a seed in your inventory: **Inspect Seed**. Below
   Agriculture 3 it says "Unknown cannabis seed"; at 3+ it shows type and sex.
3. Plow a plot, then use the vanilla **Sow Seed** menu. Cannabis is listed there.
4. Right-click the plant: **Inspect Cannabis Plant** shows what your
   Agriculture level allows (floating text, and printed to console.txt).
5. Right-click the plant: **[Debug] Cannabis: next stage** to skip ahead.
   The sprite should change at each stage, and a vanilla Harvest option
   should appear at Ripe.
6. Harvest a female: you get a **Wet Whole Plant (Indica / Sativa / Hybrid)**,
   and the plant is removed from the map. Harvest a male: no
   buds, and a message says so.
7. Breeding: plant a male next to a female, skip both to Flowering, and
   wait 10 in-game minutes. Harvest the female for seeds.

### Strains

Every seed carries a strain: a name and four hidden traits (indica share,
potency, yield, flowering speed). Looted seeds are one of six starters, three
indica and three sativa. Cross two plants and the seeds are a new strain with
the parents' traits averaged (plus a little noise) and a generated name. The
same strain crossed with itself breeds true. Indica / Sativa / Hybrid is read
from the indica share (65%+, 35% or less, between), and sets the sprites and
which Wet Whole Plant item you get. Strains tint their plants a little
(sandbox: Strain Tint). All the numbers live in `CannabisStrains.lua`.

### Nutrients and grow lights

15. Right-click the ground: **[Debug] Give grow kit** (2 Veg, 2 Bloom, a
    Basic and a Pro grow light).
16. Right-click a plant in veg: **Feed Veg Nutrients** uses one bottle and
    gives a small care bonus. Feeding twice in one stage burns the plant.
    Bloom food in veg is the wrong food. Seedlings and ripe plants refuse.
17. Indoors, a plant with no light stops growing and loses care. Drop a grow
    light on the floor or a table within 2 tiles of it. It only works while
    the square has power (grid or generator). Inspect shows the light source
    at Agriculture 3. Light ceilings: sun 70, Basic 85, Pro 100. Quality
    follows a running average of the light the plant got, so days in the
    dark hurt but one bad night doesn't.
18. In Flowering, cutting the power after the plant had light costs care
    (a broken light cycle).

### Grow bags

19. The grow kit also gives 2 small and 2 large **Grow Bags**. Right-click
    a free square (indoors works): **Place Small Grow Bag** / **Place Large
    Grow Bag**. Then use the normal **Sow Seed** menu on it. Bags are
    optional: plowed ground still works.
20. Bags breathe, so overwatering costs less care (small 60%, large 50%).
    A large bag gives 25% more buds. Inspect shows "Planted in".
21. After harvest the bag stays, empty, ready to sow again. An empty bag
    has **Pick Up Grow Bag**. A dead plant has **Empty Grow Bag**.
22. Cannabis is flagged as a houseplant, so the vanilla "kill crops
    indoors" sandbox option no longer affects it.

### Cloning

8. Right-click the ground: **[Debug] Give cloning kit** (a Cloning Dome
   container, rooting gel, 3 fresh cuttings). Get scissors or a kitchen knife too.
9. With a plant in Vegetative or Pre-flower, right-click it: **Take Cutting**.
   The option is greyed out without a cutting tool.
10. Right-click a cutting in your inventory: **Inspect Cutting** (type at
    Agriculture 3, generation at 9) and **Dip in Rooting Gel**. A dipped
    cutting is renamed **Cannabis Cutting (Rooting Gel)**.
11. Drag cuttings into the dome like a bag (it refuses anything that isn't
    a cutting, and a 13th cutting). Drop the dome or place it on a table: it
    shows as a container in the loot window, and right-clicking it gives
    **Check Cuttings** / **Take Rooted Cuttings**. **[Debug] Finish rooting
    now** skips the wait.
12. Plant a rooted cutting with **Sow Seed**. It starts in Vegetative.
13. Or sow a fresh cutting straight into a plot. Inspect shows "Still
    rooting" until it roots or dies. **[Debug] Cannabis: finish rooting**
    on the plant settles it on the next 10-minute tick.
14. Leave a cutting in your inventory for a day or two: it goes stale and
    disappears from the Sow menu (fridges slow this down).

Rooting chance = 35% + 4% per Agriculture level, +15% gel, +15% dome,
-10% soil instead of a dome, -15% outside 18-28 C, -10% without light,
-20% if not kept moist (a dome always is), -2% per hour of wilting after
the first 6. Capped between 5% and 95%. Conditions are measured where you
stand when the cuttings go in.

## Save compatibility (read before changing items)

Never change the `ItemType` of an item that may already exist in a save
(for example `base:normal` to `base:food` or `base:drainable`). The game
saves each item in a format set by its type. Loading it with a different
type fails, and if the item is in a player's inventory **the whole
character fails to load** (they spawn stripped, and dressing then throws
errors in ISWearClothing). This happened in testing when Cannabis
Cutting became a food item and Rooting Gel became a drainable.

Items that were replaced this way and are kept only for old saves:
`CloningDome` (now `CloningDomeTray`, a container) and `WetCannabisPlant`
(now `WetIndicaPlant` / `WetSativaPlant` / `WetHybridPlant`).

If an item's type has to change: add a NEW item ID and keep the old item
exactly as it was. While the mod is unreleased, test each build with item
type changes on a fresh save.

## Files

| File | Runs on | What it does |
| --- | --- | --- |
| shared/CannabisMod/CannabisConfig.lua | both | Every tunable number |
| shared/CannabisMod/CannabisGenetics.lua | both | Sex, breeding, cloning, rooting, hermies, quality math |
| shared/CannabisMod/CannabisStrains.lua | both | Starter strains, trait blending, cross names, what each trait does |
| shared/CannabisMod/CannabisInfo.lua | both | What each Agriculture level can see |
| shared/CannabisMod/CannabisSeeds.lua | both | Hidden seed data (from item ID, or written by the server) |
| shared/CannabisMod/CannabisNet.lua | both | Server-to-player replies that work in SP and MP |
| server/CannabisMod/CannabisCrop.lua | both | Registers the vanilla crop (clients need it for the Sow menu) |
| server/CannabisMod/CannabisFarming.lua | server | Sowing, growth sync and harvest hooks |
| server/CannabisMod/CannabisLight.lua | server | Sun and grow-lamp light, stalling, light interruptions |
| server/CannabisMod/CannabisGrowBags.lua | server | Placing, picking up and emptying grow bags |
| server/CannabisMod/CannabisGrowing.lua | server | Feeding nutrients, debug grow kit |
| server/CannabisMod/CannabisRegistry.lua | server | Plant records, growth clock, water, feeding, pollination |
| server/CannabisMod/CannabisServerCommands.lua | server | Validates and answers client requests |
| client/CannabisMod/CannabisClient.lua | client | Right-click menus and the plant info window |
| client/CannabisMod/CannabisDomeContainer.lua | client | Cloning dome rules: cuttings only, max 12 |

## Art (placeholders)

Plant sprites and item icons are drawn by `tools/draw_placeholders.py`
(Pillow). There's one shared seedling, then Indica (squat, broad leaves,
fat buds, a little purple when ripe), Sativa (tall, thin leaflets, long
spear cola) and Hybrid (in between) for Veg, PreFlower, Flowering and Ripe.
The unhealthy, dying, dead and trampled versions are generated from those.
That's 65 ground sprites, plus the same set in a small and a large grow bag and 2 empty bags: 197 in all.

To redraw and repack after changing the script:

    python tools/draw_placeholders.py build/art
    # then, from a pz-sprite-forge checkout (github.com/Leeheejin/pz-sprite-forge):
    python -m pzforge.cli build <DazedDank>/build/art/cells --mod-id DazedDank \
        --prop CustomName=Cannabis --tiledef-id 7420 --no-style --out build/dist
    # copy build/dist/DazedDank/42/media/texturepacks/dazeddank_plants_01.pack
    #  and build/dist/DazedDank/42/media/dazeddank_plants_01.tiles into 42/media/

Keep `--no-style`: the packer's style pass is tuned for furniture and turns
foliage brown. The sprite numbering lives in `Config.spriteName`
(CannabisConfig.lua); change it together with `sprite_slot` in the script.

Tile id **7420** must not clash with another installed mod's `tiledef=` line.

## Offline tests

`tests/run_tests.lua` stubs the game API (shaped like the vanilla B42
farming files) and runs 191 checks. From the repo root:

    lua tests/run_tests.lua .
