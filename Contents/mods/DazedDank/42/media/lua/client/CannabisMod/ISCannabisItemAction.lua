-- A short timed action on an item (like trimming a plant) that sends a command to the server when it finishes.

require "TimedActions/ISBaseTimedAction"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

ISCannabisItemAction = ISBaseTimedAction:derive("ISCannabisItemAction")

function ISCannabisItemAction:isValid()
    return self.item ~= nil and self.item:getContainer() ~= nil
end

function ISCannabisItemAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function ISCannabisItemAction:perform()
    sendClientCommand(self.character, Config.COMMAND_MODULE, self.command, { id = self.item:getID() })
    ISBaseTimedAction.perform(self)
end

--- @param item the inventory item acted on; command: the server command; ticks: how long it takes
function ISCannabisItemAction:new(character, item, command, ticks)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.command = command
    o.maxTime = ticks or 100
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
