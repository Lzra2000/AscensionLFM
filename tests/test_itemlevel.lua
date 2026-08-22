-- AscensionLFM: tests/test_itemlevel.lua
-- Pure helpers for average-ilvl format/filter (no invent).

package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local passed, failed = 0, 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
        print("OK: " .. name)
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. tostring(detail)) or "") .. "\n")
    end
end

-- Minimal Safe + API stub (no WoW globals).
_G.AscensionLFM = {}
function AscensionLFM.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    return a
end

dofile("core/ItemLevel.lua")
local IL = AscensionLFM.ItemLevel

check("FormatBadge empty", IL.FormatBadge(nil) == "")
check("FormatBadge zero", IL.FormatBadge(0) == "")
check("FormatBadge rounds", IL.FormatBadge(141.6) == "i142")

check("FormatRoster level only", IL.FormatRoster(59, nil) == "59")
check("FormatRoster both", IL.FormatRoster(59, 141.6) == "59·142")
check("FormatRoster ilvl only", IL.FormatRoster(0, 120) == "i120")
check("FormatRoster empty", IL.FormatRoster(0, nil) == "")

check("PassesMin off", IL.PassesMin(50, 0) == true)
check("PassesMin unknown passes", IL.PassesMin(nil, 100) == true)
check("PassesMin below blocks", IL.PassesMin(90, 100) == false)
check("PassesMin equal ok", IL.PassesMin(100, 100) == true)
check("PassesMin above ok", IL.PassesMin(110, 100) == true)

-- Cache remember via GetForUnit with stubbed API + UnitName
_G.UnitName = function(unit)
    if unit == "player" then return "Host" end
    return nil
end
AscensionLFM.API = {
    GetAverageItemLevel = function(unit)
        if unit == "player" then return 133.4 end
        return nil
    end,
}
IL._ResetCacheForTests()
local avg = IL.GetForUnit("player")
check("GetForUnit returns API value", avg and math.abs(avg - 133.4) < 0.01, tostring(avg))
check("GetForName uses cache after leave", IL.GetCached("Host") ~= nil)
-- No unit → still cached
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
check("GetForName cache hit", math.abs((IL.GetForName("Host") or 0) - 133.4) < 0.01)

dofile("core/Reject.lua")
local Reject = AscensionLFM.Reject
check("ilvl low is rejectable", Reject.IsRejectableReason("ilvl low") == true)
local msg = Reject.FormatTemplate(
    "Sorry, dein ilvl liegt unter unserem Minimum ({ilvl} / min {min}).",
    "dps", "?", "?", 90, 120)
check("FormatTemplate ilvl/min", msg:find("90", 1, true) and msg:find("120", 1, true), msg)

print(string.format("test_itemlevel: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
