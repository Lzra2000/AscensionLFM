-- AscensionLFM: core/Database.lua
-- SavedVariables defaults and accessors.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Database = {}
AscensionLFM.Database = Database

-- Modes: "off" | "notify" | "seeking" | "hosting"
-- Default "notify": Log fills from public LFM/LFG MS lines; kick/auto-invite stay off.
local DEFAULTS = {
    mode = "notify",
    defaultsRev = 5, -- bumped when shipping default-mode / stock-copy changes
    roles = {
        tank = true,
        healer = false,
        aura = false,
        dps = true,
    },
    -- Manastorm level-run style defaults (2/3/3/7)
    slotMax = {
        tank = 2,
        healer = 3,
        aura = 3,
        dps = 7,
    },
    assignedRoles = {}, -- [nameLower] = role
    scanLfg = true, -- also scan LFG Manastorm lines
    requireRoleWhisper = true, -- default-deny blind invites without a role
    autoWhisper = false,
    whisperMessage = "inv ms tank",
    -- Seeking: rotating auto-whisper variants ({role} substituted)
    whisperVariants = {
        "inv ms {role}",
        "inv for ms as {role}",
        "ms {role} ready",
    },
    useWhisperVariants = true,
    whisperVariantIndex = 1,
    leaderBlacklist = {}, -- [nameLower] = true — skip auto-whisper / seeking notify soft
    autoInvite = true, -- only used while mode == "hosting" (whisper applicants)
    autoInviteLfg = true, -- hosting: InviteUnit players who post LFG MS in chat
    lfgInviteWithoutRole = false, -- if LFG has no role, do not guess (default-deny)
    autoAcceptInvite = false, -- seeking: opt-in auto-accept party/raid invites
    maxPartySize = 15, -- typical MS level-run raid size
    dedupeSeconds = 45,
    whisperCooldown = 30,
    inviteCooldown = 3,
    -- Dangerous: opt-in level-59 auto-kick + raid warning
    autoKickLevel59 = false,
    kickLevel = 59,
    kickWarnInterval = 10,
    -- LFM Post / auto-repost (default OFF)
    postChannel = "YELL", -- YELL | SAY | GUILD | CHANNEL
    postChannelName = "", -- used when postChannel == CHANNEL
    autoRepost = false,
    repostInterval = 60, -- seconds; clamped to min 30
    lastPostAt = 0, -- wall-clock unix when last post succeeded (display)
    announceFull = false, -- optional one FULL line when stop-when-full fires
    fullAnnounceMessage = "LFM MS FULL — thanks!",
    -- Full Auto Hosting master (default OFF — spam safety)
    fullAutoHosting = false,
    -- Reject re-whisper (default OFF; Full Auto turns on)
    rejectRewhisper = false,
    rejectTemplate = "Sorry, {role} is full ({filled}/{max}).",
    rejectTemplates = {
        ["slot full"] = "Sorry, {role} is full ({filled}/{max}).",
        full = "Group is full — thanks!",
        ["no role"] = "Please whisper a role: tank/heal/aura/dps (or T/H/A/D).",
        ["no parse"] = "Please whisper a role: tank/heal/aura/dps (or T/H/A/D).",
        ["role filtered"] = "Not looking for {role} right now — thanks!",
    },
    rejectCooldown = 30,
    rejectIgnoreList = {}, -- [nameLower] = true
    rejectSessionIgnore = true, -- after one reject, skip further auto re-whispers this session
    -- Sounds (opt-in)
    soundOnMatch = false,
    soundOnApplicant = false,
    -- RW Role Check + Aura 1-per-subgroup auto-move
    roleCheckMessage = "ROLE CHECK — whisper or party: tank/heal/aura/dps (T/H/A/D)",
    roleCheckDuration = 60,
    roleCheckWindow = 60,
    roleCheckMinInterval = 30,
    roleCheckAutoResync = true,
    lastRoleCheckAt = 0,
    autoMoveAura = true, -- at most one aura player per raid subgroup; auto SetRaidSubgroup
    -- Presets / queue / activity
    presets = {},
    applicantQueue = {},
    activityLog = {},
    matchHistory = {}, -- { {leader=, text=, source=, t=}, ... } max 30
    kickHistory = {}, -- { {name=, level=, t=}, ... } max 20
}

local function DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
    return dst
end

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = DeepCopy(v)
            else
                MergeDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Database.Init()
    if type(_G.AscensionLFMDB) ~= "table" then
        _G.AscensionLFMDB = DeepCopy(DEFAULTS)
    else
        MergeDefaults(_G.AscensionLFMDB, DEFAULTS)
        -- v0.2.2: leftover installs still on silent Off → listen (notify) once.
        local rev = tonumber(_G.AscensionLFMDB.defaultsRev) or 0
        if rev < 2 then
            if _G.AscensionLFMDB.mode == "off" then
                _G.AscensionLFMDB.mode = "notify"
            end
            _G.AscensionLFMDB.defaultsRev = 2
            rev = 2
        end
        -- v0.4.2/0.4.4: refresh stock Role Check raid warning if still on an old default.
        if rev < 4 then
            local oldMsgs = {
                ["ROLE CHECK — whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK — whisper tank / heal / aura / dps"] = true,
            }
            if oldMsgs[tostring(_G.AscensionLFMDB.roleCheckMessage or "")] then
                _G.AscensionLFMDB.roleCheckMessage = DEFAULTS.roleCheckMessage
            end
            -- v0.4.3 saved Full Auto with healer/aura accept off → heal whispers role-filtered.
            if _G.AscensionLFMDB.fullAutoHosting then
                if type(_G.AscensionLFMDB.roles) ~= "table" then
                    _G.AscensionLFMDB.roles = DeepCopy(DEFAULTS.roles)
                end
                _G.AscensionLFMDB.roles.tank = true
                _G.AscensionLFMDB.roles.healer = true
                _G.AscensionLFMDB.roles.aura = true
                _G.AscensionLFMDB.roles.dps = true
            end
            _G.AscensionLFMDB.defaultsRev = 4
            rev = 4
        end
        -- v0.4.8: Role Check accepts party/raid replies; refresh stock RW copy.
        if rev < 5 then
            local oldMsgs = {
                ["ROLE CHECK — whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK — whisper tank / heal / aura / dps"] = true,
                ["ROLE CHECK — whisper tank/heal/aura/dps (or T/H/A/D)"] = true,
            }
            if oldMsgs[tostring(_G.AscensionLFMDB.roleCheckMessage or "")] then
                _G.AscensionLFMDB.roleCheckMessage = DEFAULTS.roleCheckMessage
            end
            _G.AscensionLFMDB.defaultsRev = 5
        end
    end
end

function Database.Get()
    if type(_G.AscensionLFMDB) ~= "table" then
        Database.Init()
    end
    return _G.AscensionLFMDB
end

function Database.SetMode(mode)
    local db = Database.Get()
    if mode == "off" or mode == "notify" or mode == "seeking" or mode == "hosting" then
        db.mode = mode
        -- Leaving hosting turns off Full Auto master (keeps individual flags as last set
        -- only when still hosting; master off clears bundled autos for spam safety).
        if mode ~= "hosting" and db.fullAutoHosting then
            Database.SetFullAutoHosting(false)
        end
    end
end

--- Full Auto (Hosting) master: whisper+LFG invite + scan + repost + reject-rewhisper.
-- Default OFF. Turning ON forces mode=hosting and enables the bundle.
-- Turning OFF disables the bundled automation flags (spam safety).
function Database.SetFullAutoHosting(on)
    local db = Database.Get()
    on = on and true or false
    db.fullAutoHosting = on
    if on then
        db.mode = "hosting"
        db.autoInvite = true
        db.autoInviteLfg = true
        db.autoRepost = true
        db.rejectRewhisper = true
        -- MS level-run hosts need all four accept roles; defaults otherwise leave
        -- healer/aura off so heal/aura whispers die as "role filtered".
        if type(db.roles) ~= "table" then
            db.roles = {}
        end
        db.roles.tank = true
        db.roles.healer = true
        db.roles.aura = true
        db.roles.dps = true
        -- Roster scan already runs while hosting / autoRepost (Scanner.HandleRoster)
        if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
            AscensionLFM.Poster.RefreshMessage()
        end
        if AscensionLFM.Print then
            AscensionLFM.Print("Full Auto Hosting ON — whisper+LFG invite + scan + repost + reject")
        end
    else
        db.autoInvite = false
        db.autoInviteLfg = false
        db.autoRepost = false
        db.rejectRewhisper = false
        if AscensionLFM.Print then
            AscensionLFM.Print("Full Auto Hosting OFF")
        end
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.SyncFromDB then
        AscensionLFM.MainWindow.SyncFromDB()
    end
end

function Database.PushMatch(entry)
    local db = Database.Get()
    if type(db.matchHistory) ~= "table" then
        db.matchHistory = {}
    end
    table.insert(db.matchHistory, 1, entry)
    while #db.matchHistory > 30 do
        table.remove(db.matchHistory)
    end
end

function Database.ClearMatches()
    local db = Database.Get()
    db.matchHistory = {}
end

function Database.ClearKicks()
    local db = Database.Get()
    db.kickHistory = {}
end

--- Leader blacklist helpers (seeking).
function Database.IsLeaderBlacklisted(name)
    local db = Database.Get()
    if type(db.leaderBlacklist) ~= "table" then
        return false
    end
    local key = tostring(name or ""):lower():gsub("%-.*$", "")
    return db.leaderBlacklist[key] == true
end

function Database.AddLeaderBlacklist(name)
    local db = Database.Get()
    if type(db.leaderBlacklist) ~= "table" then
        db.leaderBlacklist = {}
    end
    local key = tostring(name or ""):lower():gsub("%-.*$", "")
    if key == "" then
        return false
    end
    db.leaderBlacklist[key] = true
    return true
end

function Database.RemoveLeaderBlacklist(name)
    local db = Database.Get()
    if type(db.leaderBlacklist) == "table" then
        local key = tostring(name or ""):lower():gsub("%-.*$", "")
        db.leaderBlacklist[key] = nil
    end
end

function Database.Defaults()
    return DeepCopy(DEFAULTS)
end
