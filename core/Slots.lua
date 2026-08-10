-- AscensionLFM: core/Slots.lua
-- Host role slot caps + filled counts; whisper-assigned role map.
-- Pure helpers are WoW-free; Sync uses party/raid APIs when present.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Slots = {}
AscensionLFM.Slots = Slots

local ROLE_ORDER = { "tank", "healer", "aura", "dps" }

local DEFAULT_MAX = {
    tank = 2,
    healer = 3,
    aura = 3,
    dps = 7,
}

-- Runtime maps (also mirrored into SavedVariables via Database when available)
local assigned = {} -- [nameLower] = role

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function DB()
    if AscensionLFM.Database and AscensionLFM.Database.Get then
        return AscensionLFM.Database.Get()
    end
    return nil
end

local function EnsureDBSlots(db)
    if not db then
        return
    end
    if type(db.slotMax) ~= "table" then
        db.slotMax = {
            tank = DEFAULT_MAX.tank,
            healer = DEFAULT_MAX.healer,
            aura = DEFAULT_MAX.aura,
            dps = DEFAULT_MAX.dps,
        }
    end
    for _, role in ipairs(ROLE_ORDER) do
        if db.slotMax[role] == nil then
            db.slotMax[role] = DEFAULT_MAX[role]
        end
    end
    if type(db.assignedRoles) ~= "table" then
        db.assignedRoles = {}
    end
end

function Slots.DefaultMax()
    local out = {}
    for k, v in pairs(DEFAULT_MAX) do
        out[k] = v
    end
    return out
end

function Slots.GetMax(role)
    local db = DB()
    EnsureDBSlots(db)
    if db and db.slotMax and db.slotMax[role] ~= nil then
        return tonumber(db.slotMax[role]) or DEFAULT_MAX[role] or 0
    end
    return DEFAULT_MAX[role] or 0
end

function Slots.SetMax(role, n)
    local db = DB()
    if not db then
        return
    end
    EnsureDBSlots(db)
    n = tonumber(n) or DEFAULT_MAX[role] or 0
    if n < 0 then
        n = 0
    end
    if n > 40 then
        n = 40
    end
    db.slotMax[role] = n
end

--- Count assigned players currently tracked for a role.
function Slots.CountFilled(role)
    local db = DB()
    EnsureDBSlots(db)
    local map = assigned
    if db and type(db.assignedRoles) == "table" then
        map = db.assignedRoles
    end
    local n = 0
    for _, r in pairs(map) do
        if r == role then
            n = n + 1
        end
    end
    return n
end

function Slots.HasOpenSlot(role)
    if type(role) ~= "string" then
        return false
    end
    local max = Slots.GetMax(role)
    if max <= 0 then
        return false
    end
    return Slots.CountFilled(role) < max
end

function Slots.GetAssigned(name)
    local key = LowerName(name)
    local db = DB()
    EnsureDBSlots(db)
    if db and db.assignedRoles and db.assignedRoles[key] then
        return db.assignedRoles[key]
    end
    return assigned[key]
end

--- Remember whisper role for a player (invite path).
function Slots.Assign(name, role)
    if type(name) ~= "string" or name == "" or type(role) ~= "string" then
        return false
    end
    local key = LowerName(name)
    assigned[key] = role
    local db = DB()
    EnsureDBSlots(db)
    if db then
        db.assignedRoles[key] = role
    end
    -- Keep proper casing for Mini HUD regroup re-invites
    if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.RememberPlayer then
        AscensionLFM.MiniHUD.RememberPlayer(name)
    end
    if role == "aura" and AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.Balance then
        AscensionLFM.AuraBalance.Balance()
    end
    return true
end

function Slots.ClearName(name)
    local key = LowerName(name)
    assigned[key] = nil
    local db = DB()
    if db and type(db.assignedRoles) == "table" then
        db.assignedRoles[key] = nil
    end
end

function Slots.ClearAll()
    assigned = {}
    local db = DB()
    if db then
        db.assignedRoles = {}
    end
end

--- Apply totals from a parsed LFM line onto slotMax (only roles present).
function Slots.ApplyParsedCaps(parsed)
    local totals = AscensionLFM.Parser and AscensionLFM.Parser.SlotTotals and AscensionLFM.Parser.SlotTotals(parsed)
    if not totals then
        return false
    end
    for role, total in pairs(totals) do
        Slots.SetMax(role, total)
    end
    return true
end

--- Pure: given assigned map + present name set, drop leavers; keep roles for stayers.
-- @param assignedMap { [nameLower]=role }
-- @param presentSet { [nameLower]=true }
-- @return newMap, removedCount
function Slots.ReconcileAssigned(assignedMap, presentSet)
    local out = {}
    local removed = 0
    if type(assignedMap) ~= "table" then
        return out, 0
    end
    presentSet = presentSet or {}
    for name, role in pairs(assignedMap) do
        if presentSet[name] then
            out[name] = role
        else
            removed = removed + 1
        end
    end
    return out, removed
end

local function CollectPresentNames()
    local present = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local name
            if type(GetRaidRosterInfo) == "function" then
                name = GetRaidRosterInfo(i)
            end
            if (type(name) ~= "string" or name == "") and type(UnitName) == "function" then
                name = UnitName("raid" .. i)
            end
            if type(name) == "string" and name ~= "" then
                present[LowerName(name)] = true
            end
        end
        return present
    end
    if type(UnitName) == "function" then
        local me = UnitName("player")
        if me then
            present[LowerName(me)] = true
        end
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local unit = "party" .. i
        if type(UnitName) == "function" then
            local name = UnitName(unit)
            if type(name) == "string" and name ~= "" then
                present[LowerName(name)] = true
            end
        end
    end
    return present
end

--- Pure: names in presentSet with no assigned role.
-- @return list of nameLower, count
function Slots.ListUnassigned(presentSet, assignedMap)
    local out = {}
    if type(presentSet) ~= "table" then
        return out, 0
    end
    assignedMap = assignedMap or {}
    for name, _ in pairs(presentSet) do
        if type(name) == "string" and name ~= "" and not assignedMap[name] then
            table.insert(out, name)
        end
    end
    table.sort(out)
    return out, #out
end

--- Live: members currently in group without a remembered role.
-- @return names (lower), count
function Slots.UnassignedMembers()
    local present = CollectPresentNames()
    local db = DB()
    EnsureDBSlots(db)
    local map = assigned
    if db and type(db.assignedRoles) == "table" then
        map = db.assignedRoles
    end
    return Slots.ListUnassigned(present, map)
end

--- Assign the local player a host role if still unassigned (Hosting / Full Auto).
-- Prefers db.hostRole, else first accepted role with an open slot.
-- Never invents a role: if nothing accepted has room, the host stays
-- unassigned rather than being force-counted into an unrelated/disabled
-- role's slot (previously hard-fell back to "dps" even when dps was not
-- accepted or already full, which silently skewed slot counts and the
-- posted LFM message).
-- @return assignedRole or nil
function Slots.EnsureHostAssigned()
    local me
    if type(UnitName) == "function" then
        me = UnitName("player")
    end
    if type(me) ~= "string" or me == "" then
        return nil
    end
    if Slots.GetAssigned(me) then
        return nil
    end
    local db = DB()
    local role = db and db.hostRole
    if type(role) ~= "string" or role == "" then
        role = nil
    end
    if not role and db and type(db.roles) == "table" then
        for _, r in ipairs({ "tank", "healer", "aura", "dps" }) do
            if db.roles[r] and Slots.HasOpenSlot(r) then
                role = r
                break
            end
        end
    end
    if not role then
        return nil
    end
    if Slots.Assign(me, role) then
        return role
    end
    return nil
end


--- Drop assigned roles for players who left the group; keep whisper roles for unknowns.
function Slots.SyncFromRoster()
    local db = DB()
    EnsureDBSlots(db)
    local map = assigned
    if db and type(db.assignedRoles) == "table" then
        map = db.assignedRoles
    end
    local present = CollectPresentNames()
    -- If alone / empty group APIs, still drop people not present when group exists.
    local groupSize = 0
    for _ in pairs(present) do
        groupSize = groupSize + 1
    end
    if groupSize == 0 then
        -- No roster info (tests / loading) — leave assignments alone.
        return 0
    end
    local newMap, removed = Slots.ReconcileAssigned(map, present)
    assigned = {}
    for k, v in pairs(newMap) do
        assigned[k] = v
    end
    if db then
        db.assignedRoles = newMap
    end
    return removed
end

--- Snapshot for UI: { tank={filled,max}, ... }
function Slots.Snapshot()
    local out = {}
    for _, role in ipairs(ROLE_ORDER) do
        out[role] = {
            filled = Slots.CountFilled(role),
            max = Slots.GetMax(role),
            open = Slots.HasOpenSlot(role),
        }
    end
    return out
end

--- Recount filled from current party/raid roster + assignedRoles map.
-- Drops leavers via SyncFromRoster, then returns a fresh Snapshot.
-- Does not invent roles for unassigned members (whisper/host assign still required).
-- @return snapshot, removedCount, unassignedCount
function Slots.ScanRaid()
    local removed = Slots.SyncFromRoster() or 0
    local db = DB()
    if db and (db.mode == "hosting" or db.fullAutoHosting) then
        Slots.EnsureHostAssigned()
    end
    if AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.Balance then
        AscensionLFM.AuraBalance.Balance()
    end
    local snap = Slots.Snapshot()
    local _, unassigned = Slots.UnassignedMembers()
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
    return snap, removed, unassigned
end

function Slots._SetAssignedForTests(map)
    assigned = {}
    local db = DB()
    if db then
        db.assignedRoles = {}
    end
    if type(map) == "table" then
        for k, v in pairs(map) do
            Slots.Assign(k, v)
        end
    end
end

Slots.ROLE_ORDER = ROLE_ORDER
