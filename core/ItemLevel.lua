-- AscensionLFM: core/ItemLevel.lua
-- Average ilvl display + min-ilvl invite filter when Ascension APIs provide data.
--
-- Source of truth: AscensionLFM.API.GetAverageItemLevel(unit) →
-- UnitAverageItemLevel (extract-verified). Never invent a number.
-- Unknown (no unit / API missing / <=0) → hide display, pass filters.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local ItemLevel = {}
AscensionLFM.ItemLevel = ItemLevel

local CACHE_TTL = 90
local cache = {} -- [nameLower] = { avg=, t= }

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function SafeAvg(unit)
    if AscensionLFM.API and AscensionLFM.API.GetAverageItemLevel then
        return AscensionLFM.API.GetAverageItemLevel(unit)
    end
    return nil
end

--- Resolve a party/raid/player unit token for a display name, or nil.
function ItemLevel.FindUnit(name)
    local key = LowerName(name)
    if key == "" then
        return nil
    end
    if type(UnitName) == "function" then
        local me = UnitName("player")
        if me and LowerName(me) == key then
            return "player"
        end
    end
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            local n = type(UnitName) == "function" and UnitName(unit)
            if n and LowerName(n) == key then
                return unit
            end
        end
        return nil
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        local n = type(UnitName) == "function" and UnitName(unit)
        if n and LowerName(n) == key then
            return unit
        end
    end
    return nil
end

local function Remember(name, avg)
    if not avg or avg <= 0 then
        return
    end
    local key = LowerName(name)
    if key == "" then
        return
    end
    cache[key] = { avg = avg, t = Now() }
end

--- Fresh read for a unit token; caches by UnitName when possible.
function ItemLevel.GetForUnit(unit)
    if type(unit) ~= "string" or unit == "" then
        return nil
    end
    local avg = SafeAvg(unit)
    if avg and type(UnitName) == "function" then
        local n = UnitName(unit)
        if n then
            Remember(n, avg)
        end
    end
    return avg
end

--- Prefer live unit read; fall back to short-lived cache (re-whispers).
function ItemLevel.GetForName(name)
    local unit = ItemLevel.FindUnit(name)
    if unit then
        local avg = ItemLevel.GetForUnit(unit)
        if avg then
            return avg
        end
    end
    local key = LowerName(name)
    local entry = cache[key]
    if entry and entry.avg and entry.avg > 0 then
        if (Now() - (entry.t or 0)) <= CACHE_TTL then
            return entry.avg
        end
    end
    return nil
end

function ItemLevel.GetCached(name)
    local entry = cache[LowerName(name)]
    if entry and entry.avg and entry.avg > 0 then
        return entry.avg
    end
    return nil
end

--- Compact badge for queue rows: "i142" or "".
function ItemLevel.FormatBadge(avg)
    avg = tonumber(avg)
    if not avg or avg <= 0 then
        return ""
    end
    return string.format("i%d", math.floor(avg + 0.5))
end

--- Roster column: "59" / "59·142" / "i142" / "" — only real numbers.
function ItemLevel.FormatRoster(level, avg)
    level = tonumber(level) or 0
    avg = tonumber(avg)
    local hasIlvl = avg and avg > 0
    local iRounded = hasIlvl and math.floor(avg + 0.5) or nil
    if level > 0 and iRounded then
        return string.format("%d·%d", level, iRounded)
    end
    if iRounded then
        return string.format("i%d", iRounded)
    end
    if level > 0 then
        return tostring(level)
    end
    return ""
end

--- minIlvl <= 0 → off. Unknown avg → pass (never invent a block).
function ItemLevel.PassesMin(avg, minIlvl)
    minIlvl = tonumber(minIlvl) or 0
    if minIlvl <= 0 then
        return true
    end
    avg = tonumber(avg)
    if not avg or avg <= 0 then
        return true
    end
    return avg >= minIlvl
end

--- Scan visible group members into cache (Safe reads only).
function ItemLevel.RefreshGroupCache()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid > 0 then
        for i = 1, raid do
            ItemLevel.GetForUnit("raid" .. i)
        end
        return
    end
    ItemLevel.GetForUnit("player")
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        ItemLevel.GetForUnit("party" .. i)
    end
end

--- Test hook: wipe cache between unit tests.
function ItemLevel._ResetCacheForTests()
    cache = {}
end

return ItemLevel
