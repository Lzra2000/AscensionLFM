-- AscensionLFM: core/Activity.lua
-- Bounded activity log (posts, invites, rejects, matches).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Activity = {}
AscensionLFM.Activity = Activity

local MAX_ENTRIES = 40
local VALID_KINDS = {
    post = true,
    invite = true,
    reject = true,
    match = true,
    full = true,
    preset = true,
    kick = true,
    aura = true,
    tank = true,
    healer = true,
    wipe = true,
    shield = true,
    regroup = true,
    rolecheck = true,
}

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
    if type(db.activityLog) ~= "table" then
        db.activityLog = {}
    end
    return db.activityLog
end

--- Push an activity line.
-- @param kind "post"|"invite"|"reject"|"match"|"full"|"preset"
-- @param text short description
-- @param meta optional table (name, role, ...)
function Activity.Push(kind, text, meta)
    local db = DB()
    local log = Ensure(db)
    if not log then
        return false
    end
    kind = tostring(kind or "match")
    if not VALID_KINDS[kind] then
        kind = "match"
    end
    local entry = {
        kind = kind,
        text = tostring(text or ""),
        t = (type(time) == "function" and time()) or 0,
    }
    if type(meta) == "table" then
        entry.name = meta.name
        entry.role = meta.role
        entry.detail = meta.detail
    end
    table.insert(log, 1, entry)
    while #log > MAX_ENTRIES do
        table.remove(log)
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshActivity then
        AscensionLFM.MainWindow.RefreshActivity()
    end
    return true
end

function Activity.Clear()
    local db = DB()
    if db then
        db.activityLog = {}
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshActivity then
        AscensionLFM.MainWindow.RefreshActivity()
    end
end

function Activity.Recent(n)
    local db = DB()
    local log = Ensure(db) or {}
    n = tonumber(n) or #log
    local out = {}
    for i = 1, math.min(n, #log) do
        out[i] = log[i]
    end
    return out
end

Activity.MAX_ENTRIES = MAX_ENTRIES
Activity.VALID_KINDS = VALID_KINDS
