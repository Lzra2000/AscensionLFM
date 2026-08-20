-- AscensionLFM: tests/test_raid_marks.lua
-- RaidMarks.lua: pure BuildPlan (tank/healer -> icon assignment) + the
-- live-roster ClearAllMarks/AutoMark helpers. No test file existed for
-- this module before - added alongside the ClearAllMarks fix below.

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

_G.AscensionLFM = nil
dofile("core/RaidMarks.lua")
local RaidMarks = assert(_G.AscensionLFM.RaidMarks)

--------------------------------------------------------------------
-- BuildPlan: pure tank/healer name lists -> {nameLower = {icon=, role=}}
--------------------------------------------------------------------
local plan = RaidMarks.BuildPlan({ "Tanky", "Tanky2", "Tanky3" }, { "Healy", "Healy2" })
check("first tank gets Skull (8)", plan["tanky"] and plan["tanky"].icon == 8)
check("second tank gets Cross (7)", plan["tanky2"] and plan["tanky2"].icon == 7)
check("third tank has no icon left (only 2 tank icons)", plan["tanky3"] == nil)
check("first healer gets Square (6)", plan["healy"] and plan["healy"].icon == 6)
check("second healer gets Moon (5)", plan["healy2"] and plan["healy2"].icon == 5)

-- Same person listed as both tank and healer: tank (passed first) wins,
-- not overwritten by the healer pass.
local dual = RaidMarks.BuildPlan({ "Both" }, { "Both" })
check("dual-listed member keeps the tank assignment", dual["both"] and dual["both"].role == "tank")

check("empty lists produce an empty plan", next(RaidMarks.BuildPlan({}, {})) == nil)
check("nil lists produce an empty plan (no error)", next(RaidMarks.BuildPlan(nil, nil)) == nil)

--------------------------------------------------------------------
-- ClearAllMarks: must only clear icons this addon's own tank/healer set
-- uses (Skull/Cross/Square/Moon/Triangle = 8,7,6,5,4) - previously
-- cleared all 8 icons raid-wide unconditionally, wiping unrelated
-- manually-placed encounter markers (e.g. Star/Circle/Diamond for
-- interrupt/kill-priority) as a side effect of refreshing tank/healer
-- icons.
--------------------------------------------------------------------
_G.GetNumRaidMembers = function() return 3 end
-- raid1 = Skull (8, owned by this addon), raid2 = Star (1, a raid
-- leader's own manually-placed marker, NOT owned by this addon),
-- raid3 = no icon.
local icons = { [1] = 8, [2] = 1, [3] = nil }
_G.GetRaidTargetIndex = function(unit)
    local i = tonumber(unit:match("raid(%d+)"))
    return i and icons[i] or nil
end
local setCalls = {}
_G.SetRaidTarget = function(unit, icon)
    table.insert(setCalls, { unit = unit, icon = icon })
    local i = tonumber(unit:match("raid(%d+)"))
    if i then icons[i] = (icon ~= 0) and icon or nil end
    return true
end

local cleared = RaidMarks.ClearAllMarks()
check("ClearAllMarks only clears the one owned (Skull) icon", cleared == 1, tostring(cleared))
check("ClearAllMarks left raid1's Skull cleared", icons[1] == nil)
check("ClearAllMarks left raid2's Star untouched", icons[2] == 1, tostring(icons[2]))
check("ClearAllMarks never touched the unmarked raid3", #setCalls == 1 and setCalls[1].unit == "raid1")

-- No raid members: no-op, no error.
_G.GetNumRaidMembers = function() return 0 end
check("ClearAllMarks with no raid returns 0", RaidMarks.ClearAllMarks() == 0)

io.write(string.format("test_raid_marks: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
