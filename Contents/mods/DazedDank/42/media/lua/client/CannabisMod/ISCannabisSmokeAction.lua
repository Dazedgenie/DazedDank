-- The timed action for smoking a joint or a bud in a pipe; it uses up a little of the lighter and then asks the server for the dose.

require "TimedActions/ISBaseTimedAction"
require "CannabisMod/CannabisConfig"

local Config = CannabisMod.Config

ISCannabisSmokeAction = ISBaseTimedAction:derive("ISCannabisSmokeAction")

function ISCannabisSmokeAction:isValid()
    return self.item ~= nil and self.item:getContainer() ~= nil
end

function ISCannabisSmokeAction:start()
    self:setActionAnim(CharacterActionAnims.Eat)
    self:setAnimVariable("FoodType", "Cigarettes")
    -- Hold the joint, or the pipe when smoking a bud in it, in the off hand like a vanilla cigarette.
    local held = self.item
    if self.method == "pipe" then
        local pipe = self.character:getInventory():getFirstTypeRecurse(Config.Smoking.PIPE_ITEM:match("%.(.+)$"))
        if pipe then held = pipe end
    end
    self:setOverrideHandModels(nil, held)
    if self.lighter and not self.fromRelaunch then
        pcall(function()
            self.lighter:setUsedDelta(self.lighter:getCurrentUsesFloat() - self.lighter:getUseDelta())
        end)
    end
end

function ISCannabisSmokeAction:perform()
    sendClientCommand(self.character, Config.COMMAND_MODULE, "smoke", { id = self.item:getID(), method = self.method })
    ISBaseTimedAction.perform(self)
end

--- @param method "joint" or "pipe"; lighter: the lighter item to drain, or nil when an open flame is used
function ISCannabisSmokeAction:new(character, item, method, lighter)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.method = method
    o.lighter = lighter
    o.stopOnWalk = false
    o.stopOnRun = true
    o.maxTime = Config.Smoking.METHODS[method].ticks
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end
