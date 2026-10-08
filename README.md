# Dazed Dank (Project Zomboid B42)

Realistic cannabis growing: strains and breeding, five growth stages, sexed seeds, cloning, grow lights and bags, three hydro systems, grow rooms with climate control, drying, trimming, curing and smoking. Cannabis is a
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

1. Right-click the ground: **[Debug] Give cannabis test seeds**. You get 18
   seeds: 2 female and 1 male of each of the six starter strains.
2. Right-click a seed in your inventory: **Inspect Seed**. Below
   Agriculture 3 it says "Unknown cannabis seed"; at 3+ it shows type and sex.
3. Plow a plot, then use the vanilla **Sow Seed** menu. Cannabis is listed there.
4. Right-click the plant: **Inspect Cannabis Plant** shows what your
   Agriculture level allows in a status window: strain tag, a five-step growth track, a water bar with the healthy zone marked, Health, Stress, Genetics and quality meters, and coloured warning chips. The footer says what level unlocks more detail. The same info is printed to console.txt.
5. Right-click the plant: **[Debug] Cannabis: next stage** to skip ahead.
   The sprite should change at each stage, and a vanilla Harvest option
   should appear at Ripe.
6. Harvest a female: you get a **Wet Whole Plant (Indica / Sativa / Hybrid)**,
   and the plant is removed from the map. From pre-flower on, males look
   different: taller and sparser, hung with pollen sacs. Harvest a male: no
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

### Topping, cuttings and mother plants

Right-click a plant in veg: **Top Plant** (needs a cutting tool) gives +20%
buds, 10 stress and a 12-hour pause, once per plant. Every pot has a cutting
budget that refills over about 4 days (ground 3, small 2, large 4, DWC 4,
XL 8). Cutting past it sets the plant back to the start of veg. The **XL Grow
Bag** and **XL DWC Bucket** are mother pots: 8 cuttings, clone drift of 0-2
instead of 1-5, feeding every 96 hours in held veg, and cut stress that fades.
Numbers live in `Config.Topping`, `Config.Cuttings` and `Config.Mother`.

### Nutrients and grow lights

15. Right-click the ground: **[Debug] Give grow kit** (2 Veg, 2 Bloom, a
    six grow lamps, 2 light timers, bags).
16. Right-click a plant in veg: **Feed Veg Nutrients** uses one bottle and
    gives a small care bonus. Feeding twice in one stage burns the plant.
    Bloom food in veg is the wrong food. Seedlings and ripe plants refuse.
17. Indoors, a plant with no light stops growing and loses care. Grow
    **lamps hang from the ceiling**: right-click one in your inventory and place it on a free indoor floor square (not outside, not on tables); pick it up again with the move-furniture tool.
    The two **flood lights** stand on the ground on a tripod instead, so they place indoors or out (outdoors they need a generator).
    Each lamp lights a round zone: Basic reaches 2 tiles, Pro 2.5, Large Basic 3, Large Pro 4, Flood 3.5, Pro Flood 4.5 (the two Large bars light a capsule-shaped zone
    around all their tiles). It only works while its
    square has power (grid or generator). Inspect shows the light source at
    Agriculture 3. Light ceilings: sun 70, Basic 85, Pro 100 (the Large
    lamps share the Basic and Pro ceilings but cover far more space).
    Quality follows a running average of the light the plant got, so days
    in the dark hurt but one bad night doesn't.
17b. **Light timers.** A lamp without a timer runs 24/0, and plants under it stay in veg. Right-click a placed lamp with a
    light timer to install it (it starts on 18/6), then use the lamp's **Light Timer** menu to switch between 18/6 (veg)
    and 12/12 (flower). Once a plant finishes its normal veg stage it only moves on to pre-flower under 12/12; every
    extra veg day after that adds yield, each day a little less, up to +50% after about a week. Held-veg plants drink
    more and want feeding every 2 days (a "Hungry" warning otherwise). Light from a veg lamp reaching a 12/12 plant
    during its dark hours (6 pm to 6 am) is a **light leak**: it stops the flip and adds stress, which can make
    flowering plants turn hermie. Sun-grown plants (no lamp) still flip on their own. Picking up a lamp drops its
    timer on the floor. Lights switch on at 6:00 on both schedules.
18. In Flowering, cutting the power after the plant had light costs care
    (a broken light cycle).

### Grow bags

19. The grow kit also gives 2 small and 2 large **Grow Bags**, which are
    placed like furniture: open the move-furniture tool (right-click the
    ground, **Place Item**), pick the bag and set it on a free square
    (indoors works). It turns into a farming plot as soon as it lands; then
    use the normal **Sow Seed** menu on it. **Bags have collision**: you
    can't walk through one. If a bag stays as plain furniture instead of becoming
    a plot, tell me: that is the thing to check.
20. Bags breathe, so overwatering costs less care (small 60%, large 50%).
    A large bag gives 25% more buds. Inspect shows "Planted in".
21. A new bag is **empty of soil** and sowing is refused ("Fill the grow
    bag with soil first"). Right-click it: **Fill ... with Soil** uses
    sacks of soil (small bag 1, large bag 2; the debug kit gives 6, and
    vanilla's dirt bag counts too). It only has to be done once: the bag
    keeps its soil through every harvest. Picking the bag up loses it.
22. After harvest the bag stays, empty, ready to sow again. An empty bag
    has **Pick Up Grow Bag**. A dead plant has **Empty Grow Bag**, and the shovel's **Remove** also just empties the bag.
23. Cannabis is flagged as a houseplant, so the vanilla "kill crops
    indoors" sandbox option no longer affects it.

### Smoking, effects, tolerance and dependency (first iteration)

29. Right-click the ground: **[Debug] Give smoking kit** (papers, pipe,
    lighter, 3 buds each of Indica, Sativa and Hybrid, quality 80).
30. Right-click a bud: **Roll Joint** (needs rolling papers) or **Smoke in
    Pipe** (needs the pipe and a lighter or open flame). Right-click a
    joint: **Smoke Joint**. A joint is gentler; a pipe hit is about 30%
    stronger and builds tolerance faster. Quality, strain and mold carry
    from the bud to the joint (it's named, e.g. "Good Indica Joint").
31. The high lasts about 2.5 game hours at full strength and eases in and
    out. Indica: relaxes (stress, unhappiness down), tires, hungry, thirsty.
    Sativa: lifts boredom and unhappiness, a little wakeful; a very strong
    hit can make you anxious. Hybrid sits between. Moldy smoke only hurts.
32. **Tolerance**: every dose makes the next one weaker (up to 65% weaker);
    it fades over a couple of weeks off. **Dependency** builds with regular
    use. After about a day without it, a dependent player gets **withdrawal**
    (stress, unhappiness, boredom up, appetite down) until they smoke again;
    it fades after days of staying clean. "You're craving a smoke" shows
    when it starts.
33. Debug options: **Dependent: tolerance 60, dependency 80, 48h clean**
    (you should get withdrawal) and **Reset tolerance and dependency**.
    If a stat doesn't move, tell me which: effects use game stat names I
    couldn't check offline and skip any that don't exist.


**High Tracker:** right-click anywhere and pick **High Tracker** for a live readout of the current high or withdrawal, tolerance, dependency and the stat changes per hour.

### Placement range preview

While placing a grow lamp or the drying fan, the floor squares it affects
are tinted (orange for lamps, blue for the fan; a bar lamp shows the range of every tile). I couldn't test this
offline: if nothing is tinted, tell me.

### Drying, trimming and curing

24. Right-click the ground: **[Debug] Give drying kit** (rack, jar, fan,
    scissors, 2 wet plants). The **Drying Rack** (two tiles, rotates with R; each tile holds 8 plants) and the **Large lamps** (Large Basic 1x2, Large Pro 1x3)
    and **Drying Fan** are furniture: place them with the move-furniture
    tool on free floor. The jar is set down in the world. They're found
    automatically when you are within 8 tiles.
25. Drag wet plants into the rack (it refuses anything else, max 8). Plants
    dry in 48 hours at a normal pace: warmth speeds it up, a powered
    **Drying Fan** within 3 tiles speeds it a little and cuts mold risk.
    Once a plant has fully dried (48 hours at a normal pace) it turns into a **Dried Whole Plant** in the rack, which can still be trimmed; leaving it there too long over-dries it. **[Debug] Racks and jars: +24 hours** skips time. **Check Drying Rack**
    reports each plant's progress.
26. Mold chance is highest while a plant is wet, and rises outdoors, in rain
    and in warm air (the Mold Chance sandbox option scales it). Direct sun
    outdoors bleaches buds. Drying far past 5 days over-dries them. A moldy
    plant makes moldy buds worth 20%.
27. Right-click a wet plant: **Trim Plant** (needs scissors or a sharp
    knife). You get one **Cannabis Bud** per bud, named by quality (Premium,
    Good, Average, Poor, or Moldy). Rushed drying lowers it. **Inspect Bud**
    gives details by Agriculture level.
28. Put buds in the **Curing Jar** (max 30, buds only). Curing for 6 days
    gives up to +10% quality. **Burp Jar** about every day and a half: an unburped
    jar risks mold that spreads to every bud, and buds trimmed under 80% dry
    ("moist") raise the risk. **Check Curing Jar** shows progress. The jar
    and the cloning dome can be set down with the game's **Place Item**.
28b. For bigger harvests, the **Curing Barrel** is floor furniture (place it
    like the rack) holding up to 300 buds. It cures exactly like a jar:
    right-click it for **Check Curing Barrel** and **Burp Barrel**.

### Loot and recipes

Seeds turn up in garden stores, farm crates and drug shacks (rarely in bedroom dressers). Rolling papers and pipes are found in tobacco shops, smoking rooms and drug shacks. Grow gear (bags, soil, nutrients, rooting gel, lamps, fans, cloning domes, curing jars) spawns in garden and hardware stores and drug labs, and the large lamps are rare. The **Loot Rarity** sandbox option scales all of it (0 turns mod loot off).

Everything is also craftable. Each recipe needs its skill level and must be learned by reading the **Grower's Handbook** magazine, which spawns in garden stores, gas station and other magazine racks, drug shacks and drug labs. Turn off the **Recipes Need Magazine** sandbox option and every character knows the recipes from the start:

| Item | Skill | Main ingredients |
|------|-------|------------------|
| Small grow bag | Farming 1 | 3 ripped sheets, thread, needle |
| Large grow bag | Farming 2 | 6 ripped sheets, thread, needle |
| Sack of potting soil (x2) | Farming 2 | dirt bag, compost bag |
| Drying rack | Carpentry 2 | 4 planks, 8 nails, 2 rope, hammer, saw |
| Drying fan | Electrical 2 | 2 electronics scrap, wire, aluminum scrap, screwdriver |
| Basic / Pro grow lamp | Electrical 2 / 4 | light bulbs, wire, scrap |
| Large Basic / Large Pro lamp | Electrical 3 / 5 | 2-3 bulbs, wire, scrap, plank, nails |
| Light timer | Electrical 2 | kitchen timer, wire, electronics scrap |
| Flood / Pro Flood grow light | Electrical 3 / 5 | 2-4 bulbs, wire, scrap metal, sheet metal, screws |
| Curing jar | none | empty jar and lid |
| Curing barrel | Carpentry 3 | 6 planks, 10 nails, 2 scrap metal |
| DWC bucket | Electrical 2 | empty bucket, rubber hose, 2 electronics scrap, wire |
| Clay pebbles | none | 3 clay, then fired in a kiln |
| RDWC site bucket | Farming 3 | empty bucket, 2 rubber hoses, knife |
| RDWC control bucket | Electrical 4 | 2 empty buckets, 2 rubber hoses, 4 electronics scrap, 2 wire |
| Flood table | Carpentry 3 | 3 planks, 8 nails, sheet metal, rubber hose, hammer, saw |
| Flood reservoir | Electrical 4 | 2 empty buckets, 2 rubber hoses, 3 electronics scrap, 2 wire |
| Flood timer | Electrical 3 | timer, wire, electronics scrap |
| Rolling papers | none | vanilla rolling papers (repack) |

### Sandbox options

All under the **Dazed Dank** page of the sandbox settings:

| Option | Default | Effect |
|--------|---------|--------|
| Growth Speed | 1.0 | how fast plants grow |
| Harvest Quantity | 1.0 | buds and seeds per harvest |
| Male Seed Chance | 10% | share of seeds that are male |
| Drying Time | 48 h | game hours on the rack to dry fully |
| Curing Time | 6 days | days in a jar for the full bonus |
| Mold Chance | 1.0 | mold risk while drying and curing (0 = off) |
| Grow Lamp Range | 1.0 | how far lamps reach |
| Lamps Need Power | on | placed lamps only work with power |
| High Effect Strength | 1.0 | mood and need changes from highs and withdrawal |
| Tolerance Build Rate | 1.0 | how fast tolerance builds (0 = none) |
| Dependency | on | dependency and withdrawal |
| Dependency Build Rate | 1.0 | how fast dependency builds |
| Loot Rarity | 1.0 | world loot frequency (0 = none) |
| Recipes Need Magazine | on | crafting recipes must be learned from the Grower's Handbook and Hydroponics Monthly (off = known from the start) |
| Root Rot Risk | 1.0 | how fast root rot builds and spreads in hydro (0 = off) |
| Reservoir Use Rate | 1.0 | how fast hydro reservoirs drain, use nutrients and go stale |
| Hydro Quality Bonus | 0.15 | how far above 100 RDWC quality can reach |
| Pumps Need Power | on | hydro pumps only run with power |
| Grower Occupations and Traits | on | the three occupations and four traits below (off = hidden at character creation and no effect) |

### Occupations and traits

| Occupation | Points | What it brings |
|------------|--------|----------------|
| Cultivation Tech | -4 | Agriculture +2, Electrical +1, Maintenance +1. Knows every Grower's Handbook and Hydroponics Monthly recipe. Reads plants as if Agriculture were 2 higher (not genetics). Cuttings root 10% more often. |
| Budtender | +2 | Agriculture +1, Short Blade +1. Knows rolling papers, curing jar and barrel. Inspect Bud shows everything. Buds they jar or burp cure up to +15%. |
| Botanist / Breeder | -4 | Agriculture +2, Foraging +1. Reads strain traits and hermie lines on any seed, cutting, plant or bud. One extra seed per pollination harvested; crosses vary less (±5) and big jumps in potency, yield and flower time go their way 3 times in 4. |

| Trait | Points | Effect |
|-------|--------|--------|
| Green Thumb | 4 | Agriculture +1. Cannabis they plant takes 15% less from care mistakes; cuttings root 5% more often. Excludes Gardener. |
| Trim Hand | 2 | Trims twice as fast. Won't trim a plant still too wet to cure safely; **Trim Plant Anyway** does it. |
| Chronic | -3 | Starts with dependency 45 and tolerance 30. Excludes Smoker and Lightweight. |
| Lightweight | -2 | Highs are 50% stronger and last longer; tolerance builds 50% faster. Excludes Chronic. |

### Hydroponics: DWC (deep water culture)

29. A **DWC Bucket** is placed like furniture, **indoors only**, and turns into a hydro plot. Before planting, give its
    net pot a medium: **Add Rockwool Cube** (spent each harvest; best for seeds) or **Fill With Clay Pebbles**
    (reusable; a quarter of seeds sown straight into pebbles slip down and fail, clones are fine).
30. The plant drinks from the bucket's **15 L reservoir**, not the plot. Use the plot's **Reservoir** menu:
    **Top Up Reservoir** pours water from bottles, pots or buckets you carry; **Change Reservoir** drains it and
    refills it fresh (and clears the nutrients). In flower a DWC plant drinks about a bucket a day.
31. **Feed Veg/Bloom Nutrients** on a hydro plant mixes the bottle into the reservoir. A dose runs down over about
    three days; below 20% the plant goes hungry. Dosing a reservoir that's still above 60% burns the plant.
32. **Root rot.** The air pump needs power (sandbox **Pumps Need Power**). With no power, a reservoir older than
    7 days (stale), or tainted water, root rot starts, and once started it keeps spreading. Early rot ("Browning"
    roots) is cured by **Change Reservoir** and then **Treat Roots With Bleach** within 6 hours (0.1 L of bleach).
    Past early it can't be saved: the plant loses care and slows, and at 100 it dies.
33. DWC is more forgiving (care penalties x0.75) and yields x1.3 (a small bag is x1, a large bag x1.25).
    **Check Reservoir** and the status window show litres, nutrient strength, age and root health.
34. Clay pebbles: **Roll Clay Pebbles** from 3 clay, then fire them in a vanilla small or large kiln with a fire
    starter and a log or charcoal, like bricks. Rockwool cubes are loot only. **Hydroponics Monthly** teaches
    the DWC bucket, clay pebble, RDWC and Ebb and Flow recipes.

### Hydroponics: RDWC (recirculating DWC)

35. An **RDWC Control Bucket** (plain furniture, indoors) holds the pumps and the shared reservoir. **RDWC Site
    Buckets** placed within 3 tiles on the same floor connect to it automatically, up to 6 per control. A site with no
    control in range shows "Not connected" and gets no water.
36. The reservoir holds 40 L plus 20 L per connected site. Use the **Reservoir** menu on the control bucket or on any
    site: topping up, changing, dosing nutrients and bleach all act on the whole system. The pumps need power at the
    control bucket. Root rot lives in the shared water, so it reaches every site at once.
37. RDWC is the most forgiving system (care penalties x0.6), yields x1.4, and lifts the quality ceiling to **115**
    (sandbox **Hydro Quality Bonus**). Buds above 100 are named **Top Shelf**, hit harder and last longer, and cure up
    to 115 (ordinary buds still stop at 100). Sites need a rockwool cube or clay pebbles like DWC buckets.

### Hydroponics: Ebb and Flow (flood tables)

38. A **Flood Table** is a 1x2 bench placed like the drying rack, **indoors only**; each of its two tiles is a plant site.
    Tables that touch (not diagonally) form a row. A **Flood Reservoir** (60 L) standing beside any table of a row
    feeds up to **12 sites**, nearest first, across every row touching it. Picking up either half takes the whole table.
39. Sites take **rockwool cubes only**. **Flood Tables** (on the reservoir or any table) runs the flood pump: every fed
    site stays wet for about **12 hours**, then the rockwool dries and the plants go thirsty. The pump needs power and
    at least 0.5 L of water per site.
40. A **Flood Timer** (installs on the reservoir) floods automatically a few times a day while there is power and
    water, so the rockwool never dries. After a power cut the tables dry out within 12 hours.
41. Roots air out between floods, so Ebb and Flow needs no air pump and root rot builds at a quarter of the rate.
    Care penalties x0.85, yield x1.2, quality up to 100. **Hydroponics Monthly** teaches the table, reservoir and timer.

### Hydroponics: away from the grow and plumbing

42. While a grow is out of loaded range its hydro side pauses: reservoirs don't drain, go hungry or rot, and flood
    tables don't dry. It picks up again when you come back.
43. With **Dazed Utilities: Plumbing** installed, a DWC bucket, RDWC control bucket or flood reservoir can be piped
    to a water tank ("Reservoir Water Line"). **Change Reservoir** then dumps the old water and the line refills it.

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
    now** skips the wait. A cutting that is rooting in the dome doesn't go stale;
    one that won't root still wilts on the normal timer.
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

The pre-release leftovers (the old cloning dome, generic wet plant, loose
grow lights and loose grow bags) were removed before release; any copies in
a test save simply disappear on load.

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
| server/CannabisMod/CannabisSmoking.lua | server | Joints, pipe doses, tolerance and dependency records |
| shared/CannabisMod/CannabisUse.lua | shared | The rules for potency, effects, tolerance and withdrawal |
| server/CannabisMod/CannabisDrying.lua | server | Drying racks, trimming into buds, curing jars, mold |
| server/CannabisMod/CannabisLight.lua | server | Sun and grow-lamp light, stalling, light interruptions |
| server/CannabisMod/CannabisGrowBags.lua | server | Placing (furniture or menu), picking up and emptying grow bags |
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
That's 65 ground sprites, plus the same set in a small and a large grow bag, empty and unfilled bags, 4 lamps, 2 furniture bags, the fan, the 8 rack tiles, the bar lamps, the 2 flood lights, the curing barrel, and 135 male plant sprites (pre-flower to ripe, for each type, condition and container): 372 in all.

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

## Art pipeline

Plants, furniture and item icons are rendered in Blender by `tools/blender/render_plants.py`, `render_furniture.py` and `render_icons.py`. The renders in `tools/blender/{plants,furniture,icons}` feed `tools/draw_placeholders.py`, which falls back to its procedural drawings for any missing render.
