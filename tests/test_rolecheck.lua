-- AscensionLFM RoleCheck pure-function + whisper/resync tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/RoleCheck.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local RoleCheck = assert(_G.AscensionLFM.RoleCheck)
local Slots = AscensionLFM.Slots

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

-- Message build
local def = RoleCheck.BuildMessage(nil)
check("default message non-empty", type(def) == "string" and #def > 10)
check("default mentions ROLE CHECK", def:find("ROLE CHECK", 1, true) ~= nil)
check("custom message kept", RoleCheck.BuildMessage("hello") == "hello")
check("empty custom → default", RoleCheck.BuildMessage("") == RoleCheck.DEFAULT_MESSAGE)
check("message truncated to 255", #RoleCheck.BuildMessage(string.rep("x", 300)) == 255)

-- Window / interval clamps
check("window default 60", RoleCheck.ClampWindow(nil) == 60)
check("ClampDuration alias", RoleCheck.ClampDuration(5) == 15)
check("window floor 15", RoleCheck.ClampWindow(5) == 15)
check("window ceil 300", RoleCheck.ClampWindow(999) == 300)
check("min interval floor 30", RoleCheck.ClampMinInterval(10) == 30)

-- Rate limit / who can RW (pure)
check("allow first RW", RoleCheck.ShouldAllowRW(100, 0, 30) == true)
check("rate limit blocks", RoleCheck.ShouldAllowRW(120, 100, 30) == false)
check("after interval allows", RoleCheck.ShouldAllowRW(130, 100, 30) == true)

local present = { alice = true, bob = true }
check("member alice", RoleCheck.IsGroupMemberName("Alice", present) == true)
check("non-member carl", RoleCheck.IsGroupMemberName("Carl", present) == false)

-- Whisper → role
check("whisper tank", RoleCheck.ParseWhisperRole("tank") == "tank")
check("whisper heal", RoleCheck.ParseWhisperRole("heal") == "healer")
-- v0.4.131: aura is a tag on a combat seat, so a bare "aura" reply resolves
-- to dps + the tag rather than to an "aura" role that no longer exists.
local wr, wa = RoleCheck.ParseWhisperRole("aura")
check("whisper aura seats as dps", wr == "dps", tostring(wr))
check("whisper aura carries the tag", wa == true, tostring(wa))
wr, wa = RoleCheck.ParseWhisperRole("dps with aura")
check("whisper 'dps with aura' seats as dps", wr == "dps", tostring(wr))
check("whisper 'dps with aura' carries the tag", wa == true, tostring(wa))
wr, wa = RoleCheck.ParseWhisperRole("tank no aura")
check("whisper 'tank no aura' seats as tank", wr == "tank", tostring(wr))
check("whisper 'tank no aura' has no tag", wa == false, tostring(wa))
check("whisper dps", RoleCheck.ParseWhisperRole("dps please") == "dps")
check("whisper inv ms tank", RoleCheck.ParseWhisperRole("inv ms tank") == "tank")
check("whisper garbage nil", RoleCheck.ParseWhisperRole("hello world xyz") == nil)

-- Resync prune + re-apply
local assigned = { alice = "tank", bob = "healer", gone = "dps" }
local responses = { alice = "dps", carl = "aura" }
local newMap, removed, applied = RoleCheck.ResyncAssigned(assigned, responses, present)
check("prune removed gone", removed == 1)
check("alice role updated", newMap.alice == "dps")
check("bob kept", newMap.bob == "healer")
check("gone pruned", newMap.gone == nil)
check("carl ignored", newMap.carl == nil)
check("applied 1", applied == 1)

check("active status format",
    RoleCheck.BuildStatusText(true, 42, 3) == "Role check active - 42s left * 3 responses")

-- Live StartCheck needs hosting + privilege
RoleCheck._ResetForTests()
local db = AscensionLFM.Database.Get()
db.mode = "notify"
local ok, reason = RoleCheck.StartCheck()
check("refuse when not hosting", ok == false and reason == "not hosting")

db.mode = "hosting"
-- In a raid but not lead/assist → no privilege
_G.GetNumRaidMembers = function() return 2 end
_G.GetNumPartyMembers = function() return 0 end
_G.IsRaidLeader = function() return false end
_G.IsRaidOfficer = function() return false end
_G.UnitIsPartyLeader = function() return false end
ok, reason = RoleCheck.StartCheck()
check("refuse without privilege", ok == false and reason == "no privilege", tostring(reason))

_G.GetNumRaidMembers = function() return 3 end
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.UnitIsPartyLeader = function() return false end
_G.GetRaidRosterInfo = function(i)
    return ({ "Host", "Alice", "Bob" })[i]
end
_G.SendChatMessage = function(msg, ch)
    _G._lastRW = { msg = msg, ch = ch }
end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    if u == "raid1" then return "Host" end
    if u == "raid2" then return "Alice" end
    if u == "raid3" then return "Bob" end
    return nil
end
_G.GetTime = function() return _G._now or 2000 end
_G.CreateFrame = function()
    return { SetScript = function() end }
end

RoleCheck._ResetForTests()
_G._now = 2000
ok, reason = RoleCheck.StartCheck()
check("start check ok", ok == true, tostring(reason))
check("sent RAID_WARNING", _G._lastRW and _G._lastRW.ch == "RAID_WARNING")
check("active after start", RoleCheck.IsActive() == true)

ok, reason = RoleCheck.StartCheck()
check("second RW rate limited", ok == false and reason == "rate limited")

-- Whisper from group member during window
local handled = RoleCheck.HandleWhisper("Alice", "tank")
check("whisper handled", handled == true)
check("alice assigned tank", Slots.GetAssigned("Alice") == "tank")
check("response count 1", RoleCheck.ResponseCount() == 1)

handled = RoleCheck.HandleWhisper("Stranger", "dps")
check("stranger ignored", handled == false)

handled = RoleCheck.HandleWhisper("Alice", "heal")
check("alice role update", handled == true)
check("alice now healer", Slots.GetAssigned("Alice") == "healer")
check("response count still 1", RoleCheck.ResponseCount() == 1)

Slots.Assign("Ghost", "dps")
local rem = RoleCheck.Resync()
check("resync returns", rem ~= nil)
check("alice still healer after resync", Slots.GetAssigned("Alice") == "healer")
check("ghost protected immediately after assign (grace period)", Slots.GetAssigned("Ghost") == "dps",
    tostring(Slots.GetAssigned("Ghost")))

-- Ghost never actually shows up in the roster; once the grace period
-- (default 20s) has genuinely elapsed, the NEXT resync correctly prunes
-- it as a real stale assignment (declined/expired invite).
_G._now = 2000 + 25
rem = RoleCheck.Resync()
check("ghost cleared after grace period elapses", Slots.GetAssigned("Ghost") == nil,
    tostring(Slots.GetAssigned("Ghost")))

-- Regression: Resync's ClearAll()+re-Assign() pattern used to stamp
-- assignedAt = now for every SURVIVING present member too, not just
-- genuinely new assignments - silently refreshing everyone's
-- RecentlyAssigned grace window on every single resync. Alice was
-- assigned at _now=2000 (25s ago at this point, well past the 20s
-- default grace) and has been present the whole time - she must NOT
-- read as "recently assigned" just because a resync happened to run.
check("long-present member's assignment age survives a resync (not refreshed to 'now')",
    Slots.RecentlyAssigned("Alice") == false,
    "RecentlyAssigned(Alice) at t=" .. tostring(_G._now))

-- Auto-resync on window end
RoleCheck._ResetForTests()
db.roleCheckAutoResync = true
_G._now = 3000
ok = RoleCheck.StartCheck()
check("restart ok", ok == true)
RoleCheck.HandleWhisper("Bob", "aura")
check("bob seats as dps", Slots.GetAssigned("Bob") == "dps", tostring(Slots.GetAssigned("Bob")))
check("bob tagged as aura carrier", Slots.HasAura("Bob") == true)
_G._now = 3000 + 61
local tick = RoleCheck.Tick(_G._now)
check("tick ended", tick == "ended")
check("inactive after end", RoleCheck.IsActive() == false)

-- Full Auto counts as hosting
RoleCheck._ResetForTests()
db.mode = "seeking"
db.fullAutoHosting = true
_G._now = 4000
ok, reason = RoleCheck.StartCheck()
check("full auto allows check", ok == true, tostring(reason))

-- UnitIsPartyLeader alone is enough (IsRaidLeader false — Ascension quirk)
RoleCheck._ResetForTests()
db.mode = "hosting"
db.fullAutoHosting = false
_G.IsRaidLeader = function() return false end
_G.UnitIsPartyLeader = function(u) return u == "player" end
_G._now = 5000
ok, reason = RoleCheck.StartCheck()
check("UnitIsPartyLeader enough", ok == true, tostring(reason))

-- Roster name nil + UnitName fallback still counts as member
RoleCheck._ResetForTests()
_G.GetRaidRosterInfo = function(i)
    -- name empty/nil (Ascension load flake); UnitName still has it
    return nil
end
_G._now = 6000
ok = RoleCheck.StartCheck()
check("start with nil roster names", ok == true)
handled = RoleCheck.HandleWhisper("Alice", "dps")
check("UnitName fallback membership", handled == true, tostring(handled))
check("alice dps via UnitName", Slots.GetAssigned("Alice") == "dps")

local st = RoleCheck.GetStatus()
check("status canWarn", st.canWarn == true)
check("status hosting", st.hosting == true)
check("status lastStart", type(st.lastStart) == "string" and st.lastStart:find("started", 1, true) ~= nil)

-- Solo (no group): StartCheck still opens window + yell
RoleCheck._ResetForTests()
db.mode = "hosting"
db.fullAutoHosting = false
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitIsPartyLeader = function() return false end
_G.IsRaidLeader = function() return false end
_G._lastRW = nil
_G._now = 7000
_G.SendChatMessage = function(msg, ch)
    _G._lastRW = { msg = msg, ch = ch }
end
ok, reason = RoleCheck.StartCheck()
check("solo start ok", ok == true, tostring(reason))
check("solo yells", _G._lastRW and _G._lastRW.ch == "YELL", tostring(_G._lastRW and _G._lastRW.ch))

--------------------------------------------------------------------
-- Regression: passive group-chat role detection (no active Role Check
-- required). Reported live: "Thapuckyman" replied "heal" in raid chat
-- ([R]) well outside any formal role-check window — players often just
-- say their role whenever it occurs to them, not right after an RW.
--------------------------------------------------------------------
db.mode = "hosting"
db.fullAutoHosting = false
Slots.ClearAll()
RoleCheck._ResetForTests()
_G.GetNumRaidMembers = function() return 3 end
_G.GetRaidRosterInfo = function(i)
    return ({ "Host", "Alice", "Thapuckyman" })[i]
end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    if u == "raid1" then return "Host" end
    if u == "raid2" then return "Alice" end
    if u == "raid3" then return "Thapuckyman" end
    return nil
end
check("no active role check right now", RoleCheck.IsActive() == false)

local passiveOk, passiveRole = RoleCheck.HandlePassiveGroupChat("Thapuckyman", "heal")
check("passive raid-chat 'heal' recognized without active role check",
    passiveOk == true and passiveRole == "healer", tostring(passiveRole))
check("passive reply assigned via Slots", Slots.GetAssigned("Thapuckyman") == "healer",
    tostring(Slots.GetAssigned("Thapuckyman")))

-- Exact-only: a full sentence merely mentioning "heal" must NOT match —
-- this runs continuously (not window-gated), so it must stay conservative.
Slots.ClearAll()
local sentenceOk = RoleCheck.HandlePassiveGroupChat("Thapuckyman", "was dyslexic not perma afk ?")
check("unrelated raid chat is not misread as a role", sentenceOk == false, tostring(sentenceOk))
local sentenceOk2 = RoleCheck.HandlePassiveGroupChat("Thapuckyman", "that fight needs more heal players")
check("mid-sentence 'heal' mention does not match (exact-only)", sentenceOk2 == false, tostring(sentenceOk2))
check("no false-positive assignment", Slots.GetAssigned("Thapuckyman") == nil,
    tostring(Slots.GetAssigned("Thapuckyman")))

-- Not a group member: no match, no assignment.
local strangerOk = RoleCheck.HandlePassiveGroupChat("SomeRandomPerson", "dps")
check("non-group-member raid chat ignored", strangerOk == false, tostring(strangerOk))

--------------------------------------------------------------------
-- Regression (v0.4.131): RoleCheck.Resync() rebuilds the whole assignment
-- map via Slots.ClearAll() + re-Assign(). Aura is its own table now, so
-- without SnapshotAuraFlags() being carried across that ClearAll every
-- single Role Check would silently wipe the raid's entire aura coverage.
--------------------------------------------------------------------
_G.GetNumRaidMembers = function() return 3 end
_G.GetRaidRosterInfo = function(i)
    return ({ "Host", "Alice", "Bob" })[i]
end
_G.UnitName = function(u)
    if u == "player" or u == "raid1" then return "Host" end
    if u == "raid2" then return "Alice" end
    if u == "raid3" then return "Bob" end
    return nil
end
_G._now = 9000

RoleCheck._ResetForTests()
Slots.ClearAll()
Slots.Assign("Host", "tank")
Slots.Assign("Alice", "healer", nil, true) -- healer WITH an aura
Slots.Assign("Bob", "dps", nil, true)      -- dps WITH an aura
check("pre-resync: aura coverage is 2", Slots.CountAura() == 2, tostring(Slots.CountAura()))

RoleCheck.Resync()

check("resync keeps Alice's healer seat", Slots.GetAssigned("Alice") == "healer",
    tostring(Slots.GetAssigned("Alice")))
check("resync keeps Bob's dps seat", Slots.GetAssigned("Bob") == "dps",
    tostring(Slots.GetAssigned("Bob")))
check("resync preserves Alice's aura tag", Slots.HasAura("Alice") == true)
check("resync preserves Bob's aura tag", Slots.HasAura("Bob") == true)
check("resync does not invent an aura tag for the tank", Slots.HasAura("Host") == false)
check("post-resync: aura coverage still 2", Slots.CountAura() == 2, tostring(Slots.CountAura()))

if failed > 0 then
    io.stderr:write(string.format("test_rolecheck: %d failed, %d passed\n", failed, passed))
    os.exit(1)
end
print(string.format("test_rolecheck: %d passed", passed))
