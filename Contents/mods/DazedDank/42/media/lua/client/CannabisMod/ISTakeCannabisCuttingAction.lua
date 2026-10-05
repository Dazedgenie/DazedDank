-- The short animation of a player snipping a plant: taking a cutting, or topping it.

require "TimedActions/ISBaseTimedAction"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

ISTakeCannabisCuttingAction = ISBaseTimedAction:derive("ISTakeCannabisCuttingAction")

--- Keep going only while the plot is still there.
function ISTakeCannabisCuttingAction:isValid()
    return self.square ~= nil and self.plot ~= nil and self.plot:getIsoObject() ~= nil
end

function ISTakeCannabisCuttingAction:waitToStart()
    self.character:faceThisObject(self.plot:getIsoObject())
    return self.character:isTurning() or self.character:shouldBeTurning()
end

function ISTakeCannabisCuttingAction:update()
    self.character:faceThisObject(self.plot:getIsoObject())
end

function ISTakeCannabisCuttingAction:start()
    -- the same crouch-and-reach vanilla uses for harvesting tall crops
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.character:reportEvent("EventLootItem")
end

function ISTakeCannabisCuttingAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISTakeCannabisCuttingAction:perform()
    sendClientCommand(self.character, Config.COMMAND_MODULE, self.command, {
        x = self.square:getX(), y = self.square:getY(), z = self.square:getZ(),
    })
    -- needed to remove from queue / start the next action
    ISBaseTimedAction.perform(self)
end

--- `command` is the server command to send when done: "takeCutting" (the default) or "topPlant".
function ISTakeCannabisCuttingAction:new(character, plot, square, command)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.plot = plot
    o.square = square
    o.command = command or "takeCutting"
    o.maxTime = 80
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
