-- AscensionLFM: core/Kick.lua
-- Opt-in Manastorm level-59 auto-kick with raid warnings (dangerous automation).
-- Pure selection helpers are WoW-free for unit tests.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Kick = {}
AscensionLFM.Kick = Kick

local DEFAULT_LEVEL = 59
local DEFAULT_INTERVAL = 10

local frame
local lastWarnAt = 0
local lastTickAt = 0

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function DB()
    if AscensionLFM.Database and AscensionLFM.Database.Get then
        return AscensionLFM.Database.Get()
    end
    return nil
end

local function PlayerName()
    if type(UnitName) == "function" then
        return UnitName("player")
    end
    return nil
end

--- Pure: members at/above kick level, excluding self.
-- @param roster { {name=string, level=number}, ... }
-- @param kickLevel number
-- @param selfName string|nil
-- @return { {name=, level=}, ... } sorted by name
function Kick.SelectTargets(roster, kickLevel, selfName)
    kickLevel = tonumber(kickLevel) or DEFAULT_LEVEL
    local selfKey = selfName and LowerName(selfName) or nil
    local out = {}
    if type(roster) ~= "table" then
        return out
    end
    for _, m in ipairs(roster) do
        if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            local lvl = tonumber(m.level) or 0
            if lvl >= kickLevel then
                if not selfKey or LowerName(m.name) ~= selfKey then
                    table.insert(out, { name = m.name, level = lvl })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return LowerName(a.name) < LowerName(b.name)
    end)
    return out
end

--- Pure: whether a warn/kick cycle may fire given last warn time.
function Kick.ShouldWarn(now, lastAt, interval)
    now = tonumber(now) or 0
    lastAt = tonumber(lastAt) or 0
    interval = tonumber(interval) or DEFAULT_INTERVAL
    if interval < 1 then
        interval = 1
    end
    return (now - lastAt) >= interval
end

--- Pure: build raid-warning text naming targets.
function Kick.BuildWarnMessage(targets, kickLevel)
    kickLevel = tonumber(kickLevel) or DEFAULT_LEVEL
    if type(targets) ~= "table" or #targets == 0 then
        return nil
    end
    local names = {}
    for _, t in ipairs(targets) do
        table.insert(names, string.format("%s (%d)", tostring(t.name), tonumber(t.level) or kickLevel))
    end
    return string.format(
        "AscensionLFM: level %d — kicking: %s",
        kickLevel,
        table.concat(names, ", ")
    )
end

function Kick.CanKick()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
        local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
        return lead or assist, "raid"
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    if party and party > 0 then
        if type(IsPartyLeader) == "function" then
            return IsPartyLeader() and true or false, "party"
        end
        return false, "party"
    end
    return false, "none"
end

local function BuildRoster()
    local roster = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 and type(GetRaidRosterInfo) == "function" then
        for i = 1, raid do
            local name, _, _, level = GetRaidRosterInfo(i)
            if type(name) == "string" and name ~= "" then
                local lvl = tonumber(level)
                if not lvl and type(UnitLevel) == "function" then
                    lvl = UnitLevel("raid" .. i)
                end
                table.insert(roster, { name = name, level = lvl or 0 })
            end
        end
        return roster
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        local name = type(UnitName) == "function" and UnitName(unit) or nil
        local lvl = type(UnitLevel) == "function" and UnitLevel(unit) or 0
        if type(name) == "string" and name ~= "" then
            table.insert(roster, { name = name, level = tonumber(lvl) or 0 })
        end
    end
    return roster
end

local function SendWarn(msg, groupKind)
    if type(SendChatMessage) ~= "function" or not msg then
        return false
    end
    if groupKind == "raid" then
        local ok = pcall(SendChatMessage, msg, "RAID_WARNING")
        if ok then
            return true
        end
        ok = pcall(SendChatMessage, msg, "RAID")
        if ok then
            return true
        end
        pcall(SendChatMessage, msg, "YELL")
        return true
    end
    -- Party: no RW channel — party chat, then yell fallback
    local ok = pcall(SendChatMessage, msg, "PARTY")
    if not ok then
        pcall(SendChatMessage, msg, "YELL")
    end
    return true
end

local function LogKick(name, level)
    local db = DB()
    local entry = {
        name = name,
        level = level,
        t = (type(time) == "function" and time()) or 0,
    }
    if db then
        if type(db.kickHistory) ~= "table" then
            db.kickHistory = {}
        end
        table.insert(db.kickHistory, 1, entry)
        while #db.kickHistory > 20 do
            table.remove(db.kickHistory)
        end
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(string.format("kicked %s at level %s", tostring(name), tostring(level)))
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshKicks then
        AscensionLFM.MainWindow.RefreshKicks()
    end
end

local function DoKick(name)
    if type(UninviteUnit) ~= "function" then
        return false, "UninviteUnit missing"
    end
    local ok, err = pcall(UninviteUnit, name)
    if not ok then
        return false, tostring(err)
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.ClearName then
        AscensionLFM.Slots.ClearName(name)
    end
    return true
end

--- One warn+kick cycle if enabled and privileged. Returns status string.
function Kick.Tick(now)
    now = tonumber(now) or Now()
    local db = DB()
    if not db or not db.autoKickLevel59 then
        return "disabled"
    end
    -- Only meaningful while hosting Manastorm runs
    if db.mode ~= "hosting" then
        return "not hosting"
    end

    local can, groupKind = Kick.CanKick()
    if not can then
        return "no privilege"
    end

    local kickLevel = tonumber(db.kickLevel) or DEFAULT_LEVEL
    local interval = tonumber(db.kickWarnInterval) or DEFAULT_INTERVAL
    if not Kick.ShouldWarn(now, lastWarnAt, interval) then
        return "rate limited"
    end

    local targets = Kick.SelectTargets(BuildRoster(), kickLevel, PlayerName())
    if #targets == 0 then
        return "none"
    end

    local msg = Kick.BuildWarnMessage(targets, kickLevel)
    SendWarn(msg, groupKind)
    lastWarnAt = now

    for _, t in ipairs(targets) do
        local ok = DoKick(t.name)
        if ok then
            LogKick(t.name, t.level)
        end
    end
    return "kicked", #targets
end

function Kick.Start()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(_, elapsed)
        lastTickAt = lastTickAt + (elapsed or 0)
        -- Poll every ~1s; internal rate limit enforces 10s warn/kick cadence
        if lastTickAt < 1 then
            return
        end
        lastTickAt = 0
        Kick.Tick(Now())
    end)
end

function Kick._ResetForTests()
    lastWarnAt = 0
    lastTickAt = 0
end

function Kick._SetLastWarnAt(t)
    lastWarnAt = tonumber(t) or 0
end

Kick.DEFAULT_LEVEL = DEFAULT_LEVEL
Kick.DEFAULT_INTERVAL = DEFAULT_INTERVAL
