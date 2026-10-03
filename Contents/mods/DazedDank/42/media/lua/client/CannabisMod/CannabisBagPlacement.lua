-- Grow bags are placed like furniture; when placement runs on this client, ask the server to turn the placed bag into a plot.

require "CannabisMod/CannabisConfig"
require "Moveables/ISMoveableSpriteProps"

local Config = CannabisMod.Config

if ISMoveableSpriteProps and ISMoveableSpriteProps.placeMoveableInternal then
    local originalPlace = ISMoveableSpriteProps.placeMoveableInternal

    function ISMoveableSpriteProps:placeMoveableInternal(character, square, item, spriteName)
        local result = originalPlace(self, character, square, item, spriteName)
        if isClient() and Config.bagFromFurnSprite(spriteName) and square and character then
            sendClientCommand(character, Config.COMMAND_MODULE, "convertBag",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        end
        -- A flood reservoir changes which tables are fed; tell the server in case its object event didn't fire.
        if isClient() and spriteName == Config.Hydro.FLOOD_SPRITE and square and character then
            sendClientCommand(character, Config.COMMAND_MODULE, "floodPlaced",
                { x = square:getX(), y = square:getY(), z = square:getZ() })
        end
        return result
    end
end
