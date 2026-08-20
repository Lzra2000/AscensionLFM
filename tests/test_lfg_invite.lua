-- AscensionLFM: tests/test_lfg_invite.lua
-- Hosting auto-invite of public LFG MS seekers.

package.path = "./?.lua;./core/?.lua;./tests/?.lua;" .. (package.path or "")

-- Minimal WoW stubs
_G.AscensionLFMDB = nil
GetTime = function() return 100 end
InviteUnit = function(name) _G._lastInvite = name; return true end
IsIgnored = function() return false end
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
IsPartyLeader = function() return true end
IsRaidLeader = function() return true end
IsRaidOfficer = function() return false end
UnitName = function() return "Host" end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Activity.lua")
dofile("core/Queue.lua")
dofile("core/Invite.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
local Slots = AscensionLFM.Slots
db.mode = "hosting"
db.autoInvite = true
db.autoInviteLfg = true
db.lfgInviteWithoutRole = false
db.roles = { tank = true, healer = true, aura = false, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
db.assignedRoles = {}
db.inviteCooldown = 0

local passed, failed = 0, 0
local function check(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end

AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
local p = AscensionLFM.Parser.Parse("LFG MS tank")
check("parse lfg tank", p and p.isManastormLFG)
local ok, reason = AscensionLFM.Invite.TryLfgInvite("SeekerOne", "LFG MS tank", p)
check("invite lfg tank", ok == true)
check("InviteUnit called", _G._lastInvite == "SeekerOne")

AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
db.autoInviteLfg = false
ok, reason = AscensionLFM.Invite.TryLfgInvite("SeekerTwo", "LFG MS dps", AscensionLFM.Parser.Parse("LFG MS dps"))
check("lfg invite off blocks", ok == false and reason == "lfg invite off")

db.autoInviteLfg = true
db.mode = "seeking"
AscensionLFM.Invite._ResetCooldowns()
ok = AscensionLFM.Invite.TryLfgInvite("SeekerThree", "LFG MS dps", AscensionLFM.Parser.Parse("LFG MS dps"))
check("seeking mode does not lfg-invite", ok == false)

db.mode = "hosting"
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
ok, reason = AscensionLFM.Invite.TryLfgInvite("SeekerFour", "LFG MS", AscensionLFM.Parser.Parse("LFG MS"))
check("lfg without role denied", ok == false)

-- Glued MS15 heal LFG
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
Slots.ClearAll()
local pHeal = AscensionLFM.Parser.Parse("Heal lfg MS15")
check("parse Heal lfg MS15", pHeal and pHeal.isManastormLFG)
ok, reason = AscensionLFM.Invite.TryLfgInvite("HealerFive", "Heal lfg MS15", pHeal)
check("invite Heal lfg MS15", ok == true)
check("healer invited", _G._lastInvite == "HealerFive")

-- Last seats + a support applicant already waiting: prefer support over DPS.
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
Slots.ClearAll()
if AscensionLFM.Queue and AscensionLFM.Queue.Clear then
    AscensionLFM.Queue.Clear()
end
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.maxPartySize = 15
GetNumRaidMembers = function() return 14 end
AscensionLFM.Queue.Push("WaitingTank", "tank", "LFG MS tank", "pending")
ok, reason = AscensionLFM.Invite.TryLfgInvite("DpsSix", "LFG MS DPS", AscensionLFM.Parser.Parse("LFG MS DPS"))
check("last seat blocks dps when support is waiting", ok == false and reason == "prefer support seat",
    tostring(reason))

-- Same near-full situation but nobody is actually waiting for a support
-- role: the seat would otherwise sit empty forever, so DPS gets invited
-- normally instead of being held back for a support applicant who may
-- never come.
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
Slots.ClearAll()
AscensionLFM.Queue.Clear()
ok, reason = AscensionLFM.Invite.TryLfgInvite("DpsSeven", "LFG MS DPS", AscensionLFM.Parser.Parse("LFG MS DPS"))
check("last seat invites dps when nobody is waiting for support", ok == true, tostring(reason))
GetNumRaidMembers = function() return 0 end

-- Full Auto enables autoInviteLfg
db.autoInviteLfg = false
AscensionLFM.Database.SetFullAutoHosting(true)
check("full auto sets autoInviteLfg", db.autoInviteLfg == true)
AscensionLFM.Database.SetFullAutoHosting(false)
check("full auto off clears autoInviteLfg", db.autoInviteLfg == false)

-- Regression: pause LFG-chat auto-invite/reply while inside an instance —
-- General/Trade still relays OTHER unrelated players' own "LFG MS" posts
-- while you're already in your own Manastorm, and replying to them (invite
-- or reject) reads as a bizarre unprompted DM to someone who never actually
-- applied to your group. Direct whispers (TryHostInvite) are unaffected.
db.autoInvite = true
db.autoInviteLfg = true
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
Slots.ClearAll()
_G.IsInInstance = function() return true, "party" end
ok, reason = AscensionLFM.Invite.TryLfgInvite("StrangerOutside", "LFG MS tank",
    AscensionLFM.Parser.Parse("LFG MS tank"))
check("lfg invite paused while in instance", ok == false and reason == "in instance", tostring(reason))
check("no invite sent while in instance", _G._lastInvite == nil)

_G.IsInInstance = function() return false, "none" end
AscensionLFM.Invite._ResetCooldowns()
_G._lastInvite = nil
Slots.ClearAll()
ok, reason = AscensionLFM.Invite.TryLfgInvite("StrangerOutside2", "LFG MS tank",
    AscensionLFM.Parser.Parse("LFG MS tank"))
check("lfg invite works again outside instance", ok == true, tostring(reason))
_G.IsInInstance = nil

print(string.format("lfg invite tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
