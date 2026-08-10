-- AscensionLFM: tests/test_aura_rolecheck.lua

local function Fail(msg)
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    os.exit(1)
end

local function check(name, cond)
    if not cond then
        Fail(name)
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

-- Aura plan: two auras in group 1 → move one to empty group
local members = {
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 1, isAura = true },
    { name = "D1", index = 3, subgroup = 1, isAura = false },
    { name = "D2", index = 4, subgroup = 2, isAura = false },
}
local moves = AscensionLFM.AuraBalance.PlanMoves(members)
check("plans one move", #moves == 1)
check("moves excess aura out of g1", moves[1].from == 1 and moves[1].to ~= 1)
check("name is A2 (higher index kept second)", moves[1].name == "A2")

-- Already balanced
moves = AscensionLFM.AuraBalance.PlanMoves({
    { name = "A1", index = 1, subgroup = 1, isAura = true },
    { name = "A2", index = 2, subgroup = 2, isAura = true },
})
check("no moves when one aura per group", #moves == 0)

-- Role check duration clamp
check("clamp low", AscensionLFM.RoleCheck.ClampDuration(5) == 15)
check("clamp high", AscensionLFM.RoleCheck.ClampDuration(999) == 300)
check("clamp mid", AscensionLFM.RoleCheck.ClampDuration(60) == 60)

check("inactive by default", AscensionLFM.RoleCheck.IsActive(1000) == false)

print("aura/rolecheck tests passed")
