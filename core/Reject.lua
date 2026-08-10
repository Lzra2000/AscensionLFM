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

local DEFAULT_TEMPLATES = {
    ["slot full"] = "Sorry, {role} is full ({filled}/{max}).",
    full = "Group is full — thanks!",
    ["no role"] = "Please whisper a role: tank / heal / aura / dps.",
    ["no parse"] = "Please whisper a role: tank / heal / aura / dps.",
    ["role filtered"] = "Not looking for {role} right now — thanks!",
    ["prefer support seat"] = "Saving the last couple seats for tank/heal/aura — try again if one opens up!",
}

local REJECTABLE = {
    ["slot full"] = true,
    full = true,
    ["no role"] = true,
    ["no parse"] = true,
    ["role filtered"] = true,
    ["prefer support seat"] = true,
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

--- Pure: substitute {role} {filled} {max} in a template.
function Reject.FormatTemplate(template, role, filled, max)
    template = tostring(template or "")
    role = tostring(role or "role")
    filled = tostring(filled ~= nil and filled or "?")
    max = tostring(max ~= nil and max or "?")
    template = template:gsub("{role}", role)
    template = template:gsub("{filled}", filled)
    template = template:gsub("{max}", max)
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

function Reject.BuildMessage(reason, role, db)
    db = db or DB()
    local filled, max = CountsForReason(reason, role, db)
    local tmpl = Reject.TemplateForReason(reason, db)
    return Reject.FormatTemplate(tmpl, role or "role", filled, max)
end

--- Send reject whisper if enabled + rate-limit / ignore allow.
-- @return ok, err
function Reject.TryRewhisper(name, reason, role)
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
    if type(SendChatMessage) ~= "function" then
        return false, "SendChatMessage missing"
    end
    local msg = Reject.BuildMessage(reason, role, db)
    if msg == "" then
        return false, "empty"
    end
    local ok, err = pcall(SendChatMessage, msg:sub(1, 255), "WHISPER", nil, name)
    if not ok then
        return false, tostring(err)
    end
    lastRejectAt[key] = Now()
    -- Optional: add to session ignore so we do not spam the same applicant
    if db.rejectSessionIgnore ~= false then
        sessionIgnore[key] = true
    end
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("reject", name .. " · " .. tostring(reason) .. " · " .. msg, {
            name = name,
            role = role,
            detail = reason,
        })
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("reject → " .. tostring(name) .. ": " .. msg)
    end
    return true
end

--- Add / remove permanent reject-ignore (no re-whisper).
function Reject.AddIgnore(name)
    local db = DB()
    if not db then
        return
    end
    if type(db.rejectIgnoreList) ~= "table" then
        db.rejectIgnoreList = {}
    end
    db.rejectIgnoreList[LowerName(name)] = true
end

function Reject.RemoveIgnore(name)
    local db = DB()
    if db and type(db.rejectIgnoreList) == "table" then
        db.rejectIgnoreList[LowerName(name)] = nil
    end
    sessionIgnore[LowerName(name)] = nil
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
end

function Reject._SessionIgnoreForTests()
    return sessionIgnore
end

Reject.DEFAULT_TEMPLATES = DEFAULT_TEMPLATES
Reject.REJECTABLE = REJECTABLE
