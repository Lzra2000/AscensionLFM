-- AscensionLFM: core/Presets.lua
-- Save/load host slot caps + post settings (MS 2/3/3/10 built-in).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Presets = {}
AscensionLFM.Presets = Presets

-- Built-in presets (not stored in SV; always available)
-- Preset names read "tank/healer/aura/dps", but since v0.4.131 only tank,
-- healer and dps are SEATS - they must sum to maxPartySize. The aura number
-- is a coverage target riding on top of those seats, which is why 2/3/3/10
-- is a 15-man raid and not an 18-man one.
local BUILTIN = {
    ["MS 2/3/3/10"] = {
        slotMax = { tank = 2, healer = 3, aura = 3, dps = 10 },
        maxPartySize = 15,
        postChannel = "YELL",
        postChannelName = "",
        repostInterval = 60,
        roles = { tank = true, healer = true, aura = true, dps = true },
    },
    ["MS 2/2/2/7"] = {
        slotMax = { tank = 2, healer = 2, aura = 2, dps = 7 },
        maxPartySize = 11,
        postChannel = "YELL",
        postChannelName = "",
        repostInterval = 60,
        roles = { tank = true, healer = true, aura = true, dps = true },
    },
    ["MS tanks+heals"] = {
        slotMax = { tank = 2, healer = 3, aura = 0, dps = 5 },
        maxPartySize = 10,
        postChannel = "YELL",
        postChannelName = "",
        repostInterval = 60,
        roles = { tank = true, healer = true, aura = false, dps = true },
    },
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
    if type(db.presets) ~= "table" then
        db.presets = {}
    end
    return db.presets
end

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

--- Snapshot current host/post settings into a preset table.
function Presets.CaptureFromDB(db)
    db = db or DB()
    if not db then
        return nil
    end
    return {
        slotMax = DeepCopy(db.slotMax or {}),
        maxPartySize = tonumber(db.maxPartySize) or 15,
        postChannel = tostring(db.postChannel or "YELL"),
        postChannelName = tostring(db.postChannelName or ""),
        repostInterval = tonumber(db.repostInterval) or 60,
        roles = DeepCopy(db.roles or {}),
        announceFull = db.announceFull and true or false,
        rejectRewhisper = db.rejectRewhisper and true or false,
    }
end

--- Apply a preset table onto db (does not change mode / fullAuto).
function Presets.ApplyToDB(preset, db)
    db = db or DB()
    if not db or type(preset) ~= "table" then
        return false
    end
    if type(preset.slotMax) == "table" then
        db.slotMax = DeepCopy(preset.slotMax)
        if AscensionLFM.Slots and AscensionLFM.Slots.SetMax then
            for role, n in pairs(preset.slotMax) do
                AscensionLFM.Slots.SetMax(role, n)
            end
        end
    end
    if preset.maxPartySize ~= nil then
        local n = tonumber(preset.maxPartySize) or 15
        if n < 2 then n = 2 end
        if n > 40 then n = 40 end
        db.maxPartySize = n
    end
    if preset.postChannel then
        db.postChannel = tostring(preset.postChannel)
    end
    if preset.postChannelName ~= nil then
        db.postChannelName = tostring(preset.postChannelName)
    end
    if preset.repostInterval ~= nil then
        local n = tonumber(preset.repostInterval) or 60
        if AscensionLFM.Poster and AscensionLFM.Poster.ClampInterval then
            n = AscensionLFM.Poster.ClampInterval(n)
        end
        db.repostInterval = n
    end
    if type(preset.roles) == "table" then
        db.roles = DeepCopy(preset.roles)
    end
    if preset.announceFull ~= nil then
        db.announceFull = preset.announceFull and true or false
    end
    if preset.rejectRewhisper ~= nil then
        db.rejectRewhisper = preset.rejectRewhisper and true or false
    end
    if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
        AscensionLFM.Poster.RefreshMessage()
    end
    if AscensionLFM.MainWindow then
        if AscensionLFM.MainWindow.RefreshSlots then
            AscensionLFM.MainWindow.RefreshSlots()
        end
        if AscensionLFM.MainWindow.RefreshPost then
            AscensionLFM.MainWindow.RefreshPost()
        end
    end
    return true
end

function Presets.Save(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return false, "empty name"
    end
    if BUILTIN[name] then
        return false, "builtin name"
    end
    local db = DB()
    local store = Ensure(db)
    if not store then
        return false, "no db"
    end
    store[name] = Presets.CaptureFromDB(db)
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("preset", "saved preset: " .. name)
    end
    return true
end

function Presets.Load(name)
    name = tostring(name or "")
    local preset = BUILTIN[name]
    if not preset then
        local db = DB()
        local store = Ensure(db)
        if store then
            preset = store[name]
        end
    end
    if not preset then
        return false, "not found"
    end
    Presets.ApplyToDB(DeepCopy(preset))
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("preset", "loaded preset: " .. name)
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("loaded preset: " .. name)
    end
    return true
end

function Presets.Delete(name)
    name = tostring(name or "")
    if BUILTIN[name] then
        return false, "builtin"
    end
    local db = DB()
    local store = Ensure(db)
    if not store or not store[name] then
        return false, "not found"
    end
    store[name] = nil
    return true
end

--- Ordered list of preset names (builtins first, then user).
function Presets.List()
    local names = {}
    local builtinOrder = { "MS 2/3/3/10", "MS 2/2/2/7", "MS tanks+heals" }
    for _, n in ipairs(builtinOrder) do
        if BUILTIN[n] then
            table.insert(names, n)
        end
    end
    local db = DB()
    local store = Ensure(db) or {}
    local user = {}
    for n in pairs(store) do
        table.insert(user, n)
    end
    table.sort(user)
    for _, n in ipairs(user) do
        table.insert(names, n)
    end
    return names
end

function Presets.IsBuiltin(name)
    return BUILTIN[tostring(name or "")] ~= nil
end

function Presets.Get(name)
    name = tostring(name or "")
    if BUILTIN[name] then
        return DeepCopy(BUILTIN[name]), true
    end
    local db = DB()
    local store = Ensure(db)
    if store and store[name] then
        return DeepCopy(store[name]), false
    end
    return nil, false
end

Presets.BUILTIN = BUILTIN
