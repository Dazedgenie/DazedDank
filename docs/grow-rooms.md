# Grow rooms: design for the first major update

Agreed 2026-10-03. Builds on the released mod without changing any existing item or save; every feature here is optional and layered on top of the current per-lamp, per-reservoir behaviour.

## Room and panel

- **Grow Room Panel**: wall-mounted furniture (four facings), Electrical 5, taught by the new **Controlled Environment Quarterly** magazine. Needs power on its square (Off-Grid decides that; no battery item).
- The room is a **flood fill** from the panel across connected indoor floor, stopping at walls, door frames and window frames, one floor only, capped at 400 tiles with a radius fallback past the cap. Rebuilt when a wall or door changes.
- **One panel per room per floor.** A second panel in the same fill is refused with the first panel's position.
- Picking the panel up: lamps get their own behaviour back (24/0 until re-timed), reservoirs keep working on their own menus, the room record is dropped.
- MP access follows vanilla safehouse rules.

## Lights

- Every lamp and flood light inside the fill is synced to the room schedule (24/0, 18/6, 12/12). A lamp placed in the room with its own timer has the timer removed and handed back.
- Flood lights outside any room stay independent.
- **Leaks:** any light not from the room's lamps during the room's dark hours. Sources: a lamp in another room through a doorway, a flood light outside, and sun through a window or a door to the outside. A vanilla sheet or curtain hung and drawn shut seals a window or door. A closed door with no drawn sheet seeps a share of a full leak round its edges (sandbox **Closed Door Light Leak**, 25% by default, 0 to seal); an open door or uncovered window leaks fully. A seep adds its share of the leak stress but never counts as the plant's light. Blackout curtains already hung still seal. The Lights tab lists each opening as covered, seeping or open.
- The existing per-plant leak stress stays as the effect.

## Hydro

- Hydro tab lists every DWC bucket, RDWC control and flood reservoir in the room with water, food and root health, with Top Up, Change, Dose, Bleach per row and "all" versions. Top Up and Dose use what the player carries.
- The room's Dazed Plumbing water line feeds every reservoir in the room on Change.
- **Flood Timer** attaches to the panel (consumes the item) and gives one flood schedule for every flood reservoir in the room.
- "Highlight" on a row tints the equipment's tile for a few seconds, like the range preview.

## Plants

- Plants tab: every plant in the room with stage, water and status, gated by the viewer's Agriculture level exactly like Inspect. Clicking a row opens the plant's Inspect window.

## Power loss

- Lamps and pumps go off, the schedule clock keeps running, and everything resumes where the clock says when power returns. No reset step.
- Extra room penalty on top of the per-plant one: stress to every flowering plant in the room scaled by how long the lights were due on while power was out.

## Climate (temperature and humidity only; no CO2 or VPD)

- Room temperature starts at outdoor temperature. Each lit lamp adds heat; the heater adds heat; exhaust and intake fans pull toward outdoor values.
- Humidity rises from plants, open reservoirs and wet plants on racks; dehumidifier lowers, humidifier raises, fans pull toward outdoor.
- Targets by the **player-set mode** (Veg, Flower, Drying); the panel warns when the room's contents don't match the mode.
  - Temperature: veg 24–28 C, flower 20–26 C, drying 15–21 C; stress below 15 or above 32.
  - The panel shows temperatures in Celsius or Fahrenheit: the **Temperatures** choice on the Dazed Core options page when Dazed Core 1.6.0+ is loaded (Game setting, Celsius, Fahrenheit), otherwise the game's own Display > Temperature display option. Everything is still worked out in C.
  - Humidity: seedlings and clones 65–75%, veg 50–65%, flower 40–50%, drying 55–62%; above 65% in flower raises mold.
- Equipment (all need power): **exhaust fan**, **intake fan**, **heater**, **dehumidifier**, **humidifier**. Fans on a wall bordering outdoors work fully; on an inside wall 25%. They run **automatically** toward the targets, with a manual override on the panel.
- A **drying room** is a room in Drying mode: racks use room humidity and temperature instead of the outdoor and rain guesses. Racks in a Veg or Flower room raise its humidity for real and the panel warns to separate them.

## Log

- Last 30 entries: power lost and restored, schedule and mode changes, floods, root rot starting, harvests, mold.

## Sandbox switches

- **Room Climate** (off = rooms always sit at target), **Light Leaks** (off = never), **Room Power Penalty** (off = only the per-plant penalty).

## Panel window

- One window, 560×420, tabs Lights, Hydro, Plants, Climate, Log. Mockups in `tools/workshop/panel_mock.py`.

## New art

- Panel (4 facings), blackout curtain (door and window, 4 facings each), exhaust fan, intake fan, heater, dehumidifier, humidifier, magazine; icons for each.

## Settled details

- Blackout curtain: retired (no longer craftable); vanilla sheets do the job. Curtains already hung or carried still work. On a door it also hides the room from zombies looking through the door's window, like a vanilla sheet.
- Rooms can be renamed from the panel; the name shows in the panel title and log entries.

## Build progress (fork `DazedDank-GrowRooms`, branch `growrooms`)

- Built and offline-tested: room model and flood fill, panel registration and removal, shared lamp schedule, power loss with forgiving outage penalty, light leaks and blackout curtains, Hydro and Plants tabs with the panel flood timer, climate model (temperature and humidity, Veg/Flower/Drying targets, five equipment kinds with auto control and manual Auto/On/Off), plant stress and warnings, Drying reading the room's air, Climate and Log tabs (log covers power, schedule, mode, rename, equipment, hydro actions, hand floods, root rot setting in, harvests and mold), the room water line (one plumbed reservoir's Dazed Plumbing line refills every reservoir in the room after a Change), sandbox switches (RoomClimate, LightLeaks, RoomPowerPenalty), items, recipes, icons, loot, art (panel, curtains, 8 fan facings, 3 floor units; sheet `dazeddank_rooms_01`, tiledef 7422).
- Needs a check in game: wall, door and window detection in the flood fill; wall-mounted placement of the panel and fan sprites; curtain overlay placement; the tab window layout; outdoor humidity reading (falls back to a cloud/rain estimate); recipe item ids (Motor, SheetMetal, WaterBottleEmpty).
- Not built: a curtain on a door hiding the room from zombies (no known API).
