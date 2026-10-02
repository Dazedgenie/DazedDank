-- Sends a message from the server to a player, in both multiplayer and single
-- player.

require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

local Net = {}
CannabisMod.Net = Net

-- Client-side handlers register here, keyed by command name (see CannabisClient.lua).
Net.clientHandlers = {}

--- Send a reply from server code to one player.
--- @param player the IsoPlayer to send to
--- @param command reply name, e.g. "plantInfo"
--- @param args table of data
function Net.toPlayer(player, command, args)
    if isServer() then
        -- Real server (dedicated, or the host of a listen server): goes over
        -- the network to that player's game.
        sendServerCommand(player, Config.COMMAND_MODULE, command, args)
        return
    end
    -- Single player: same game, call the client handler directly.
    local handler = Net.clientHandlers[command]
    if handler then
        handler(args)
    end
end

--- Show a short floating message over a player, from server code.
function Net.notify(player, text)
    Net.toPlayer(player, "notify", { text = text })
end
