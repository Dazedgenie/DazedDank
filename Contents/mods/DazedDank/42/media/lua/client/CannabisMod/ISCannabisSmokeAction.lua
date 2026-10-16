-- The timed action for smoking a joint, a bud in a pipe or one session of a blunt; it uses up a little of the lighter
-- and then asks the server for the dose. A blunt put out partway (Put Out Blunt, or the action cancelled) counts as a
-- smaller session once at least Config.Smoking.PUT_OUT_COUNTS of it was smoked; before that nothing is used.

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

--- Ask the server for the dose. `portion` (blunts only) is how much of the session was smoked.
function ISCannabisSmokeAction:sendSmoke(portion)
    if self.sent then return end
    self.sent = true
    local args = { id = self.item:getID(), method = self.method }
    if self.method == "blunt" then
        args.portion = portion or 1
        -- No lighter means the menu found an open flame next to the player; the server takes that as lit.
        if not self.lighter then args.flame = true end
    end
    sendClientCommand(self.character, Config.COMMAND_MODULE, "smoke", args)
end

function ISCannabisSmokeAction:perform()
    self:sendSmoke(1)
    ISBaseTimedAction.perform(self)
end

--- Stopped partway: a blunt smoked far enough counts as a smaller session; otherwise it is just put out.
function ISCannabisSmokeAction:stop()
    if self.method == "blunt" and not self.sent then
        local done = 0
        pcall(function() done = self:getJobDelta() end)
        if done >= Config.Smoking.PUT_OUT_COUNTS then
            self:sendSmoke(done)
        else
            pcall(function() self.character:setHaloNote("You put the blunt out before it really got going") end)
        end
    end
    ISBaseTimedAction.stop(self)
end

--- @param method "joint", "pipe" or "blunt"; lighter: the lighter item to drain, or nil when an open flame is used
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
