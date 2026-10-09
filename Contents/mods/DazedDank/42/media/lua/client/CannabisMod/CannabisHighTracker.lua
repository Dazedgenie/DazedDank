-- High Tracker: a small window showing the current high or withdrawal, tolerance, dependency and the stat changes
-- applied each hour. Opened from the right-click menu; mainly for checking effects while testing.

require "ISUI/ISCollapsableWindow"
require "CannabisMod/CannabisConfig"
require "CannabisMod/CannabisHighReport"
require "CannabisMod/CannabisHigh"

local Config = CannabisMod.Config
local Report = CannabisMod.HighReport

local Tracker = {}
CannabisMod.HighTracker = Tracker

local W, ROW, TOP = 300, 18, 24
local window = nil
Tracker.REBUILD_MS = 500   -- the rows are worked out again this often, not every frame

local TrackerWindow = ISCollapsableWindow:derive("DazedDankHighTracker")

--- Read one stat into `out` (run under pcall, so a stat this game version lacks is skipped).
local function readStat(player, statKey, out)
    local key = CharacterStat and CharacterStat[statKey]
    if key then out[statKey] = player:getStats():get(key) end
end

--- The player's current value of each tracked stat, skipping any this game version lacks.
local function currentStats(player)
    local out = {}
    for _, stat in ipairs(Report.STATS) do pcall(readStat, player, stat.key, out) end
    return out
end

function TrackerWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    -- Ask the server for fresh tolerance and dependency now and then while the window is open.
    local ms = getTimestampMs()
    if not self.askedAt or ms - self.askedAt > 15000 then
        self.askedAt = ms
        sendClientCommand(player, Config.COMMAND_MODULE, "requestUseState", {})
    end
    if not self.rowsAt or ms - self.rowsAt >= Tracker.REBUILD_MS or ms < self.rowsAt then
        self.rowsAt = ms
        self.heading, self.rows = Report.build(CannabisMod.High.state, getGameTime():getWorldAgeHours(), currentStats(player))
    end
    local heading, rows = self.heading, self.rows
    self:drawText(heading, 10, TOP, 1, 0.85, 0.4, 1, UIFont.Medium)
    local y = TOP + 26
    for _, r in ipairs(rows) do
        self:drawText(r[1], 10, y, 0.75, 0.75, 0.8, 1, UIFont.Small)
        self:drawText(r[2], 100, y, 1, 1, 1, 1, UIFont.Small)
        y = y + ROW
    end
    local h = y + 8
    if math.abs(self.height - h) > 1 then self:setHeight(h) end
end

function TrackerWindow:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if window == self then window = nil end
end

--- Open the tracker, or close it when it's already open.
function Tracker.toggle()
    if window then window:close() return end
    window = TrackerWindow:new(80, 200, W, 200)
    window:initialise()
    window:setTitle("High Tracker")
    window.resizable = false
    window:addToUIManager()
    window:setVisible(true)
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context)
    context:addOption(window and "Close High Tracker" or "High Tracker", playerNum, Tracker.toggle)
end)

return Tracker
