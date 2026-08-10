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
local KICK_DELAY = 0.6
local KICK_STAGGER = 0.35

local frame
local lastWarnAt = 0
local lastTickAt = 0
local lastStatus = "idle"
local lastDetail = nil
-- { targets = { {name=, level=}... }, readyAt = number }
local pending = nil

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function BareName(name)
    if type(name) ~= "string" then
        return nil
    end
    return name:match("^([^-]+)") or name
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

local function SetStatus(status, detail)
    lastStatus = status or "idle"
    lastDetail = detail
end

--- Pure: pick a usable level. UnitLevel recovers when roster reports 0 (offline
--- placeholder / not-yet-cached). Never treat 0 as “known”.
function Kick.ResolveLevel(unitLevel, rosterLevel)
    local u = tonumber(unitLevel) or 0
    local r = tonumber(rosterLevel) or 0
    if u > 0 then
        return u
    end
    if r > 0 then
        return r
    end
    return 0
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
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    local groupKind = "none"
    if raid and raid > 0 then
        groupKind = "raid"
    elseif party and party > 0 then
        groupKind = "party"
    else
        return false, "none"
    end

    -- Most reliable on 3.3.5a / Ascension for both party and raid lead.
    if type(UnitIsPartyLeader) == "function" and UnitIsPartyLeader("player") then
        return true, groupKind
    end

    if groupKind == "raid" then
        local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
        local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
        return lead or assist, "raid"
    end

    if type(IsPartyLeader) == "function" then
        return IsPartyLeader() and true or false, "party"
    end
    return false, "party"
end

--- Live roster with hardened level reads (UnitLevel preferred when > 0).
function Kick.BuildRoster()
    local roster = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            local name, rosterLevel
            if type(GetRaidRosterInfo) == "function" then
                local n, _, _, lvl = GetRaidRosterInfo(i)
                name = n
                rosterLevel = lvl
            end
            if (type(name) ~= "string" or name == "") and type(UnitName) == "function" then
                name = UnitName(unit)
            end
            if type(name) == "string" and name ~= "" then
                local unitLevel = (type(UnitLevel) == "function" and UnitLevel(unit)) or 0
                table.insert(roster, {
                    name = name,
                    level = Kick.ResolveLevel(unitLevel, rosterLevel),
                    unit = unit,
                })
            end
        end
        return roster
    end

    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        local name = type(UnitName) == "function" and UnitName(unit) or nil
        local unitLevel = type(UnitLevel) == "function" and UnitLevel(unit) or 0
        if type(name) == "string" and name ~= "" then
            table.insert(roster, {
                name = name,
                level = Kick.ResolveLevel(unitLevel, 0),
                unit = unit,
            })
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
    if type(name) ~= "string" or name == "" then
        return false, "no name"
    end
    -- Try roster name first (may be Name-Realm), then bare name.
    local attempts = { name }
    local bare = BareName(name)
    if bare and bare ~= name then
        table.insert(attempts, bare)
    end
    for _, id in ipairs(attempts) do
        local ok, err = pcall(UninviteUnit, id)
        if ok then
            if AscensionLFM.Slots and AscensionLFM.Slots.ClearName then
                AscensionLFM.Slots.ClearName(name)
                if bare and bare ~= name then
                    AscensionLFM.Slots.ClearName(bare)
                end
            end
            return true
        end
        -- keep last err
        if not ok and err then
            -- continue
        end
    end
    return false, "UninviteUnit failed"
end

local function ProcessPending(now)
    if not pending or type(pending.targets) ~= "table" then
        pending = nil
        return nil
    end
    if now < (tonumber(pending.readyAt) or 0) then
        SetStatus("pending", #pending.targets)
        return "pending"
    end
    local t = table.remove(pending.targets, 1)
    if not t then
        pending = nil
        SetStatus("none")
        return "none"
    end
    local ok, err = DoKick(t.name)
    if ok then
        LogKick(t.name, t.level)
        SetStatus("kicked", t.name)
    else
        SetStatus("kick failed", tostring(err or t.name))
        if AscensionLFM.Print then
            AscensionLFM.Print(string.format("kick failed for %s (%s)", tostring(t.name), tostring(err)))
        end
    end
    if #pending.targets == 0 then
        pending = nil
    else
        pending.readyAt = now + KICK_STAGGER
    end
    return ok and "kicked" or "kick failed"
end

local function IsHosting(db)
    return db and (db.mode == "hosting" or db.fullAutoHosting) and true or false
end

--- One warn+kick cycle if enabled and privileged. Returns status string.
function Kick.Tick(now)
    now = tonumber(now) or Now()

    -- Finish deferred uninvites even if toggles flip mid-cycle.
    if pending then
        local p = ProcessPending(now)
        if p then
            return p
        end
    end

    local db = DB()
    if not db or not db.autoKickLevel59 then
        SetStatus("disabled")
        return "disabled"
    end
    if not IsHosting(db) then
        SetStatus("not hosting")
        return "not hosting"
    end

    local can, groupKind = Kick.CanKick()
    if not can then
        SetStatus("no privilege", groupKind)
        return "no privilege"
    end

    local kickLevel = tonumber(db.kickLevel) or DEFAULT_LEVEL
    local interval = tonumber(db.kickWarnInterval) or DEFAULT_INTERVAL
    if not Kick.ShouldWarn(now, lastWarnAt, interval) then
        SetStatus("rate limited")
        return "rate limited"
    end

    local roster = Kick.BuildRoster()
    local targets = Kick.SelectTargets(roster, kickLevel, PlayerName())
    if #targets == 0 then
        -- Distinguish “nobody high enough” from “levels still 0 / unknown”.
        local unknown = 0
        local known = 0
        for _, m in ipairs(roster) do
            local lvl = tonumber(m.level) or 0
            if lvl <= 0 then
                unknown = unknown + 1
            else
                known = known + 1
            end
        end
        if #roster > 0 and known == 0 then
            SetStatus("levels unknown", unknown)
            return "levels unknown"
        end
        SetStatus("none")
        return "none"
    end

    local msg = Kick.BuildWarnMessage(targets, kickLevel)
    SendWarn(msg, groupKind)
    lastWarnAt = now
    -- Defer UninviteUnit slightly: same-frame chat+uninvite is flaky on some
    -- Ascension builds; stagger multi-target kicks.
    pending = {
        targets = targets,
        readyAt = now + KICK_DELAY,
    }
    SetStatus("warned", #targets)
    return "warned", #targets
end

function Kick.GetStatus()
    local db = DB()
    local can, groupKind = Kick.CanKick()
    return {
        enabled = db and db.autoKickLevel59 and true or false,
        hosting = IsHosting(db),
        last = lastStatus,
        detail = lastDetail,
        canKick = can and true or false,
        group = groupKind,
        pending = pending and #pending.targets or 0,
    }
end

function Kick.Start()
    if frame then
        return
    end
    if type(CreateFrame) ~= "function" then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(_, elapsed)
        lastTickAt = lastTickAt + (elapsed or 0)
        -- Poll every ~1s; internal rate limit enforces warn cadence
        if lastTickAt < 1 then
            -- Still drain deferred kicks on a faster cadence
            if pending then
                local now = Now()
                if now >= (tonumber(pending.readyAt) or 0) then
                    Kick.Tick(now)
                end
            end
            return
        end
        lastTickAt = 0
        Kick.Tick(Now())
    end)
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function()
        -- Roster changed: re-evaluate soon (pending kicks still drain via Tick)
        Kick.Tick(Now())
    end)
end

function Kick._ResetForTests()
    lastWarnAt = 0
    lastTickAt = 0
    lastStatus = "idle"
    lastDetail = nil
    pending = nil
end

function Kick._SetLastWarnAt(t)
    lastWarnAt = tonumber(t) or 0
end

function Kick._GetPending()
    return pending
end

Kick.DEFAULT_LEVEL = DEFAULT_LEVEL
Kick.DEFAULT_INTERVAL = DEFAULT_INTERVAL
Kick.KICK_DELAY = KICK_DELAY
