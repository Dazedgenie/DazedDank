-- The short animation for handling a grow bag: placing one, picking one up,
-- or emptying a dead plant out of one.

require "TimedActions/ISBaseTimedAction"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

ISGrowBagAction = ISBaseTimedAction:derive("ISGrowBagAction")

function ISGrowBagAction:isValid()
    return self.square ~= nil
end

function ISGrowBagAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:isTurning() or self.character:shouldBeTurning()
end

function ISGrowBagAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
end

function ISGrowBagAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
end

function ISGrowBagAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISGrowBagAction:perform()
    local args = { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ() }
    for k, v in pairs(self.extra) do args[k] = v end
    sendClientCommand(self.character, Config.COMMAND_MODULE, self.command, args)
    ISBaseTimedAction.perform(self)
end

--- @param command server command, e.g. pickUpGrowBag, emptyGrowBag or a light timer command
--- @param extra extra arguments, e.g. { size = "small" }
function ISGrowBagAction:new(character, square, command, extra)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.square = square
    o.command = command
    o.extra = extra or {}
    o.maxTime = 60
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
