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

--------------------------------------------------------------------
-- WoW event wiring: the module-level `if type(CreateFrame) == "function"`
-- block at the bottom of ManastormTracker.lua was never exercised by any
-- test before (no CreateFrame mock existed in this file), so the
-- MANASTORM_FAILED -> C_Manastorm.GetActiveLevel() fallback logic in
-- particular had zero coverage. Mock CreateFrame now and re-dofile so
-- that block actually runs, capturing the real OnEvent handler to drive
-- directly - same "track real state" mocking convention AGENTS.md
-- documents for test_ui_smoke.lua/test_mini_hud.lua.
--------------------------------------------------------------------

local registeredEvents = {}
local onEventHandler = nil
_G.CreateFrame = function()
    local f = {}
    function f:RegisterEvent(ev)
        table.insert(registeredEvents, ev)
    end
    function f:SetScript(script, fn)
        if script == "OnEvent" then
            onEventHandler = fn
        end
    end
    return f
end

dofile("core/ManastormTracker.lua")

check("registers MANASTORM_LEVEL_COMPLETED", (function()
    for _, ev in ipairs(registeredEvents) do
        if ev == "MANASTORM_LEVEL_COMPLETED" then return true end
    end
    return false
end)())
check("registers MANASTORM_FAILED", (function()
    for _, ev in ipairs(registeredEvents) do
        if ev == "MANASTORM_FAILED" then return true end
    end
    return false
end)())
check("OnEvent handler captured", type(onEventHandler) == "function")

Activity.ResetSession()

-- MANASTORM_LEVEL_COMPLETED: payload level flows straight through.
onEventHandler(nil, "MANASTORM_LEVEL_COMPLETED", 9)
summary = Activity.GetSessionSummary()
check("event wiring: level-completed increments cleared", summary.manastormCleared == 1,
    tostring(summary.manastormCleared))

-- MANASTORM_FAILED with its own payload level: used directly, no
-- C_Manastorm fallback needed.
_G.C_Manastorm = nil
onEventHandler(nil, "MANASTORM_FAILED", 6)
local log = AscensionLFM.Database.Get().activityLog
check("event wiring: failed-with-payload uses that level directly",
    log[1] and log[1].text == "Manastorm level 6 failed", log[1] and log[1].text)

-- MANASTORM_FAILED with NO payload level: falls back to
-- C_Manastorm.GetActiveLevel() when available.
_G.C_Manastorm = { GetActiveLevel = function() return 13 end }
onEventHandler(nil, "MANASTORM_FAILED", nil)
log = AscensionLFM.Database.Get().activityLog
check("event wiring: failed-without-payload falls back to C_Manastorm.GetActiveLevel()",
    log[1] and log[1].text == "Manastorm level 13 failed", log[1] and log[1].text)

-- C_Manastorm present but GetActiveLevel errors: caught, falls back to
-- nil (no level) rather than propagating the error into the event handler.
_G.C_Manastorm = { GetActiveLevel = function() error("not in a Manastorm run") end }
local okCall = pcall(onEventHandler, nil, "MANASTORM_FAILED", nil)
check("event wiring: GetActiveLevel error doesn't propagate", okCall == true)
log = AscensionLFM.Database.Get().activityLog
check("event wiring: GetActiveLevel error falls back to no level",
    log[1] and log[1].text == "Manastorm run failed", log[1] and log[1].text)

-- C_Manastorm entirely absent (Bronzebeard/Epoch variants): no fallback
-- attempted, still handled gracefully.
_G.C_Manastorm = nil
onEventHandler(nil, "MANASTORM_FAILED", nil)
log = AscensionLFM.Database.Get().activityLog
check("event wiring: no C_Manastorm at all still handled gracefully",
    log[1] and log[1].text == "Manastorm run failed", log[1] and log[1].text)

io.write(string.format("manastorm_tracker tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
