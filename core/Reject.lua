-- AscensionLFM: core/Reject.lua
-- Opt-in reject re-whisper when invite is denied (slot/group full, no/unaccepted role).
-- Pure helpers are WoW-free for unit tests.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Reject = {}
AscensionLFM.Reject = Reject

local lastRejectAt = {} -- [nameLower] = GetTime()
local sessionIgnore = {} -- [nameLower] = true (session: do not re-whisper again)
local lastGlobalRejectAt = 0 -- gap between any two reject whispers (anti-flood)
local slotFullWindow = {} -- [role] = { startAt=, count= } quiet after N slot-full rejects
local SLOT_FULL_MAX = 2 -- whispers per role per window
local SLOT_FULL_WINDOW = 60 -- seconds
local GLOBAL_GAP = 2.5 -- min seconds between any reject whispers

local DEFAULT_TEMPLATES = {
    ["slot full"] = "Sorry, {role} is full ({filled}/{max}).",
    full = "Group is full - thanks!",
    -- Since v0.4.131 aura is a tag, not a seat you can apply for: telling
    -- applicants to whisper "aura" as their role asks for something the
    -- addon can no longer honour (it seats them as dps anyway).
    ["no role"] = "Please whisper a role: tank / heal / dps - add 'aura' if you bring one.",
    ["no parse"] = "Please whisper a role: tank / heal / dps - add 'aura' if you bring one.",
    ["role filtered"] = "Not looking for {role} right now - thanks!",
    ["prefer support seat"] = "Saving the last seats for tank/heal or an aura carrier - try again if one opens up!",
    ["dps seat reserved for aura"] = "DPS seats are held for aura carriers right now - whisper again with 'aura' if you have one!",
    -- Only fired when Ascension UnitAverageItemLevel is known and below db.minIlvl.
    ["ilvl low"] = "Sorry, dein ilvl liegt unter unserem Minimum ({ilvl} / min {min}).",
}

local REJECTABLE = {
    ["slot full"] = true,
    full = true,
    ["no role"] = true,
    ["no parse"] = true,
    ["role filtered"] = true,
    ["prefer support seat"] = true,
    -- A held-back DPS applicant is a real, understood block (same class as
    -- "prefer support seat"), so they get told why instead of being
    -- silently dropped - and the reply tells them how to get in.
    ["dps seat reserved for aura"] = true,
    ["ilvl low"] = true,
}

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

local function IsIgnoredName(name)
    if type(IsIgnored) == "function" then
        local ok, result = pcall(IsIgnored, name)
        if ok and result then
            return true
        end
    end
    local db = DB()
    if db and type(db.rejectIgnoreList) == "table" then
        if db.rejectIgnoreList[LowerName(name)] then
            return true
        end
    end
    if sessionIgnore[LowerName(name)] then
        return true
    end
    return false
end

--- Pure: substitute {role} {filled} {max} [{ilvl} {min}] in a template.
function Reject.FormatTemplate(template, role, filled, max, ilvl, minIlvl)
    template = tostring(template or "")
    role = tostring(role or "role")
    filled = tostring(filled ~= nil and filled or "?")
    max = tostring(max ~= nil and max or "?")
    template = template:gsub("{role}", role)
    template = template:gsub("{filled}", filled)
    template = template:gsub("{max}", max)
    template = template:gsub("{ilvl}", tostring(ilvl ~= nil and ilvl or "?"))
    template = template:gsub("{min}", tostring(minIlvl ~= nil and minIlvl or "?"))
    return template
end

--- Pure: whether an invite-failure reason should trigger a reject whisper.
function Reject.IsRejectableReason(reason)
    return REJECTABLE[tostring(reason or "")] == true
end

--- Resolve template string for a reason (db overrides or defaults).
function Reject.TemplateForReason(reason, db)
    db = db or DB()
    reason = tostring(reason or "")
    if db and type(db.rejectTemplates) == "table" and db.rejectTemplates[reason] then
        return tostring(db.rejectTemplates[reason])
    end
    -- Single custom override applied to slot-full path when set
    if reason == "slot full" and db and db.rejectTemplate and db.rejectTemplate ~= "" then
        return tostring(db.rejectTemplate)
    end
    return DEFAULT_TEMPLATES[reason] or "Sorry, not a fit right now."
end

--- Filled/max for template: role slot when slot-full, else group size / maxPartySize.
local function CountsForReason(reason, role, db)
    local filled, max = "?", "?"
    if reason == "slot full" and role and AscensionLFM.Slots then
        filled = AscensionLFM.Slots.CountFilled and AscensionLFM.Slots.CountFilled(role) or 0
        max = AscensionLFM.Slots.GetMax and AscensionLFM.Slots.GetMax(role) or 0
    elseif reason == "full" then
        if AscensionLFM.Invite and AscensionLFM.Invite.GetGroupSize then
            filled = AscensionLFM.Invite.GetGroupSize()
        end
        max = (db and db.maxPartySize) or 15
    elseif role and AscensionLFM.Slots then
        filled = AscensionLFM.Slots.CountFilled and AscensionLFM.Slots.CountFilled(role) or 0
        max = AscensionLFM.Slots.GetMax and AscensionLFM.Slots.GetMax(role) or 0
    end
    return filled, max
end

function Reject.BuildMessage(reason, role, db, extra)
    db = db or DB()
    local filled, max = CountsForReason(reason, role, db)
    local tmpl = Reject.TemplateForReason(reason, db)
    extra = type(extra) == "table" and extra or {}
    return Reject.FormatTemplate(
        tmpl, role or "role", filled, max,
        extra.ilvl, extra.minIlvl or (db and db.minIlvl))
end

--- Send reject whisper if enabled + rate-limit / ignore allow.
-- @param extra optional { ilvl=, minIlvl= } for "ilvl low" templates
-- @return ok, err
function Reject.TryRewhisper(name, reason, role, extra)
    local db = DB()
    if not db or not db.rejectRewhisper then
        return false, "disabled"
    end
    if not Reject.IsRejectableReason(reason) then
        return false, "not rejectable"
    end
    if type(name) ~= "string" or name == "" then
        return false, "bad name"
    end
    if IsIgnoredName(name) then
        return false, "ignored"
    end
    local cd = tonumber(db.rejectCooldown) or 30
    if cd < 5 then
        cd = 5
    end
    local key = LowerName(name)
    local last = lastRejectAt[key]
    if last and (Now() - last) < cd then
        return false, "cooldown"
    end
    local now = Now()
    -- Global gap: avoid reject whisper floods when 10 people apply at once
    if (now - lastGlobalRejectAt) < GLOBAL_GAP then
        return false, "global gap"
    end
    -- Slot-full: after SLOT_FULL_MAX whispers for the same role in the window,
    -- stay quiet (still queues via Invite) until the window expires.
    reason = tostring(reason or "")
    if reason == "slot full" then
        local rkey = tostring(role or "role")
        local w = slotFullWindow[rkey]
        if not w or (now - (w.startAt or 0)) >= SLOT_FULL_WINDOW then
            w = { startAt = now, count = 0 }
            slotFullWindow[rkey] = w
        end
        if (w.count or 0) >= SLOT_FULL_MAX then
            return false, "slot full quiet"
        end
    end
    if type(SendChatMessage) ~= "function" then
        return false, "SendChatMessage missing"
    end
    local msg = Reject.BuildMessage(reason, role, db, extra)
    if msg == "" then
        return false, "empty"
    end
    local ok, err = pcall(SendChatMessage, msg:sub(1, 255), "WHISPER", nil, name)
    if not ok then
        return false, tostring(err)
    end
    lastRejectAt[key] = now
    lastGlobalRejectAt = now
    if reason == "slot full" then
        local rkey = tostring(role or "role")
        local w = slotFullWindow[rkey]
        if w then
            w.count = (w.count or 0) + 1
        end
    end
    -- Optional: add to session ignore so we do not spam the same applicant
    if db.rejectSessionIgnore ~= false then
        sessionIgnore[key] = true
    end
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("reject", name .. " * " .. tostring(reason) .. " * " .. msg, {
            name = name,
            role = role,
            detail = reason,
        })
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("reject -> " .. tostring(name) .. ": " .. msg)
    end
    return true
end

--- Add / remove permanent reject-ignore (no re-whisper). reason is
-- optional free text (why they're blocked - the actual "hall of shame"
-- record); db.rejectIgnoreList itself stays a plain boolean map for
-- backward compat with every existing IsIgnoredName truthiness check
-- across the addon (Invite.CanInvite, Scanner whisper filtering, etc.) -
-- db.hallOfShame is the richer record layered on top, purely additive.
function Reject.AddIgnore(name, reason)
    local db = DB()
    if not db then
        return
    end
    if type(db.rejectIgnoreList) ~= "table" then
        db.rejectIgnoreList = {}
    end
    local key = LowerName(name)
    db.rejectIgnoreList[key] = true

    if type(db.hallOfShame) ~= "table" then
        db.hallOfShame = {}
    end
    local existing = db.hallOfShame[key]
    db.hallOfShame[key] = {
        name = name,
        reason = (type(reason) == "string" and reason ~= "" and reason)
            or (existing and existing.reason) or nil,
        addedAt = (existing and existing.addedAt) or Now(),
    }
end

function Reject.RemoveIgnore(name)
    local db = DB()
    if db and type(db.rejectIgnoreList) == "table" then
        db.rejectIgnoreList[LowerName(name)] = nil
    end
    if db and type(db.hallOfShame) == "table" then
        db.hallOfShame[LowerName(name)] = nil
    end
    sessionIgnore[LowerName(name)] = nil
end

--- Ordered (most recently added first) list of { name=, reason=, addedAt= }.
function Reject.GetHallOfShame()
    local db = DB()
    local out = {}
    if not db or type(db.hallOfShame) ~= "table" then
        return out
    end
    for _, entry in pairs(db.hallOfShame) do
        table.insert(out, entry)
    end
    table.sort(out, function(a, b)
        return (a.addedAt or 0) > (b.addedAt or 0)
    end)
    return out
end

function Reject.IsOnIgnore(name)
    return IsIgnoredName(name)
end

function Reject.ClearCooldown(name)
    if name then
        lastRejectAt[LowerName(name)] = nil
        sessionIgnore[LowerName(name)] = nil
    end
end

function Reject._ResetForTests()
    lastRejectAt = {}
    sessionIgnore = {}
    lastGlobalRejectAt = 0
    slotFullWindow = {}
end

function Reject._SessionIgnoreForTests()
    return sessionIgnore
end

Reject.DEFAULT_TEMPLATES = DEFAULT_TEMPLATES
Reject.REJECTABLE = REJECTABLE
