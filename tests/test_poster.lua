-- AscensionLFM Poster unit tests: message builder, stop-when-full, interval clamp.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

dofile("core/Database.lua")
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
check("empty build format", msg == "LFM MS | 0/2 Tanks | 0/3 Healers | 0/3 Aura | 0/7 DPS", msg)

local midSnap = {
    tank = { filled = 1, max = 2 },
    healer = { filled = 2, max = 3 },
    aura = { filled = 0, max = 3 },
    dps = { filled = 5, max = 7 },
}
msg = Poster.BuildMessage(midSnap)
check("mid build format", msg == "LFM MS | 1/2 Tanks | 2/3 Healers | 0/3 Aura | 5/7 DPS", msg)

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
check("all full fallback text", msg == "LFM MS — full", msg)

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

io.write(string.format("poster tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
