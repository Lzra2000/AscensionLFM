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
    defaultsRev = 2, -- bumped when shipping default-mode changes
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
    autoInvite = true, -- only used while mode == "hosting"
    maxPartySize = 15, -- typical MS level-run raid size
    dedupeSeconds = 45,
    whisperCooldown = 30,
    inviteCooldown = 3,
    -- Dangerous: opt-in level-59 auto-kick + raid warning
    autoKickLevel59 = false,
    kickLevel = 59,
    kickWarnInterval = 10,
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

function Database.Defaults()
    return DeepCopy(DEFAULTS)
end
