-- AscensionLFM: tests/test_spec_role.lua
-- SpecRole.lua: keyword -> role matching (pure) + talent-tab fallback path.

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
dofile("core/Database.lua")
dofile("core/Slots.lua")
dofile("core/SpecRole.lua")

local AscensionLFM = _G.AscensionLFM
local SpecRole = assert(AscensionLFM.SpecRole)

--------------------------------------------------------------------
-- _MatchRole: pure keyword -> role classification.
--------------------------------------------------------------------
check("protection matches tank", SpecRole._MatchRole("Protection") == "tank")
check("prot matches tank", SpecRole._MatchRole("Prot") == "tank")
check("blood matches tank", SpecRole._MatchRole("Blood") == "tank")
check("guardian matches tank", SpecRole._MatchRole("Guardian") == "tank")

check("holy matches healer", SpecRole._MatchRole("Holy") == "healer")
check("discipline matches healer", SpecRole._MatchRole("Discipline") == "healer")
check("restoration matches healer", SpecRole._MatchRole("Restoration") == "healer")
check("mistweaver matches healer", SpecRole._MatchRole("Mistweaver") == "healer")

-- v0.4.131: aura is a tag, not a seat. A spec that ONLY reads as aura seats
-- as DPS and carries the tag - the same rule Parser uses for a bare "aura"
-- whisper. Previously this assigned the host role="aura", which is no longer
-- a valid combat role and would leave them reading as unseated.
local sr, sa = SpecRole._MatchRole("Aura Specialist")
check("aura-only spec seats as dps", sr == "dps", tostring(sr))
check("aura-only spec carries the tag", sa == true, tostring(sa))

sr, sa = SpecRole._MatchRole("Path of Experience")
check("experience spec seats as dps", sr == "dps", tostring(sr))
check("experience spec carries the tag", sa == true, tostring(sa))

-- A spec naming BOTH a combat role and an aura must report both halves,
-- not collapse to one (the whole point of the tag model).
sr, sa = SpecRole._MatchRole("Fire Aura of Experience")
check("combat+aura spec keeps the combat seat", sr == "dps", tostring(sr))
check("combat+aura spec keeps the tag", sa == true, tostring(sa))

sr, sa = SpecRole._MatchRole("Protection Aura")
check("tank spec with aura keeps the tank seat", sr == "tank", tostring(sr))
check("tank spec with aura keeps the tag", sa == true, tostring(sa))

sr, sa = SpecRole._MatchRole("Frost")
check("plain combat spec has no aura tag", sr == "dps" and sa == false,
    tostring(sr) .. "/" .. tostring(sa))

check("fury matches dps", SpecRole._MatchRole("Fury") == "dps")
check("shadow matches dps", SpecRole._MatchRole("Shadow") == "dps")
check("retribution matches dps", SpecRole._MatchRole("Retribution") == "dps")
check("beast mastery matches dps", SpecRole._MatchRole("Beast Mastery") == "dps")

check("unrecognized text matches nothing", SpecRole._MatchRole("Wildcard Path") == nil)
check("empty string matches nothing", SpecRole._MatchRole("") == nil)
check("nil matches nothing", SpecRole._MatchRole(nil) == nil)

-- Order matters: tank/heal/aura are checked before the generic dps bucket
-- (e.g. a name mentioning both "Protection" and "dps" should read as tank).
check("tank keyword takes priority over dps keyword",
    SpecRole._MatchRole("Protection dps spec") == "tank")

-- Case-insensitive.
check("case-insensitive match", SpecRole._MatchRole("HOLY") == "healer")

--------------------------------------------------------------------
-- GuessFromActiveSpec: classic 3.3.5a talent-tab fallback (no
-- SpecializationUtil global present - falls through to
-- GetNumTalentTabs/GetTalentTabInfo, picking whichever tab has the most
-- invested points).
--------------------------------------------------------------------
_G.SpecializationUtil = nil
_G.GetNumTalentTabs = function() return 3 end
_G.GetTalentTabInfo = function(i)
    local tabs = {
        { "Arms", nil, nil, 12 },
        { "Protection", nil, nil, 31 }, -- most points invested -> active spec
        { "Fury", nil, nil, 8 },
    }
    local t = tabs[i]
    if not t then return nil end
    return t[1], t[2], t[3], t[4]
end
local role, src = SpecRole.GuessFromActiveSpec()
check("talent-tab fallback picks highest-invested tab", src == "Protection", tostring(src))
check("talent-tab fallback maps Protection to tank", role == "tank", tostring(role))

-- No talent APIs at all and no SpecializationUtil - fails soft (nil, nil),
-- never errors.
_G.GetNumTalentTabs = nil
_G.GetTalentTabInfo = nil
local role2, src2 = SpecRole.GuessFromActiveSpec()
check("no talent API available fails soft", role2 == nil and src2 == nil)

--------------------------------------------------------------------
-- ApplyToSelf: assigns the guessed role to the player via Slots.
--------------------------------------------------------------------
_G.GetNumTalentTabs = function() return 1 end
_G.GetTalentTabInfo = function(i)
    if i == 1 then return "Holy", nil, nil, 25 end
    return nil
end
_G.UnitName = function(u) if u == "player" then return "Lazra" end return nil end
AscensionLFM.Slots.ClearAll()
local appliedRole = SpecRole.ApplyToSelf()
check("ApplyToSelf returns the guessed role", appliedRole == "healer", tostring(appliedRole))
check("ApplyToSelf assigns via Slots", AscensionLFM.Slots.GetAssigned("Lazra") == "healer",
    tostring(AscensionLFM.Slots.GetAssigned("Lazra")))

-- No usable spec info: ApplyToSelf returns nil, doesn't touch Slots.
_G.GetNumTalentTabs = nil
_G.GetTalentTabInfo = nil
AscensionLFM.Slots.ClearAll()
local appliedRole2 = SpecRole.ApplyToSelf()
check("ApplyToSelf returns nil when nothing to guess from", appliedRole2 == nil)
check("ApplyToSelf makes no assignment when nothing to guess from",
    AscensionLFM.Slots.GetAssigned("Lazra") == nil)

io.write(string.format("test_spec_role: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
