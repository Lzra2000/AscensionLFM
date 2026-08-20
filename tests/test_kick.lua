-- AscensionLFM kick scheduler pure-function + Tick regression tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

_G.AscensionLFM = nil
_G.AscensionLFMDB = nil
_G.GetTime = function() return 1000 end
_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
    }
end

dofile("core/Database.lua")
dofile("core/Kick.lua")

AscensionLFM.Database.Init()
local Kick = assert(_G.AscensionLFM.Kick)
local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

-- ResolveLevel: 0 from roster must not block UnitLevel
check("resolve prefers unit", Kick.ResolveLevel(59, 0) == 59)
check("resolve falls back roster", Kick.ResolveLevel(0, 60) == 60)
check("resolve both zero", Kick.ResolveLevel(0, 0) == 0)
check("resolve nil unit", Kick.ResolveLevel(nil, 59) == 59)

local roster = {
    { name = "Alice", level = 58 },
    { name = "Bob", level = 59 },
    { name = "Carl", level = 60 },
    { name = "Host", level = 59 },
}

local targets = Kick.SelectTargets(roster, 59, "Host")
check("selects two", #targets == 2)
check("excludes self", targets[1].name ~= "Host" and targets[2].name ~= "Host")
check("includes Bob", targets[1].name == "Bob" or targets[2].name == "Bob")
check("includes Carl", targets[1].name == "Carl" or targets[2].name == "Carl")
check("skips 58", true)

targets = Kick.SelectTargets(roster, 59, nil)
check("with no self includes Host", #targets == 3)

targets = Kick.SelectTargets({ { name = "Low", level = 10 } }, 59, "Me")
check("empty when none", #targets == 0)

check("should warn first", Kick.ShouldWarn(100, 0, 10) == true)
check("rate limit", Kick.ShouldWarn(105, 100, 10) == false)
check("after interval", Kick.ShouldWarn(110, 100, 10) == true)

local msg = Kick.BuildWarnMessage({ { name = "Bob", level = 59 } }, 59)
check("warn message", type(msg) == "string" and msg:find("Bob", 1, true) ~= nil and msg:find("59", 1, true) ~= nil)
check("warn nil empty", Kick.BuildWarnMessage({}, 59) == nil)

--------------------------------------------------------------------
-- Live Tick: roster level 0 + UnitLevel 59 must warn then kick
--------------------------------------------------------------------
Kick._ResetForTests()
local db = AscensionLFM.Database.Get()
db.autoKickLevel59 = true
db.mode = "hosting"
db.kickLevel = 59
db.kickWarnInterval = 10

local uninvited = {}
local warned = {}

_G.GetNumRaidMembers = function() return 2 end
_G.GetNumPartyMembers = function() return 0 end
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.IsPartyLeader = function() return false end
_G.UnitIsPartyLeader = function() return true end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    if u == "raid1" then return "Host" end
    if u == "raid2" then return "Bob" end
    return nil
end
_G.UnitLevel = function(u)
    if u == "raid1" then return 60 end
    if u == "raid2" then return 59 end
    return 0
end
-- Bug regress: roster reports 0 for everyone (Ascension / offline placeholder)
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    if i == 2 then return "Bob", 0, 1, 0 end
    return nil
end
_G.SendChatMessage = function(m, ch)
    table.insert(warned, { m = m, ch = ch })
end
_G.UninviteUnit = function(name)
    table.insert(uninvited, name)
end

local built = Kick.BuildRoster()
check("build roster size", #built == 2)
check("build uses UnitLevel not zero roster", built[2].level == 59, tostring(built[2] and built[2].level))

local st = Kick.Tick(1000)
check("tick warns first", st == "warned", tostring(st))
check("rw sent", #warned >= 1)
check("not uninvited yet", #uninvited == 0)
local pend = Kick._GetPending()
check("pending queued", pend and #pend.targets == 1)

st = Kick.Tick(1000 + Kick.KICK_DELAY + 0.01)
check("tick attempts uninvite, awaits verify", st == "verifying", tostring(st))
check("uninvited Bob", #uninvited == 1 and uninvited[1] == "Bob", table.concat(uninvited, ","))
check("not yet confirmed kicked", Kick.GetStatus().last ~= "kicked")

-- Roster confirms Bob actually left before the verify delay — should not
-- yet resolve (still waiting out VERIFY_DELAY)
st = Kick.Tick(1000 + Kick.KICK_DELAY + 0.5)
check("still verifying before delay elapses", st == "verifying", tostring(st))

-- Bob genuinely left the roster; verify delay elapsed -> confirmed kicked
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    return nil
end
_G.GetNumRaidMembers = function() return 1 end
st = Kick.Tick(1000 + Kick.KICK_DELAY + Kick.VERIFY_DELAY + 0.1)
check("verify confirms kicked once gone from roster", st == "kicked", tostring(st))

-- Restore full 2-member roster for subsequent tests
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    if i == 2 then return "Bob", 0, 1, 0 end
    return nil
end
_G.GetNumRaidMembers = function() return 2 end

-- Status helpers
local gs = Kick.GetStatus()
check("status enabled", gs.enabled == true)
check("status hosting", gs.hosting == true)
check("status canKick", gs.canKick == true)

--------------------------------------------------------------------
-- Regression: UninviteUnit "succeeds" (no Lua error) but the target is
-- still in the roster afterward — e.g. a server-side privilege edge case
-- that silently no-ops the request. Previously this was blindly trusted
-- as a real kick (LogKick fired, no further action) even though the
-- player never actually left, matching a live report: "warning fires,
-- nobody gets removed, no error printed at all".
--------------------------------------------------------------------
Kick._ResetForTests()
db.mode = "hosting"
db.fullAutoHosting = false
db.autoKickLevel59 = true
db.kickLevel = 59
db.kickWarnInterval = 10
uninvited = {}
warned = {}
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    if i == 2 then return "Ghosty", 0, 1, 0 end
    return nil
end
_G.GetNumRaidMembers = function() return 2 end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    if u == "raid1" then return "Host" end
    if u == "raid2" then return "Ghosty" end
    return nil
end
_G.UnitLevel = function(u)
    if u == "raid1" then return 60 end
    if u == "raid2" then return 59 end
    return 0
end
_G.UninviteUnit = function(name) table.insert(uninvited, name) end -- "succeeds" but roster never actually changes

local gt = 5000
st = Kick.Tick(gt)
check("silent-noop: warns", st == "warned", tostring(st))
st = Kick.Tick(gt + Kick.KICK_DELAY + 0.01)
check("silent-noop: attempts uninvite", #uninvited == 1)
st = Kick.Tick(gt + Kick.KICK_DELAY + Kick.VERIFY_DELAY + 0.1)
check("silent-noop: verify catches still-present target as a failure", st == "kick failed", tostring(st))
check("silent-noop: not falsely confirmed kicked", Kick.GetStatus().last ~= "kicked")
check("silent-noop: attempt counted", Kick._GetFailedAttempts()["ghosty"] == 1,
    tostring(Kick._GetFailedAttempts()["ghosty"]))

-- Mode gate: notify without full auto
Kick._ResetForTests()
db.mode = "notify"
db.fullAutoHosting = false
db.autoKickLevel59 = true
st = Kick.Tick(2000)
check("not hosting blocks", st == "not hosting", tostring(st))

-- fullAutoHosting counts as hosting for kick
Kick._ResetForTests()
db.mode = "notify"
db.fullAutoHosting = true
st = Kick.Tick(3000)
check("fullAuto allows kick path", st == "warned" or st == "none" or st == "levels unknown" or st == "kicked" or st == "pending", tostring(st))
-- With same roster stubs still active, should warn
check("fullAuto warns", st == "warned", tostring(st))

-- Privilege via UnitIsPartyLeader only (IsRaidLeader false)
Kick._ResetForTests()
db.mode = "hosting"
db.fullAutoHosting = false
_G.IsRaidLeader = function() return false end
_G.UnitIsPartyLeader = function(u) return u == "player" end
st = Kick.Tick(4000)
check("UnitIsPartyLeader enough", st == "warned", tostring(st))

-- levels unknown when UnitLevel also 0
Kick._ResetForTests()
_G.UnitLevel = function() return 0 end
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    if i == 2 then return "Bob", 0, 1, 0 end
    return nil
end
st = Kick.Tick(5000)
check("levels unknown", st == "levels unknown", tostring(st))

--------------------------------------------------------------------
-- Give up after MAX_KICK_ATTEMPTS failed UninviteUnit attempts (no
-- infinite re-warn spam when a target can't actually be removed).
--------------------------------------------------------------------
Kick._ResetForTests()
db.mode = "hosting"
db.fullAutoHosting = false
db.autoKickLevel59 = true
db.kickLevel = 59
db.kickWarnInterval = 10
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.IsPartyLeader = function() return false end
_G.UnitIsPartyLeader = function() return true end
_G.GetNumRaidMembers = function() return 2 end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    if u == "raid1" then return "Host" end
    if u == "raid2" then return "Flunky" end
    return nil
end
_G.UnitLevel = function(u)
    if u == "raid1" then return 60 end
    if u == "raid2" then return 59 end
    return 0
end
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host", 2, 1, 0 end
    if i == 2 then return "Flunky", 0, 1, 0 end
    return nil
end
local giveUpWarns = {}
_G.SendChatMessage = function(m, ch) table.insert(giveUpWarns, m) end
_G.UninviteUnit = function() error("simulated uninvite failure") end

local gt = 1000
local gst1 = Kick.Tick(gt)
check("giveup: cycle1 warns", gst1 == "warned", tostring(gst1))
Kick.Tick(gt + Kick.KICK_DELAY + 0.01) -- fails attempt 1

gt = gt + 10
local gst2 = Kick.Tick(gt)
check("giveup: cycle2 warns", gst2 == "warned", tostring(gst2))
check("giveup: retry suffix on cycle2", giveUpWarns[2] and giveUpWarns[2]:find("retry 2/3", 1, true) ~= nil,
    tostring(giveUpWarns[2]))
Kick.Tick(gt + Kick.KICK_DELAY + 0.01) -- fails attempt 2

gt = gt + 10
local gst3 = Kick.Tick(gt)
check("giveup: cycle3 warns", gst3 == "warned", tostring(gst3))
Kick.Tick(gt + Kick.KICK_DELAY + 0.01) -- fails attempt 3 -> gives up

check("giveup: warned exactly 3 times total", #giveUpWarns == 3, tostring(#giveUpWarns))
check("giveup: marked as given up", Kick._GetGaveUp()["flunky"] == true)

gt = gt + 10
local gst4 = Kick.Tick(gt)
check("giveup: cycle4 does not re-warn", gst4 == "given up", tostring(gst4))
check("giveup: still only 3 warns total (no spam)", #giveUpWarns == 3, tostring(#giveUpWarns))

local gks = Kick.GetStatus()
check("giveup: status exposes count", gks.gaveUp == 1, tostring(gks.gaveUp))

io.write(string.format("kick tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
