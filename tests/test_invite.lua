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
local whispersSent = {}
_G.SendChatMessage = function(msg, chan, lang, target)
    table.insert(whispersSent, { msg = msg, chan = chan, target = target })
end

dofile("core/Database.lua")
dofile("core/AscensionAPI.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")
dofile("core/Activity.lua")
dofile("core/Reject.lua")
dofile("core/Queue.lua")
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
-- v0.4.131: aura is a tag, not a seat - an aura-only signup takes a DPS
-- seat and carries the tag, instead of occupying an "aura slot".
check("aura-only signup seats as dps", Slots.GetAssigned("Ann") == "dps",
    tostring(Slots.GetAssigned("Ann")))
check("aura-only signup gets the aura tag", Slots.HasAura("Ann") == true)

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
check("Aura of Exp seats as dps", Slots.GetAssigned("AuraGuy") == "dps",
    tostring(Slots.GetAssigned("AuraGuy")))
check("Aura of Exp gets the aura tag", Slots.HasAura("AuraGuy") == true)

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
db.rejectRewhisper = true
if AscensionLFM.Reject and AscensionLFM.Reject._ResetForTests then
    AscensionLFM.Reject._ResetForTests()
end
whispersSent = {}
ok, reason = Invite.TryHostInvite("DpsWhisper", "dps")
check("whisper last seat blocks dps", ok == false and reason == "prefer support seat", tostring(reason))
check("whisper last seat did not invite", #invited == 0)
check("whisper last seat still gets an auto-reply (regression)", #whispersSent == 1, tostring(#whispersSent))

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

-- Regression: unrelated whispers ("no role"/"no parse") must NOT trigger an
-- automatic reject-rewhisper — that's what made the addon whisper a random
-- player "please whisper a role" after THEY whispered the host about
-- something unrelated, which reads as a bizarre unprompted reply.
db.rejectRewhisper = true
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
Invite._ResetCooldowns()
if AscensionLFM.Reject and AscensionLFM.Reject._ResetForTests then
    AscensionLFM.Reject._ResetForTests()
end
whispersSent = {}
ok, reason = Invite.TryHostInvite("Qoochi", "i didnt whisper you so dont whisper me XD")
check("unrelated whisper not invited", ok == false)
check("unrelated whisper reason is no-role/no-parse", reason == "no role" or reason == "no parse", tostring(reason))
check("unrelated whisper gets no auto-reply", #whispersSent == 0, whispersSent[1] and whispersSent[1].msg or "none")

-- ... but a genuine detected-and-unfulfillable request still auto-replies
db.roles = { tank = true, healer = false, aura = false, dps = false }
db.slotMax = { tank = 0, healer = 0, aura = 0, dps = 0 }
Slots.ClearAll()
Invite._ResetCooldowns()
if AscensionLFM.Reject and AscensionLFM.Reject._ResetForTests then
    AscensionLFM.Reject._ResetForTests()
end
whispersSent = {}
ok, reason = Invite.TryHostInvite("RealApplicant", "tank")
check("slot-full request still gets auto-reply", #whispersSent == 1, tostring(#whispersSent))
check("slot-full auto-reply mentions tank", whispersSent[1] and whispersSent[1].msg:find("tank", 1, true) ~= nil,
    whispersSent[1] and whispersSent[1].msg or "none")

db.roles.tank = true
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }

--------------------------------------------------------------------
-- Regression: a cooldown-blocked invite ("global cooldown"/"per-name
-- cooldown") must auto-retry once the cooldown passes, not silently drop
-- the applicant forever. Reported live: in a busy hosting session, a
-- genuinely acceptable tank/healer whisper got zero feedback (no invite,
-- no reject message — those cooldown reasons are deliberately NOT
-- rejectable, since replying to a transient internal throttle would be
-- misleading) whenever it landed within ~3s of another successful invite.
--------------------------------------------------------------------
Invite._ResetForTests()
Invite._ResetCooldowns()
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
db.inviteCooldown = 3
Slots.ClearAll()
_G.GetTime = function() return 9000 end
invited = {}
ok, reason = Invite.TryHostInvite("First", "tank")
check("retry-regress: first invite succeeds", ok == true, tostring(reason))
check("retry-regress: first invited", invited[1] == "First")

invited = {}
ok, reason = Invite.TryHostInvite("Second", "heal")
check("retry-regress: second hits global cooldown immediately", ok == false and reason == "global cooldown",
    tostring(reason))
check("retry-regress: second NOT invited yet", #invited == 0)
check("retry-regress: queued for retry", #Invite._GetPendingRetries() == 1,
    tostring(#Invite._GetPendingRetries()))

-- Ticking before the cooldown has elapsed does nothing yet.
local processedEarly = Invite.Tick(9001)
check("retry-regress: no early retry before cooldown elapses", processedEarly == 0, tostring(processedEarly))
check("retry-regress: still not invited", #invited == 0)

-- Once the cooldown (+buffer) has passed, the tick auto-retries and it
-- succeeds normally.
_G.GetTime = function() return 9003.3 end
local processed = Invite.Tick(9003.3)
check("retry-regress: tick processes the queued retry", processed == 1, tostring(processed))
check("retry-regress: second now invited automatically", invited[1] == "Second", tostring(invited[1]))
check("retry-regress: queue drained", #Invite._GetPendingRetries() == 0)

--------------------------------------------------------------------
-- New: retry queue gives up after MAX_RETRY_ATTEMPTS (3) instead of
-- retrying forever, and de-duplicates a CHAT_MSG event firing twice for
-- the same applicant before the first retry has executed.
--------------------------------------------------------------------
Invite._ResetForTests()
Invite._ResetCooldowns()
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
db.inviteCooldown = 3
Slots.ClearAll()
_G.GetTime = function() return 30000 end
invited = {}

ok, reason = Invite.TryHostInvite("First", "tank")
check("retry-cap: first invite succeeds", ok == true, tostring(reason))
invited = {}
ok, reason = Invite.TryHostInvite("Persistent", "heal")
check("retry-cap: second hits global cooldown, queued", ok == false and reason == "global cooldown",
    tostring(reason))
check("retry-cap: queued once", #Invite._GetPendingRetries() == 1)

-- Duplicate CHAT_MSG for the same applicant before the first retry has
-- fired must not add a second queued entry.
ok, reason = Invite.TryHostInvite("Persistent", "heal")
check("retry-cap: duplicate whisper does not double-queue", #Invite._GetPendingRetries() == 1,
    tostring(#Invite._GetPendingRetries()))

-- Keep re-triggering the same cooldown-blocked scenario on every retry
-- (simulate: Host keeps inviting someone else right before each retry
-- fires, so Persistent's retry itself always re-hits the cooldown) up to
-- the cap, then confirm it gives up rather than retrying a 4th time.
local now = 30000
for i = 1, 3 do
    now = now + 3.3
    _G.GetTime = function() return now end
    -- Re-arm the global cooldown right before Persistent's retry fires,
    -- so this retry attempt also fails and gets re-queued (or gives up).
    Invite.TryHostInvite("Blocker" .. i, "dps")
    Invite.Tick(now)
end
check("retry-cap: gives up after MAX_RETRY_ATTEMPTS, not queued forever",
    #Invite._GetPendingRetries() == 0, tostring(#Invite._GetPendingRetries()))
check("retry-cap: Persistent never actually got invited", invited[1] ~= "Persistent")

--------------------------------------------------------------------
-- New: auto-convert party->raid when about to grow past 5, so inviting
-- a 6th person while still a plain party (which WoW rejects client-side)
-- doesn't silently cap group size below the addon's own slotMax total.
--------------------------------------------------------------------
Invite._ResetCooldowns()
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
_G.GetTime = function() return 10000 end
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 4 end -- 4 others + you = full 5-person party
local convertCalled = 0
_G.ConvertToRaid = function() convertCalled = convertCalled + 1 end
invited = {}
ok, reason = Invite.TryHostInvite("SixthPerson", "dps")
check("convert: 6th invite still succeeds", ok == true, tostring(reason))
check("convert: ConvertToRaid called once", convertCalled == 1, tostring(convertCalled))
check("convert: sixth person invited", invited[1] == "SixthPerson", tostring(invited[1]))

-- Already in a raid: never calls ConvertToRaid again.
convertCalled = 0
_G.GetNumRaidMembers = function() return 6 end
_G.GetNumPartyMembers = function() return 0 end
Invite._ResetCooldowns()
invited = {}
ok = Invite.TryHostInvite("SeventhPerson", "dps")
check("convert: no-op once already a raid", convertCalled == 0, tostring(convertCalled))
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 2 end

--------------------------------------------------------------------
-- New: whisper-invite path (TryHostInvite) now pauses while the host is
-- inside the instance too, same as the LFG-scan path already did (v0.4.27)
-- - a fresh invite can't meaningfully join a run already underway.
-- db.pauseInviteInInstance (default true) lets a host opt back in.
--------------------------------------------------------------------
Invite._ResetCooldowns()
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
_G.IsInInstance = function() return true, "party" end
invited = {}
ok, reason = Invite.TryHostInvite("InsideApplicant", "dps")
check("whisper invite paused while host is in instance", ok == false and reason == "in instance",
    tostring(reason))
check("no invite sent while in instance", #invited == 0)

-- Toggle off: host explicitly wants whisper invites to keep working
-- inside the instance.
db.pauseInviteInInstance = false
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("InsideApplicant2", "dps")
check("toggle off allows whisper invite even in instance", ok == true, tostring(reason))
db.pauseInviteInInstance = true

-- Outside the instance again: works normally.
_G.IsInInstance = function() return false, "none" end
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("OutsideApplicant", "dps")
check("whisper invite works normally outside instance", ok == true, tostring(reason))
_G.IsInInstance = nil

--------------------------------------------------------------------
-- New: prefers C_Manastorm.IsInManastorm() (confirmed real via
-- Ascension's own client source) over the generic IsInInstance() - a
-- host in some unrelated instance (not Manastorm) should NOT have
-- hosting paused, and IsInManastorm() gives that precision.
--------------------------------------------------------------------
db.pauseInviteInInstance = true
_G.IsInInstance = function() return true, "party" end -- generic instance: true
_G.C_Manastorm = { IsInManastorm = function() return false end } -- but not Manastorm specifically
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("NotManastormApplicant", "dps")
check("C_Manastorm takes priority: unrelated instance does not pause", ok == true, tostring(reason))

_G.C_Manastorm = { IsInManastorm = function() return true end }
Invite._ResetCooldowns()
invited = {}
ok, reason = Invite.TryHostInvite("InManastormApplicant", "dps")
check("C_Manastorm takes priority: actual Manastorm does pause", ok == false and reason == "in instance",
    tostring(reason))

_G.C_Manastorm = nil
_G.IsInInstance = nil

--------------------------------------------------------------------
-- New: CHAT_MSG_SYSTEM invite-failure detection frees a slot immediately
-- instead of waiting out the 5s verify-delay fallback. Patterns confirmed
-- real via Ascension's own extracted client GlobalStrings.lua (enUS).
--------------------------------------------------------------------

check("parses ERR_ALREADY_IN_GROUP_S",
    select(1, Invite.ParseInviteFailure("Mighty is already in a group.")) == "Mighty")
check("parses ERR_ALREADY_IN_GROUP_S reason", select(2, Invite.ParseInviteFailure("Mighty is already in a group.")) == "already_in_group")
check("parses ERR_BAD_PLAYER_NAME_S",
    select(1, Invite.ParseInviteFailure("Cannot find player 'Doriofran'.")) == "Doriofran")
check("parses ERR_BAD_PLAYER_NAME_S reason",
    select(2, Invite.ParseInviteFailure("Cannot find player 'Doriofran'.")) == "not_found")
check("parses ERR_CHAT_PLAYER_NOT_FOUND_S",
    select(1, Invite.ParseInviteFailure("No player named 'Stingz' is currently playing.")) == "Stingz")
check("parses ERR_CHAT_PLAYER_NOT_FOUND_S reason",
    select(2, Invite.ParseInviteFailure("No player named 'Stingz' is currently playing.")) == "offline")
check("parses ERR_DECLINE_GROUP_S",
    select(1, Invite.ParseInviteFailure("Addicted declines your group invitation.")) == "Addicted")
check("parses ERR_DECLINE_GROUP_S reason",
    select(2, Invite.ParseInviteFailure("Addicted declines your group invitation.")) == "declined")
check("unrelated system text does not match", Invite.ParseInviteFailure("Looting changed to Group Loot.") == nil)
check("nil/empty input does not match", Invite.ParseInviteFailure(nil) == nil and Invite.ParseInviteFailure("") == nil)

-- Live path: an active invite's pendingInviteVerify entry is cleared and
-- the slot freed the instant the matching system message arrives -
-- before the 5s verify-delay would otherwise have caught it.
Invite._ResetForTests()
AscensionLFM.Slots.ClearAll()
Invite._ResetCooldowns()
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
invited = {}
local ok3 = Invite.InvitePlayer("Moltenuke", "dps")
check("invite sent for immediate-failure test", ok3 == true and invited[1] == "Moltenuke")
check("slot shows assigned right after invite", AscensionLFM.Slots.GetAssigned("Moltenuke") == "dps")

local printed = {}
AscensionLFM.Print = function(m) table.insert(printed, tostring(m)) end
local handled = Invite.HandleSystemMessage("Cannot find player 'Moltenuke'.")
check("system message recognized as this pending invite", handled == true)
check("slot freed immediately (not waiting for the 5s verify)",
    AscensionLFM.Slots.GetAssigned("Moltenuke") == nil)
local sawFreedMsg = false
for _, m in ipairs(printed) do
    if m:find("Moltenuke", 1, true) and m:find("slot freed", 1, true) then
        sawFreedMsg = true
    end
end
check("prints the specific failure reason", sawFreedMsg, table.concat(printed, " | "))

-- An unrelated name (nothing pending for them) is a harmless no-op.
local handled2 = Invite.HandleSystemMessage("Cannot find player 'NobodyWeInvited'.")
check("unrelated name is a no-op", handled2 == false)

io.write(string.format("invite tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
