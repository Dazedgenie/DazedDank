# Vanilla crops in Dazed Dank containers: design

Agreed 2026-10-04. Vanilla crops (tomatoes, lettuce, potatoes and the rest) can be sown into grow bags and hydro containers and grow on vanilla's own rules. No quality, light schedule, nutrients, root rot or room-climate stress for them; vanilla handles growth, watering by hand, pests and harvest.

## Where each crop can go

- **Grow bags (small and large):** every vanilla crop.
- **Hydro (DWC bucket, RDWC site, flood table):** every crop except these, which are soil only:
  - Root and bulb crops: Potatoes, SweetPotato, Carrots, Radishes, SugarBeets, Turnip, Onion, Garlic, WildGarlic, Leek.
  - Big sprawling crops: Pumpkin, Watermelon, Corn, Zucchini.
  - Grains: Wheat, Barley, Rye, Flax.
  - Sowing one into hydro is refused with "This crop needs soil: use a grow bag".
- The existing checks still apply to every seed: a bag needs soil, a hydro site needs its medium and a connected reservoir with water.

## Look

- The container is drawn as it is now (bag, bucket or table), and the vanilla crop sprite is lifted so it sits on top of it, per container height.
- Needs one in-game check first: whether lifting the plot's sprite works and syncs in MP. Fallback: the crop drawn over the container without a lift.

## Water

- Soil bags: vanilla watering by hand, as on any plot (no rain indoors).
- Hydro: every 10 minutes, each hydro container with a living vanilla crop takes its water from the reservoir. It drinks a flat amount per hour, and the plot stays watered while the reservoir has water (flood tables: while the rockwool is wet). A dry reservoir leaves the plot dry, and the crop goes thirsty the vanilla way.

## Growth

- Hydro crops grow 15% faster: each growth step's wait is cut by 15%. Bags grow at vanilla speed.

## Indoors

- With vanilla's **Kill Crops Grown Inside** on, a crop in one of our containers survives indoors only while a powered grow lamp or flood light reaches its tile, or while it stands inside a grow room (a room with a Grow Room Panel). Otherwise vanilla's slow indoor death applies.
- Done by adding back vanilla's inside penalty after its health check, for those crops only.

## Keeping the container

- Harvesting a crop that doesn't regrow, or clearing a dead one, returns the container to empty (as cannabis does now). Rockwool is spent per harvest, clay pebbles and soil stay.
- Containers are protected from vanilla's slow fade of dead, harvested and empty plots, which could otherwise delete a bag.
- Regrowing crops (tomato, strawberry and others with growBack) keep growing in place after harvest.

## Grow room panel

- Plants tab: an "Other crops" list with name, stage and water for vanilla crops in the room.
- Hydro tab: unchanged; its reservoirs already include what vanilla crops drink.

## Performance

- Vanilla crop simulation costs the same as outdoor farming. New work: one pass over containers every 10 minutes, and one tile lookup per vanilla plant in vanilla's health check (every 2 hours). Well under the existing cannabis tick.

## Open checks in game

- Crop sprite lift on each container (bag, large bag, bucket, RDWC site, flood table).
- Vanilla's Sow menu offers vanilla seeds on our plots indoors.
