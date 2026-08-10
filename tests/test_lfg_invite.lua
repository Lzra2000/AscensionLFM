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
UnitName = function() return "Host" end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Invite.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
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

-- Full Auto enables autoInviteLfg
db.autoInviteLfg = false
AscensionLFM.Database.SetFullAutoHosting(true)
check("full auto sets autoInviteLfg", db.autoInviteLfg == true)
AscensionLFM.Database.SetFullAutoHosting(false)
check("full auto off clears autoInviteLfg", db.autoInviteLfg == false)

print(string.format("lfg invite tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
