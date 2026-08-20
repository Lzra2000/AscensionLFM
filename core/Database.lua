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
    defaultsRev = 6, -- bumped when shipping default-mode / stock-copy changes
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
    chatFilterEnabled = false, -- hide public MS LFM/LFG listings from chat (already in Log tab)
    minimapIconShown = true, -- draggable minimap icon (mode/activity tooltip, click to open settings)
    minimapAngle = 220, -- degrees around the minimap where the icon sits
    minKeystoneLevel = 0, -- 0 = off; hides only explicitly "[Dungeon +N]"-tagged posts below N
    requireRoleWhisper = true, -- default-deny blind invites without a role
    passiveRoleDetect = true, -- catch exact bare role words in raid/party chat continuously, not just during an active Role Check
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
    leaderBlacklist = {}, -- [nameLower] = true - skip auto-whisper / seeking notify soft
    autoInvite = true, -- only used while mode == "hosting" (whisper applicants)
    autoInviteLfg = true, -- hosting: InviteUnit players who post LFG MS in chat
    lfgInviteWithoutRole = false, -- if LFG has no role, do not guess (default-deny)
    autoAcceptInvite = false, -- seeking: opt-in auto-accept party/raid invites
    maxPartySize = 15, -- typical MS level-run raid size
    dedupeSeconds = 45,
    whisperCooldown = 30,
    inviteCooldown = 3,
    pauseInviteInInstance = true, -- pause auto-invite (both whisper and LFG-scan) while the host is inside the instance
    pauseRepostInInstance = true, -- pause LFM auto-repost while the host is inside the instance
    -- Dangerous: opt-in level-59 auto-kick + raid warning
    autoKickLevel59 = false,
    kickLevel = 59,
    kickWarnInterval = 10,
    -- LFM Post / auto-repost (default OFF)
    postChannel = "YELL", -- YELL | SAY | GUILD | CHANNEL
    postChannelName = "", -- used when postChannel == CHANNEL
    autoRepost = false,
    postShowAllRoles = false, -- LFM shows filled roles too when true

    repostInterval = 60, -- seconds; clamped to min 30
    lastPostAt = 0, -- wall-clock unix when last post succeeded (display)
    announceFull = false, -- optional one FULL line when stop-when-full fires
    fullAnnounceMessage = "LFM MS FULL - thanks!",
    wipeAnnounceMessage = "WIPE",
    shieldAnnounceMessage = "KILL MOBS - boss shield still up!",
    regroupAnnounceMessage = "REGROUP - accept invite",
    -- Per-message delivery override (Message Studio style routing). Keys:
    -- "rw" (Role Check trigger), "wipe", "shield", "regroup", "full",
    -- "need". Values: "auto" (default smart cascade), "raidwarning"
    -- (RW only), "raid" (raid/party chat, skip RW), "local" (don't
    -- broadcast, just note it locally), "disabled" (send nothing).
    -- Absent/nil key == "auto".
    messageRouting = {},
    regroupRoster = {}, -- display names remembered for regroup re-invite
    regroupDisplay = {}, -- [nameLower] = displayName for InviteUnit casing
    regroupSeenAt = {}, -- [nameLower] = GetTime() last seen present; ages out old raids
    -- Mini Quick HUD (floating bar - no /alfm needed)
    miniHudShow = true,
    miniHudExpanded = true,
    miniHudPoint = "CENTER",
    miniHudRelPoint = "CENTER",
    miniHudX = 0,
    miniHudY = 180,
    -- Appearance / DragonUI chrome (Appearance tab). Nil fields = profile defaults.
    uiChrome = {
        metalEnabled = true, -- outer metal nineslice
        topSize = 75,        -- corner size (bag-style)
        bottomSize = 32,
        topY = 16,
        bottomY = -3,
        leftOffset = -8,
        rightOffset = 4,
    },
    -- Full Auto Hosting master (default OFF - spam safety)
    fullAutoHosting = false,
    -- Reject re-whisper (default OFF; Full Auto turns on)
    rejectRewhisper = false,
    rejectTemplate = "Sorry, {role} is full ({filled}/{max}).",
    rejectTemplates = {
        ["slot full"] = "Sorry, {role} is full ({filled}/{max}).",
        full = "Group is full - thanks!",
        ["no role"] = "Please whisper a role: tank/heal/aura/dps (or T/H/A/D).",
        ["no parse"] = "Please whisper a role: tank/heal/aura/dps (or T/H/A/D).",
        ["role filtered"] = "Not looking for {role} right now - thanks!",
    },
    rejectCooldown = 30,
    rejectIgnoreList = {}, -- [nameLower] = true
    hallOfShame = {}, -- [nameLower] = { name=, reason=, addedAt= } - private, never posted anywhere
    mplusDungeon = "", -- current Mythic+ dungeon name, prepended to the LFM post when set
    mplusLevel = 0, -- current keystone level, 0 = not set / not shown
    contentType = "ms", -- "ms" | "raid" | "mplus" - unified LFG/LFM mode selector
    rejectSessionIgnore = true, -- after one reject, skip further auto re-whispers this session
    -- Sounds (opt-in)
    soundOnMatch = false,
    soundOnApplicant = false,
    -- RW Role Check + Aura 1-per-subgroup auto-move
    roleCheckMessage = "ROLE CHECK - whisper or party: tank/heal/aura/dps (T/H/A/D)",
    roleCheckDuration = 60,
    roleCheckWindow = 60,
    roleCheckMinInterval = 30,
    roleCheckAutoResync = true,
    lastRoleCheckAt = 0,
    autoMoveAura = true, -- at most one aura player per raid subgroup; auto SetRaidSubgroup
    autoMoveTank = true, -- at most one tank per raid subgroup, filling group 1/2 first
    autoMoveHealer = true, -- at most one healer per raid subgroup
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
        -- Read the revision BEFORE MergeDefaults backfills a missing
        -- defaultsRev to DEFAULTS.defaultsRev - otherwise every migration
        -- block below is skipped for saves that predate this field.
        local rev = tonumber(_G.AscensionLFMDB.defaultsRev) or 0
        MergeDefaults(_G.AscensionLFMDB, DEFAULTS)
        -- v0.2.2: leftover installs still on silent Off -> listen (notify) once.
        if rev < 2 then
            if _G.AscensionLFMDB.mode == "off" then
                _G.AscensionLFMDB.mode = "notify"
            end
            _G.AscensionLFMDB.defaultsRev = 2
            rev = 2
        end
        -- v0.4.2/0.4.4: refresh stock Role Check raid warning if still on an old default.
        if rev < 4 then
            -- Hyphen (current) and em-dash (pre-ASCII-normalization, what
            -- real existing users' SavedVariables may still contain)
            -- variants both need to match, or upgraders whose stored
            -- message predates the em-dash removal never get migrated.
            local oldMsgs = {
                ["ROLE CHECK - whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK - whisper tank / heal / aura / dps"] = true,
                ["ROLE CHECK \226\128\148 whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK \226\128\148 whisper tank / heal / aura / dps"] = true,
            }
            if oldMsgs[tostring(_G.AscensionLFMDB.roleCheckMessage or "")] then
                _G.AscensionLFMDB.roleCheckMessage = DEFAULTS.roleCheckMessage
            end
            -- v0.4.3 saved Full Auto with healer/aura accept off -> heal whispers role-filtered.
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
                ["ROLE CHECK - whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK - whisper tank / heal / aura / dps"] = true,
                ["ROLE CHECK - whisper tank/heal/aura/dps (or T/H/A/D)"] = true,
                ["ROLE CHECK \226\128\148 whisper me tank / heal / aura / dps to sync MS slots"] = true,
                ["ROLE CHECK \226\128\148 whisper tank / heal / aura / dps"] = true,
                ["ROLE CHECK \226\128\148 whisper tank/heal/aura/dps (or T/H/A/D)"] = true,
            }
            if oldMsgs[tostring(_G.AscensionLFMDB.roleCheckMessage or "")] then
                _G.AscensionLFMDB.roleCheckMessage = DEFAULTS.roleCheckMessage
            end
            _G.AscensionLFMDB.defaultsRev = 5
            rev = 5
        end
        if rev < 6 then
            _G.AscensionLFMDB.auraScanAutoKick = false
            _G.AscensionLFMDB.auraScanEnabled = false
            _G.AscensionLFMDB.defaultsRev = 6
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
        if mode == "hosting" and AscensionLFM.Slots and AscensionLFM.Slots.EnsureHostAssigned then
            AscensionLFM.Slots.EnsureHostAssigned()
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
        if AscensionLFM.Slots and AscensionLFM.Slots.EnsureHostAssigned then
            AscensionLFM.Slots.EnsureHostAssigned()
        end
        if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
            AscensionLFM.Poster.RefreshMessage()
        end
        if AscensionLFM.Print then
            AscensionLFM.Print("Full Auto Hosting ON - whisper+LFG invite + scan + repost + reject")
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
