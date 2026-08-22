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
    manastorm_cleared = true,
    manastorm_failed = true,
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

-- Session totals: unlike activityLog (capped at MAX_ENTRIES so a busy
-- hosting burst quickly rolls old entries off), these counters are
-- uncapped and persist for the whole session (until ResetSession()),
-- giving an accurate "how did this session go" summary regardless of
-- how many events happened.
local function EnsureStats(db)
    if not db then
        return nil
    end
    if type(db.sessionStats) ~= "table" then
        db.sessionStats = {}
    end
    if not db.sessionStartedAt or db.sessionStartedAt == 0 then
        db.sessionStartedAt = (type(time) == "function" and time()) or 0
    end
    return db.sessionStats
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
    local stats = EnsureStats(db)
    if stats then
        stats[kind] = (tonumber(stats[kind]) or 0) + 1
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshActivity then
        AscensionLFM.MainWindow.RefreshActivity()
    end
    return true
end

--- Raw session counters + elapsed time since the session started (or was
-- last reset). Counts every Activity.Push kind seen this session, not
-- just invite/reject/kick.
function Activity.GetSessionSummary(nowOverride)
    local db = DB()
    -- EnsureStats also lazily sets sessionStartedAt on first call, so the
    -- panel doesn't show elapsed-since-epoch before any Push() this session.
    local stats = EnsureStats(db) or (db and db.sessionStats) or {}
    local startedAt = (db and tonumber(db.sessionStartedAt)) or 0
    local now = tonumber(nowOverride) or (type(time) == "function" and time()) or 0
    local elapsed = now - startedAt
    if elapsed < 0 then
        elapsed = 0
    end
    return {
        invited = tonumber(stats.invite) or 0,
        rejected = tonumber(stats.reject) or 0,
        kicked = tonumber(stats.kick) or 0,
        matched = tonumber(stats.match) or 0,
        posted = tonumber(stats.post) or 0,
        manastormCleared = tonumber(stats.manastorm_cleared) or 0,
        manastormFailed = tonumber(stats.manastorm_failed) or 0,
        elapsedSeconds = elapsed,
        startedAt = startedAt,
    }
end

--- Pure: turn a summary table (from GetSessionSummary) into one readable
-- line. Kept separate from GetSessionSummary so it's testable without a
-- live DB/clock.
function Activity.FormatSessionSummary(summary)
    summary = summary or {}
    local totalSeconds = math.max(0, tonumber(summary.elapsedSeconds) or 0)
    local mins = math.floor(totalSeconds / 60)
    local hours = math.floor(mins / 60)
    mins = mins % 60
    local timeStr
    if hours > 0 then
        timeStr = string.format("%dh%dm", hours, mins)
    else
        timeStr = string.format("%dm", mins)
    end
    local line = string.format("Sitzung (%s): %d eingeladen, %d abgelehnt, %d gekickt, %d Matches, %d Posts",
        timeStr,
        tonumber(summary.invited) or 0,
        tonumber(summary.rejected) or 0,
        tonumber(summary.kicked) or 0,
        tonumber(summary.matched) or 0,
        tonumber(summary.posted) or 0)

    -- Only append Manastorm level stats when there's something to show -
    -- these stay at 0 on non-CoA server variants (Bronzebeard/Epoch),
    -- where MANASTORM_LEVEL_COMPLETED/MANASTORM_FAILED never fire, so
    -- always showing "0 cleared, 0 failed" there would just be noise.
    local cleared = tonumber(summary.manastormCleared) or 0
    local failed = tonumber(summary.manastormFailed) or 0
    if cleared > 0 or failed > 0 then
        line = line .. string.format(", %d Stufen geschafft, %d fehlgeschlagen", cleared, failed)
    end

    return line
end

--- Clear session totals and restart the elapsed-time clock. Does NOT
-- touch the rolling activityLog (use Activity.Clear() for that).
function Activity.ResetSession()
    local db = DB()
    if not db then
        return false
    end
    db.sessionStats = {}
    db.sessionStartedAt = (type(time) == "function" and time()) or 0
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
