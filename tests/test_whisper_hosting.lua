-- AscensionLFM: Scanner hosting whisper → auto-invite regression (Full Auto path).
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

_G.GetNumPartyMembers = function() return 0 end
_G.GetNumRaidMembers = function() return 0 end
_G.IsPartyLeader = function() return true end
_G.IsRaidLeader = function() return false end
_G.IsRaidOfficer = function() return false end
_G.IsIgnored = function() return false end
_G.GetTime = function() return 1000 end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    return nil
end
local invited = {}
_G.InviteUnit = function(name)
    table.insert(invited, name)
end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Activity.lua")
dofile("core/Reject.lua")
dofile("core/Queue.lua")
dofile("core/Invite.lua")
dofile("core/RoleCheck.lua")
dofile("core/Scanner.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
local Scanner = AscensionLFM.Scanner
local Invite = AscensionLFM.Invite
local RoleCheck = AscensionLFM.RoleCheck
local Slots = AscensionLFM.Slots

local failed, passed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

-- Full Auto ON: heal whisper must invite (not role-filtered)
AscensionLFM.Database.SetFullAutoHosting(true)
db.inviteCooldown = 0
db.maxPartySize = 15
Slots.ClearAll()
Invite._ResetCooldowns()
invited = {}
Scanner._HandleWhisper("HealBob", "heal")
check("scanner heal invite", invited[1] == "HealBob", invited[1] or "none")
check("scanner heal role", Slots.GetAssigned("HealBob") == "healer")

-- Letter H fallback via Scanner path
Invite._ResetCooldowns()
invited = {}
Scanner._HandleWhisper("LetterH", "H")
check("scanner letter H invite", invited[1] == "LetterH", invited[1] or "none")

-- Role Check active: stranger still invites; group member consumed
_G.GetNumRaidMembers = function() return 2 end
_G.IsRaidLeader = function() return true end
_G.GetRaidRosterInfo = function(i)
    return ({ "Host", "Alice" })[i]
end
_G.SendChatMessage = function() end
_G.CreateFrame = function()
    return { SetScript = function() end }
end
RoleCheck._ResetForTests()
RoleCheck.StartCheck(2000)
Invite._ResetCooldowns()
invited = {}
Scanner._HandleWhisper("Stranger", "tank")
check("RC active stranger invites", invited[1] == "Stranger", invited[1] or "none")
invited = {}
Scanner._HandleWhisper("Alice", "heal")
check("RC active member not invited", invited[1] == nil)

-- Party/raid chat role reply during Role Check (common after RW)
_G.GetRaidRosterInfo = function(i)
    return ({ "Host", "Alice" })[i]
end
RoleCheck._ResetForTests()
RoleCheck.StartCheck(3000)
invited = {}
check("group chat event detect", Scanner._IsGroupChatEvent("CHAT_MSG_PARTY") == true)
check("party role reply consumed", Scanner._TryRoleCheckReply("Alice", "tank") == true)
check("alice tank from party chat", Slots.GetAssigned("Alice") == "tank")
check("party reply not invited", invited[1] == nil)

-- Passive group-chat detection (no active Role Check): "heal" in raid
-- chat, well outside any role-check window.
RoleCheck._ResetForTests()
check("no active role check", RoleCheck.IsActive() == false)
db.mode = "hosting"
db.passiveRoleDetect = true
Slots.ClearAll()
check("passive wrapper picks it up",
    Scanner._TryPassiveGroupRoleReply("Alice", "heal") == true)
check("alice healer via passive raid chat", Slots.GetAssigned("Alice") == "healer",
    tostring(Slots.GetAssigned("Alice")))

-- Toggle off: passiveRoleDetect=false disables it entirely.
Slots.ClearAll()
db.passiveRoleDetect = false
check("passive detection disabled via toggle",
    Scanner._TryPassiveGroupRoleReply("Alice", "heal") == false)
check("no assignment while toggle is off", Slots.GetAssigned("Alice") == nil,
    tostring(Slots.GetAssigned("Alice")))
db.passiveRoleDetect = true

io.write(string.format("test_whisper_hosting: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
