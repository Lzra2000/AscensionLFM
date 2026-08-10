-- AscensionLFM: core/AuraBalance.lua
-- Keep at most one "aura" role per raid subgroup (1–8); auto-move extras.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local AuraBalance = {}
AscensionLFM.AuraBalance = AuraBalance

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

local function CanMoveRaid()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if not raid or raid < 1 then
        return false
    end
    local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
    local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
    return lead or assist
end

--- Pure: plan moves so each subgroup has at most one aura.
-- @param members { {name=, index=, subgroup=, isAura=}, ... }
-- @return moves { {name=, index=, from=, to=}, ... }
function AuraBalance.PlanMoves(members)
    local moves = {}
    if type(members) ~= "table" then
        return moves
    end

    local byGroup = {}
    for g = 1, 8 do
        byGroup[g] = { auras = {}, others = 0 }
    end

    for _, m in ipairs(members) do
        if type(m) == "table" and type(m.name) == "string" and m.name ~= "" then
            local g = tonumber(m.subgroup) or 1
            if g < 1 then g = 1 end
            if g > 8 then g = 8 end
            if m.isAura then
                table.insert(byGroup[g].auras, m)
            else
                byGroup[g].others = byGroup[g].others + 1
            end
        end
    end

    local excess = {}
    for g = 1, 8 do
        local auras = byGroup[g].auras
        if #auras > 1 then
            -- Keep first (stable by index), move the rest
            table.sort(auras, function(a, b)
                return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
            end)
            for i = 2, #auras do
                table.insert(excess, auras[i])
            end
            -- leave only first in group count for capacity
            local keep = auras[1]
            byGroup[g].auras = { keep }
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

    for _, m in ipairs(excess) do
        local targets = groupsWithoutAura()
        if #targets == 0 then
            break
        end
        -- Prefer emptier groups (others count)
        table.sort(targets, function(a, b)
            local ca = byGroup[a].others + #byGroup[a].auras
            local cb = byGroup[b].others + #byGroup[b].auras
            if ca == cb then
                return a < b
            end
            return ca < cb
        end)
        local to = targets[1]
        local from = tonumber(m.subgroup) or 1
        if to ~= from then
            table.insert(moves, {
                name = m.name,
                index = m.index,
                from = from,
                to = to,
            })
            table.insert(byGroup[to].auras, m)
            -- remove from conceptual from-group auras already handled
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

--- Execute planned SetRaidSubgroup moves. Returns number moved.
function AuraBalance.ApplyMoves(moves)
    moves = moves or {}
    local n = 0
    if type(SetRaidSubgroup) ~= "function" then
        return 0
    end
    for _, mv in ipairs(moves) do
        local idx = tonumber(mv.index)
        local to = tonumber(mv.to)
        if idx and to and to >= 1 and to <= 8 then
            local ok = pcall(SetRaidSubgroup, idx, to)
            if ok then
                n = n + 1
                if AscensionLFM.Activity and AscensionLFM.Activity.Push then
                    AscensionLFM.Activity.Push(
                        "aura",
                        string.format("moved %s aura g%d → g%d", tostring(mv.name), tonumber(mv.from) or 0, to),
                        { name = mv.name }
                    )
                end
                if AscensionLFM.Print then
                    AscensionLFM.Print(string.format(
                        "Aura balance: %s  group %d → %d",
                        tostring(mv.name), tonumber(mv.from) or 0, to
                    ))
                end
            end
        end
    end
    return n
end

--- Scan roster + assignedRoles and auto-move so each subgroup has ≤1 aura.
-- @return movedCount, plannedCount
function AuraBalance.Balance()
    local db = DB()
    if db and db.autoMoveAura == false then
        return 0, 0
    end
    if not CanMoveRaid() then
        return 0, 0
    end
    local members = CollectRaidMembers()
    local plan = AuraBalance.PlanMoves(members)
    if #plan == 0 then
        return 0, 0
    end
    local moved = AuraBalance.ApplyMoves(plan)
    return moved, #plan
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

AuraBalance._CollectRaidMembers = CollectRaidMembers
AuraBalance._CanMoveRaid = CanMoveRaid
