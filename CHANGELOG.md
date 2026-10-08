# Dazed Dank patch notes

## dd54 (Climate and UI redesign, in testing)
- Added: **choose which seed to sow.** In Sow Seed, the cannabis row opens a list of the seeds you carry, grouped by what you can read of them ("Knox Kush (Indica), Female : 2"). Below Agriculture 3 they all show as one "Unknown cannabis seed" group. After the first plot, clicking more plots keeps sowing from the group you picked.
- Changed: the debug **Give drying kit** option gives 3 wet plants, each a random starter strain and named for it, instead of 2 plain Indica plants.
- Changed: **old blackout curtains are cleared out.** Any still hanging are taken down as their squares load, their light-blocking records are dropped at game start, and curtains in your inventory and bags are removed when you load in (a message says how many). The Hang Blackout Curtain option is gone; hang a vanilla sheet instead.
- Changed: the debug **Give cannabis test seeds** option gives 2 female and 1 male seed of each of the six starter strains (18 seeds) instead of one of each type.
- Changed: harvested whole plants carry their strain name, wet and dried: "Wet Knox Kush (Indica)", "Dried Purple Riverside Haze (Sativa)". Plants already harvested pick the name up the first time they hang on a rack. Buds and joints were already named by strain; a bud only says "Hybrid Bud" when its plant had no strain (from before strains existed, or debug kits).
- Added: **High Tracker** (right-click anywhere). A small window showing whether you're high, in withdrawal or sober: the strain smoked, coming up / peak / coming down, strength now and at peak, time left, tolerance, dependency, whether the hit has turned anxious, and each stat change per hour with your current value.
- Changed: the grow panel's **Refresh** button shows what happened: "..." while it asks, "Updated" when the room comes back, and "No reply" if the server never answers. A panel the server has no record of, or one in someone else's safehouse, now says so instead of doing nothing.
- Fixed: the occupation and trait descriptions logged formatting errors. A bare "%" reads as a format code in the game's translations, so they say "percent" now.
- Added: **grower occupations and traits.** Three occupations: **Cultivation Tech** (-4: knows every Dank recipe, reads plants 2 Agriculture levels higher short of genetics, cuttings root 10% more often), **Budtender** (+2: knows papers, jar and barrel, reads every bud, cures up to +15%) and **Botanist / Breeder** (-4: reads genetics and hermie lines on everything, one extra seed per pollination, truer and luckier crosses). Four traits: **Green Thumb** (4: 15% less from care mistakes, +5% rooting), **Trim Hand** (2: trims twice as fast and asks before trimming a wet plant, see **Trim Plant Anyway**), **Chronic** (-3: starts dependent with some tolerance) and **Lightweight** (-2: highs 50% stronger, tolerance builds 50% faster). Sandbox: **Grower Occupations and Traits** (on); off hides them all and switches their effects off.
- Art: placeholder icons for the occupations and traits.
- Added: works with **DazedCore 1.3.0** and **Dazed Climate**. Outdoor plants, rooting cuttings, drying racks and grow room outdoor air now read temperatures from DazedCore when it's loaded (real room temperatures with Dazed Climate). Without them, the game's own temperatures are used as before.
- Added: lit grow lamps warm the room they hang in under Dazed Climate (about 3 C·squares per hour per tile of reach, so a large pro lamp is about 12). Sandbox: **Lamp Heat**.
- Added: plants outside a grow room feel the weather. Below 15 C or above 32 C they take the same stress as in a bad grow room (warning: "Outdoor temperature"). Cold slows growth: half speed at 10 C, stopped at 5 C. A Dazed Climate frost cover keeps the plant 4 C warmer. Plants nobody is near are left alone. With Dazed Climate's crop frost on, frost (0 C and below) is left to Dazed Climate, so it isn't counted twice. Sandbox: **Plant Temperature**.
- Added: **purple buds.** In the second half of flower and while ripe, nights (8 PM to 6 AM, or the lights-off hours in a grow room on a timer) at 5-15 C add up. After 12 cold night hours the plant gets one roll to turn purple: about 15% for a pure sativa up to 75% for a pure indica. Purple plants show purple, and their buds and joints are named "Purple ..." (unless the strain name already says Purple) and are worth 5% more quality. Clones and seeds don't inherit it. Sandbox: **Purple Buds**.
- Added: nights under 5 C in late flower cost 2% yield per hour, up to 25% (frost itself is Dazed Climate's job). Part of **Plant Temperature**.
- Added: curing temperature. Jars and barrels cure at full speed at 15-21 C, slower outside that, and at half speed below 10 C or above 25 C. Above 25 C a missed burp molds 1.5x as often. Jars in a grow room use the room's air. Sandbox: **Curing Temperature**.
- Changed: the **Grow Room Panel** is one dashboard instead of tabs: a 24-hour lights ring, temperature and humidity against their targets, room seal, a sideways-scrolling row of plant cards (each showing the plant in its pot), reservoir tanks, equipment tiles and the newest alert. Click the room name to rename it, the mode pill or lights card to change them, a plant to inspect it, a tank or equipment tile for its actions (right-click a plant for Show in room). The mouse wheel scrolls the plant row; **Log** opens the full log.
- Changed: the plant **Inspect** window is a light card in the same style: the plant drawn in its pot, vitals, care facts, genetics as bars at Agriculture 9, and warnings as chips. Info your level can't read yet is left out.
- Art: Blender renders for both windows: a grow-tent backdrop behind every plant photo, glass reservoir tanks with the water level showing through, and icons for each section (lights, temperature, humidity, room seal, plants, reservoirs, equipment, vitals, care and genetics).
- Changed: plants in the Inspect window are sized to fit their photo, so tall sativas no longer poke out of the top.
- Fixed: a blackout curtain could hide a player standing on its square in front of it, so it looked like you'd stepped in behind it. Build 42 treats a modded tile with no depth map as a solid block filling its square. The grow room tiles (curtains, panel, fans, wall and floor units) now ship one, so players show in front of what hangs on a wall and behind what stands in front of them.
- Fixed: ceiling grow lamps couldn't hang over some floor gear, like an RDWC reservoir on a Dazed Plumbing line: every Plumbing tile, pipes included, is flagged to block placement. Ceiling lamps now hang over Dazed Dank pots and hydro, Dazed Plumbing pipes and tanks, and farm plots. Floor flood lights still need a clear square.
- Fixed: the **Drip Irrigation Tank** couldn't go under a wall Humidifier, AC or other unit hung up high on the same square. It counts as low gear now, so it fits under them.
- Fixed: the **Wall Air Conditioner** couldn't hold a sealed lamp room. It only took a flat 6 C off, while lamp heat in a room with no fans climbed the full 30 C, so a room could sit at 53 C with the AC running. Each running AC now first carries out the heat of about two large pro lamps (the heat of any extra lamps still warms the room), then takes its 6 C off. A room with more lamps needs a second AC or exhaust fans. Under Dazed Climate an AC pulls 24 instead of 18, to match.
- Fixed: a bar lamp (large basic or large pro) heated a grow room once per tile, so a 3-tile lamp gave three times its heat. It now counts once, shared across its tiles.
- Fixed: the close button (X) on the Grow Room Panel and the plant Inspect window was hidden under the title bar. Both windows now draw their layout first and the buttons on top.
- Added: a **Refresh** button on the Grow Room Panel title bar that asks for the room again.
- Changed: the debug **Fill reservoirs** option now fills drip tanks too.
- Changed: **blackout curtains are retired**: use vanilla sheets. A sheet or curtain hung and drawn shut seals a window or door. A closed door with no sheet lets a little light seep round its edges, a quarter of an open door's leak by default (new sandbox option **Closed Door Light Leak**, 0 to 100, 0 = closed doors seal). Open doors and doors to the outside now leak sunlight like windows. The panel shows each opening as covered, seeping or open. Curtains already hung or in your bags keep working, but the recipe is gone.
- Fixed: after a crash, grow bags, DWC and RDWC buckets, flood tables and grow room panels could stay on the map but stop working: missing from menus, the panel doing nothing. The map saves as you play, but their records only save on a full save. Now, when one loads without its record, it comes back: a pot that still carries its farming state is restored as it was, plant included; otherwise it is rebuilt empty (soil bags keep their soil, hydro buckets and tables ask for their medium again). A panel registers its room again.
- Fixed: the first version of that recovery deleted the very pots it rebuilt, because the game's plow takes an existing plot object as its own. It no longer deletes them, and any registered pot whose object went missing is drawn back.
- Fixed: the Grow Room Panel's buttons, Refresh included, did nothing once you were more than 3 tiles from the panel. They now work from anywhere in the room, and outside it they say why.
- Fixed: hovering the **Drip Irrigation Tank** filled the console with formatting errors. A bare "%" in its tooltip read as a format code; it now says "percent".
- Fixed: a plant card's warning badge covered its Health row. The badge (or a green "all good") now sits on the bottom of the plant photo.
- Fixed: "12 tiles ? 2 lamps" and "Sativa ? Haze" showed a question mark: the game font has no middle dot. Those spots use a bar now.
- Fixed: you could still step into the gap between a blackout curtain and its door and vanish behind the curtain. Curtains now sit flush in the frame, so a player against the door always shows in front.
- Fixed: light timers. **18/6** stayed lit all night and **12/12** ran like 18/6 (lit until midnight), on the grow room panel's ring and the lamps' glow. The game's Lua works out a negative remainder differently from standard Lua, so the hours before 6:00 counted as lit. 18/6 is now dark midnight to 6:00 and 12/12 dark 18:00 to 6:00, for the lamps, the ring and the plants.
- Fixed: the **drying rack** takes only whole plants (wet or dried), and **curing jars and barrels** take only buds, however the item is moved (drag and drop, Transfer All, or another mod's inventory tools). The game's own container check now enforces it, so other items can't be dropped in at all.
- Added: **Drip Irrigation Tank.** Waters soil pots for you with a slow drip, holding each one at about 70% water (under the overwatering line) and using water only as the plants drink.
  - In a grow room it waters every soil pot and grow bag in the room; outside one, every pot within 5 tiles (sandbox **Drip Irrigation Radius**, 1-15). Cannabis planted in the ground counts too; hydro is left alone.
  - Its 50 L tank fills by hand (right-click > Drip Tank > Top Up) or from a Dazed Plumbing water line, which tops it up on its own whenever it drops under half.
  - Mix Veg or Bloom nutrients into the tank and the drip feeds each pot once per stage as it waters it, like a hand feeding (the wrong food for the stage still costs care). Topping up with plain water thins the food.
  - The pump needs power (Pumps Need Power). In a grow room it shows on the panel: the tank with the reservoirs (Top up all and Dose all work on it) and a Drip tile with Auto/On/Off under Equipment.
  - Made with Electrical 3 (2 buckets, 4 rubber hoses, a timer, wire, electronics scrap) from the Controlled Environment magazine, or found in garden stores, farm crates and drug labs. Placeholder art until its Blender render is done.
- Added: right-clicking a **flood table** or **flood reservoir** shows how wet the rockwool is: "Rockwool: 75% wet, dry in 9 h", "flood timer keeps it wet", or "dry, flood the tables". 100% is a fresh flood; it runs down over the 12 hours the rockwool stays wet.
- Added: **Wall Air Conditioner.** Real cooling for a grow room whatever the weather, so an inside room or a heat wave no longer cooks the plants: each running unit takes about 6 C off the room (never below 12 C) and dries the air a little. Hangs on any wall, up high, in four facings. The panel runs it when the room passes its top temperature and rests it 2 C under; Auto, On and Off work like the other gear. Needs panel power. With Dazed Climate it cools that room's temperature too. Made with Electrical 5 (blower fan, 2 rubber hoses, sheet metal, aluminum, wire, electronics scrap, screws), or found in electronics stores and crates.
- Added: **Circulation Fan.** A cheap wall fan that keeps the air moving so lamp hot spots don't build up: about 1.5 C cooler each, 3 C at most. Starts 1 C under the room's top temperature. Made with Electrical 2 (blower fan, wire, scrap metal, electronics scrap), or found in electronics and tool stores.
- Both are in the Controlled Environment magazine, and the panel's Equipment card now fits all seven kinds of unit.
- Art: the AC and circulation fan use placeholder art until their Blender renders are done.
- Added: debug option **[Debug] Cut grow room power** on the Grow Room Panel's right-click menu (it turns into **Restore grow room power** while cut). It works like a real outage with the grid still on: lamps, fans and climate gear stop at once, the panel shows no power, the log says "Power cut (debug)", and restoring it counts lit hours lost like a real outage would.
- Added: debug option **[Debug] Fill reservoirs and water pots nearby** (right-click the ground in debug mode). Within 20 tiles on any floor it fills every DWC, XL DWC, RDWC control and flood reservoir to the brim (clean water if it was empty, nutrients kept), and waters every soil pot, grow bag and in-ground cannabis plot to 80, under the overwatering line.
- Changed: **exhaust and intake fans** hang up high, level with the wall heater, dehumidifier and humidifier. Fans already placed move up too.
- Fixed: the climate features (purple buds, outdoor plant temperature, lamp heat, curing temperature) lost their settings when the UI update was installed over them, which would have thrown an error at harvest. Both are now in one build.

## dd53.2
- Changed: the **Heater**, **Dehumidifier** and **Humidifier** now hang on a wall up high, like an overhead cupboard or a poster, in all four facings. The art is a placeholder until the Blender pass. Units already standing on the floor keep working.
- Added: an **Equipment** tab on the Grow Room Panel listing every fan, heater, dehumidifier and humidifier in the room, with where it is, which wall it hangs on, whether it's running, and a Show button.
- The panel also refreshes when equipment is placed or picked up near it.
- Changed: basic (purple) grow lamps glow twice as strongly.
- Added: more strain name variety. New crosses can be named after about 80 more Kentucky towns (Bardstown to Monkeys Eyebrow, Rabbit Hash and Possum Trot), and about 4 in 10 get a zombie-style name, like "Shambler Rush", "Patient Zero Kush" or "Frankfort Fever".
- Added: real strain names as strain words: 14 each for indica (Northern Lights, Bubba Kush, Granddaddy Purple...), sativa (Sour Diesel, Durban Poison, Jack Herer...) and hybrid (Blue Dream, Gelato, Wedding Cake...), giving names like "Ekron Sour Diesel" or "Shambler Bubba Kush". New sandbox option **Strain Name Words**: original and real strains (default), original words only, or real strains only.
- Art: the wall-mounted Heater, Dehumidifier and Humidifier are now Blender renders in the same style as the panel and fans, with new inventory icons.
- Changed: grow bags, DWC and RDWC buckets and flood tables only take cannabis. The **Sow** menu there lists only the cannabis seeds you're carrying.
- Changed: every cannabis plant, in the ground or in a container, is now drawn as its own layer over its plot (a furrow, bag, bucket or flood table), so one set of plant art serves them all (a bigger set for the XL mother pots). Plants already growing in an old save may show the wrong art; replant them.
- Added: **plant shapes and colours.** Every strain now carries two looks genes, passed down whole from one parent when you breed: a body shape (Landrace Sativa, Haze, Hybrid, Kush, Afghan, Autoflower or Christmas Tree) and a bud colour that shows in flower (Green, Purple, Frosty White, Lime Gold or Dark). About 3 in 100 crossed seeds show a shape or colour neither parent had, so there are phenos to hunt. A strain bred with itself keeps its looks. Looks only; traits still do the work. The starters: Knox Kush (Kush), Muldraugh Purple (Afghan, Purple), Rosewood Stone (Christmas Tree, Dark), Riverside Haze (Haze), West Point Lightning (Landrace, Frosty), March Ridge Gold (Hybrid, Lime Gold). Older strains get looks from their indica share and name.
- Added: Inspect and the Plants tab show a plant's shape and colour from Agriculture 3.
- Fixed: the strain's traits line at Agriculture 9 ran off the edge of the Inspect window; it now wraps.
- Art: all 7 shapes (4 stages each, plus males) and the 4 bud colours are new Blender renders in the mod's style.
- Changed: strain colours (the Strain Tint option) now colour only the plant, not the pot.
- Added: the Grow Room Panel's **Plants** tab shows each plant's strain and sex under its row once your Agriculture level can read them (level 3). Males and hermaphrodites are shown in orange.
- Fixed: a blackout curtain drew over pipes on the same wall, and over people standing in front of it. It now draws with its wall, behind both.
- Changed: hanging a blackout curtain takes down any vanilla sheet or curtain on that window or door and gives it back.

## dd53.1
- Fixed: the Exhaust Fan, Intake Fan, Dehumidifier and Humidifier recipes used items that don't exist in 42.21 (Motor, Empty Water Bottle), so the game threw those recipes out. They now take a Blower Fan and a Water Bottle.
- Fixed: the Grow Room Panel updates by itself when a lamp is hung or taken down while the window is open.
- Fixed: a bar lamp (large basic or large pro) shows as one lamp in the panel, not one row per tile.
- Fixed: a reservoir on a Dazed Plumbing water line takes its first fill from the line, and **Top Up** on a piped reservoir now fills it from the line instead of asking for carried water.
- Fixed: **Hang Blackout Curtain** shows up when you right-click near a door or window, the way vanilla sheets do, and works on player-built windows and doors too.

## dd53 (Grow Rooms, in testing)
- Added: **Grow Rooms.** Seal a room with walls, doors and windows, place a **Grow Room Panel** on a wall, and right-click it to open the room window (Lights, Hydro, Plants, Climate, Log tabs).
- Added: one shared lamp schedule per room, bulk hydro actions (Top Up, Change, Dose, Bleach) and a plant overview from the panel.
- Added: power loss. If the panel loses power, lamps and climate equipment stop. Plants take a forgiving penalty (sandbox: RoomPowerPenalty).
- Added: light leaks. Doors and windows with no curtain let light in during the dark period. **Blackout Curtains** go on a door or window frame via right-click (sandbox: LightLeaks).
- Added: room climate for temperature and humidity, with Veg, Flower and Drying targets. Sealed rooms run warmer, lamps add heat, and a room with no fans runs hotter still. Plants outside their range are stressed, and flowering plants in humid air risk mold (sandbox: RoomClimate).
- Added: **Exhaust Fan, Intake Fan, Heater, Dehumidifier, Humidifier**, each with a recipe in the magazine, loot spawns and art. Fans on an outside wall work fully; on an inside wall they work at 25%. Equipment runs automatically, or set Auto, On or Off per kind in the Climate tab.
- Added: the room's Log tab records light schedule and mode changes, renames, floods by hand, root rot setting in, harvests, and mold on racks and in jars.
- Added: one water line for the room. If any reservoir in a grow room has a Dazed Plumbing line, a Change on any other reservoir in that room is refilled from it too.
- Changed: Drying racks in a room use the room's temperature and humidity.
- Fixed: the "require Farming/farming_vegetableconf failed" warning in console.txt at startup. The guard that keeps a soil-only grow bag's hover name from erroring now switches on at game start, where before it never switched on.
- Changed: pro lamps glow a stronger HPS-style yellow-orange instead of pale yellow.
- Fixed: watering a tall plant (such as a rooted cutting, which starts at Vegetative) said "Furrow needs seeds" when the cursor was on its leaves. The watering cursor now finds the plant in front of the hovered furrow.
- Added: Inspect Bud shows the bud's moisture (about 75% wet, 12% properly dried, lower when over-dried) and its mold state and mold risk. Buds trimmed before this update show an estimate.
- Fixed: placing a flood table only made one of its two tiles a plant site, and picking it up then took two tiles but gave back one table. Both halves now become sites together.
- Fixed: ceiling grow lamps couldn't be hung over an RDWC control bucket or flood reservoir.
- Not included: a curtain on a door does not hide the room from zombies.

## dd52
- Added: Top Plant. In veg, snip the main tip (scissors or a sharp knife) for +20% buds at harvest. Costs 10 stress and pauses growth for 12 hours. Once per plant. The status window shows "Topped" to anyone.
- Added: cutting budget. Each pot holds a number of cuttings that regrows (full again after about 4 days): ground 3, small bag 2, large bag 4, DWC 4, RDWC 4, flood table 2, XL pots 8. Cutting past it costs 8 extra stress and sets her back: pre-flower drops to veg and the veg timer starts over. The status window shows "Cuttings ready: 3 of 8" from Agriculture 2, and a "Cut too hard" warning after an overcut.
- Added: XL Grow Bag (3 soil sacks) and XL DWC Bucket (30 L reservoir), made for mother plants. Both have the same yield as the large bag and the DWC. Mothers in them get an 8-cutting budget and lose only 0-2 genetics per clone generation (normal pots: 1-5). While held in veg they need feeding every 96 hours instead of 48, and the stress from cuttings fades at 1 per hour (other stress stays).
- Added: recipes Make XL Grow Bag (Farming 3, Grower's Handbook) and Make XL DWC Bucket (Electricity 3, Hydroponics Monthly). The debug grow and hydro kits include one of each.
- Art: the XL sprites are scaled from the large bag and DWC renders (hydro sheet tiles 235-460). After re-rendering those, `python tools/make_xl_sprites.py` rebuilds them. `tools/pzpack.py` and `tools/tdef.py` read and write the .pack and .tiles files.
- Changed: Plumbing and the reservoir menu treat the XL DWC as a DWC bucket.
- Fixed: two different crosses could get the same strain name. The server now keeps a list of every name it gives out, and a new strain that lands on a taken name is numbered ("Dixie Mist #2"). Starter names are reserved. All seeds from one pollination share one name, and breeding a strain with itself keeps its name.
- Changed: indica starters now flower faster than normal (Knox Kush 9%, Muldraugh Purple 12%, Rosewood Stone 6%) and sativas slower (Riverside Haze 10%, March Ridge Gold 4%, West Point Lightning 14%), so crossing and keeping the fastest seeds can breed a strain that flowers up to 20% faster. A flowering speed of 50 now means exactly normal time.
- Changed: strain traits read as exact numbers ("potency +8%, yield +17%, flowers 2% faster") instead of Low/Mid/High, so growers can tell which seed to keep.
- Kept: seeds and plants already in a save keep their old trait numbers; only new starter seeds use the new speeds. Names given out before this update aren't on the list, so one of them could match a new cross once.
- Tests: 33 new checks (203 total).

## dd51
- Added: strains. Every seed, cutting, plant, bud and joint now carries a named strain with four hidden traits: indica share, potency, yield and flowering speed. Looted seeds are one of six starters: Knox Kush, Muldraugh Purple and Rosewood Stone (indica), Riverside Haze, West Point Lightning and March Ridge Gold (sativa).
- Added: breeding makes new strains. A pollinated female's seeds average both parents' traits with a little noise (and a rare bigger throw), and the cross gets a generated name like "Riverside Mist". The same strain crossed with itself breeds true. Every seed from one pollination is the same strain.
- Added: traits matter. Fast strains finish pre-flower and flowering up to 20% sooner, slow ones take up to 25% longer. Yield runs from x0.75 to x1.25 buds, potency from x0.8 to x1.2 on the high. The high itself mixes the indica and sativa effects by the strain's indica share, so a 70/30 cross is mostly calm with a little lift. Only strains under 65% indica can get anxious on a strong hit.
- Added: Indica / Sativa / Hybrid is now read from the strain (65%+ indica, 35% or less, between). Sprites and the Wet / Dried Whole Plant items still follow that type.
- Added: strain names on items. Buds and joints read "Good Knox Kush Bud", "Premium Riverside Mist Joint". Seeds, cuttings and the status window show the strain at Agriculture 3, and its traits in words at 9 (buds at 6 on Inspect Bud).
- Added: plants take a light tint from their strain (indica leans violet, sativa gold). Sandbox option Strain Tint turns it off. An emptied bag loses the colour.
- Kept: old saves. A plant, seed or bud from before this update gets a starter strain of its own type the first time it is read, picked by its item ID or tile so it never changes. Nothing on an old item is rewritten in place.
- Tests: the offline suite is back in step with the mod (container dome, whole-plant harvest, sex readable at Agriculture 3) and gains 18 strain checks. Run with `texlua tests/run_tests.lua .` or any Lua 5.1+ (`lua tests/run_tests.lua .`).

## dd50
- Changed: buds and joints now carry their own type, quality and mold on the item. The save only keeps records for buds part-way through a cure and plants that have been on a rack, so it no longer grows with every bud you trim.
- Changed: when a bud finishes curing in a jar or barrel, it is swapped for a bud that carries its full cure, and its record is dropped. Its name updates to its cured quality (e.g. Good becomes Premium), or "Moldy" if the jar went bad. Mold in a neglected jar still spoils finished buds in it.
- Changed: once a game day, leftover records that hold nothing the item doesn't already have, untouched for 90 days, are dropped. Records with cure or drying progress are never dropped.
- Changed: a curing barrel's burp clock is cleared once the barrel is gone.
- Changed: "Inspect Bud" now works on buds in nearby containers, not only in your inventory.
- Fixed: buds or plants tucked inside a bag in a jar, barrel or rack no longer cure or dry. Swapping them could have duplicated them.
- Kept: buds and joints made before this update still use their old records. An old bud switches to the new storage when it finishes curing.

## dd49
- Changed (performance): the server's 10-minute plant tick reads each lamp square once per tick, not once per plant. Pollination lists the flowering females once per tick instead of once per male.
- Changed (performance): drying racks and barrels check fans and the room once each, and hydro lookups are cached for the tick.
- Changed (performance): the lamp glow now scans one row per tick instead of 3,700 squares in one frame every second. This removes a once-a-second hitch near big grows.
- Changed (performance): the lamp and fan range preview works out its tiles once per cursor square, not every frame. Right-click menus walk your inventory and the clicked square once.
- Changed (performance): sowing, item transfers and furniture placement no longer redo their checks every tick.
- Changed: the smoking, high and lamp-glow trace lines in console.txt only appear in debug mode.
- Changed: empty cloning domes no longer leave a record in the save.
- Fixed: plants out of loaded range could read as sunlit. They now keep their last light reading.
- Fixed: the fan's placement preview showed a circle scaled by the lamp range setting. It now shows the 7x7 square the fan actually dries.
- Fixed: the lamp placement preview ignored the LampRange sandbox setting.

## dd48
- Added: Ebb and Flow, the last hydro system.
  - **Flood Table:** a 1x2 bench placed like the drying rack. Each tile is a plant site, rockwool only.
  - **Flood Reservoir (60 L):** stands beside a row of touching tables and feeds the nearest 12 sites.
  - **Flood Tables** (manual) keeps every fed site wet for about 12 hours.
  - **Flood Timer:** installs on the reservoir and keeps the tables flooded while there's power and water. After a power cut they dry out within 12 hours.
  - Root rot builds at a quarter of the usual rate, and no air pump is needed. Yield x1.2, care penalties x0.85, quality up to 100.
  - New recipes in Hydroponics Monthly; Blender art for the table, reservoir and icons; table and reservoir are in the debug hydro kit.
- Fixed: hydro roots rotting, and flood tables drying out, while you were away from the grow. Hydro now pauses while out of loaded range, and a shared reservoir keeps running while any of its sites are loaded.
- Fixed: feeding an empty or unconnected hydro plant used up the nutrient bottle.
- Fixed: cuttings planted in hydro always rooted as if dry.
- Fixed: "Check Reservoir" could add root rot.
- Fixed: "Change Reservoir" greyed out on RDWC sites and flood tables whose reservoir is plumbed.
- Fixed: a bucket placed where another had been picked up could inherit its old medium or reservoir.
- Fixed: a reservoir left "refilling from the water line" forever after its line was removed.
- Fixed: a brand-new reservoir counted as old (stale) from the moment it was placed.
- Changed: site counting and table-network lookups are cached, so big grows cost less each tick.

## dd47
- Added (debug mode): "[Debug] Cannabis: quality +20" and "[Debug] Cannabis: max quality" on a plant. They raise genetics, light score and care and clear stress, and the message gives the quality it would harvest at.

## dd46
- Fixed: new plants in DWC and RDWC buckets getting root rot straight away and dying fast. A reservoir with nothing growing in it built up rot for the whole time it sat empty (up to a day), and the first plant took it all at once. Rot now only builds while roots are in the water.
- Changed: you can't sow into a hydro bucket until its reservoir has water, and an RDWC site has to be connected to a control bucket first.
- Added: "Pull Male Plant" once a male shows its sex, in the ground, grow bags or buckets. It asks for confirmation first.
- Changed: outdoors, a lit lamp or flood light adds to the sun instead of replacing it. The plant gets the stronger of the two plus 10, up to 100. The status window shows "Sun + <lamp>".

## dd45
- Added: Dazed Plumbing support (optional). DWC buckets and RDWC control buckets get a "Reservoir Water Line" menu to pipe them to a water tank.
- Changed: "Change Reservoir" on a plumbed reservoir dumps the old water and the line refills it, so there's no water to carry. The line doesn't top it up between changes.
- Tainted water from the tank taints the reservoir, the same as pouring it in by hand. "Check Reservoir" says when it's on a line or refilling.

## dd44
- Art: Blender renders replace the placeholders for the flood lights, curing barrel, DWC buckets, RDWC site and control buckets, and every plant growing in a bucket.
- Art: new Blender icons for the soil sack, flood lights, light timer, curing barrel, DWC bucket, RDWC buckets, rockwool cube, clay pebbles (raw and fired) and Hydroponics Monthly.
- Art: lamp sprites and icons now glow in their in-game light colour: purple for basic, warm yellow for pro.

## dd43
- Fixed: buckets, grow bags, the fan and the curing barrel couldn't be placed in front of windows or curtains. They're now low furniture, so they fit under them.
- Fixed: lamp glow staying on in a timer's dark hours. The server now re-copies each timer's schedule onto its lamp at load and every 10 minutes. Each switch-off is logged to console.txt.
- Added: Pull Rotted Plant on hydro plants. Works once root rot is past saving (30%+) or the plant is dead.
- Changed: changing a reservoir with no living plants left on it clears its rot. A DWC bucket is already clean once its plant is pulled.
- Changed: bleach now heals early rot over a few hours instead of instantly.
- Added: a root rot trend arrow on the status window from Agriculture 5: red up while rot spreads, green down while it heals, grey dash when steady.
- Changed: pro grow lights are twice as bright.
- Changed: the RDWC control bucket (reservoir) is taller.

## dd42
- Fixed: no Dazed Dank item could be placed and placed objects vanished. dd41's sprite sheet had 600 tiles and the game refuses any sheet over 512, so the whole sheet failed to load.
- Changed: RDWC buckets and their plants moved to a second sheet (dazeddank_hydro_01); every other sprite keeps its old number.

## dd41
- Added: RDWC. A control bucket runs up to 6 site buckets within 3 tiles, sharing one reservoir (40 L + 20 L per site). Root rot in the shared water reaches every site.
- Added: Top Shelf. RDWC grows can reach quality 115 (Hydro Quality Bonus); those buds are named Top Shelf, smoke stronger and longer, and cure up to 115.
- Added: RDWC site and control bucket recipes in Hydroponics Monthly; both buckets in the debug hydro kit.
- Changed: hydro plants now drink on their own clock, so several plants can share one reservoir.

## dd40
- Added: hydro plants' status window shows a Root rot bar with its level (0-100%) and a mark at 30%, where early rot can no longer be cured with bleach. Shown from Agriculture 3, with the roots word.

## dd39
- Changed: male plants are now Blender-rendered: taller and leggier than females, with clusters of pollen sacs that open into small flowers with yellow anthers at ripe. Applies in the ground, both grow bags and DWC buckets.

## dd38
- Fixed: grow lamp lights spamming errors in console.txt every time a light switched off (two lighting calls Build 42 doesn't support).
- Changed: lamp lights now switch off by being removed, and come back when power or the timer turns the lamp on again.
