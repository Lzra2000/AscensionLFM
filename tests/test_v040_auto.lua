-- AscensionLFM Reject + Queue + Full Auto + Presets unit tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

_G.GetNumPartyMembers = function() return 2 end
_G.GetNumRaidMembers = function() return 0 end
_G.IsPartyLeader = function() return true end
_G.IsRaidLeader = function() return false end
_G.IsRaidOfficer = function() return false end
_G.IsIgnored = function() return false end
_G.GetTime = function() return 1000 end
local invited = {}
_G.InviteUnit = function(name) table.insert(invited, name) end
local whispers = {}
_G.SendChatMessage = function(msg, ch, _, target)
    table.insert(whispers, { msg = msg, ch = ch, target = target })
end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Activity.lua")
dofile("core/Reject.lua")
dofile("core/Presets.lua")
dofile("core/Queue.lua")
dofile("core/Invite.lua")
dofile("core/Poster.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
local Reject = AscensionLFM.Reject
local Queue = AscensionLFM.Queue
local Presets = AscensionLFM.Presets
local Invite = AscensionLFM.Invite
local Slots = AscensionLFM.Slots
local Poster = AscensionLFM.Poster
local Activity = AscensionLFM.Activity

local failed, passed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

-- Defaults: Full Auto OFF, reject OFF, kick OFF
local defs = AscensionLFM.Database.Defaults()
check("default fullAutoHosting off", defs.fullAutoHosting == false)
check("default rejectRewhisper off", defs.rejectRewhisper == false)
check("default autoKick off", defs.autoKickLevel59 == false)
check("default announceFull off", defs.announceFull == false)
check("default soundOnMatch off", defs.soundOnMatch == false)
check("default useWhisperVariants on", defs.useWhisperVariants == true)
check("default whisperVariants 3", type(defs.whisperVariants) == "table" and #defs.whisperVariants == 3)

-- Template formatting
local msg = Reject.FormatTemplate("Sorry, {role} is full ({filled}/{max}).", "tank", 2, 2)
check("format template", msg == "Sorry, tank is full (2/2).", msg)
check("rejectable slot full", Reject.IsRejectableReason("slot full") == true)
check("rejectable full", Reject.IsRejectableReason("full") == true)
check("rejectable no role", Reject.IsRejectableReason("no role") == true)
check("rejectable role filtered", Reject.IsRejectableReason("role filtered") == true)
check("not rejectable cooldown", Reject.IsRejectableReason("per-name cooldown") == false)

-- Reject disabled by default
Reject._ResetForTests()
whispers = {}
db.rejectRewhisper = false
local ok, why = Reject.TryRewhisper("Bob", "slot full", "tank")
check("reject disabled", ok == false and why == "disabled")

-- Reject when enabled
db.rejectRewhisper = true
db.rejectCooldown = 5
db.rejectSessionIgnore = true
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.Assign("T1", "tank")
Slots.Assign("T2", "tank")
Reject._ResetForTests()
whispers = {}
ok, why = Reject.TryRewhisper("Bob", "slot full", "tank")
check("reject sends", ok == true, tostring(why))
check("reject whisper channel", whispers[1] and whispers[1].ch == "WHISPER")
check("reject target", whispers[1] and whispers[1].target == "Bob")
check("reject has filled/max", whispers[1] and tostring(whispers[1].msg):find("2/2", 1, true) ~= nil, whispers[1] and whispers[1].msg)
check("activity has reject", #(db.activityLog or {}) >= 1 and db.activityLog[1].kind == "reject")

-- Session ignore blocks second
ok, why = Reject.TryRewhisper("Bob", "slot full", "tank")
check("session ignore blocks", ok == false and why == "ignored", tostring(why))

-- Ignore list
Reject._ResetForTests()
Reject.AddIgnore("Evil")
ok = Reject.TryRewhisper("Evil", "full", "dps")
check("reject ignore list", ok == false)

-- Queue push + invite/reject
Queue.Clear()
Activity.Clear()
Reject._ResetForTests()
db.rejectRewhisper = true
Queue.Push("Ann", "healer", "inv ms heal", "pending")
local recent = Queue.Recent(5)
check("queue has ann", recent[1] and recent[1].name == "Ann")
check("queue role healer", recent[1].role == "healer")

invited = {}
Invite._ResetCooldowns()
db.mode = "hosting"
db.autoInvite = true
db.inviteCooldown = 0
db.maxPartySize = 15
Slots.ClearAll()
ok = Queue.Invite("Ann")
check("queue invite", ok == true)
check("queue invite called InviteUnit", invited[1] == "Ann")
check("queue status invited", Queue.Recent(1)[1].status == "invited")

-- Host invite slot-full triggers reject rewhisper
Reject._ResetForTests()
whispers = {}
Activity.Clear()
Queue.Clear()
db.rejectRewhisper = true
db.mode = "hosting"
db.autoInvite = true
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.requireRoleWhisper = true
Slots.ClearAll()
Slots.Assign("T1", "tank")
Slots.Assign("T2", "tank")
Invite._ResetCooldowns()
ok, why = Invite.TryHostInvite("T3", "tank")
check("host slot full", ok == false and why == "slot full", tostring(why))
check("host reject whispered", #whispers >= 1, tostring(#whispers))
check("queue blocked entry", Queue.Recent(1)[1] and Queue.Recent(1)[1].status == "blocked")

-- No role reject
Reject._ResetForTests()
whispers = {}
ok, why = Invite.TryHostInvite("Quiet", "inv ms please")
check("no role denied", ok == false)
check("no role reason", why == "no role" or why == "no parse", tostring(why))
check("no role reject whisper", #whispers >= 1)

-- Role filtered
Reject._ResetForTests()
whispers = {}
db.roles.dps = false
ok, why = Invite.TryHostInvite("DD", "dps")
check("role filtered", ok == false and why == "role filtered")
check("role filtered whisper", #whispers >= 1)
db.roles.dps = true

-- Full Auto wiring
db.fullAutoHosting = false
db.autoInvite = false
db.autoRepost = false
db.rejectRewhisper = false
db.mode = "notify"
AscensionLFM.Database.SetFullAutoHosting(true)
check("full auto sets hosting", db.mode == "hosting")
check("full auto invite on", db.autoInvite == true)
check("full auto repost on", db.autoRepost == true)
check("full auto reject on", db.rejectRewhisper == true)
check("full auto flag on", db.fullAutoHosting == true)
check("full auto accepts tank", db.roles.tank == true)
check("full auto accepts healer", db.roles.healer == true)
check("full auto accepts aura", db.roles.aura == true)
check("full auto accepts dps", db.roles.dps == true)

-- Whisper invites must work for heal/aura under Full Auto (not role-filtered)
db.roles.healer = false
db.roles.aura = false
AscensionLFM.Database.SetFullAutoHosting(true)
Invite._ResetCooldowns()
Slots.ClearAll()
invited = {}
local okHeal = Invite.TryHostInvite("HealBob", "heal")
check("full auto heal whisper invites", okHeal == true, tostring(okHeal))
Invite._ResetCooldowns()
_G.GetTime = function() return 2000 end
local okAura = Invite.TryHostInvite("AuraBob", "aura")
check("full auto aura whisper invites", okAura == true, tostring(okAura))
_G.GetTime = function() return 1000 end

AscensionLFM.Database.SetFullAutoHosting(false)
check("full auto off flag", db.fullAutoHosting == false)
check("full auto clears invite", db.autoInvite == false)
check("full auto clears repost", db.autoRepost == false)
check("full auto clears reject", db.rejectRewhisper == false)

-- Leaving hosting while full auto on clears master
AscensionLFM.Database.SetFullAutoHosting(true)
AscensionLFM.Database.SetMode("seeking")
check("mode seeking clears full auto", db.fullAutoHosting == false)
check("mode seeking clears repost", db.autoRepost == false)

-- Presets
local names = Presets.List()
check("builtin MS 2/3/3/7 listed", names[1] == "MS 2/3/3/7")
db.slotMax = { tank = 1, healer = 1, aura = 1, dps = 1 }
db.maxPartySize = 5
ok = Presets.Load("MS 2/3/3/7")
check("load preset ok", ok == true)
check("preset tank 2", db.slotMax.tank == 2)
check("preset healer 3", db.slotMax.healer == 3)
check("preset aura 3", db.slotMax.aura == 3)
check("preset dps 7", db.slotMax.dps == 7)
check("preset maxParty 15", db.maxPartySize == 15)

ok, why = Presets.Save("MS 2/3/3/7")
check("cannot overwrite builtin", ok == false)

db.slotMax.tank = 4
ok = Presets.Save("CustomRun")
check("save custom preset", ok == true)
db.slotMax.tank = 2
ok = Presets.Load("CustomRun")
check("load custom", ok == true and db.slotMax.tank == 4)

-- Poster still green: BuildMessage + stop-when-full
Poster._ResetForTests()
local built = Poster.BuildMessage({
    tank = { filled = 0, max = 2 },
    healer = { filled = 0, max = 3 },
    aura = { filled = 0, max = 3 },
    dps = { filled = 0, max = 7 },
})
check("poster build still green", built == "LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS", built)

db.mode = "hosting"
db.autoRepost = true
db.announceFull = true
db.fullAnnounceMessage = "LFM MS FULL — thanks!"
db.postChannel = "YELL"
db.maxPartySize = 15
Presets.Load("MS 2/3/3/7")
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)
for _, n in ipairs({ "a", "b" }) do Slots.Assign(n, "tank") end
for _, n in ipairs({ "c", "d", "e" }) do Slots.Assign(n, "healer") end
for _, n in ipairs({ "f", "g", "h" }) do Slots.Assign(n, "aura") end
for i = 1, 7 do Slots.Assign("d" .. i, "dps") end
AscensionLFM.Invite.GetGroupSize = function() return 10 end
whispers = {}
db.autoRepost = true -- Load preset may not touch this; ensure on
local status = Poster.Tick(5000)
check("poster stops full", status == "stopped: full" or status == "stopped: full (announced)", status)
check("poster cleared autoRepost", db.autoRepost == false)
check("full announce sent", #whispers >= 1 and tostring(whispers[1].msg):find("FULL", 1, true) ~= nil)

-- Leader blacklist
check("blacklist add", AscensionLFM.Database.AddLeaderBlacklist("SpamLord") == true)
check("blacklist hit", AscensionLFM.Database.IsLeaderBlacklisted("SpamLord") == true)
AscensionLFM.Database.RemoveLeaderBlacklist("SpamLord")
check("blacklist removed", AscensionLFM.Database.IsLeaderBlacklisted("SpamLord") == false)

-- Whisper variants rotation (Scanner helper)
dofile("core/Scanner.lua")
db.useWhisperVariants = true
db.whisperVariantIndex = 1
db.whisperVariants = { "inv ms {role}", "inv for ms as {role}", "ms {role} ready" }
local w1 = AscensionLFM.Scanner._NextWhisperMessage(db, "tank")
local w2 = AscensionLFM.Scanner._NextWhisperMessage(db, "tank")
local w3 = AscensionLFM.Scanner._NextWhisperMessage(db, "healer")
check("variant1", w1 == "inv ms tank", w1)
check("variant2", w2 == "inv for ms as tank", w2)
check("variant3", w3 == "ms healer ready", w3)
local w4 = AscensionLFM.Scanner._NextWhisperMessage(db, "dps")
check("variant wraps", w4 == "inv ms dps", w4)

-- Regression: hosting-mode LFG notify must respect db.roles acceptance, not
-- just HasOpenSlot — the specific-role branch used to skip the db.roles
-- check that the generic/ambiguous branch right below it already had,
-- so a disabled role (e.g. healer explicitly off) still logged LFG matches
-- for it as long as the slot cap technically had room.
db.mode = "hosting"
db.roles = { tank = true, healer = false, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
AscensionLFM.Slots.ClearAll()
local beforeCount = #db.matchHistory
AscensionLFM.Scanner._HandlePublicListing("DisabledRoleLeader", "LFG MS heal", "CHAT_MSG_SAY")
check("disabled role LFG not logged", #db.matchHistory == beforeCount, tostring(#db.matchHistory))

db.roles.healer = true
AscensionLFM.Scanner._HandlePublicListing("AcceptedRoleLeader", "LFG MS heal", "CHAT_MSG_SAY")
check("accepted role LFG still logged", #db.matchHistory == beforeCount + 1, tostring(#db.matchHistory))

io.write(string.format("test_v040_auto: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
