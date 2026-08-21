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

-- Kept 4-wide on purpose even though "aura" is no longer a seat: Snapshot()
-- iterates this, and Poster/MiniHUD/RosterPanel/MainWindow all render an
-- "A x/y" figure from the resulting snapshot. For aura that figure means
-- coverage/target rather than filled/cap - see COMBAT_ROLES below.
local ROLE_ORDER = { "tank", "healer", "aura", "dps" }

-- The roles that actually consume a raid seat. Since v0.4.131 aura is an
-- orthogonal tag (a player is tank/healer/dps AND optionally carries an XP
-- aura), so it is deliberately absent here - anything picking "which seat
-- does this applicant take" must iterate COMBAT_ROLES, not ROLE_ORDER.
local COMBAT_ROLES = { "tank", "healer", "dps" }

-- The three seat caps must add up to the raid size you actually want.
-- Before v0.4.131 aura was a fourth SEAT and the split was 2/3/3/7 = 15.
-- Making aura a tag silently deleted those 3 seats, so the raid capped at
-- 2+3+7 = 12 and could never reach 15 (reported live: "D 8/7", "12 total",
-- and applicants rejected with "dps is full (7/7)" at only 12 people).
-- Those 3 seats belong to DPS now: 2+3+10 = 15. Same blueprint the
-- competing ManastormRecruiter documents (2 Tanks, 3 Healers, 10 DPS,
-- plus 3 Auras as a coverage target rather than seats).
local DEFAULT_MAX = {
    tank = 2,
    healer = 3,
    -- Not a seat cap: the aura COVERAGE TARGET (ideally one per subgroup).
    aura = 3,
    dps = 10,
}

-- Runtime maps (also mirrored into SavedVariables via Database when available)
local assigned = {} -- [nameLower] = combat role ("tank"/"healer"/"dps")
local auraFlags = {} -- [nameLower] = true when that player carries an XP aura
local assignedAt = {} -- [nameLower] = GetTime() when last (re)assigned

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
    if type(db.auraFlags) ~= "table" then
        db.auraFlags = {}
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

-- Inline present-set (CollectPresentNames is defined later as a local).
-- Shared by CountFilled/CountAura so both apply the exact same
-- "still actually here (or freshly invited)" filter.
local function PresentSet()
    local present = {}
    local groupSize = 0
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
                groupSize = groupSize + 1
            end
        end
        return present, groupSize
    end
    if type(UnitName) == "function" then
        local me = UnitName("player")
        if type(me) == "string" and me ~= "" then
            present[LowerName(me)] = true
            groupSize = groupSize + 1
        end
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        local name = type(UnitName) == "function" and UnitName("party" .. i) or nil
        if type(name) == "string" and name ~= "" then
            present[LowerName(name)] = true
            groupSize = groupSize + 1
        end
    end
    return present, groupSize
end

--- True when this name still counts toward filled/coverage totals: either
-- actually in the live roster, or invited so recently that they haven't
-- shown up yet. groupSize==0 means "no roster APIs" (tests / loading), where
-- everything counts.
local function CountsTowardTotals(key, present, groupSize)
    if groupSize == 0 then
        return true
    end
    return present[key] or Slots.RecentlyAssigned(key)
end

--- How many tracked players currently carry an XP aura. Counts the aura
-- TAG across every combat role - since v0.4.131 a tank/healer/dps can each
-- carry one, so this is coverage, not an occupied seat count.
function Slots.CountAura()
    local db = DB()
    EnsureDBSlots(db)
    local map = auraFlags
    if db and type(db.auraFlags) == "table" then
        map = db.auraFlags
    end
    local present, groupSize = PresentSet()
    local n = 0
    for key, on in pairs(map) do
        if on and CountsTowardTotals(key, present, groupSize) then
            n = n + 1
        end
    end
    return n
end

--- Count assigned players currently tracked for a role.
-- Only counts names present in the live roster OR assigned within the
-- invite grace window. Stale leaver entries used to inflate counts
-- (live reject: "tank is full (3/2)" with max 2).
-- role=="aura" is special: it is not a seat, so this returns aura COVERAGE
-- (how many members of any combat role carry an aura).
function Slots.CountFilled(role)
    if role == "aura" then
        return Slots.CountAura()
    end
    local db = DB()
    EnsureDBSlots(db)
    local map = assigned
    if db and type(db.assignedRoles) == "table" then
        map = db.assignedRoles
    end
    local present, groupSize = PresentSet()
    local n = 0
    for key, r in pairs(map) do
        if r == role and CountsTowardTotals(key, present, groupSize) then
            n = n + 1
        end
    end
    return n
end

--- For role=="aura" this reads as "aura coverage still below target".
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

--- How many more aura carriers are still wanted to reach the target.
function Slots.AuraShortfall()
    local target = Slots.GetMax("aura")
    if target <= 0 then
        return 0
    end
    local short = target - Slots.CountAura()
    if short < 0 then
        return 0
    end
    return short
end

--- Seat check that also knows whether the applicant brings an aura.
-- Aura-aware version of HasOpenSlot(); HasOpenSlot() itself is unchanged
-- for the many callers that have no aura info to pass.
--
-- Modelled on MSBuilder's aura reservation: XP auras are party-scoped, so
-- you want roughly one per subgroup, but you must not let the raid fill up
-- with non-aura DPS and end with zero coverage. Therefore:
--   * tank/healer are NEVER blocked for aura - they fill on their own quota
--     (there are far fewer of them, blocking them would just stall the raid).
--   * a DPS who brings an aura is always accepted while DPS has room - they
--     satisfy both needs at once.
--   * a DPS without an aura is accepted only up to (dps cap - aura shortfall);
--     the remaining DPS seats are held open for aura carriers.
-- Turning off db.roles.aura disables the reservation entirely (fill with
-- whoever shows up) - MSBuilder's `auratarget 0` equivalent.
function Slots.HasOpenSlotFor(role, hasAura)
    if type(role) ~= "string" then
        return false
    end
    if not Slots.HasOpenSlot(role) then
        return false
    end
    if role ~= "dps" or hasAura then
        return true
    end
    local db = DB()
    if db and db.roles and db.roles.aura == false then
        return true -- not recruiting toward aura coverage
    end
    local shortfall = Slots.AuraShortfall()
    if shortfall <= 0 then
        return true
    end
    local reservedFrom = Slots.GetMax("dps") - shortfall
    if reservedFrom < 0 then
        reservedFrom = 0
    end
    return Slots.CountFilled("dps") < reservedFrom
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

--- Does this player carry an XP aura? Orthogonal to their combat role.
function Slots.HasAura(name)
    local key = LowerName(name)
    local db = DB()
    EnsureDBSlots(db)
    if db and type(db.auraFlags) == "table" and db.auraFlags[key] ~= nil then
        return db.auraFlags[key] and true or false
    end
    return auraFlags[key] and true or false
end

--- Tag/untag a player as an aura carrier WITHOUT touching their combat
-- role - that separation is the whole point of the v0.4.131 model change.
function Slots.SetAura(name, on)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local key = LowerName(name)
    local value = on and true or nil -- nil, not false, so the table stays sparse
    auraFlags[key] = value
    local db = DB()
    EnsureDBSlots(db)
    if db then
        db.auraFlags[key] = value
    end
    return true
end

--- Copy of the current aura-tag map, so a caller that's about to
-- ClearAll()+re-Assign() everyone (RoleCheck.Resync) can restore the tags
-- instead of silently dropping them. Mirrors Slots.SnapshotAssignedAt().
function Slots.SnapshotAuraFlags()
    local out = {}
    local db = DB()
    EnsureDBSlots(db)
    local map = (db and type(db.auraFlags) == "table" and db.auraFlags) or auraFlags
    for k, v in pairs(map) do
        if v then
            out[k] = true
        end
    end
    return out
end

--- Ordered (oldest-assigned first) lowercase names currently slotted to a
-- role. Used by RaidMarks so "Tank 1" deterministically means the tank
-- assigned longest ago, not whatever order Lua's pairs() happens to give.
-- assignedAt isn't persisted across reloads, so this only stays strictly
-- ordered within one session - acceptable for a marker-assignment order.
function Slots.GetNamesForRole(role)
    local db = DB()
    EnsureDBSlots(db)
    local map = (db and db.assignedRoles) or assigned
    local out = {}
    for key, r in pairs(map) do
        if r == role then
            table.insert(out, key)
        end
    end
    table.sort(out, function(a, b)
        return (assignedAt[a] or 0) < (assignedAt[b] or 0)
    end)
    return out
end

--- Whether name was (re)assigned within the last graceSeconds. Used to
-- protect a just-invited applicant's role from being pruned by a resync
-- that races ahead of them actually appearing in the live roster -
-- InviteUnit succeeding doesn't mean they've joined yet; there's a real
-- gap between "invited" and "X has joined the raid group", and a resync
-- landing in that gap would otherwise see "assigned but not present" and
-- wrongly treat it as a stale leaver's assignment to clean up.
function Slots.RecentlyAssigned(name, graceSeconds)
    local key = LowerName(name)
    local t = assignedAt[key]
    if not t then
        return false
    end
    return (Now() - t) < (tonumber(graceSeconds) or 20)
end

--- Copy of the current [nameLower]=timestamp assignment-age map, so a
-- caller that's about to ClearAll()+re-Assign() everyone (RoleCheck.Resync)
-- can pass each name's original timestamp back into Assign() instead of
-- silently refreshing everyone's RecentlyAssigned grace window.
function Slots.SnapshotAssignedAt()
    local out = {}
    for k, v in pairs(assignedAt) do
        out[k] = v
    end
    return out
end

--- Remember whisper role for a player (invite path).
-- @param assignedAtOverride optional - reuse an earlier timestamp instead
--   of stamping "now" (see Slots.SnapshotAssignedAt / RoleCheck.Resync,
--   which needs to re-Assign every present member without resetting the
--   RecentlyAssigned grace clock for people who've been assigned for a
--   while - only a genuinely new assignment should get a fresh "now").
-- @param hasAura optional - when true, also tags them as an aura carrier.
--   Deliberately only ever SETS the tag, never clears it: an applicant
--   whispering just "dps" later shouldn't silently strip an aura the host
--   already confirmed. Use Slots.SetAura(name, false) to actually remove it.
function Slots.Assign(name, role, assignedAtOverride, hasAura)
    if type(name) ~= "string" or name == "" or type(role) ~= "string" then
        return false
    end
    local key = LowerName(name)
    assigned[key] = role
    assignedAt[key] = tonumber(assignedAtOverride) or Now()
    local db = DB()
    EnsureDBSlots(db)
    if db then
        db.assignedRoles[key] = role
    end
    if hasAura then
        Slots.SetAura(name, true)
    end
    if AscensionLFM.Invite and AscensionLFM.Invite.RememberRole then
        AscensionLFM.Invite.RememberRole(name, role)
    end
    -- Keep proper casing for Mini HUD regroup re-invites
    if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.RememberPlayer then
        AscensionLFM.MiniHUD.RememberPlayer(name)
    end
    -- Deliberately does NOT auto-trigger AuraBalance here anymore (used to,
    -- for role=="aura") - Assign() is called from event/timer contexts
    -- (whisper auto-invite, Role Check resync) where SetRaidSubgroup is
    -- not allowed to fire (WoW's secure-execution model requires a real
    -- click). Group sorting is now the host-triggered "Sort Groups"
    -- button (AuraBalance.SortGroupsNow()) instead.
    return true
end

function Slots.ClearName(name)
    local key = LowerName(name)
    assigned[key] = nil
    assignedAt[key] = nil
    auraFlags[key] = nil
    local db = DB()
    if db and type(db.assignedRoles) == "table" then
        db.assignedRoles[key] = nil
    end
    if db and type(db.auraFlags) == "table" then
        db.auraFlags[key] = nil
    end
end

function Slots.ClearAll()
    assigned = {}
    assignedAt = {}
    auraFlags = {}
    local db = DB()
    if db then
        db.assignedRoles = {}
        db.auraFlags = {}
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
--- @param protectedNames optional set of lowered names to never prune even
--   if not currently present - see Slots.RecentlyAssigned / the same
--   protection RoleCheck.ResyncAssigned applies.
function Slots.ReconcileAssigned(assignedMap, presentSet, protectedNames)
    local out = {}
    local removed = 0
    if type(assignedMap) ~= "table" then
        return out, 0
    end
    presentSet = presentSet or {}
    protectedNames = protectedNames or {}
    for name, role in pairs(assignedMap) do
        if presentSet[name] or protectedNames[name] then
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
    -- A manually-picked host role (v0.4.22) that's since been disabled via
    -- Accept Roles must not still be trusted - fall through to auto-pick
    -- instead of assigning the host to a role they no longer accept. Same
    -- "don't trust a stale role selection" pattern as v0.4.17/21/26.
    -- Since v0.4.131 a stored hostRole of "aura" is also stale by
    -- definition - aura is a tag now, not a seat the host can occupy.
    if role == "aura" then
        role = nil
    end
    if role and db and type(db.roles) == "table" and not db.roles[role] then
        role = nil
    end
    if not role and db and type(db.roles) == "table" then
        for _, r in ipairs(COMBAT_ROLES) do
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
        -- No roster info (tests / loading) - leave assignments alone.
        return 0
    end
    local protectedNames = {}
    for k in pairs(map) do
        if Slots.RecentlyAssigned(k) then
            protectedNames[k] = true
        end
    end
    local newMap, removed = Slots.ReconcileAssigned(map, present, protectedNames)
    assigned = {}
    for k, v in pairs(newMap) do
        assigned[k] = v
    end
    if db then
        db.assignedRoles = newMap
    end
    -- Prune aura tags the same way, or a leaver's aura keeps counting toward
    -- coverage forever and the DPS reservation stops holding seats it should.
    local auraMap = (db and type(db.auraFlags) == "table" and db.auraFlags) or auraFlags
    local newAura = {}
    for k, on in pairs(auraMap) do
        if on and newMap[k] then
            newAura[k] = true
        end
    end
    auraFlags = newAura
    if db then
        db.auraFlags = newAura
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
    -- Deliberately does NOT auto-trigger AuraBalance here anymore - ScanRaid
    -- is called from event/timer-driven roster tracking, where
    -- SetRaidSubgroup is not allowed to fire (see Slots.Assign's comment
    -- above). Group sorting is now the host-triggered "Sort Groups" button.
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
    auraFlags = {}
    local db = DB()
    if db then
        db.assignedRoles = {}
        db.auraFlags = {}
    end
    if type(map) == "table" then
        for k, v in pairs(map) do
            Slots.Assign(k, v)
        end
    end
end

Slots.ROLE_ORDER = ROLE_ORDER
Slots.COMBAT_ROLES = COMBAT_ROLES
