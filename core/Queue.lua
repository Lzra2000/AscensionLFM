-- AscensionLFM: core/Queue.lua
-- Hosting applicant queue: recent role whispers with Invite / Reject actions.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Queue = {}
AscensionLFM.Queue = Queue

local MAX_ENTRIES = 20

local function DB()
    if AscensionLFM.Database and AscensionLFM.Database.Get then
        return AscensionLFM.Database.Get()
    end
    return nil
end

local function Ensure(db)
    if not db then
        return nil
    end
    if type(db.applicantQueue) ~= "table" then
        db.applicantQueue = {}
    end
    return db.applicantQueue
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function RefreshUI()
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshQueue then
        AscensionLFM.MainWindow.RefreshQueue()
    end
end

local function IsRejectableDetail(detail)
    if AscensionLFM.Reject and AscensionLFM.Reject.IsRejectableReason then
        return AscensionLFM.Reject.IsRejectableReason(detail)
    end
    return false
end

--- Push or update an applicant from a hosting whisper.
-- @param name sender
-- @param role parsed role or nil
-- @param message raw whisper
-- @param status "pending"|"invited"|"rejected"|"blocked"
-- @param detail optional reason string
--- Build short dual-role label from primary role + OfferedRoles (e.g. "dps+aura").
function Queue.FormatRoleLabel(role, message)
    local primary = role and tostring(role) or nil
    local offered = {}
    if message and AscensionLFM.Parser and AscensionLFM.Parser.OfferedRoles then
        offered = AscensionLFM.Parser.OfferedRoles(message) or {}
    end
    local order = { "tank", "healer", "aura", "dps" }
    local parts = {}
    local seen = {}
    if primary then
        table.insert(parts, primary)
        seen[primary] = true
    end
    for _, r in ipairs(order) do
        if offered[r] and not seen[r] then
            table.insert(parts, r)
            seen[r] = true
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "+")
end

function Queue.Push(name, role, message, status, detail)
    local db = DB()
    local q = Ensure(db)
    if not q then
        return false
    end
    if type(name) ~= "string" or name == "" then
        return false
    end
    local key = LowerName(name)
    for i = 1, #q do
        if LowerName(q[i].name) == key then
            q[i].role = role or q[i].role
            -- Recompute the label from the RESOLVED role (which may have
            -- just kept the old value above), not the raw incoming `role`
            -- param - otherwise a follow-up whisper with no primary role
            -- of its own but a mentioned secondary one (e.g. "aura") could
            -- overwrite roleLabel with text that no longer matches
            -- q[i].role, showing one role in the Queue UI while Invite
            -- (which reads q[i].role) still uses the other.
            q[i].roleLabel = Queue.FormatRoleLabel(q[i].role, message) or q[i].roleLabel or q[i].role
            q[i].message = message or q[i].message
            q[i].status = status or q[i].status or "pending"
            q[i].detail = detail
            q[i].t = (type(time) == "function" and time()) or 0
            local entry = table.remove(q, i)
            table.insert(q, 1, entry)
            RefreshUI()
            return true
        end
    end
    local roleLabel = Queue.FormatRoleLabel(role, message)
    table.insert(q, 1, {
        name = name,
        role = role,
        roleLabel = roleLabel or role,
        message = tostring(message or ""):sub(1, 120),
        status = status or "pending",
        detail = detail,
        t = (type(time) == "function" and time()) or 0,
    })
    while #q > MAX_ENTRIES do
        table.remove(q)
    end
    RefreshUI()
    return true
end

function Queue.Recent(n)
    local db = DB()
    local q = Ensure(db) or {}
    n = tonumber(n) or #q
    local out = {}
    for i = 1, math.min(n, #q) do
        out[i] = q[i]
    end
    return out
end

function Queue.Clear()
    local db = DB()
    if db then
        db.applicantQueue = {}
    end
    RefreshUI()
end

function Queue.SetStatus(name, status, detail)
    local db = DB()
    local q = Ensure(db)
    if not q then
        return false
    end
    local key = LowerName(name)
    for i = 1, #q do
        if LowerName(q[i].name) == key then
            q[i].status = status
            q[i].detail = detail
            RefreshUI()
            return true
        end
    end
    return false
end

--- Manual Invite from Queue UI.
function Queue.Invite(name)
    local db = DB()
    local q = Ensure(db) or {}
    local key = LowerName(name)
    local role
    for i = 1, #q do
        if LowerName(q[i].name) == key then
            role = q[i].role
            break
        end
    end
    if not AscensionLFM.Invite or not AscensionLFM.Invite.InvitePlayer then
        return false, "Invite missing"
    end
    local ok, reason = AscensionLFM.Invite.InvitePlayer(name, role)
    if ok then
        Queue.SetStatus(name, "invited")
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("invite", "manual invite " .. tostring(name)
                .. (role and (" as " .. role) or ""), { name = name, role = role })
        end
    end
    return ok, reason
end

--- Manual Reject + re-whisper from Queue UI (sends once even if auto reject off).
function Queue.Reject(name, reason)
    reason = reason or "slot full"
    local db = DB()
    local q = Ensure(db) or {}
    local key = LowerName(name)
    local role
    for i = 1, #q do
        if LowerName(q[i].name) == key then
            role = q[i].role
            if q[i].detail and IsRejectableDetail(q[i].detail) then
                reason = q[i].detail
            end
            break
        end
    end
    local saved = db and db.rejectRewhisper
    if db then
        db.rejectRewhisper = true
    end
    if AscensionLFM.Reject and AscensionLFM.Reject.ClearCooldown then
        AscensionLFM.Reject.ClearCooldown(name)
    end
    local ok, err = false, "Reject missing"
    if AscensionLFM.Reject and AscensionLFM.Reject.TryRewhisper then
        ok, err = AscensionLFM.Reject.TryRewhisper(name, reason, role)
    end
    if db then
        db.rejectRewhisper = saved and true or false
    end
    Queue.SetStatus(name, "rejected", reason)
    return ok, err
end

Queue.MAX_ENTRIES = MAX_ENTRIES
