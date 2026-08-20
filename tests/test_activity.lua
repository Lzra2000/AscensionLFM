-- AscensionLFM: tests/test_activity.lua
-- Activity.lua: bounded rolling log + uncapped session-total counters.

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

dofile("core/Database.lua")
dofile("core/Activity.lua")

local AscensionLFM = _G.AscensionLFM
local Activity = assert(AscensionLFM.Activity)
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()

--------------------------------------------------------------------
-- Rolling log stays bounded (unchanged existing behavior).
--------------------------------------------------------------------
for i = 1, 45 do
    Activity.Push("match", "entry " .. i)
end
check("rolling log caps at MAX_ENTRIES", #db.activityLog == Activity.MAX_ENTRIES,
    tostring(#db.activityLog))

--------------------------------------------------------------------
-- Session counters: uncapped, survive well past MAX_ENTRIES worth of
-- events - this is the whole point (a busy hosting burst of 40+
-- applicants must not lose count of "how many were actually invited").
--------------------------------------------------------------------
db.sessionStats = {}
db.sessionStartedAt = 0
_G._now = 2000
for i = 1, 23 do
    Activity.Push("invite", "invited applicant " .. i)
end
for i = 1, 4 do
    Activity.Push("reject", "rejected applicant " .. i)
end
for i = 1, 2 do
    Activity.Push("kick", "kicked applicant " .. i)
end
for i = 1, 15 do
    Activity.Push("match", "matched applicant " .. i)
end
Activity.Push("post", "posted LFM")

local summary = Activity.GetSessionSummary(2600)
check("session invited count uncapped past 40 events", summary.invited == 23, tostring(summary.invited))
check("session rejected count", summary.rejected == 4, tostring(summary.rejected))
check("session kicked count", summary.kicked == 2, tostring(summary.kicked))
check("session matched count", summary.matched == 15, tostring(summary.matched))
check("session posted count", summary.posted == 1, tostring(summary.posted))
check("elapsed seconds computed from sessionStartedAt",
    summary.elapsedSeconds == 600, tostring(summary.elapsedSeconds))

--------------------------------------------------------------------
-- FormatSessionSummary: pure, testable without DB/clock.
--------------------------------------------------------------------
local text = Activity.FormatSessionSummary({
    invited = 23, rejected = 4, kicked = 2, matched = 15, posted = 1, elapsedSeconds = 600,
})
check("format shows minutes for < 1h", text:find("10m", 1, true) ~= nil, text)
check("format shows invited count", text:find("23 invited", 1, true) ~= nil, text)
check("format shows rejected count", text:find("4 rejected", 1, true) ~= nil, text)
check("format shows kicked count", text:find("2 kicked", 1, true) ~= nil, text)
check("format shows matched count", text:find("15 matches", 1, true) ~= nil, text)
check("format shows posted count", text:find("1 posts", 1, true) ~= nil, text)
check("format uses ASCII only (no em-dash)", text:find("\226\128\148", 1, true) == nil, text)

local textHours = Activity.FormatSessionSummary({ elapsedSeconds = 3725 }) -- 1h 2m 5s
check("format shows hours when >= 1h", textHours:find("1h2m", 1, true) ~= nil, textHours)

local textZero = Activity.FormatSessionSummary(nil)
check("format is nil-safe", textZero:find("0 invited", 1, true) ~= nil, textZero)

--------------------------------------------------------------------
-- ResetSession: clears counters and restarts the clock, leaves the
-- rolling activityLog untouched.
--------------------------------------------------------------------
local logCountBefore = #db.activityLog
_G._now = 5000
Activity.ResetSession()
check("reset clears session counters", Activity.GetSessionSummary(5000).invited == 0)
check("reset restarts the clock", db.sessionStartedAt == 5000, tostring(db.sessionStartedAt))
check("reset does not touch the rolling log", #db.activityLog == logCountBefore,
    tostring(#db.activityLog))

-- Counting resumes correctly after a reset.
Activity.Push("invite", "fresh applicant")
check("counting resumes after reset", Activity.GetSessionSummary(5000).invited == 1)

io.write(string.format("test_activity: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
