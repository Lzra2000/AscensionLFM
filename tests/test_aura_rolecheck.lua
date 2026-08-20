-- AscensionLFM: tests/test_aura_rolecheck.lua

local function Fail(msg)
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    os.exit(1)
end

local function check(name, cond, detail)
    if not cond then
        Fail(name .. (detail and (" — " .. tostring(detail)) or ""))
    end
    print("OK: " .. name)
end

-- stubs
_G.AscensionLFM = nil
_G.AscensionLFMDB = nil
GetTime = function() return 1000 end
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end }
end

dofile("core/Database.lua")
dofile("core/AuraBalance.lua")
dofile("core/RoleCheck.lua")

AscensionLFM.Database.Init()
local AB = AscensionLFM.AuraBalance
AB._ResetForTests()

-- Aura plan: two auras in group 1 → move one to empty group
local members = {
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 1, isAura = true },
    { name = "D1", index = 3, subgroup = 1, isAura = false },
    { name = "D2", index = 4, subgroup = 2, isAura = false },
}
local moves = AB.PlanMoves(members)
check("plans one move", #moves == 1)
check("moves excess aura out of g1", moves[1].from == 1 and moves[1].to ~= 1)
check("name is A2 (higher index kept second)", moves[1].name == "A2")
check("set into roomy group", moves[1].kind == "set")
check("prefers emptier group 3 over g2", moves[1].to == 3)

-- Already balanced
moves = AB.PlanMoves({
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 2, isAura = true },
})
check("no moves when one aura per group", #moves == 0)

-- Full target group (5) without aura → swap, not set into overflow
members = {
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 1, isAura = true },
}
for i = 1, 5 do
    table.insert(members, {
        name = "F" .. i,
        index = 10 + i,
        subgroup = 2,
        isAura = false,
    })
end
moves = AB.PlanMoves(members)
check("plans move when only full empty-aura group exists", #moves >= 1)
-- group 3–8 empty preferred over full g2
check("prefers empty g3 over full g2", moves[1].kind == "set" and moves[1].to == 3)

-- Only group 2 has space conceptually but is full; groups 3-8 also filled → swap into g2
members = {
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 1, isAura = true },
}
local idx = 3
for g = 2, 8 do
    for i = 1, 5 do
        idx = idx + 1
        table.insert(members, {
            name = "G" .. g .. "_" .. i,
            index = idx,
            subgroup = g,
            isAura = false,
        })
    end
end
moves = AB.PlanMoves(members)
check("swap when all no-aura groups are full", #moves == 1 and moves[1].kind == "swap", moves[1] and moves[1].kind)
check("swap has victim", moves[1].swapName ~= nil)
check("swap target has no aura", moves[1].to >= 2 and moves[1].to <= 8)

-- Three auras → two moves to distinct groups
moves = AB.PlanMoves({
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 1, isAura = true },
    { name = "A3", index = 3, subgroup = 1, isAura = true },
})
check("three auras plan two moves", #moves == 2)
check("distinct targets", moves[1].to ~= moves[2].to)

-- Live Balance applies one move at a time (index-safe)
local roster = {
    { name = "Keep", sub = 1, role = "aura" },
    { name = "MoveMe", sub = 1, role = "aura" },
    { name = "Other", sub = 2, role = "dps" },
}
_G.GetNumRaidMembers = function() return #roster end
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.UnitAffectingCombat = function() return false end
_G.GetRaidRosterInfo = function(i)
    local r = roster[i]
    if not r then return end
    return r.name, nil, r.sub
end
local setCalls = {}
_G.SetRaidSubgroup = function(i, to)
    local r = roster[i]
    table.insert(setCalls, { name = r and r.name, to = to })
    if r then r.sub = to end
end
_G.SwapRaidSubgroup = function() end

local db = AscensionLFM.Database.Get()
db.assignedRoles = { keep = "aura", moveme = "aura", other = "dps" }
db.autoMoveAura = true
AB._ResetForTests()
_G.GetTime = function() return 5000 end
local moved, planned = AB.Balance()
check("balance moves one", moved == 1, tostring(moved))
check("balance planned at least one", planned >= 1)
check("SetRaidSubgroup once", #setCalls == 1)
check("moved MoveMe", setCalls[1] and setCalls[1].name == "MoveMe")

-- While waiting for settle, second Balance is a no-op
_G.GetTime = function() return 5000.5 end
local moved2 = AB.Balance()
check("settle wait blocks", moved2 == 0)

-- After roster shows new group, continue
_G.GetTime = function() return 5001 end
moved2 = select(1, AB.Balance())
check("after settle idle if balanced", moved2 == 0)

-- Role check duration clamp
check("clamp low", AscensionLFM.RoleCheck.ClampDuration(5) == 15)
check("clamp high", AscensionLFM.RoleCheck.ClampDuration(999) == 300)
check("clamp mid", AscensionLFM.RoleCheck.ClampDuration(60) == 60)
check("inactive by default", AscensionLFM.RoleCheck.IsActive(1000) == false)

print("aura/rolecheck tests passed")

--------------------------------------------------------------------
-- New: PlanRoleMoves generalization (Tank always fills g1/g2 first,
-- Healer/Aura fill emptiest-group-first, Healer never displaces Tank
-- unless a full group leaves no other choice) + BalanceAll orchestration.
--------------------------------------------------------------------

-- Tank sortByGroupNumber: two tanks both in group 3 -> excess one goes to
-- the LOWEST-numbered empty group (1), not just any empty group.
local tankMoves = AB.PlanRoleMoves({
    { name = "T1", index = 1, subgroup = 3, role = "tank" },
    { name = "T2", index = 2, subgroup = 3, role = "tank" },
    { name = "D1", index = 3, subgroup = 3, role = "dps" },
}, "tank", { sortByGroupNumber = true })
check("tank plan moves excess out of g3", #tankMoves == 1)
check("tank fills lowest empty group (g1)", tankMoves[1].to == 1, tostring(tankMoves[1].to))
check("tank move stamped with roleKey", tankMoves[1].roleKey == "tank")

-- Two tanks starting in separate near-empty groups already satisfy "one
-- per group" -> no moves needed even though they're not literally g1/g2.
local noTankMoves = AB.PlanRoleMoves({
    { name = "T1", index = 1, subgroup = 2, role = "tank" },
    { name = "T2", index = 2, subgroup = 4, role = "tank" },
}, "tank", { sortByGroupNumber = true })
check("already-1-per-group tanks need no moves", #noTankMoves == 0, tostring(#noTankMoves))

-- Healer swap protects Tank: group 1 has 2 healers (excess) and is full;
-- ALL other groups are also full (either already has a healer, or is
-- group 2 which has a tank + dps and no healer) — forces a real swap
-- rather than a plain move into empty space. The swap-victim must be a
-- dps, never the tank, even though the tank is listed first in group 2.
local healerMembers = {
    { name = "Tnk1", index = 1, subgroup = 1, role = "tank" },
    { name = "D1", index = 2, subgroup = 1, role = "dps" },
    { name = "D2", index = 3, subgroup = 1, role = "dps" },
    { name = "H2", index = 4, subgroup = 1, role = "healer" },
    { name = "H3", index = 5, subgroup = 1, role = "healer" }, -- excess healer
    { name = "Tnk2", index = 6, subgroup = 2, role = "tank" },
    { name = "D3", index = 7, subgroup = 2, role = "dps" },
    { name = "D4", index = 8, subgroup = 2, role = "dps" },
    { name = "D5", index = 9, subgroup = 2, role = "dps" },
    { name = "D6", index = 10, subgroup = 2, role = "dps" },
}
-- Fill groups 3-8 with a healer each (already satisfied, no room) so
-- there's no empty target to plainly move into — only the full group 2
-- (no healer) remains, forcing a swap there.
local idx = 11
for g = 3, 8 do
    for slot = 1, 5 do
        local role = slot == 1 and "healer" or "dps"
        table.insert(healerMembers, { name = "G" .. g .. "P" .. slot, index = idx, subgroup = g, role = role })
        idx = idx + 1
    end
end
local healerMoves = AB.PlanRoleMoves(healerMembers, "healer", { protectRoles = { "tank" } })
check("healer plan swaps out of full g1", #healerMoves == 1, tostring(#healerMoves))
check("healer swap kind", healerMoves[1].kind == "swap", tostring(healerMoves[1].kind))
check("healer swap target is g2", healerMoves[1].to == 2, tostring(healerMoves[1].to))
check("healer swap victim is not the tank", healerMoves[1].swapName ~= "Tnk2",
    tostring(healerMoves[1].swapName))

-- BalanceAll: tank pass runs before healer/aura passes, one move per call.
AB._ResetForTests()
local roster2 = {
    { name = "T1", sub = 1, role = "tank" },
    { name = "T2", sub = 1, role = "tank" }, -- excess tank, group 1
    { name = "H1", sub = 2, role = "healer" },
    { name = "H2", sub = 2, role = "healer" }, -- excess healer, group 2
    { name = "A1", sub = 3, role = "aura" },
    { name = "A2", sub = 3, role = "aura" }, -- excess aura, group 3
}
_G.GetNumRaidMembers = function() return #roster2 end
_G.GetRaidRosterInfo = function(i)
    local r = roster2[i]
    if not r then return end
    return r.name, nil, r.sub
end
local setCalls2 = {}
_G.SetRaidSubgroup = function(i, to)
    local r = roster2[i]
    table.insert(setCalls2, { name = r and r.name, to = to })
    if r then r.sub = to end
end
_G.SwapRaidSubgroup = function() end
local db2 = AscensionLFM.Database.Get()
db2.assignedRoles = { t1 = "tank", t2 = "tank", h1 = "healer", h2 = "healer", a1 = "aura", a2 = "aura" }
db2.autoMoveTank = true
db2.autoMoveHealer = true
db2.autoMoveAura = true

_G.GetTime = function() return 6000 end
local m1 = AB.BalanceAll()
check("BalanceAll first call moves tank first", m1 == 1 and setCalls2[1] and setCalls2[1].name == "T2",
    setCalls2[1] and setCalls2[1].name or "none")

_G.GetTime = function() return 6003 end -- past SETTLE_TIMEOUT
local m2 = AB.BalanceAll()
check("BalanceAll second call moves healer next", m2 == 1 and setCalls2[2] and setCalls2[2].name == "H2",
    setCalls2[2] and setCalls2[2].name or "none")

_G.GetTime = function() return 6006 end
local m3 = AB.BalanceAll()
check("BalanceAll third call moves aura last", m3 == 1 and setCalls2[3] and setCalls2[3].name == "A2",
    setCalls2[3] and setCalls2[3].name or "none")

_G.GetTime = function() return 6009 end
local m4 = AB.BalanceAll()
check("BalanceAll settles with nothing left to do", m4 == 0, tostring(m4))

-- Regression: Balance() (aura-only, fired on almost every roster event)
-- and BalanceAll() (tank->healer->aura, fired once per Role Check resync)
-- used to share ONE `waitingFor` variable. A still-unsettled BalanceAll()
-- move (tank not yet landed) used to also block Balance() from doing its
-- own, completely unrelated aura-balance work - Balance() couldn't tell
-- "not settled because it's my own pending move" from "not settled
-- because it's someone else's". Separate waitingForAura/waitingForAll
-- variables fix this: an interleaved Balance() call must succeed on its
-- own unrelated aura excess even while BalanceAll()'s tank move is still
-- pending.
AB._ResetForTests()
local roster5 = {
    { name = "T1", sub = 1, role = "tank" },
    { name = "T2", sub = 1, role = "tank" }, -- excess tank
    { name = "A1", sub = 2, role = "aura" },
    { name = "A2", sub = 2, role = "aura" }, -- excess aura, unrelated to the tank move
}
_G.GetNumRaidMembers = function() return #roster5 end
_G.GetRaidRosterInfo = function(i)
    local r = roster5[i]
    if not r then return end
    return r.name, nil, r.sub
end
-- Simulates the tank's SetRaidSubgroup never landing within the
-- observation window (still-pending settle), while any other move (the
-- aura swap) applies normally.
_G.SetRaidSubgroup = function(i, to)
    local r = roster5[i]
    if r and r.name ~= "T2" then
        r.sub = to
    end
end
_G.SwapRaidSubgroup = function() end
local db5 = AscensionLFM.Database.Get()
db5.assignedRoles = { t1 = "tank", t2 = "tank", a1 = "aura", a2 = "aura" }
db5.autoMoveTank = true
db5.autoMoveHealer = true
db5.autoMoveAura = true

_G.GetTime = function() return 9000 end
local rm1 = AB.BalanceAll()
check("regression: BalanceAll starts the (still-pending) tank move", rm1 == 1, tostring(rm1))

_G.GetTime = function() return 9000.2 end -- well within SETTLE_TIMEOUT, tank move still unsettled
local rm2 = select(1, AB.Balance())
check("regression: interleaved Balance() still fixes its own unrelated aura excess",
    rm2 == 1, tostring(rm2))

-- Toggle off: autoMoveTank=false skips tank pass entirely.
AB._ResetForTests()
local roster3 = {
    { name = "T1", sub = 1, role = "tank" },
    { name = "T2", sub = 1, role = "tank" },
}
_G.GetNumRaidMembers = function() return #roster3 end
_G.GetRaidRosterInfo = function(i)
    local r = roster3[i]
    if not r then return end
    return r.name, nil, r.sub
end
local setCalls3 = {}
_G.SetRaidSubgroup = function(i, to)
    table.insert(setCalls3, to)
end
local db3 = AscensionLFM.Database.Get()
db3.assignedRoles = { t1 = "tank", t2 = "tank" }
db3.autoMoveTank = false
db3.autoMoveHealer = true
db3.autoMoveAura = true
_G.GetTime = function() return 7000 end
local m5 = AB.BalanceAll()
check("autoMoveTank=false skips tank pass", m5 == 0 and #setCalls3 == 0, tostring(m5))

print("tank/healer balance tests passed")
