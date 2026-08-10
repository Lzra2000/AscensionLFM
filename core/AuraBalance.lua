-- AscensionLFM: core/AuraBalance.lua
-- Keep at most one "aura" role per raid subgroup (1–8); auto-move extras.
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
    }
end

--- Pure: plan moves so each subgroup has at most one aura.
-- Respects 5-player group cap: uses kind="set" or kind="swap".
-- @param members { {name=, index=, subgroup=, isAura=}, ... }
-- @return moves { {name=, from=, to=, kind=, swapName?=}, ... }
function AuraBalance.PlanMoves(members)
    local moves = {}
    if type(members) ~= "table" then
        return moves
    end

    local byGroup = {}
    for g = 1, 8 do
        byGroup[g] = { auras = {}, people = {} }
    end

    for _, raw in ipairs(members) do
        if type(raw) == "table" and type(raw.name) == "string" and raw.name ~= "" then
            local m = CopyMember(raw)
            local g = tonumber(m.subgroup) or 1
            if g < 1 then g = 1 end
            if g > 8 then g = 8 end
            m.subgroup = g
            table.insert(byGroup[g].people, m)
            if m.isAura then
                table.insert(byGroup[g].auras, m)
            end
        end
    end

    local excess = {}
    for g = 1, 8 do
        local auras = byGroup[g].auras
        if #auras > 1 then
            table.sort(auras, function(a, b)
                return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
            end)
            for i = 2, #auras do
                table.insert(excess, auras[i])
            end
            byGroup[g].auras = { auras[1] }
        end
    end

    local function removePerson(g, name)
        local people = byGroup[g].people
        for i = #people, 1, -1 do
            if LowerName(people[i].name) == LowerName(name) then
                table.remove(people, i)
            end
        end
        local auras = byGroup[g].auras
        for i = #auras, 1, -1 do
            if LowerName(auras[i].name) == LowerName(name) then
                table.remove(auras, i)
            end
        end
    end

    local function addPerson(g, m)
        m.subgroup = g
        table.insert(byGroup[g].people, m)
        if m.isAura then
            table.insert(byGroup[g].auras, m)
        end
    end

    local function groupsWithoutAura()
        local out = {}
        for g = 1, 8 do
            if #byGroup[g].auras == 0 then
                table.insert(out, g)
            end
        end
        return out
    end

    local function pickSwapVictim(g)
        for _, p in ipairs(byGroup[g].people) do
            if not p.isAura then
                return p
            end
        end
        return nil
    end

    for _, m in ipairs(excess) do
        local from = tonumber(m.subgroup) or 1
        local targets = groupsWithoutAura()
        table.sort(targets, function(a, b)
            local ca = #byGroup[a].people
            local cb = #byGroup[b].people
            if ca == cb then
                return a < b
            end
            return ca < cb
        end)

        local placed = false
        for _, to in ipairs(targets) do
            if to == from then
                -- already counted as no-aura somehow; skip
            elseif #byGroup[to].people < GROUP_CAP then
                table.insert(moves, {
                    name = m.name,
                    index = m.index,
                    from = from,
                    to = to,
                    kind = "set",
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
                        swapName = victim.name,
                        swapIndex = victim.index,
                    })
                    removePerson(from, m.name)
                    removePerson(to, victim.name)
                    addPerson(to, m)
                    victim.isAura = false
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
    local msg = detail or string.format(
        "moved %s to raid group %d (was %d)",
        tostring(mv.name), tonumber(mv.to) or 0, tonumber(mv.from) or 0
    )
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("aura", msg, { name = mv.name })
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("Aura: " .. msg)
    end
end

--- Apply a single planned move using live roster indices (by name).
-- @return ok
function AuraBalance.ApplyOne(mv, members)
    if type(mv) ~= "table" or type(mv.name) ~= "string" then
        return false
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
                "swapped %s ↔ %s (aura → g%d)",
                tostring(mv.name), tostring(mv.swapName), to
            ))
        end
        return ok and true or false
    end

    if type(SetRaidSubgroup) ~= "function" then
        return false
    end
    -- Target may have filled since plan — fall back to swap with a non-aura there.
    local targetCount = 0
    local victim = nil
    for _, m in ipairs(members) do
        if tonumber(m.subgroup) == to then
            targetCount = targetCount + 1
            if not m.isAura and not victim then
                victim = m
            end
        end
    end
    if targetCount >= GROUP_CAP then
        if victim and type(SwapRaidSubgroup) == "function" then
            local ok = pcall(SwapRaidSubgroup, me.index, victim.index)
            if ok then
                LogMove(mv, string.format(
                    "swapped %s ↔ %s (aura → g%d, group was full)",
                    tostring(mv.name), tostring(victim.name), to
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

--- Apply all moves in sequence (tests only — live path uses one-at-a-time).
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

--- Scan roster + assignedRoles and auto-move so each subgroup has ≤1 aura.
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
