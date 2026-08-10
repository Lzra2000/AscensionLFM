-- AscensionLFM invite helper unit tests (mocked WoW APIs).
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

-- Mocks before loading modules
_G.GetNumPartyMembers = function() return 2 end -- 2 others => group size 3
_G.GetNumRaidMembers = function() return 0 end
_G.IsPartyLeader = function() return true end
_G.IsRaidLeader = function() return false end
_G.IsRaidOfficer = function() return false end
_G.IsIgnored = function() return false end
_G.GetTime = function() return 100 end
local invited = {}
_G.InviteUnit = function(name)
    table.insert(invited, name)
end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Invite.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
db.mode = "hosting"
db.autoInvite = true
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.maxPartySize = 15
db.inviteCooldown = 0
db.requireRoleWhisper = true
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }

local Invite = AscensionLFM.Invite
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

Slots.ClearAll()
check("group size includes player", Invite.GetGroupSize() == 3)
check("not full at 3/15", Invite.IsGroupFull(15) == false)

Invite._ResetCooldowns()
local ok = Invite.TryHostInvite("Bob", "inv ms tank")
check("host invite tank", ok == true)
check("InviteUnit called", invited[1] == "Bob")
check("tank assigned", Slots.GetAssigned("Bob") == "tank")
check("tank filled 1", Slots.CountFilled("tank") == 1)

Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("Ann", "aura ready")
check("aura accepted when role enabled", ok == true)
check("aura assigned", Slots.GetAssigned("Ann") == "aura")

Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("Carl", "inv ms heal")
check("host invite heal", ok == true)

Invite._ResetCooldowns()
invited = {}
Slots.ClearAll()
ok = Invite.TryHostInvite("Dana", "healers")
check("host invite healers plural", ok == true, tostring(ok))
check("healers → healer", Slots.GetAssigned("Dana") == "healer")

Invite._ResetCooldowns()
invited = {}
Slots.ClearAll()
ok = Invite.TryHostInvite("Eva", "H")
check("host invite letter H", ok == true, tostring(ok))
check("H → healer", Slots.GetAssigned("Eva") == "healer")

Invite._ResetCooldowns()
invited = {}
Slots.ClearAll()
ok = Invite.TryHostInvite("Fritz", "heiler")
check("host invite DE heiler", ok == true, tostring(ok))
check("heiler → healer", Slots.GetAssigned("Fritz") == "healer")

-- Slot full blocks invite
Slots.ClearAll()
Slots.Assign("T1", "tank")
Slots.Assign("T2", "tank")
check("tank slots full", Slots.HasOpenSlot("tank") == false)
Invite._ResetCooldowns()
invited = {}
local reason
ok, reason = Invite.TryHostInvite("T3", "tank")
check("slot full blocks", ok == false)
check("slot full reason", reason == "slot full")

-- Aura of Exp
Slots.ClearAll()
Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("AuraGuy", "Aura of Exp")
check("Aura of Exp invite", ok == true)
check("Aura of Exp role", Slots.GetAssigned("AuraGuy") == "aura")

-- No role = no blind invite
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("Quiet", "inv ms please")
check("no role denied", ok == false)
check("no role reason", reason == "no role" or reason == "no parse")

-- Role filtered
db.roles.dps = false
Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("DD", "dps")
check("dps filtered", ok == false)
db.roles.dps = true

_G.GetNumPartyMembers = function() return 14 end -- size 15
Invite._ResetCooldowns()
invited = {}
Slots.ClearAll()
ok, reason = Invite.TryHostInvite("Dana", "tank")
check("full party blocks", ok == false)
check("full reason", reason == "full")

_G.IsIgnored = function(name) return name == "Evil" end
_G.GetNumPartyMembers = function() return 1 end
Invite._ResetCooldowns()
ok = Invite.InvitePlayer("Evil")
check("ignore blocks invite", ok == false)

-- Reconcile leavers
local newMap, removed = Slots.ReconcileAssigned(
    { bob = "tank", ann = "healer", gone = "dps" },
    { bob = true, ann = true }
)
check("reconcile keeps bob", newMap.bob == "tank")
check("reconcile drops gone", newMap.gone == nil)
check("reconcile removed 1", removed == 1)

-- Last 1-2 seats prefer support over DPS — same policy as TryLfgInvite
-- (regression: this used to only apply to the LFG-chat path, not whispers)
_G.GetNumPartyMembers = function() return 0 end
_G.GetNumRaidMembers = function() return 14 end
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.maxPartySize = 15
Slots.ClearAll()
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("DpsWhisper", "dps")
check("whisper last seat blocks dps", ok == false and reason == "prefer support seat", tostring(reason))
check("whisper last seat did not invite", #invited == 0)

-- ... but if no support role is actually open, dps still gets invited
_G.IsRaidLeader = function() return true end
db.slotMax = { tank = 0, healer = 0, aura = 0, dps = 7 }
Slots.ClearAll()
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("DpsWhisperOk", "dps")
check("whisper last seat allows dps when no support open", ok == true, tostring(reason))
_G.IsRaidLeader = function() return false end
_G.GetNumRaidMembers = function() return 0 end

io.write(string.format("invite tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
