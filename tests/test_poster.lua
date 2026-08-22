-- AscensionLFM Poster unit tests: message builder, stop-when-full, interval clamp.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

dofile("core/Database.lua")
dofile("core/AscensionAPI.lua")
dofile("core/Slots.lua")
dofile("core/Poster.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local Poster = AscensionLFM.Poster
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

-- Interval clamp
check("default interval 60", Poster.ClampInterval(nil) == 60)
check("clamp below 30 → 30", Poster.ClampInterval(10) == 30)
check("clamp 30 stays", Poster.ClampInterval(30) == 30)
check("clamp 90 stays", Poster.ClampInterval(90) == 90)
check("clamp above 600 → 600", Poster.ClampInterval(999) == 600)
check("MIN_INTERVAL is 30", Poster.MIN_INTERVAL == 30)

-- Message builder from snapshot
local emptySnap = {
    tank = { filled = 0, max = 2 },
    healer = { filled = 0, max = 3 },
    aura = { filled = 0, max = 3 },
    dps = { filled = 0, max = 7 },
}
local msg = Poster.BuildMessage(emptySnap)
check("empty build format", msg == "LFM MS | 0/2 Tanks | 0/3 Healers | 0/3 Auras | 0/7 DPS", msg)

local midSnap = {
    tank = { filled = 1, max = 2 },
    healer = { filled = 2, max = 3 },
    aura = { filled = 0, max = 3 },
    dps = { filled = 5, max = 7 },
}
msg = Poster.BuildMessage(midSnap)
check("mid build format", msg == "LFM MS | 1/2 Tanks | 2/3 Healers | 0/3 Auras | 5/7 DPS", msg)

-- Full/disabled roles are omitted entirely, not shown as 0/0 or N/N
local partialFullSnap = {
    tank = { filled = 2, max = 2 },
    healer = { filled = 1, max = 3 },
    aura = { filled = 0, max = 0 }, -- disabled
    dps = { filled = 7, max = 7 },
}
msg = Poster.BuildMessage(partialFullSnap)
check("full/disabled roles omitted", msg == "LFM MS | 1/3 Healers", msg)

local allFullSnap = {
    tank = { filled = 2, max = 2 },
    healer = { filled = 3, max = 3 },
    aura = { filled = 3, max = 3 },
    dps = { filled = 7, max = 7 },
}
msg = Poster.BuildMessage(allFullSnap)
check("all full fallback text", msg == "LFM MS - full", msg)

--------------------------------------------------------------------
-- postShowAllRoles opt-in: default behavior (v0.4.29) is unchanged —
-- only the second BuildMessage argument, when truthy, includes filled
-- roles too.
--------------------------------------------------------------------
local mixedSnap = {
    tank = { filled = 2, max = 2 },
    healer = { filled = 1, max = 3 },
    aura = { filled = 3, max = 3 },
    dps = { filled = 4, max = 7 },
}
check("default (no 2nd arg) still omits full roles",
    Poster.BuildMessage(mixedSnap) == "LFM MS | 1/3 Healers | 4/7 DPS", Poster.BuildMessage(mixedSnap))
check("showAll=false explicitly still omits full roles",
    Poster.BuildMessage(mixedSnap, false) == "LFM MS | 1/3 Healers | 4/7 DPS", Poster.BuildMessage(mixedSnap, false))
check("showAll=true includes filled roles too",
    Poster.BuildMessage(mixedSnap, true) == "LFM MS | 2/2 Tanks | 1/3 Healers | 3/3 Auras | 4/7 DPS",
    Poster.BuildMessage(mixedSnap, true))

-- Mythic+ prefix (0.4.101 Raid+M+ tabs): only shown when BOTH dungeon and
-- a positive level are set - one without the other stays silent rather
-- than printing "[Deadmines +0]" or "[ +14]".
check("mplus prefix needs both dungeon and level",
    Poster.MPlusPrefix("Deadmines", 0) == "", Poster.MPlusPrefix("Deadmines", 0))
check("mplus prefix needs both dungeon and level 2",
    Poster.MPlusPrefix("", 14) == "", Poster.MPlusPrefix("", 14))
check("mplus prefix format",
    Poster.MPlusPrefix("Deadmines", 14) == "[Deadmines +14] ", Poster.MPlusPrefix("Deadmines", 14))
check("mplus prefix trims whitespace",
    Poster.MPlusPrefix("  Deadmines  ", 14) == "[Deadmines +14] ", Poster.MPlusPrefix("  Deadmines  ", 14))
check("BuildMessage prepends mplus prefix",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14) == "[Deadmines +14] LFM MS | 1/3 Healers | 4/7 DPS",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14))

-- Unified content-type selector (0.4.103 LFG/LFM tab): "raid" always tags
-- [RAID] regardless of mplus fields, "ms" suppresses any tag even if
-- mplus fields happen to still be set (switching types doesn't clear the
-- other type's saved values), omitted/"mplus" keeps the plain M+ prefix.
check("content type raid always tags RAID",
    Poster.ContentPrefix("raid", "", 0) == "[RAID] ", Poster.ContentPrefix("raid", "", 0))
check("content type raid ignores leftover mplus fields",
    Poster.ContentPrefix("raid", "Deadmines", 14) == "[RAID] ", Poster.ContentPrefix("raid", "Deadmines", 14))
check("content type ms suppresses even set mplus fields",
    Poster.ContentPrefix("ms", "Deadmines", 14) == "", Poster.ContentPrefix("ms", "Deadmines", 14))
check("content type mplus uses the plain mplus prefix",
    Poster.ContentPrefix("mplus", "Deadmines", 14) == "[Deadmines +14] ", Poster.ContentPrefix("mplus", "Deadmines", 14))
check("content type omitted behaves like mplus (back-compat)",
    Poster.ContentPrefix(nil, "Deadmines", 14) == "[Deadmines +14] ", Poster.ContentPrefix(nil, "Deadmines", 14))
check("BuildMessage 5th arg raid overrides mplus fields",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14, "raid") == "[RAID] LFM MS | 1/3 Healers | 4/7 DPS",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14, "raid"))
check("BuildMessage 5th arg ms suppresses mplus fields",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14, "ms") == "LFM MS | 1/3 Healers | 4/7 DPS",
    Poster.BuildMessage(mixedSnap, false, "Deadmines", 14, "ms"))

-- Disabled roles (max<=0) are never shown even with showAll=true.
local withDisabled = {
    tank = { filled = 2, max = 2 },
    healer = { filled = 0, max = 0 }, -- disabled
    aura = { filled = 1, max = 3 },
    dps = { filled = 4, max = 7 },
}
check("showAll=true still omits disabled (max<=0) roles",
    Poster.BuildMessage(withDisabled, true):find("Healers", 1, true) == nil,
    Poster.BuildMessage(withDisabled, true))

check("nil snapshot still builds", type(Poster.BuildMessage(nil)) == "string")

-- IsFull
local full, reason = Poster.IsFull({
    tank = { filled = 2, max = 2 },
    healer = { filled = 3, max = 3 },
    aura = { filled = 3, max = 3 },
    dps = { filled = 7, max = 7 },
}, 10, 15)
check("full when all slots filled", full == true)
check("full reason slots", reason == "slots")

full, reason = Poster.IsFull(midSnap, 10, 15)
check("not full when open slots", full == false)

full, reason = Poster.IsFull(midSnap, 15, 15)
check("full when maxPartySize", full == true)
check("full reason maxPartySize", reason == "maxPartySize")

full = Poster.IsFull(midSnap, 14, 15)
check("not full under maxPartySize", full == false)

full, reason = Poster.IsFull(midSnap, 14, 15, 3)
check("unassigned near full", full == true and reason == "unassigned")
full = Poster.IsFull(midSnap, 10, 15, 3)
check("unassigned mid group still open", full == false)

-- zero-max roles ignored for "all filled"
full, reason = Poster.IsFull({
    tank = { filled = 1, max = 1 },
    healer = { filled = 0, max = 0 },
    aura = { filled = 0, max = 0 },
    dps = { filled = 0, max = 0 },
}, 1, 40)
check("full when only nonzero caps filled", full == true)

-- ShouldRepost
local ok, why = Poster.ShouldRepost(100, 0, 60, true, "hosting", false)
check("repost ok first time", ok == true)

ok, why = Poster.ShouldRepost(100, 80, 60, true, "hosting", false)
check("repost waiting", ok == false and why == "waiting")

ok, why = Poster.ShouldRepost(100, 80, 10, true, "hosting", false) -- clamp→30; 20s elapsed
check("repost still waiting after clamp", ok == false and why == "waiting")

ok, why = Poster.ShouldRepost(130, 100, 30, true, "hosting", false)
check("repost after interval", ok == true)

ok, why = Poster.ShouldRepost(200, 0, 60, false, "hosting", false)
check("repost disabled", ok == false and why == "disabled")

ok, why = Poster.ShouldRepost(200, 0, 60, true, "notify", false)
check("repost not hosting", ok == false and why == "not hosting")

ok, why = Poster.ShouldRepost(200, 0, 60, true, "hosting", true)
check("repost stop when full", ok == false and why == "full")

-- Live Tick stop-when-full clears autoRepost
Poster._ResetForTests()
local db = AscensionLFM.Database.Get()
db.mode = "hosting"
db.autoRepost = true
db.repostInterval = 60
db.maxPartySize = 15
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
Slots.Assign("a", "tank")
Slots.Assign("b", "tank")
Slots.Assign("c", "healer")
Slots.Assign("d", "healer")
Slots.Assign("e", "healer")
Slots.Assign("f", "aura")
Slots.Assign("g", "aura")
Slots.Assign("h", "aura")
for i = 1, 7 do
    Slots.Assign("dps" .. i, "dps")
end

-- Mock group size below max so slots-full is the stop reason
AscensionLFM.Invite = AscensionLFM.Invite or {}
AscensionLFM.Invite.GetGroupSize = function() return 10 end

local status = Poster.Tick(1000)
check("tick stops when full", status == "stopped: full" or status == "full (slots)", status)
check("autoRepost cleared on full", db.autoRepost == false)

-- Tick posts when open
Poster._ResetForTests()
db.autoRepost = true
db.mode = "hosting"
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)

local sent = {}
_G.SendChatMessage = function(msg, ch)
    table.insert(sent, { msg = msg, ch = ch })
end

status = Poster.Tick(2000)
check("tick posts when open", status == "reposted", status)
check("sent one message", #sent == 1)
check("sent yell by default", sent[1].ch == "YELL")
check("sent LFM prefix", tostring(sent[1].msg):find("^LFM MS") ~= nil)

-- Second tick within interval waits
status = Poster.Tick(2010)
check("tick waits inside interval", status == "waiting", status)
check("still one message", #sent == 1)

--------------------------------------------------------------------
-- New: auto-repost pauses while the host is inside the instance,
-- resumes normally once outside again. db.pauseRepostInInstance
-- (default true) lets a host opt back in.
--------------------------------------------------------------------
Poster._ResetForTests()
db.autoRepost = true
db.mode = "hosting"
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)
sent = {}
_G.IsInInstance = function() return true, "party" end
status = Poster.Tick(3000)
check("tick pauses while in instance", status == "paused: in instance", status)
check("no message sent while in instance", #sent == 0)

-- Toggle off: host wants repost to keep working even inside the instance.
db.pauseRepostInInstance = false
status = Poster.Tick(3000)
check("toggle off allows repost even in instance", status == "reposted", status)
check("message sent once toggled off", #sent == 1)
db.pauseRepostInInstance = true

-- Outside again: resumes normally.
Poster._ResetForTests()
db.autoRepost = true
sent = {}
_G.IsInInstance = function() return false, "none" end
status = Poster.Tick(4000)
check("tick posts normally outside instance", status == "reposted", status)
check("message sent outside instance", #sent == 1)
_G.IsInInstance = nil

--------------------------------------------------------------------
-- New: prefers C_Manastorm.IsInManastorm() over the generic
-- IsInInstance() - same as Invite.lua's equivalent fix.
--------------------------------------------------------------------
Poster._ResetForTests()
db.autoRepost = true
db.mode = "hosting"
db.pauseRepostInInstance = true
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)
sent = {}
_G.IsInInstance = function() return true, "party" end
_G.C_Manastorm = { IsInManastorm = function() return false end }
status = Poster.Tick(5000)
check("C_Manastorm priority: unrelated instance does not pause repost", status == "reposted", status)
check("message sent in unrelated instance", #sent == 1)

Poster._ResetForTests()
db.autoRepost = true
Slots.ClearAll()
Slots.SetMax("tank", 2)
Slots.SetMax("healer", 3)
Slots.SetMax("aura", 3)
Slots.SetMax("dps", 7)
sent = {}
_G.C_Manastorm = { IsInManastorm = function() return true end }
status = Poster.Tick(6000)
check("C_Manastorm priority: actual Manastorm pauses repost", status == "paused: in instance", status)
check("no message sent while actually in Manastorm", #sent == 0)

_G.C_Manastorm = nil
_G.IsInInstance = nil

-- Defaults: autoRepost off
local defs = AscensionLFM.Database.Defaults()
check("default autoRepost off", defs.autoRepost == false)
check("default interval 60", defs.repostInterval == 60)
check("default channel YELL", defs.postChannel == "YELL")

-- ScanRaid returns snapshot
Slots.ClearAll()
Slots.Assign("Tanky", "tank")
local snap, removed = Slots.ScanRaid()
check("ScanRaid snapshot table", type(snap) == "table")
check("ScanRaid tank filled", snap.tank and snap.tank.filled == 1)
check("ScanRaid removed number", type(removed) == "number")

-- Regression: a disabled role (db.roles[role] == false) with leftover
-- positive slotMax must not still get advertised in the posted LFM text —
-- previously "0/3 Healers" would show even with healer explicitly off,
-- contradicting the "role filtered" reject applicants for that role got.
-- Since v0.4.29, full/disabled roles are omitted from the message
-- entirely (not shown as 0/0) — Healer must not appear at all.
local db = AscensionLFM.Database.Get()
db.roles = { tank = true, healer = false, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
local disabledMsg = Poster.RefreshMessage()
check("disabled role omitted entirely", disabledMsg:find("Healers", 1, true) == nil, disabledMsg)
check("disabled role max not leaked", disabledMsg:find("0/3 Healers", 1, true) == nil, disabledMsg)

local disabledStatus = Poster.GetStatus()
check("GetStatus message also filtered", disabledStatus.message:find("Healers", 1, true) == nil,
    disabledStatus.message)

--------------------------------------------------------------------
-- Channel resolution: no silent YELL fallback on failure (was posting to
-- a completely different, much shorter-range channel without the host
-- realizing why their LFM "wasn't finding people").
--------------------------------------------------------------------
db.postChannel = "CHANNEL"
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()

-- "1." (copy-pasted from the chat-tab label "1. General") resolves via
-- the numeric fallback even when GetChannelName can't match it by name.
local chSent = {}
_G.SendChatMessage = function(msg, chatType, lang, target)
    table.insert(chSent, { msg = msg, chatType = chatType, target = target })
end
_G.GetChannelName = function() return 0 end -- name lookup finds nothing
local ok1, err1 = Poster.PostOnce("test", "CHANNEL", "1.")
check("channel '1.' resolves via numeric fallback", ok1 == true, tostring(err1))
check("sent to channel index 1", chSent[1] and chSent[1].chatType == "CHANNEL" and chSent[1].target == 1,
    chSent[1] and string.format("%s/%s", tostring(chSent[1].chatType), tostring(chSent[1].target)) or "none")

-- A genuinely unresolvable channel name must fail loudly, NOT silently
-- post to YELL instead.
chSent = {}
local ok2, err2 = Poster.PostOnce("test", "CHANNEL", "NotARealChannelXYZ")
check("unresolvable channel fails", ok2 == false)
check("unresolvable channel error mentions the name", tostring(err2):find("NotARealChannelXYZ", 1, true) ~= nil,
    tostring(err2))
check("did NOT silently fall back to YELL", #chSent == 0, tostring(#chSent))

local failStatus = Poster.GetStatus()
check("status reflects channel failure", failStatus.status:find("bad channel", 1, true) ~= nil, failStatus.status)

-- A GetChannelName that errors outright must be caught, not propagate —
-- still resolves via the numeric fallback afterward.
chSent = {}
_G.GetChannelName = function() error("simulated client quirk") end
local ok3, err3 = Poster.PostOnce("test", "CHANNEL", "1")
check("GetChannelName error is caught, numeric fallback still works", ok3 == true, tostring(err3))
_G.GetChannelName = function() return 0 end

-- Regression: resolving to a real channel id the player hasn't joined
-- (e.g. "3.Zone" unchecked in the channel config, per a live report) must
-- fail loudly too — SendChatMessage doesn't error for this case either,
-- so without this check the post would silently reach nobody while
-- PostOnce reported success.
_G.GetChannelList = function()
    -- Joined: 1=Ascension, 2=Newcomers, 4=Trade, 5=LookingForGroup.
    -- NOT joined: 3=Zone.
    return 1, "Ascension", false, 2, "Newcomers", false, 4, "Trade", false, 5, "LookingForGroup", false
end
chSent = {}
local ok4, err4 = Poster.PostOnce("test", "CHANNEL", "3")
check("unjoined channel fails", ok4 == false)
check("unjoined channel error mentions the id", tostring(err4):find("3", 1, true) ~= nil, tostring(err4))
check("did NOT post to an unjoined channel", #chSent == 0, tostring(#chSent))
local unjoinedStatus = Poster.GetStatus()
check("status reflects not-joined failure", unjoinedStatus.status:find("not joined", 1, true) ~= nil,
    unjoinedStatus.status)

-- A joined channel (e.g. 4=Trade) still posts normally.
chSent = {}
local ok5, err5 = Poster.PostOnce("test", "CHANNEL", "4")
check("joined channel still posts", ok5 == true, tostring(err5))
check("sent to channel 4", chSent[1] and chSent[1].target == 4, chSent[1] and tostring(chSent[1].target) or "none")
_G.GetChannelList = nil

--------------------------------------------------------------------
-- Regression: v0.4.29's " | " role separator broke SendChatMessage
-- outright — WoW reserves "|" as its escape-code prefix, so an unescaped
-- pipe throws "Invalid escape code in chat message" and the whole post
-- silently fails. Reported live: "[AscensionLFM] LFM failed:
-- SendChatMessage(): Invalid escape code in chat message" on every post.
--------------------------------------------------------------------
db.roles = { tank = true, healer = true, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
Slots.ClearAll()
db.postChannel = "YELL"
chSent = {}
local pipeMsg = Poster.RefreshMessage()
check("built message still uses a single pipe internally", pipeMsg:find("||", 1, true) == nil
    and pipeMsg:find("|", 1, true) ~= nil, pipeMsg)
local ok6, err6 = Poster.PostOnce(pipeMsg, "YELL")
check("posting a pipe-separated message succeeds", ok6 == true, tostring(err6))
check("sent message has pipes escaped for SendChatMessage",
    chSent[1] and chSent[1].msg:find("||", 1, true) ~= nil, chSent[1] and chSent[1].msg or "none")
local afterSendStatus = Poster.GetStatus()
check("internal/UI status message keeps a single clean pipe (not doubled)",
    afterSendStatus.message:find("||", 1, true) == nil and afterSendStatus.message:find("|", 1, true) ~= nil,
    afterSendStatus.message)

io.write(string.format("poster tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
