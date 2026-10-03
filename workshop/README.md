# Steam Workshop page

- `description.bbcode`: the Workshop description. Paste it into the item's description box on Steam.
- `images/`: the graphics it shows, rendered from `art/page.html`.

## Before pasting

Steam can't load images from this repository while it's private, so host `images/` somewhere public
(Imgur, a public GitHub repo or Gist, Discord CDN...). Then find and replace in `description.bbcode`:

- `IMAGE_BASE` → the folder URL the images live at (no trailing slash)
- `WORKSHOP_ID` → the item's Workshop ID (also set `workshopid=` in `workshop.txt`)

## Changing the graphics

Edit `art/page.html` (open it in a browser to preview), then re-render every image:

    cd workshop/art
    npm install
    node render.mjs     # needs Playwright: set PLAYWRIGHT_MODULE=/path/to/playwright if it isn't installed here

The plant and furniture art in `art/sprites/` is cut from the mod's own texture packs
(`Contents/mods/DazedDank/42/media/texturepacks/`). Item icons come from `42/media/textures/` directly.
Colours live in the `:root` block at the top of `page.html`.
