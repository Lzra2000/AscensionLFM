-- AscensionLFM: core/AuraBalance.lua
-- Keep at most one "aura" role per raid subgroup (1-8); auto-move extras.
-- Uses SetRaidSubgroup when the target has room, SwapRaidSubgroup when full.
-- Applies ONE move at a time and waits for roster settle (indices reshuffle).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local AuraBalance = {}
AscensionLFM.AuraBalance = AuraBalance

local GROUP_CAP = 5
local SETTLE_TIMEOUT = 2.0

local waitingFor = nil -- { name=, to=, kind=, t0= }
local lastPlanFingerprint = ""

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

local function CanMoveRaid()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if not raid or raid < 1 then
        return false
    end
    if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then
        return false
    end
    local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
    local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
    return lead or assist
end

local function CopyMember(m)
    return {
        name = m.name,
        index = m.index,
        subgroup = m.subgroup,
        isAura = m.isAura and true or false,
        role = m.role,
    }
end

--- Pure: plan moves so each subgroup has at most one member with role==roleKey.
-- Respects 5-player group cap: uses kind="set" or kind="swap".
-- @param members { {name=, index=, subgroup=, isAura=, role=}, ... }
-- @param roleKey which role to balance ("aura" default, or "tank"/"healer")
-- @param opts { protectRoles={...} - never swap-displace these roles unless
--   no other choice exists; sortByGroupNumber=true - fill lowest-numbered
--   empty groups first (tank) instead of emptiest-group-first (aura/healer) }
-- @return moves { {name=, from=, to=, kind=, roleKey=, swapName?=}, ... }
function AuraBalance.PlanRoleMoves(members, roleKey, opts)
    roleKey = roleKey or "aura"
    opts = opts or {}
    local protect = {}
    if type(opts.protectRoles) == "table" then
        for _, r in ipairs(opts.protectRoles) do
            protect[r] = true
        end
    end
    local hasRole = function(m)
        if roleKey == "aura" then
            return m.isAura and true or false
        end
        return m.role == roleKey
    end

    local moves = {}
    if type(members) ~= "table" then
        return moves
    end

    local byGroup = {}
    for g = 1, 8 do
        byGroup[g] = { matches = {}, people = {} }
    end

    for _, raw in ipairs(members) do
        if type(raw) == "table" and type(raw.name) == "string" and raw.name ~= "" then
            local m = CopyMember(raw)
            local g = tonumber(m.subgroup) or 1
            if g < 1 then g = 1 end
            if g > 8 then g = 8 end
            m.subgroup = g
            table.insert(byGroup[g].people, m)
            if hasRole(m) then
                table.insert(byGroup[g].matches, m)
            end
        end
    end

    local excess = {}
    for g = 1, 8 do
        local matches = byGroup[g].matches
        if #matches > 1 then
            table.sort(matches, function(a, b)
                return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
            end)
            for i = 2, #matches do
                table.insert(excess, matches[i])
            end
            byGroup[g].matches = { matches[1] }
        end
    end

    local function removePerson(g, name)
        local people = byGroup[g].people
        for i = #people, 1, -1 do
            if LowerName(people[i].name) == LowerName(name) then
                table.remove(people, i)
            end
        end
        local matches = byGroup[g].matches
        for i = #matches, 1, -1 do
            if LowerName(matches[i].name) == LowerName(name) then
                table.remove(matches, i)
            end
        end
    end

    local function addPerson(g, m)
        m.subgroup = g
        table.insert(byGroup[g].people, m)
        if hasRole(m) then
            table.insert(byGroup[g].matches, m)
        end
    end

    local function groupsWithoutMatch()
        local out = {}
        for g = 1, 8 do
            if #byGroup[g].matches == 0 then
                table.insert(out, g)
            end
        end
        return out
    end

    -- Prefer a swap victim that isn't protected (e.g. don't undo an
    -- already-correct tank placement while balancing healers); only fall
    -- back to a protected member if the group has no other option.
    local function pickSwapVictim(g)
        local fallback = nil
        for _, p in ipairs(byGroup[g].people) do
            if not hasRole(p) then
                if not protect[p.role] then
                    return p
                elseif not fallback then
                    fallback = p
                end
            end
        end
        return fallback
    end

    for _, m in ipairs(excess) do
        local from = tonumber(m.subgroup) or 1
        local targets = groupsWithoutMatch()
        if opts.sortByGroupNumber then
            table.sort(targets, function(a, b) return a < b end)
        else
            table.sort(targets, function(a, b)
                local ca = #byGroup[a].people
                local cb = #byGroup[b].people
                if ca == cb then
                    return a < b
                end
                return ca < cb
            end)
        end

        local placed = false
        for _, to in ipairs(targets) do
            if to == from then
                -- already counted as no-match somehow; skip
            elseif #byGroup[to].people < GROUP_CAP then
                table.insert(moves, {
                    name = m.name,
                    index = m.index,
                    from = from,
                    to = to,
                    kind = "set",
                    roleKey = roleKey,
                })
                removePerson(from, m.name)
                addPerson(to, m)
                placed = true
                break
            else
                local victim = pickSwapVictim(to)
                if victim then
                    table.insert(moves, {
                        name = m.name,
                        index = m.index,
                        from = from,
                        to = to,
                        kind = "swap",
                        roleKey = roleKey,
                        swapName = victim.name,
                        swapIndex = victim.index,
                    })
                    removePerson(from, m.name)
                    removePerson(to, victim.name)
                    addPerson(to, m)
                    if roleKey == "aura" then
                        victim.isAura = false
                    end
                    addPerson(from, victim)
                    placed = true
                    break
                end
            end
        end
        if not placed then
            break
        end
    end

    return moves
end

--- Pure: plan moves so each subgroup has at most one aura. Back-compat
-- wrapper around PlanRoleMoves("aura") - unchanged behavior/signature.
-- @param members { {name=, index=, subgroup=, isAura=}, ... }
-- @return moves { {name=, from=, to=, kind=, swapName?=}, ... }
function AuraBalance.PlanMoves(members)
    return AuraBalance.PlanRoleMoves(members, "aura", {})
end

local function CollectRaidMembers()
    local out = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if not raid or raid < 1 or type(GetRaidRosterInfo) ~= "function" then
        return out
    end
    local db = DB()
    local map = (db and db.assignedRoles) or {}
    for i = 1, raid do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if type(name) == "string" and name ~= "" then
            local key = LowerName(name)
            local role = map[key]
            table.insert(out, {
                name = name,
                index = i,
                subgroup = tonumber(subgroup) or 1,
                isAura = role == "aura",
                role = role,
            })
        end
    end
    return out
end

local function FindByName(members, name)
    local key = LowerName(name)
    for _, m in ipairs(members) do
        if LowerName(m.name) == key then
            return m
        end
    end
    return nil
end

local function Fingerprint(members)
    local parts = {}
    for _, m in ipairs(members) do
        if m.isAura then
            table.insert(parts, LowerName(m.name) .. "@" .. tostring(m.subgroup))
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function LogMove(mv, detail)
    local roleKey = (type(mv) == "table" and mv.roleKey) or "aura"
    local msg = detail or string.format(
        "moved %s to raid group %d (was %d)",
        tostring(mv.name), tonumber(mv.to) or 0, tonumber(mv.from) or 0
    )
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push(roleKey, msg, { name = mv.name })
    end
    if AscensionLFM.Print then
        local label = roleKey:sub(1, 1):upper() .. roleKey:sub(2)
        AscensionLFM.Print(label .. ": " .. msg)
    end
end

--- Apply a single planned move using live roster indices (by name).
-- @return ok
function AuraBalance.ApplyOne(mv, members)
    if type(mv) ~= "table" or type(mv.name) ~= "string" then
        return false
    end
    local roleKey = mv.roleKey or "aura"
    local matches = function(m)
        if roleKey == "aura" then
            return m.isAura and true or false
        end
        return m.role == roleKey
    end
    members = members or CollectRaidMembers()
    local me = FindByName(members, mv.name)
    if not me then
        return false
    end
    local to = tonumber(mv.to)
    if not to or to < 1 or to > 8 then
        return false
    end
    if tonumber(me.subgroup) == to then
        return true -- already there
    end

    local kind = mv.kind or "set"
    if kind == "swap" and type(mv.swapName) == "string" then
        local other = FindByName(members, mv.swapName)
        if not other then
            return false
        end
        if type(SwapRaidSubgroup) ~= "function" then
            return false
        end
        local ok = pcall(SwapRaidSubgroup, me.index, other.index)
        if ok then
            LogMove(mv, string.format(
                "swapped %s ? %s (%s -> g%d)",
                tostring(mv.name), tostring(mv.swapName), roleKey, to
            ))
        end
        return ok and true or false
    end

    if type(SetRaidSubgroup) ~= "function" then
        return false
    end
    -- Target may have filled since plan - fall back to swap with a
    -- non-matching-role member there.
    local targetCount = 0
    local victim = nil
    for _, m in ipairs(members) do
        if tonumber(m.subgroup) == to then
            targetCount = targetCount + 1
            if not matches(m) and not victim then
                victim = m
            end
        end
    end
    if targetCount >= GROUP_CAP then
        if victim and type(SwapRaidSubgroup) == "function" then
            local ok = pcall(SwapRaidSubgroup, me.index, victim.index)
            if ok then
                LogMove(mv, string.format(
                    "swapped %s ? %s (%s -> g%d, group was full)",
                    tostring(mv.name), tostring(victim.name), roleKey, to
                ))
            end
            return ok and true or false
        end
        return false
    end

    local ok = pcall(SetRaidSubgroup, me.index, to)
    if ok then
        LogMove(mv)
    end
    return ok and true or false
end

--- Apply all moves in sequence (tests only - live path uses one-at-a-time).
function AuraBalance.ApplyMoves(moves)
    moves = moves or {}
    local n = 0
    for _, mv in ipairs(moves) do
        local members = CollectRaidMembers()
        if AuraBalance.ApplyOne(mv, members) then
            n = n + 1
        end
    end
    return n
end

local function ClearWait()
    waitingFor = nil
end

--- Scan roster + assignedRoles and auto-move so each subgroup has <=1 aura.
-- Applies at most one Set/Swap per call; waits for roster settle before the next.
-- @return movedCount, plannedCount
function AuraBalance.Balance()
    local db = DB()
    if db and db.autoMoveAura == false then
        ClearWait()
        return 0, 0
    end
    if not CanMoveRaid() then
        return 0, 0
    end

    local members = CollectRaidMembers()
    if #members == 0 then
        ClearWait()
        return 0, 0
    end

    if waitingFor then
        local m = FindByName(members, waitingFor.name)
        if m and tonumber(m.subgroup) == tonumber(waitingFor.to) then
            ClearWait()
        elseif (Now() - (waitingFor.t0 or 0)) > SETTLE_TIMEOUT then
            ClearWait()
        else
            return 0, 0
        end
    end

    local plan = AuraBalance.PlanMoves(members)
    local fp = Fingerprint(members)
    if #plan == 0 then
        lastPlanFingerprint = fp
        ClearWait()
        return 0, 0
    end

    local first = plan[1]
    local ok = AuraBalance.ApplyOne(first, members)
    if ok then
        waitingFor = {
            name = first.name,
            to = first.to,
            kind = first.kind or "set",
            t0 = Now(),
        }
        lastPlanFingerprint = fp
        return 1, #plan
    end
    return 0, #plan
end

--- Auto-move Tank, Healer, and Aura (in that priority order) so each
-- subgroup has at most one of each - same one-move-per-call + roster
-- settle-wait design as Balance(), just covering all three roles in one
-- shared queue. Tank fills the lowest-numbered empty groups first (so 2
-- tanks land in groups 1 and 2, matching how hosts read their raid frame);
-- Healer and Aura fill the emptiest group first, same rule Balance()
-- always used for Aura. Healer/Aura balancing never displaces an
-- already-placed Tank unless a full group leaves no other choice.
-- Each role respects its own toggle (autoMoveTank/autoMoveHealer/
-- autoMoveAura, all default ON) independently.
function AuraBalance.BalanceAll()
    local db = DB()
    if not CanMoveRaid() then
        return 0, 0
    end

    local members = CollectRaidMembers()
    if #members == 0 then
        ClearWait()
        return 0, 0
    end

    if waitingFor then
        local m = FindByName(members, waitingFor.name)
        if m and tonumber(m.subgroup) == tonumber(waitingFor.to) then
            ClearWait()
        elseif (Now() - (waitingFor.t0 or 0)) > SETTLE_TIMEOUT then
            ClearWait()
        else
            return 0, 0
        end
    end

    local specs = {
        { key = "tank", enabled = "autoMoveTank", protect = {}, sortByGroupNumber = true },
        { key = "healer", enabled = "autoMoveHealer", protect = { "tank" }, sortByGroupNumber = false },
        { key = "aura", enabled = "autoMoveAura", protect = { "tank", "healer" }, sortByGroupNumber = false },
    }

    for _, spec in ipairs(specs) do
        if not (db and db[spec.enabled] == false) then
            local plan = AuraBalance.PlanRoleMoves(members, spec.key, {
                protectRoles = spec.protect,
                sortByGroupNumber = spec.sortByGroupNumber,
            })
            if #plan > 0 then
                local first = plan[1]
                local ok = AuraBalance.ApplyOne(first, members)
                if ok then
                    waitingFor = {
                        name = first.name,
                        to = first.to,
                        kind = first.kind or "set",
                        t0 = Now(),
                    }
                    return 1, #plan
                end
            end
        end
    end

    ClearWait()
    return 0, 0
end

--- True if subgroup already has an assigned aura (for invite gating helpers).
function AuraBalance.SubgroupHasAura(subgroup, members)
    subgroup = tonumber(subgroup) or 0
    if type(members) ~= "table" then
        return false
    end
    for _, m in ipairs(members) do
        if m.isAura and tonumber(m.subgroup) == subgroup then
            return true
        end
    end
    return false
end

function AuraBalance._ResetForTests()
    ClearWait()
    lastPlanFingerprint = ""
end

AuraBalance._CollectRaidMembers = CollectRaidMembers
AuraBalance._CanMoveRaid = CanMoveRaid
AuraBalance.GROUP_CAP = GROUP_CAP
