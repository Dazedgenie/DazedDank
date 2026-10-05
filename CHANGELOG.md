# Dazed Dank patch notes

## dd53.2
- Changed: the **Heater**, **Dehumidifier** and **Humidifier** now hang on a wall up high, like an overhead cupboard or a poster, in all four facings. The art is a placeholder until the Blender pass. Units already standing on the floor keep working.
- Added: an **Equipment** tab on the Grow Room Panel listing every fan, heater, dehumidifier and humidifier in the room, with where it is, which wall it hangs on, whether it's running, and a Show button.
- The panel also refreshes when equipment is placed or picked up near it.

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
