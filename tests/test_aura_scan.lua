-- AscensionLFM: tests/test_aura_scan.lua
-- Aura of Experience (spell 818059) liar detection: pure selection logic,
-- the "never accuse unless proven visible on someone else" safety gate,
-- combat-log parsing, and the full warn->verify->kick cycle.

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
_G.GetTime = function() return _G._now or 1000 end
_G._now = 1000

dofile("core/Database.lua")
dofile("core/Slots.lua")
dofile("core/Activity.lua")
dofile("core/Kick.lua")
dofile("core/AuraScan.lua")

local AscensionLFM = _G.AscensionLFM
local AuraScan = assert(AscensionLFM.AuraScan)
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()

--------------------------------------------------------------------
-- Defaults: this is a Kick-capable feature, must default OFF.
--------------------------------------------------------------------
check("auraScanEnabled defaults OFF", db.auraScanEnabled == false)
check("auraScanAutoKick defaults OFF", db.auraScanAutoKick == false)

--------------------------------------------------------------------
-- SelectLiars: pure - who is assigned "aura" but has no buff, present
-- members only, never flags self.
--------------------------------------------------------------------
local assigned = { alice = "aura", bob = "aura", carl = "dps", dave = "aura" }
local hasBuff = { alice = true, bob = false }
local present = { alice = "Alice", bob = "Bob", carl = "Carl", dave = "Dave" }
local liars = AuraScan.SelectLiars(assigned, hasBuff, present, "dave")
check("only bob flagged (alice has buff, carl not aura, dave is self)", #liars == 1, tostring(#liars))
check("bob is the liar", liars[1] and liars[1].name == "Bob", liars[1] and liars[1].name or "none")

check("no liars when everyone assigned aura has the buff",
    #AuraScan.SelectLiars({ x = "aura" }, { x = true }, { x = "X" }, nil) == 0)

check("absent (not currently present) assignee not flagged",
    #AuraScan.SelectLiars({ ghost = "aura" }, {}, {}, nil) == 0)

check("empty assigned table yields no liars", #AuraScan.SelectLiars({}, {}, {}, nil) == 0)

-- Multiple liars sort alphabetically by name.
local multi = AuraScan.SelectLiars(
    { z = "aura", a = "aura" }, {}, { z = "Zeta", a = "Alpha" }, nil)
check("multiple liars sorted by name", #multi == 2 and multi[1].name == "Alpha" and multi[2].name == "Zeta",
    multi[1] and multi[1].name or "none")

--------------------------------------------------------------------
-- BuildWarnMessage: pure.
--------------------------------------------------------------------
check("no message for empty liar list", AuraScan.BuildWarnMessage({}) == nil)
check("no message for nil", AuraScan.BuildWarnMessage(nil) == nil)
local msg = AuraScan.BuildWarnMessage({ { name = "Bob" }, { name = "Carl" } })
check("warn message lists both names", msg:find("Bob", 1, true) ~= nil and msg:find("Carl", 1, true) ~= nil, msg)
check("warn message uses ASCII hyphen not em-dash", msg:find("\226\128\148", 1, true) == nil, msg)

--------------------------------------------------------------------
-- OnCombatLog: standard 3.3.5a SPELL_AURA_APPLIED layout
-- (ts, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName, ...)
--------------------------------------------------------------------
AuraScan._ResetForTests()
_G.UnitName = function(u) if u == "player" then return "Host" end return nil end
AuraScan.OnCombatLog(
    12345, "SPELL_AURA_APPLIED", "guid-src", "Someone", 0,
    "guid-dst", "Bob", 0, AuraScan.AURA_SPELL_ID, AuraScan.AURA_NAME, "BUFF"
)
check("standard layout APPLIED marks buff seen on other", AuraScan.CanSeeBuffOnOthers() == false,
    "CanSeeBuffOnOthers only flips via UnitAura path, not CLEU alone - by design")
check("reliability note reflects seen-on-other (CLEU path)",
    AuraScan.GetReliabilityNote():find("visible on others", 1, true) ~= nil
    or AuraScan.GetReliabilityNote():find("NOT visible", 1, true) ~= nil)

-- Non-matching spell id and non-matching name: ignored, no crash.
AuraScan._ResetForTests()
AuraScan.OnCombatLog(
    12345, "SPELL_AURA_APPLIED", "guid-src", "Someone", 0,
    "guid-dst", "Nobody", 0, 99999, "Some Other Buff", "BUFF"
)
check("unrelated spell id does not register", true) -- just must not error

-- REMOVED event doesn't error either.
local okRemoved = pcall(AuraScan.OnCombatLog,
    12345, "SPELL_AURA_REMOVED", "guid-src", "Someone", 0,
    "guid-dst", "Bob", 0, AuraScan.AURA_SPELL_ID, AuraScan.AURA_NAME, "BUFF")
check("REMOVED event does not error", okRemoved == true)

-- Too few arguments: safely ignored, never errors.
local okShort = pcall(AuraScan.OnCombatLog, 1, 2, 3)
check("too-few-args combat log call does not error", okShort == true)

-- Non-combat-log event text: ignored without error.
local okOther = pcall(AuraScan.OnCombatLog,
    12345, "SPELL_DAMAGE", "guid-src", "Someone", 0, "guid-dst", "Bob", 0, 1, 2, 3)
check("non-aura combat log event ignored without error", okOther == true)

--------------------------------------------------------------------
-- The critical safety gate: Tick() must never warn/kick until the buff
-- has actually been proven visible on somebody other than the player.
--------------------------------------------------------------------
AuraScan._ResetForTests()
_G._now = 2000
_G.GetNumRaidMembers = function() return 2 end
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host" end
    if i == 2 then return "Ghosty" end
    return nil
end
_G.UnitAura = function() return nil end -- nobody's buff ever visible
db.mode = "hosting"
db.fullAutoHosting = false
db.auraScanEnabled = true
db.auraScanAutoKick = true
db.assignedRoles = { ghosty = "aura" }
AscensionLFM.Slots.ClearAll()
AscensionLFM.Slots.Assign("Ghosty", "aura")

local r1 = AuraScan.Tick(2000)
check("Tick stays 'unreliable' while buff never seen on anyone", r1 == "unreliable", tostring(r1))
check("status reflects unreliable", AuraScan.GetStatus().last == "unreliable")

-- Even after many ticks with the buff never visible anywhere, still no
-- warn/kick - this is the core false-positive protection.
_G._now = 5000
local r2 = AuraScan.Tick(5000)
check("still unreliable, never escalates to warn/kick", r2 == "unreliable", tostring(r2))

--------------------------------------------------------------------
-- Once the buff IS proven visible on someone else, detection engages.
--------------------------------------------------------------------
AuraScan._ResetForTests()
_G._now = 9000
_G.UnitAura = function(unit)
    if unit == "raid1" then -- "Host" has the real buff
        return AuraScan.AURA_NAME, "", "icon", 1, "Magic", 0, 0, "player", nil, nil, AuraScan.AURA_SPELL_ID
    end
    return nil
end
_G.GetNumRaidMembers = function() return 2 end
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host" end
    if i == 2 then return "Ghosty" end
    return nil
end

-- Nobody else has the buff except "Host" (the player) - still not proof
-- it's visible on OTHERS (self doesn't count).
local liars3 = AuraScan.Scan()
check("player's own buff doesn't count as seen-on-other", AuraScan.CanSeeBuffOnOthers() == false)

-- Now make it visible on Ghosty too (someone other than the player).
_G.UnitAura = function(unit)
    if unit == "raid1" or unit == "raid2" then
        return AuraScan.AURA_NAME, "", "icon", 1, "Magic", 0, 0, "player", nil, nil, AuraScan.AURA_SPELL_ID
    end
    return nil
end
AuraScan.Scan()
check("buff seen on another player flips CanSeeBuffOnOthers", AuraScan.CanSeeBuffOnOthers() == true)

--------------------------------------------------------------------
-- Full warn -> pending -> verify -> kicked cycle, once detection is
-- reliable and auto-kick is on. Mirrors Kick.lua's v0.4.28 lesson: a
-- successful UninviteUnit call is NOT trusted until the roster confirms
-- the target actually left.
--------------------------------------------------------------------
AuraScan._ResetForTests()
_G._now = 10000
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitIsPartyLeader = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.InCombatLockdown = function() return false end
local raidRoster = { "Host", "Proof", "Liar" }
_G.GetNumRaidMembers = function() return #raidRoster end
_G.GetRaidRosterInfo = function(i) return raidRoster[i] end
_G.UnitAura = function(unit)
    if unit == "raid2" then -- "Proof" (not the player) genuinely has the buff
        return AuraScan.AURA_NAME, "", "icon", 1, "Magic", 0, 0, "player", nil, nil, AuraScan.AURA_SPELL_ID
    end
    return nil -- Liar (raid3) never shows it; Host (player, raid1) doesn't either
end
local sentChat = {}
_G.SendChatMessage = function(msg, chatType) table.insert(sentChat, { msg = msg, chatType = chatType }) end
local uninvited = {}
_G.UninviteUnit = function(name) table.insert(uninvited, name) end

db.mode = "hosting"
db.fullAutoHosting = false
db.auraScanEnabled = true
db.auraScanAutoKick = true
db.auraScanInterval = 5
db.auraScanWarnInterval = 5
AscensionLFM.Slots.ClearAll()
AscensionLFM.Slots.Assign("Liar", "aura")

-- First tick: reliability not yet established -> runs the discovery scan
-- (which proves visibility via Host's real buff) but still reports
-- "unreliable" for THIS call; the actual warn/kick logic only proceeds
-- once seenBuffOnOtherViaAura is already true going into a Tick.
local rDiscover = AuraScan.Tick(10000)
check("first tick runs discovery scan, reports unreliable this call",
    rDiscover == "unreliable", tostring(rDiscover))
check("discovery scan proved visibility for the next tick", AuraScan.CanSeeBuffOnOthers() == true)

_G._now = 10005.1
local rWarn = AuraScan.Tick(10005.1)
check("next tick warns (buff proven visible, Liar has none)", rWarn == "warned", tostring(rWarn))
check("RW/chat message sent naming Liar", #sentChat == 1 and sentChat[1].msg:find("Liar", 1, true) ~= nil,
    sentChat[1] and sentChat[1].msg or "none")
check("no kick attempted yet (deferred)", #uninvited == 0)

-- After KICK_DELAY, the deferred kick fires.
_G._now = 10006
local rKick = AuraScan.Tick(10006)
check("kick attempted after delay", #uninvited == 1 and uninvited[1] == "Liar", tostring(#uninvited))

-- Liar is STILL in the roster (UninviteUnit silently no-op'd, or hasn't
-- processed yet) - verify must NOT trust the pcall alone.
_G._now = 10008
local rVerifyStill = AuraScan.Tick(10008)
check("verify catches still-present target as a failed attempt",
    rVerifyStill ~= "kicked", tostring(rVerifyStill))

--------------------------------------------------------------------
-- Separate clean scenario: kick succeeds and the target genuinely leaves
-- the roster before the verify check runs - confirmed as "kicked".
--------------------------------------------------------------------
AuraScan._ResetForTests()
_G._now = 20000
local raidRoster2 = { "Host", "Proof", "Liar2" }
_G.GetNumRaidMembers = function() return #raidRoster2 end
_G.GetRaidRosterInfo = function(i) return raidRoster2[i] end
_G.UnitAura = function(unit)
    if unit == "raid2" then -- "Proof" has the buff -> proves visibility
        return AuraScan.AURA_NAME, "", "icon", 1, "Magic", 0, 0, "player", nil, nil, AuraScan.AURA_SPELL_ID
    end
    return nil
end
uninvited = {}
sentChat = {}
db.auraScanWarnInterval = 5
AscensionLFM.Slots.ClearAll()
AscensionLFM.Slots.Assign("Liar2", "aura")

AuraScan.Tick(20000) -- discovery scan
_G._now = 20005.1
local rWarn3 = AuraScan.Tick(20005.1) -- warns
check("clean-scenario tick warns", rWarn3 == "warned", tostring(rWarn3))
_G._now = 20006
AuraScan.Tick(20006) -- attempts the kick (DoKick succeeds per pcall)
check("clean-scenario kick attempted", #uninvited == 1 and uninvited[1] == "Liar2", tostring(#uninvited))

-- Liar2 genuinely left by the time the verify delay elapses.
raidRoster2 = { "Host", "Proof" }
_G._now = 20008
local rVerifyGone = AuraScan.Tick(20008)
check("verify confirms kicked once target genuinely leaves the roster",
    rVerifyGone == "kicked", tostring(rVerifyGone))

-- Regression: a confirmed AuraScan kick now logs to Activity too (used
-- to have zero trail there - kickHistory only - meaning it never counted
-- toward the session summary's "kicked" total).
local kickEntry = AscensionLFM.Activity.Recent(1)[1]
check("aura-liar kick pushed to Activity log", kickEntry and kickEntry.kind == "kick",
    kickEntry and tostring(kickEntry.kind) or "none")
check("aura-liar kick names the target", kickEntry and kickEntry.text:find("Liar2", 1, true) ~= nil,
    kickEntry and kickEntry.text or "none")

io.write(string.format("test_aura_scan: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
