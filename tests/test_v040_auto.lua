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
check("not rejectable global cooldown", Reject.IsRejectableReason("global cooldown") == false)
-- Regression: "prefer support seat" (v0.4.19) was a real, understood block
-- reason (a dps applicant recognized but deliberately held back for the
-- last open seats) but was missing from REJECTABLE, so those applicants
-- got silently dropped with zero feedback — unlike "slot full"/"role
-- filtered" which correctly get an auto-reply.
check("rejectable prefer support seat", Reject.IsRejectableReason("prefer support seat") == true)

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
check("builtin MS 2/3/3/10 listed", names[1] == "MS 2/3/3/10")
db.slotMax = { tank = 1, healer = 1, aura = 1, dps = 1 }
db.maxPartySize = 5
ok = Presets.Load("MS 2/3/3/10")
check("load preset ok", ok == true)
check("preset tank 2", db.slotMax.tank == 2)
check("preset healer 3", db.slotMax.healer == 3)
check("preset aura 3", db.slotMax.aura == 3)
-- v0.4.133: tank+healer+dps are the only SEATS and must sum to the raid
-- size, so the stock preset is 2+3+10 = 15. The aura 3 is a coverage
-- target riding on those seats, not a fourth block of seats.
check("preset dps 10 (seats sum to 15)", db.slotMax.dps == 10, tostring(db.slotMax.dps))
check("preset seats sum to maxPartySize",
    db.slotMax.tank + db.slotMax.healer + db.slotMax.dps == db.maxPartySize,
    string.format("%d+%d+%d vs %d", db.slotMax.tank, db.slotMax.healer,
        db.slotMax.dps, db.maxPartySize))
check("preset maxParty 15", db.maxPartySize == 15)

ok, why = Presets.Save("MS 2/3/3/10")
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
check("poster build still green", built == "LFM MS | 0/2 Tanks | 0/3 Healers | 0/3 Aura | 0/7 DPS", built)

db.mode = "hosting"
db.autoRepost = true
db.announceFull = true
db.fullAnnounceMessage = "LFM MS FULL — thanks!"
db.postChannel = "YELL"
db.maxPartySize = 15
Presets.Load("MS 2/3/3/10")
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)
-- v0.4.131: aura is a tag, so "full" means every SEAT cap is met and the
-- aura coverage target is reached by tagged members - not by seating three
-- people into a separate aura role that no longer exists.
for _, n in ipairs({ "a", "b" }) do Slots.Assign(n, "tank") end
for _, n in ipairs({ "c", "d", "e" }) do Slots.Assign(n, "healer") end
for i = 1, 7 do Slots.Assign("d" .. i, "dps") end
for _, n in ipairs({ "c", "d1", "d2" }) do Slots.SetAura(n, true) end
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

-- Favorite applicants (mirror image of leaderBlacklist)
check("favorite unset by default", AscensionLFM.Database.IsFavoriteApplicant("GoodPlayer") == false)
check("favorite add", AscensionLFM.Database.AddFavoriteApplicant("GoodPlayer") == true)
check("favorite hit", AscensionLFM.Database.IsFavoriteApplicant("GoodPlayer") == true)
check("favorite is case/realm insensitive", AscensionLFM.Database.IsFavoriteApplicant("goodplayer-Realmname") == true)
check("favorite add rejects empty name", AscensionLFM.Database.AddFavoriteApplicant("") == false)
AscensionLFM.Database.RemoveFavoriteApplicant("GoodPlayer")
check("favorite removed", AscensionLFM.Database.IsFavoriteApplicant("GoodPlayer") == false)

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

-- Regression/coverage: matchHistory entries now carry the parsed role
-- data too, not just the display text - the Log tab's "[NEEDS YOU]"
-- highlight (MainWindow.RefreshMatches -> Parser.NeedsAnyRole) depends on
-- this being present so it can tell whether a logged listing still needs
-- one of the player's own configured roles, without re-parsing the raw
-- text at render time.
db.roles = { tank = true, healer = false, aura = false, dps = false }
AscensionLFM.Scanner._HandlePublicListing("TankNeeded", "LFM MS need tank", "CHAT_MSG_SAY")
local topEntry = db.matchHistory[1]
check("matchHistory entry carries parsed roles data", topEntry and type(topEntry.roles) == "table",
    topEntry and type(topEntry.roles) or "none")
local neededByMe = topEntry and AscensionLFM.Parser.NeedsAnyRole({ roles = topEntry.roles }, db.roles)
check("NeedsAnyRole reads the stored roles data correctly", neededByMe == true, tostring(neededByMe))

--------------------------------------------------------------------
-- Seeking: auto-reply to a host's own follow-up questions (level, and
-- role+aura) after we already auto-whispered them — the Suriana-style
-- multi-step registration bot flow reported live.
--------------------------------------------------------------------
db.mode = "seeking"
db.fullAutoHosting = false
db.autoWhisper = true
db.whisperCooldown = 30
db.dedupeSeconds = 45
db.roles = { tank = false, healer = false, aura = true, dps = true }
db.whisperVariants = { "inv ms {role}" }
db.useWhisperVariants = false
db.whisperMessage = "inv ms {role}"
_G.UnitName = function(u) if u == "player" then return "Wildcard" end return nil end
_G.UnitLevel = function(u) if u == "player" then return 21 end return 0 end
local followSent = {}
_G.SendChatMessage = function(msg, chan, lang, target)
    table.insert(followSent, { msg = msg, chan = chan, target = target })
end
_G.IsIgnored = function() return false end
if AscensionLFM.Database and AscensionLFM.Database.IsLeaderBlacklisted then
    AscensionLFM.Database.IsLeaderBlacklisted = function() return false end
end

-- Step 1: Suriana posts an LFM, we auto-whisper to apply (seeds whisperSent)
followSent = {}
AscensionLFM.Scanner._HandlePublicListing("Suriana", "LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS", "CHAT_MSG_SAY")
check("seeking: applied to Suriana", #followSent == 1, tostring(#followSent))

-- Step 2: Suriana's bot whispers back asking for role+aura
followSent = {}
AscensionLFM.Scanner._HandleWhisper("Suriana", "Please whisper your role and aura as: Tank/Heal/DPS + Aura yes/no.")
check("seeking: role+aura auto-reply sent", #followSent == 1, tostring(#followSent))
check("seeking: role+aura reply content", followSent[1] and followSent[1].msg == "dps + aura yes",
    followSent[1] and followSent[1].msg or "none")

-- Step 3: Suriana's bot asks for level. Advance time past the new
-- FOLLOWUP_COOLDOWN (3s, added to prevent a chatty bot from causing
-- whisper spam across rapid-fire questions) so this second reply isn't
-- itself throttled.
_G.GetTime = function() return 1004 end
followSent = {}
AscensionLFM.Scanner._HandleWhisper("Suriana", "What level are you? Please reply with a number from 1 to 60.")
check("seeking: level auto-reply sent", #followSent == 1, tostring(#followSent))
check("seeking: level reply content", followSent[1] and followSent[1].msg == "21",
    followSent[1] and followSent[1].msg or "none")
_G.GetTime = function() return 1000 end

-- A stranger we never whispered asking the same question gets no reply —
-- avoids the exact "unsolicited auto-reply to someone unrelated" mistake
-- already fixed on the hosting side (v0.4.20).
followSent = {}
AscensionLFM.Scanner._HandleWhisper("RandomStranger", "What level are you?")
check("seeking: no reply to someone we never applied to", #followSent == 0, tostring(#followSent))

-- Regression: the bot's own CONFIRMATION message ("Registered as DPS -
-- Aura: Yes. Waiting for invite.") contains "Aura" as a whole word too —
-- must NOT trigger another unsolicited auto-reply back at it. Only real
-- questions (contain "?" or "please") should ever trigger a reply.
followSent = {}
AscensionLFM.Scanner._HandleWhisper("Suriana", "Registered as DPS - Aura: Yes. Waiting for invite.")
check("seeking: no reply to bot's own confirmation message", #followSent == 0, tostring(#followSent))

-- Regression: FOLLOWUP_COOLDOWN (3s) prevents replying to the same host
-- twice in rapid succession — guards against a chatty/looping bot causing
-- whisper spam. A second question landing within the cooldown window
-- gets no reply; the same question after the window elapses does.
-- (Stay within the outer 5-min whisperSent freshness window, seeded at
-- GetTime()=1000 back in Step 1 - only test the new inner 3s cooldown.)
_G.GetTime = function() return 1100 end
AscensionLFM.Scanner._HandleWhisper("Suriana", "What level are you?")
followSent = {}
AscensionLFM.Scanner._HandleWhisper("Suriana", "Please confirm your role?")
check("follow-up cooldown blocks a second reply within 3s", #followSent == 0, tostring(#followSent))
_G.GetTime = function() return 1104 end
followSent = {}
AscensionLFM.Scanner._HandleWhisper("Suriana", "Please confirm your role?")
check("follow-up reply allowed again once cooldown elapses", #followSent == 1, tostring(#followSent))
_G.GetTime = function() return 1000 end

--------------------------------------------------------------------
-- PARTY_INVITE_REQUEST context/auto-accept (db.autoAcceptInvite existed
-- as a saved setting for a long time but had no handler wired to it at
-- all - new Scanner.HandleInviteRequest closes that gap). Deliberately
-- scoped to only trust a recently-seen LFM leader, never a blind invite.
--------------------------------------------------------------------
local printed = {}
AscensionLFM.Print = function(msg) table.insert(printed, tostring(msg)) end
local accepted = 0
_G.AcceptGroup = function() accepted = accepted + 1 end

db.mode = "seeking"
db.autoAcceptInvite = false
_G.GetTime = function() return 2000 end
AscensionLFM.Scanner._HandlePublicListing("Questgiver", "LFM MS 0/2 Tanks", "CHAT_MSG_SAY")

printed = {}
AscensionLFM.Scanner._HandleInviteRequest("Questgiver")
check("invite context printed for a recently-seen LFM leader", #printed == 1, tostring(#printed))
check("invite context mentions their post", printed[1] and printed[1]:find("posted:", 1, true) ~= nil,
    printed[1])
check("autoAcceptInvite off: no accept called", accepted == 0, tostring(accepted))

db.autoAcceptInvite = true
printed = {}
AscensionLFM.Scanner._HandleInviteRequest("Questgiver")
check("autoAcceptInvite on: AcceptGroup called for a seen LFM leader", accepted == 1, tostring(accepted))

-- A stranger never seen posting anything gets no context and is never
-- auto-accepted, even with the setting on - this is the actual safety
-- scoping the feature is built around.
printed = {}
AscensionLFM.Scanner._HandleInviteRequest("TotalStranger")
check("no context for an unseen inviter", #printed == 0, tostring(#printed))
check("no auto-accept for an unseen inviter", accepted == 1, tostring(accepted)) -- unchanged

-- Recency window: a leader seen too long ago (past the 10 min window)
-- gets no context/accept either.
_G.GetTime = function() return 2601 end -- 601s later, just past the 600s window
printed = {}
AscensionLFM.Scanner._HandleInviteRequest("Questgiver")
check("stale LFM sighting (past window) gets no context", #printed == 0, tostring(#printed))
check("stale LFM sighting gets no auto-accept", accepted == 1, tostring(accepted)) -- unchanged
_G.GetTime = function() return 1000 end

io.write(string.format("test_v040_auto: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
