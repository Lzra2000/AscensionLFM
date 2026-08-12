-- AscensionLFM: core/AuraScan.lua
-- Detect who actually has Aura of Experience (spell 818059) on the roster.
-- Cross-check against assigned "aura" role to flag liars; optional warn+kick.
-- Default OFF - same safety model as Kick59.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local AuraScan = {}
AscensionLFM.AuraScan = AuraScan

-- Live Ascension tooltip ID (Aura of Experience).
local AURA_SPELL_ID = 818059
local AURA_NAME = "Aura of Experience"
local AURA_NAME_LOWER = "aura of experience"

local DEFAULT_INTERVAL = 30
local KICK_DELAY = 0.6
local KICK_STAGGER = 0.35
local MAX_KICK_ATTEMPTS = 3
local VERIFY_DELAY = 1.5

local frame
local lastScanAt = 0
local lastWarnAt = 0
local lastFakePrintAt = 0
local lastStatus = "idle"
local lastDetail = nil
local lastLiars = {} -- { {name=, unit=, reason=}, ... }
local lastHasBuff = {} -- [nameLower] = true/false from last full scan
local pending = nil -- { targets=, readyAt= }
local pendingVerify = nil
local failedAttempts = {}
local gaveUp = {}
local lastTickAt = 0
-- Live feedback (Ascension): Aura of Experience often does NOT appear on other
-- players' UnitAura lists even when they own the item/buff. Flagging them as
-- "no visible buff" is then always a false positive. We only treat missing-buff as
-- evidence of a liar when we have observed the buff on at least one *other*
-- group member this session (proves the client can see it on others).
local seenBuffOnOther = false
local seenBuffOnOtherViaAura = false
local warnedUnreliable = false
-- Combat-log mirror (PlateBuffs-style): UnitAura often cannot see other players'
-- auras on Ascension. SPELL_AURA_* for spell 818059 is tracked by name key.
local cleuHasBuff = {} -- [nameLower] = true

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function IsInCombat()
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        if ok and v then return true end
    end
    if type(UnitAffectingCombat) == "function" then
        local ok, v = pcall(UnitAffectingCombat, "player")
        if ok and v then return true end
    end
    return false
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
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
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

local function IsHosting(db)
    db = db or DB()
    if not db then
        return false
    end
    return db.mode == "hosting" or db.fullAutoHosting == true
end

--- Does this unit currently have Aura of Experience?
-- Ascension API docs (BuffDocumentation / UnitDocumentation): UnitAura returns
--   name, rank, icon, count, dispelType, duration, expires, caster,
--   isStealable, shouldConsolidate, spellID
-- UnitBuff is NOT documented on this client - prefer UnitAura. Optional name
-- lookup (UnitAura(unit, "Aura of Experience")) when supported.
function AuraScan.UnitHasAuraOfExp(unit)
    if type(unit) ~= "string" or unit == "" then
        return false
    end

    local function matchAura(name, spellId)
        local sid = tonumber(spellId)
        if sid == AURA_SPELL_ID then
            return true
        end
        if type(name) == "string" then
            local ln = name:lower()
            if ln == AURA_NAME_LOWER or ln:find("aura of experience", 1, true) then
                return true
            end
        end
        return false
    end

    -- Preferred path (documented): UnitAura + HELPFUL filter + spellID.
    if type(UnitAura) == "function" then
        local ok, name, _, _, _, _, _, _, _, _, _, spellId = pcall(UnitAura, unit, AURA_NAME)
        if ok and matchAura(name, spellId) then
            return true
        end
        ok, name, _, _, _, _, _, _, _, _, _, spellId = pcall(UnitAura, unit, AURA_NAME, nil, "HELPFUL")
        if ok and matchAura(name, spellId) then
            return true
        end
        local i = 1
        while i <= 40 do
            local n, _, _, _, _, _, _, _, _, _, sid = UnitAura(unit, i, "HELPFUL")
            if not n then
                n, _, _, _, _, _, _, _, _, _, sid = UnitAura(unit, i)
                if not n then
                    break
                end
            end
            if matchAura(n, sid) then
                return true
            end
            i = i + 1
        end
    end

    -- Legacy fallback if UnitBuff still exists on this build.
    if type(UnitBuff) == "function" then
        local i = 1
        while i <= 40 do
            local n, _, _, _, _, _, _, _, _, _, sid = UnitBuff(unit, i)
            if not n then
                break
            end
            if matchAura(n, sid) then
                return true
            end
            i = i + 1
        end
    end
    return false
end

--- Pure: who is assigned aura but has no buff (liars).
-- @param assigned { [nameLower]=role }
-- @param hasBuff  { [nameLower]=bool }
-- @param present  { [nameLower]=displayName }
-- @param selfKey  nameLower of player (never flagged)
function AuraScan.SelectLiars(assigned, hasBuff, present, selfKey)
    local out = {}
    if type(assigned) ~= "table" or type(present) ~= "table" then
        return out
    end
    hasBuff = hasBuff or {}
    for key, role in pairs(assigned) do
        if role == "aura" and present[key] and (not selfKey or key ~= selfKey) then
            if hasBuff[key] ~= true then
                table.insert(out, {
                    name = present[key],
                    reason = "assigned aura, no Aura of Experience buff",
                })
            end
        end
    end
    table.sort(out, function(a, b)
        return LowerName(a.name) < LowerName(b.name)
    end)
    return out
end

function AuraScan.BuildWarnMessage(liars)
    if type(liars) ~= "table" or #liars == 0 then
        return nil
    end
    local names = {}
    for _, t in ipairs(liars) do
        table.insert(names, tostring(t.name))
    end
    return "AscensionLFM: buff not visible - checking aura seat: " .. table.concat(names, ", ")
end

local function CanWarnKick()
    if AscensionLFM.Kick and AscensionLFM.Kick.CanKick then
        return AscensionLFM.Kick.CanKick()
    end
    return false, "none"
end

local function SendWarn(msg, groupKind)
    if not seenBuffOnOtherViaAura then
        return false
    end
    if type(SendChatMessage) ~= "function" or not msg then
        return false
    end
    if groupKind == "raid" then
        if pcall(SendChatMessage, msg, "RAID_WARNING") then
            return true
        end
        if pcall(SendChatMessage, msg, "RAID") then
            return true
        end
        pcall(SendChatMessage, msg, "YELL")
        return true
    end
    if not pcall(SendChatMessage, msg, "PARTY") then
        pcall(SendChatMessage, msg, "YELL")
    end
    return true
end

local function DoKick(name)
    if type(UninviteUnit) ~= "function" then
        return false, "UninviteUnit missing"
    end
    if type(name) ~= "string" or name == "" then
        return false, "no name"
    end
    local attempts = { name }
    local bare = BareName(name)
    if bare and bare ~= name then
        table.insert(attempts, bare)
    end
    for _, id in ipairs(attempts) do
        local ok = pcall(UninviteUnit, id)
        if ok then
            if AscensionLFM.Slots and AscensionLFM.Slots.ClearName then
                AscensionLFM.Slots.ClearName(name)
                if bare and bare ~= name then
                    AscensionLFM.Slots.ClearName(bare)
                end
            end
            return true
        end
    end
    return false, "UninviteUnit failed"
end

local function LogKick(name, reason)
    local db = DB()
    local entry = {
        name = name,
        level = 0,
        reason = reason or "no visible buff",
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
        AscensionLFM.Print(string.format("kicked %s (no visible buff - no Aura of Experience)", tostring(name)))
    end
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("kick",
            string.format("%s - no visible Aura of Experience (%s)", tostring(name), tostring(reason or "no visible buff")),
            { name = name })
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshKicks then
        AscensionLFM.MainWindow.RefreshKicks()
    end
end

--- Scan current party/raid for Aura of Experience buffs.
-- @return hasBuff map, present map { [nameLower]=displayName }, unitByName
function AuraScan.ScanRoster()
    local hasBuff = {}
    local present = {}
    local unitByName = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local unit = "raid" .. i
            local name
            if type(GetRaidRosterInfo) == "function" then
                name = GetRaidRosterInfo(i)
            end
            if (type(name) ~= "string" or name == "") and type(UnitName) == "function" then
                name = UnitName(unit)
            end
            if type(name) == "string" and name ~= "" then
                local key = LowerName(name)
                present[key] = name
                unitByName[key] = unit
                hasBuff[key] = AuraScan.UnitHasAuraOfExp(unit) and true or false
            end
        end
        return hasBuff, present, unitByName
    end
    -- party: include self
    if type(UnitName) == "function" then
        local me = UnitName("player")
        if type(me) == "string" and me ~= "" then
            local key = LowerName(me)
            present[key] = me
            unitByName[key] = "player"
            hasBuff[key] = AuraScan.UnitHasAuraOfExp("player") and true or false
        end
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        local name = type(UnitName) == "function" and UnitName(unit) or nil
        if type(name) == "string" and name ~= "" then
            local key = LowerName(name)
            present[key] = name
            unitByName[key] = unit
            hasBuff[key] = AuraScan.UnitHasAuraOfExp(unit) and true or false
        end
    end
    return hasBuff, present, unitByName
end

--- True when this client has seen Aura of Experience on someone who is not the player.
--- Combat-log path (Ascension-Addons/PlateBuffs pattern): track SPELL_AURA_* for
-- Aura of Experience when UnitAura cannot see the buff on other units.
function AuraScan.OnCombatLog(...)
    local argc = select("#", ...)
    if argc < 9 then
        return
    end
    -- 3.3.5: ts, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, ...
    -- Some Ascension builds insert hideCaster as arg 3 - detect by type.
    local event, dstName, spellId
    local a2 = select(2, ...)
    if type(a2) == "string" and a2:find("SPELL_AURA", 1, true) then
        event = a2
        dstName = select(7, ...)
        spellId = select(9, ...)
    else
        -- possible hideCaster at 3
        event = select(2, ...)
        if type(select(3, ...)) == "boolean" then
            -- hideCaster present (modern layout): dstName=9, spellId=12.
            event = select(2, ...)
            dstName = select(9, ...)
            spellId = select(12, ...)
        else
            event = a2
            dstName = select(7, ...)
            spellId = select(9, ...)
        end
    end
    if type(event) ~= "string" or not event:find("SPELL_AURA", 1, true) then
        return
    end
    if tonumber(spellId) ~= AURA_SPELL_ID then
        -- also accept by name in spell field
        local spellName = nil
        if type(select(3, ...)) == "boolean" then
            spellName = select(13, ...)
        else
            spellName = select(10, ...)
        end
        if type(spellName) == "string" then
            if not spellName:lower():find("aura of experience", 1, true) then
                return
            end
        else
            return
        end
    end
    if type(dstName) ~= "string" or dstName == "" then
        return
    end
    local key = LowerName(dstName)
    if event:find("REMOVED", 1, true) then
        cleuHasBuff[key] = nil
    else
        -- APPLIED / REFRESH / APPLIED_DOSE
        cleuHasBuff[key] = true
        local selfKey = LowerName(PlayerName())
        if key ~= selfKey then
            seenBuffOnOther = true
        end
    end
end

function AuraScan.GetReliabilityNote()
    if seenBuffOnOther then
        return "Buff visible on others (UnitAura and/or combat log) - liar check active."
    end
    return "Buff NOT visible on other players yet - auto-kick idle. Ascension often hides Aura of Experience."
end

function AuraScan.CanSeeBuffOnOthers()
    return seenBuffOnOtherViaAura and true or false
end

--- Full scan + liar selection. Updates lastLiars / lastHasBuff.
-- Does NOT flag liars unless CanSeeBuffOnOthers() - otherwise every aura seat
-- would be a false positive on Ascension (buff not shown on other units).
function AuraScan.Scan()
    local hasBuff, present, unitByName = AuraScan.ScanRoster()
    local selfKey = LowerName(PlayerName())
    for key, on in pairs(hasBuff) do
        if on and key ~= selfKey then
            seenBuffOnOtherViaAura = true
            seenBuffOnOther = true
            break
        end
    end
    for key, on in pairs(cleuHasBuff) do
        if on then
            hasBuff[key] = true
            if key ~= selfKey then
                seenBuffOnOther = true
            end
        end
    end
    lastHasBuff = hasBuff
    lastScanAt = Now()
    local assigned = {}
    local db = DB()
    if db and type(db.assignedRoles) == "table" then
        assigned = db.assignedRoles
    elseif AscensionLFM.Slots and AscensionLFM.Slots.GetAllAssigned then
        assigned = AscensionLFM.Slots.GetAllAssigned() or {}
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.GetAssigned then
        for key, disp in pairs(present) do
            local role = AscensionLFM.Slots.GetAssigned(disp) or AscensionLFM.Slots.GetAssigned(key)
            if role then
                assigned[key] = role
            end
        end
    end
    local liars = {}
    if seenBuffOnOtherViaAura then
        liars = AuraScan.SelectLiars(assigned, hasBuff, present, selfKey)
    else
        -- Detection unreliable on this client/session: do not accuse.
        SetStatus("unreliable", "buff not visible on other players")
    end
    lastLiars = liars
    return liars, hasBuff, present
end

--- Manual / status: how many people currently show the buff.
function AuraScan.CountBuffHolders()
    local n = 0
    for _, v in pairs(lastHasBuff) do
        if v then
            n = n + 1
        end
    end
    return n
end

function AuraScan.GetLiars()
    return lastLiars
end

local function ProcessPending(now)
    if not pending then
        return nil
    end
    if now < (tonumber(pending.readyAt) or 0) then
        return "pending"
    end
    if IsInCombat() then
        SetStatus("in combat", #pending.targets)
        pending.readyAt = now + 1.5
        return "in combat"
    end
    local t = table.remove(pending.targets, 1)
    if not t then
        pending = nil
        return "done"
    end
    local ok = DoKick(t.name)
    if ok then
        pendingVerify = {
            name = t.name,
            reason = t.reason or "no visible buff",
            checkAt = now + VERIFY_DELAY,
        }
        if #pending.targets > 0 then
            pending.readyAt = now + KICK_STAGGER
        else
            pending = nil
        end
        return "kicking"
    end
    local key = LowerName(t.name)
    failedAttempts[key] = (failedAttempts[key] or 0) + 1
    if failedAttempts[key] >= MAX_KICK_ATTEMPTS then
        gaveUp[key] = true
        if AscensionLFM.Print then
            AscensionLFM.Print("AuraScan: giving up on " .. tostring(t.name))
        end
    end
    if #pending.targets == 0 then
        pending = nil
    else
        pending.readyAt = now + KICK_STAGGER
    end
    return "kick failed"
end

local function CheckVerify(now)
    if not pendingVerify then
        return nil
    end
    if now < (tonumber(pendingVerify.checkAt) or 0) then
        return "verifying"
    end
    local name = pendingVerify.name
    local reason = pendingVerify.reason
    pendingVerify = nil
    local _, present = AuraScan.ScanRoster()
    if not present[LowerName(name)] then
        LogKick(name, reason)
        SetStatus("kicked", name)
        return "kicked"
    end
    failedAttempts[LowerName(name)] = (failedAttempts[LowerName(name)] or 0) + 1
    if failedAttempts[LowerName(name)] >= MAX_KICK_ATTEMPTS then
        gaveUp[LowerName(name)] = true
    end
    SetStatus("still in group", name)
    return "still in group"
end

function AuraScan.Tick(now)
    now = tonumber(now) or Now()
    if pendingVerify then
        local v = CheckVerify(now)
        if v then
            return v
        end
    end
    if pending then
        local p = ProcessPending(now)
        if p then
            return p
        end
    end

    local db = DB()
    if not db or not db.auraScanEnabled then
        SetStatus("disabled")
        return "disabled"
    end
    if not IsHosting(db) then
        SetStatus("not hosting")
        return "not hosting"
    end
    -- Do not warn/kick while the client cannot see this buff on other players
    -- (live Ascension: buff is client-local / not synced - every "aura" was a FP).
    if not seenBuffOnOtherViaAura then
        -- Still scan occasionally to discover if visibility appears
        local interval = tonumber(db.auraScanInterval) or DEFAULT_INTERVAL
        if interval < 5 then interval = 5 end
        if (now - lastScanAt) >= interval then
            AuraScan.Scan()
        end
        if not warnedUnreliable and AscensionLFM.Print then
            warnedUnreliable = true
            AscensionLFM.Print("AuraScan: buff not visible on other players - liar kick idle (Ascension limit)")
        end
        SetStatus("unreliable")
        return "unreliable"
    end

    local interval = tonumber(db.auraScanInterval) or DEFAULT_INTERVAL
    if interval < 5 then
        interval = 5
    end
    if (now - lastScanAt) < interval and lastScanAt > 0 then
        SetStatus("rate limited")
        return "rate limited"
    end

    local liars = AuraScan.Scan()
    if #liars == 0 then
        SetStatus("clean", AuraScan.CountBuffHolders())
        return "clean"
    end

    -- Silent by default (chat spam was unbearable). Only ScanNow / auto-kick warn talk.
    if not db.auraScanAutoKick then
        SetStatus("liars (no auto-kick)", #liars)
        return "liars"
    end

    if IsInCombat() then
        SetStatus("in combat", #liars)
        return "in combat"
    end

    local can, groupKind = CanWarnKick()
    if not can then
        SetStatus("no privilege", groupKind)
        return "no privilege"
    end

    local warnGap = tonumber(db.auraScanWarnInterval) or DEFAULT_INTERVAL
    if warnGap < 5 then
        warnGap = 5
    end
    if lastWarnAt > 0 and (now - lastWarnAt) < warnGap then
        SetStatus("warn rate limited", #liars)
        return "warn rate limited"
    end

    local targets = {}
    for _, t in ipairs(liars) do
        if not gaveUp[LowerName(t.name)] then
            table.insert(targets, t)
        end
    end
    if #targets == 0 then
        SetStatus("given up", #liars)
        return "given up"
    end

    local msg = AuraScan.BuildWarnMessage(targets)
    SendWarn(msg, groupKind)
    lastWarnAt = now
    pending = {
        targets = targets,
        readyAt = now + KICK_DELAY,
    }
    SetStatus("warned", #targets)
    return "warned", #targets
end

--- One-shot scan from UI / slash: print results, no auto-kick required.
function AuraScan.ScanNow()
    local liars, hasBuff, present = AuraScan.Scan()
    local withBuff = 0
    local total = 0
    for key, _ in pairs(present) do
        total = total + 1
        if hasBuff[key] then
            withBuff = withBuff + 1
        end
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(string.format(
            "Aura scan: %d/%d members show Aura of Experience (spell %d) on YOUR client",
            withBuff, total, AURA_SPELL_ID
        ))
        if not seenBuffOnOther then
            AscensionLFM.Print("WARNING: this client never sees Aura of Experience on OTHER players.")
            AscensionLFM.Print("Auto liar-detect/kick is DISABLED until the buff is visible on someone else.")
            AscensionLFM.Print("(Ascension often hides this buff from other clients - not a player lie.)")
        elseif #liars == 0 then
            AscensionLFM.Print("No mismatches (assigned aura seats show the buff).")
        else
            for _, t in ipairs(liars) do
                AscensionLFM.Print("MISSING BUFF: " .. tostring(t.name) .. " - " .. tostring(t.reason))
            end
        end
    end

    SetStatus(#liars > 0 and "liars" or "clean", #liars)
    return liars, withBuff, total
end

function AuraScan.GetStatus()
    local db = DB()
    local can, groupKind = CanWarnKick()
    return {
        enabled = db and db.auraScanEnabled and true or false,
        autoKick = db and db.auraScanAutoKick and true or false,
        hosting = IsHosting(db),
        last = lastStatus,
        detail = lastDetail,
        liars = #lastLiars,
        withBuff = AuraScan.CountBuffHolders(),
        canKick = can and true or false,
        group = groupKind,
        spellId = AURA_SPELL_ID,
        lastScanAt = lastScanAt,
        canSeeOnOthers = seenBuffOnOtherViaAura and true or false,
    }
end

function AuraScan.Start()
    if frame then
        return
    end
    if type(CreateFrame) ~= "function" then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(_, elapsed)
        lastTickAt = lastTickAt + (elapsed or 0)
        local now = Now()
        if pendingVerify and now >= (tonumber(pendingVerify.checkAt) or 0) then
            AuraScan.Tick(now)
            lastTickAt = 0
            return
        end
        if pending and now >= (tonumber(pending.readyAt) or 0) then
            AuraScan.Tick(now)
            lastTickAt = 0
            return
        end
        if lastTickAt < 2 then
            return
        end
        lastTickAt = 0
        AuraScan.Tick(now)
    end)
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            AuraScan.OnCombatLog(...)
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if pending and type(pending.targets) == "table" then
                pending.readyAt = 0
            end
            -- do not force full scan; OnUpdate will pick up pending
            return
        end
        -- UNIT_AURA / roster: do NOT reset lastScanAt (that caused 1s spam + bar flicker).
        -- OnUpdate + interval handles full scans.
        return
    end)
end

function AuraScan._ResetForTests()
    lastScanAt = 0
    lastWarnAt = 0
    lastStatus = "idle"
    lastDetail = nil
    lastLiars = {}
    lastHasBuff = {}
    pending = nil
    pendingVerify = nil
    failedAttempts = {}
    gaveUp = {}
    lastTickAt = 0
    seenBuffOnOther = false
    seenBuffOnOtherViaAura = false
    warnedUnreliable = false
    cleuHasBuff = {}
end

AuraScan.AURA_SPELL_ID = AURA_SPELL_ID
AuraScan.AURA_NAME = AURA_NAME
AuraScan.DEFAULT_INTERVAL = DEFAULT_INTERVAL
