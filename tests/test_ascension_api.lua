-- AscensionLFM: tests/test_ascension_api.lua
-- Safe wrappers for C_Manastorm / C_LFG / C_GameMode (extract-verified only).

package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" - " .. tostring(detail)) or "") .. "\n")
    end
end

_G.AscensionLFM = nil
_G.C_Manastorm = nil
_G.C_LFG = nil
_G.C_GameMode = nil
_G.IsInInstance = nil

dofile("core/AscensionAPI.lua")

local AscensionLFM = assert(_G.AscensionLFM)
local Safe = assert(AscensionLFM.Safe)
local API = assert(AscensionLFM.API)

check("Safe nil fn returns nil", Safe(nil) == nil)
check("Safe error returns nil", Safe(function() error("boom") end) == nil)
check("Safe returns first value", Safe(function() return 42, "x" end) == 42)

local a, b = Safe(function() return 1, 2 end)
check("Safe returns multiple", a == 1 and b == 2)

check("HasManastorm false when absent", API.HasManastorm() == false)
check("IsInManastorm false when absent", API.IsInManastorm() == false)
check("GetActiveLevel nil when absent", API.GetActiveLevel() == nil)
check("ReadActiveManastorm nil when absent", API.ReadActiveManastorm() == nil)
check("CanUseManastorm nil when C_LFG absent", API.CanUseManastorm() == nil)

_G.IsInInstance = function() return true end
check("IsHostInsideInstance falls back to IsInInstance", API.IsHostInsideInstance() == true)

_G.C_Manastorm = {
    IsInManastorm = function() return false end,
    GetActiveLevel = function() return 7 end,
    GetActiveManastormID = function() return 99 end,
    GetActiveManastormType = function() return "GROUP" end,
    GetRewardModifier = function(id)
        assert(id == 99)
        return 1.0, 1.0, 1.5, 1.2
    end,
    GetMaxCompletedLevels = function(unit)
        assert(unit == "player")
        return nil, 10, 8, 6, 12
    end,
    CanEnter = function(level) return level == 5, { "OK" } end,
    CanLeave = function() return false, { "IN_COMBAT" } end,
}
-- Re-bind after mutating global — Meth looks up each call, so OK.

check("HasManastorm true", API.HasManastorm() == true)
check("IsInManastorm false prefers MS over instance", API.IsInManastorm() == false)
check("IsHostInsideInstance uses MS when present", API.IsHostInsideInstance() == false)

_G.C_Manastorm.IsInManastorm = function() return true end
check("IsInManastorm true", API.IsInManastorm() == true)
check("IsHostInsideInstance true in MS", API.IsHostInsideInstance() == true)

local snap = API.ReadActiveManastorm()
check("ReadActiveManastorm snapshot", snap and snap.level == 7 and snap.manastorm_id == 99
    and snap.manastorm_type == "GROUP" and snap.is_active == true, snap and snap.level)

local pct = API.GetGroupRewardBonusPercent()
check("GetGroupRewardBonusPercent 50 from 1.5", pct == 50, pct)

_G.C_Manastorm.GetRewardModifier = function() return 1.0, 1.0, 1.0, 1.0 end
check("GetGroupRewardBonusPercent nil at baseline", API.GetGroupRewardBonusPercent() == nil)

local _, solo, duo = API.GetMaxCompletedLevels("player")
check("GetMaxCompletedLevels solo/duo", solo == 10 and duo == 8, tostring(solo) .. "/" .. tostring(duo))

local canEnter, reasons = API.CanEnter(5)
check("CanEnter true", canEnter == true and reasons and reasons[1] == "OK")
check("CanEnter nil without level", API.CanEnter(nil) == nil)

local canLeave, leaveReasons = API.CanLeave()
check("CanLeave false", canLeave == false and leaveReasons and leaveReasons[1] == "IN_COMBAT")

_G.C_Manastorm.GetActiveLevel = function() error("ejected") end
check("GetActiveLevel swallows error", API.GetActiveLevel() == nil)

_G.C_LFG = {
    CanUseManastorm = function(self) return true, "ok" end,
    CanUseGroupFinder = function(self) return false, "CHALLENGES_NO_GROUP_FINDER" end,
}
local okMs, reasonMs = API.CanUseManastorm()
check("CanUseManastorm", okMs == true and reasonMs == "ok")
local okGf, reasonGf = API.CanUseGroupFinder()
check("CanUseGroupFinder", okGf == false and reasonGf == "CHALLENGES_NO_GROUP_FINDER")

_G.C_GameMode = {
    IsGameModeActive = function(self, mode) return mode == "WildCard" end,
}
check("IsGameModeActive WildCard", API.IsGameModeActive("WildCard") == true)
check("IsGameModeActive other", API.IsGameModeActive("Draft") == false)
check("IsGameModeActive nil mode", API.IsGameModeActive(nil) == nil)

io.write(string.format("ascension_api tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
