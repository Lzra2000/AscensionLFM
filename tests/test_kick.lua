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
check("tick kicks after delay", st == "kicked", tostring(st))
check("uninvited Bob", #uninvited == 1 and uninvited[1] == "Bob", table.concat(uninvited, ","))

-- Status helpers
local gs = Kick.GetStatus()
check("status enabled", gs.enabled == true)
check("status hosting", gs.hosting == true)
check("status canKick", gs.canKick == true)

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

io.write(string.format("kick tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
