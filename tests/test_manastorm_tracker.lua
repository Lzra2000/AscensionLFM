-- AscensionLFM: tests/test_manastorm_tracker.lua
-- ManastormTracker.lua: pure formatters + Activity.Push wiring for
-- MANASTORM_LEVEL_COMPLETED / MANASTORM_FAILED.

package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" - " .. detail) or "") .. "\n")
    end
end

_G.AscensionLFMDB = nil
_G.AscensionLFM = nil
_G._now = 1000
_G.time = function() return _G._now end
-- No CreateFrame in the test environment: ManastormTracker's WoW event
-- wiring section is guarded by `type(CreateFrame) == "function"` and
-- skips itself entirely, matching this addon's established pattern for
-- files with a WoW-event-driven tail (see Invite.lua/Poster.lua).

dofile("core/Database.lua")
dofile("core/Activity.lua")
dofile("core/ManastormTracker.lua")

local AscensionLFM = _G.AscensionLFM
local Activity = assert(AscensionLFM.Activity)
local Tracker = assert(AscensionLFM.ManastormTracker)
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()

--------------------------------------------------------------------
-- Pure formatters
--------------------------------------------------------------------

check("FormatCleared with level", Tracker.FormatCleared(4) == "Manastorm level 4 cleared",
    Tracker.FormatCleared(4))
check("FormatCleared without level", Tracker.FormatCleared(nil) == "Manastorm level cleared",
    Tracker.FormatCleared(nil))
check("FormatFailed with level", Tracker.FormatFailed(7) == "Manastorm level 7 failed",
    Tracker.FormatFailed(7))
check("FormatFailed without level", Tracker.FormatFailed(nil) == "Manastorm run failed",
    Tracker.FormatFailed(nil))

--------------------------------------------------------------------
-- HandleLevelCompleted / HandleFailed wire into Activity.Push
--------------------------------------------------------------------

local ok = Tracker.HandleLevelCompleted(3, Activity)
check("HandleLevelCompleted returns true", ok == true, tostring(ok))

local summary = Activity.GetSessionSummary()
check("manastormCleared incremented", summary.manastormCleared == 1, tostring(summary.manastormCleared))
check("manastormFailed still 0", summary.manastormFailed == 0, tostring(summary.manastormFailed))

ok = Tracker.HandleFailed(5, Activity)
check("HandleFailed returns true", ok == true, tostring(ok))

summary = Activity.GetSessionSummary()
check("manastormFailed incremented", summary.manastormFailed == 1, tostring(summary.manastormFailed))
check("manastormCleared unaffected by failure", summary.manastormCleared == 1, tostring(summary.manastormCleared))

-- A second clear stacks correctly (not overwritten)
Tracker.HandleLevelCompleted(4, Activity)
summary = Activity.GetSessionSummary()
check("manastormCleared stacks to 2", summary.manastormCleared == 2, tostring(summary.manastormCleared))

--------------------------------------------------------------------
-- Graceful with a broken/missing Activity module (defensive, matches
-- this addon's established "never assume a dependency exists" pattern)
--------------------------------------------------------------------

ok = Tracker.HandleLevelCompleted(1, {}) -- module with no Push field
check("HandleLevelCompleted false on module without Push", ok == false, tostring(ok))

ok = Tracker.HandleFailed(1, {})
check("HandleFailed false on module without Push", ok == false, tostring(ok))

--------------------------------------------------------------------
-- FormatSessionSummary: only appends level stats when non-zero
--------------------------------------------------------------------

local zeroSummary = { invited = 2, rejected = 0, kicked = 0, matched = 1, posted = 1,
    manastormCleared = 0, manastormFailed = 0, elapsedSeconds = 60 }
local line = Activity.FormatSessionSummary(zeroSummary)
check("no level stats appended when both zero", not line:find("levels cleared"), line)

local nonZeroSummary = { invited = 2, rejected = 0, kicked = 0, matched = 1, posted = 1,
    manastormCleared = 3, manastormFailed = 1, elapsedSeconds = 60 }
line = Activity.FormatSessionSummary(nonZeroSummary)
check("level stats appended when non-zero", line:find("3 levels cleared, 1 failed") ~= nil, line)

io.write(string.format("manastorm_tracker tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
