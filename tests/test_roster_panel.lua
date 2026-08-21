-- AscensionLFM: tests/test_roster_panel.lua
-- RosterPanel.lua: BuildData (roster -> per-subgroup role-sorted entries +
-- role counts) and FormatSummary (counts -> compact status line).

package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" - " .. detail) or "") .. "\n")
    end
end

_G.AscensionLFMDB = nil
_G.AscensionLFM = nil
_G.GetTime = function() return _G._rosterNow or 1000 end
_G._rosterNow = 1000
_G.CreateFrame = function() error("RosterPanel tests are data-only - should never build UI frames") end

dofile("core/Database.lua")
dofile("core/Slots.lua")
dofile("ui/Chrome.lua")
dofile("ui/RosterPanel.lua")

local AscensionLFM = _G.AscensionLFM
local RosterPanel = assert(AscensionLFM.RosterPanel)
AscensionLFM.Database.Init()

--------------------------------------------------------------------
-- BuildData: raid roster, role sorting within a subgroup, role counts.
--------------------------------------------------------------------
AscensionLFM.Slots.ClearAll()
AscensionLFM.Slots.Assign("Tanky", "tank")
AscensionLFM.Slots.Assign("Healy", "healer")
-- v0.4.131: "Aury" is a DPS who also carries an aura (tag, not a seat).
AscensionLFM.Slots.Assign("Aury", "dps", nil, true)
AscensionLFM.Slots.Assign("Dee", "dps")
-- "Nameless" is present but never assigned a role -> counts as unknown.

local roster = {
    { "Dee", "", 1, 60, "Warrior", "WARRIOR", "", 1 },
    { "Tanky", "", 1, 60, "Paladin", "PALADIN", "", 1 },
    { "Nameless", "", 1, 60, "Rogue", "ROGUE", "", 1 },
    { "Healy", "", 2, 60, "Priest", "PRIEST", "", 1 },
    { "Aury", "", 2, 60, "Mage", "MAGE", "", 0 }, -- offline
}
_G.GetNumRaidMembers = function() return #roster end
_G.GetRaidRosterInfo = function(i)
    local r = roster[i]
    if not r then return nil end
    return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]
end

local groups, counts = RosterPanel.BuildData()

check("group 1 has 3 members", #groups[1] == 3, tostring(#groups[1]))
check("group 2 has 2 members", #groups[2] == 2, tostring(#groups[2]))
check("groups 3-8 empty", #groups[3] == 0 and #groups[8] == 0)

-- Sort order within a group: tank(1) < healer(2) < aura(3) < dps(4) < unknown(5),
-- ties broken alphabetically by name.
check("group1 sorted tank first", groups[1][1].name == "Tanky", groups[1][1].name)
check("group1 sorted dps second", groups[1][2].name == "Dee", groups[1][2].name)
check("group1 sorted unknown last", groups[1][3].name == "Nameless", groups[1][3].name)
check("group2 sorted healer first", groups[2][1].name == "Healy", groups[2][1].name)
check("group2 sorted aura-carrying dps second", groups[2][2].name == "Aury", groups[2][2].name)
check("aura carrier is flagged on the entry", groups[2][2].isAura == true,
    tostring(groups[2][2].isAura))

check("counts.tank", counts.tank == 1, tostring(counts.tank))
check("counts.healer", counts.healer == 1, tostring(counts.healer))
-- Aura is counted independently of the seat now, so Aury shows up in BOTH
-- counts.dps and counts.aura - that overlap is the point of the tag model.
check("counts.aura counts the tag", counts.aura == 1, tostring(counts.aura))
check("counts.dps includes the aura carrier", counts.dps == 2, tostring(counts.dps))
check("counts.unknown", counts.unknown == 1, tostring(counts.unknown))
check("counts.total", counts.total == 5, tostring(counts.total))
check("counts.online excludes the offline member", counts.online == 4, tostring(counts.online))

check("offline member correctly flagged", groups[2][2].online == false, tostring(groups[2][2].online))
check("online member correctly flagged", groups[1][1].online == true, tostring(groups[1][1].online))

-- Out-of-range subgroup clamps into 1..8.
local rosterBad = { { "Weird", "", 99, 60, "Warrior", "WARRIOR", "", 1 } }
_G.GetNumRaidMembers = function() return #rosterBad end
_G.GetRaidRosterInfo = function(i)
    local r = rosterBad[i]
    if not r then return nil end
    return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]
end
local groups2 = RosterPanel.BuildData()
check("out-of-range subgroup clamps to 8", #groups2[8] == 1, tostring(#groups2[8]))

--------------------------------------------------------------------
-- BuildData: party/solo fallback path (no raid).
--------------------------------------------------------------------
AscensionLFM.Slots.ClearAll()
AscensionLFM.Slots.Assign("Me", "dps")
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 1 end
_G.UnitName = function(u)
    if u == "player" then return "Me" end
    if u == "party1" then return "Buddy" end
    return nil
end
_G.UnitLevel = function() return 60 end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
local groups3, counts3 = RosterPanel.BuildData()
check("solo/party path includes self", groups3[1][1] ~= nil)
check("solo/party path total is 2 (self + party1)", counts3.total == 2, tostring(counts3.total))
check("solo/party path all online", counts3.online == 2, tostring(counts3.online))

--------------------------------------------------------------------
-- FormatSummary: pure.
--------------------------------------------------------------------
local summary = RosterPanel.FormatSummary(
    { tank = 1, healer = 2, aura = 3, dps = 4, online = 8, total = 10, unknown = 2 },
    { tank = 2, healer = 3, aura = 3, dps = 7 }
)
check("summary shows tank filled/max", summary:find("T 1/2", 1, true) ~= nil, summary)
check("summary shows healer filled/max", summary:find("H 2/3", 1, true) ~= nil, summary)
check("summary shows online/total", summary:find("8 online", 1, true) ~= nil, summary)
check("summary shows unknown count", summary:find("unk 2", 1, true) ~= nil, summary)
check("summary uses ASCII only (no em-dash)", summary:find("\226\128\148", 1, true) == nil, summary)

-- A role with slotMax 0/unset shows bare count, not "0/0".
local summaryNoMax = RosterPanel.FormatSummary({ tank = 1 }, {})
check("no slotMax shows bare filled count", summaryNoMax:find("T 1", 1, true) ~= nil
    and summaryNoMax:find("T 1/0", 1, true) == nil, summaryNoMax)

-- nil-safe: doesn't error on missing counts/slotMax.
local okNilSafe = pcall(RosterPanel.FormatSummary, nil, nil)
check("FormatSummary is nil-safe", okNilSafe == true)

--------------------------------------------------------------------
-- Regression: TryKick must not trust a successful UninviteUnit pcall as
-- proof the removal actually happened - the same "no error != it
-- worked" lesson as Kick.lua's v0.4.28 fix. Verify via the live roster
-- on a deferred check instead of confirming immediately.
--------------------------------------------------------------------
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.IsPartyLeader = function() return false end
local uninvited = {}
_G.UninviteUnit = function(name) table.insert(uninvited, name) end

-- Roster still has the target present when TryKick fires - simulates
-- UninviteUnit silently no-op'ing (e.g. an edge-case privilege check, or
-- the target being in combat) despite no Lua error.
local rosterNames = { "Host", "Ghosty" }
_G.GetNumRaidMembers = function() return #rosterNames end
_G.GetRaidRosterInfo = function(i)
    local n = rosterNames[i]
    if not n then return nil end
    return n, "", 1, 60, "Warrior", "WARRIOR", "", 1
end

RosterPanel._ResetForTests()
_G._rosterNow = 2000
RosterPanel._TryKick("Ghosty")
check("TryKick attempts UninviteUnit", #uninvited == 1 and uninvited[1] == "Ghosty", tostring(#uninvited))
check("TryKick does not immediately confirm - queued for verify",
    RosterPanel._GetPendingKickVerify() ~= nil)

-- Checking before the verify delay has elapsed does nothing yet.
RosterPanel._CheckPendingKick()
check("verify not yet due stays pending", RosterPanel._GetPendingKickVerify() ~= nil)

-- Ghosty is STILL in the roster once the delay elapses - must NOT be
-- silently confirmed as removed, and must clearly say so.
_G._rosterNow = 2000 + 1.6
local printedStill = {}
local origPrintStill = AscensionLFM.Print
AscensionLFM.Print = function(msg) table.insert(printedStill, msg) end
RosterPanel._CheckPendingKick()
AscensionLFM.Print = origPrintStill
check("verify clears the pending check either way",
    RosterPanel._GetPendingKickVerify() == nil)
local stillInGroupMsg = false
for _, msg in ipairs(printedStill) do
    if msg:find("still in group", 1, true) then
        stillInGroupMsg = true
    end
end
check("still-present target gets an honest 'still in group' message, not a false confirmation",
    stillInGroupMsg == true, table.concat(printedStill, " | "))

-- Separate clean scenario: target genuinely leaves before the verify
-- delay elapses - correctly confirmed.
rosterNames = { "Host", "Ghosty2" }
uninvited = {}
RosterPanel._ResetForTests()
_G._rosterNow = 3000
RosterPanel._TryKick("Ghosty2")
rosterNames = { "Host" } -- genuinely left
_G._rosterNow = 3000 + 1.6
local printed = {}
local origPrint = AscensionLFM.Print
AscensionLFM.Print = function(msg) table.insert(printed, msg) end
RosterPanel._CheckPendingKick()
AscensionLFM.Print = origPrint
local removedMsg = false
for _, msg in ipairs(printed) do
    if msg:find("removed", 1, true) and not msg:find("still in group", 1, true) then
        removedMsg = true
    end
end
check("genuine departure prints a clean 'removed' confirmation", removedMsg == true,
    table.concat(printed, " | "))

io.write(string.format("test_roster_panel: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
