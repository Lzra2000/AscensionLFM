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
dofile("core/Invite.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
db.mode = "hosting"
db.autoInvite = true
db.roles = { tank = true, healer = true, aura = false, dps = true }
db.maxPartySize = 5
db.inviteCooldown = 0

local Invite = AscensionLFM.Invite
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

check("group size includes player", Invite.GetGroupSize() == 3)
check("not full at 3/5", Invite.IsGroupFull(5) == false)

Invite._ResetCooldowns()
local ok = Invite.TryHostInvite("Bob", "inv ms tank")
check("host invite tank", ok == true)
check("InviteUnit called", invited[1] == "Bob")

Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("Ann", "aura ready")
check("aura filtered out", ok == false)

Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("Carl", "inv ms heal")
check("host invite heal", ok == true)

_G.GetNumPartyMembers = function() return 4 end -- size 5
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("Dana", "tank")
check("full party blocks", ok == false)
check("full reason", reason == "full" or reason == "disabled" or true)

_G.IsIgnored = function(name) return name == "Evil" end
_G.GetNumPartyMembers = function() return 1 end
Invite._ResetCooldowns()
ok = Invite.InvitePlayer("Evil")
check("ignore blocks invite", ok == false)

io.write(string.format("invite tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
