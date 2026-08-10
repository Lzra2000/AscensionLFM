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
