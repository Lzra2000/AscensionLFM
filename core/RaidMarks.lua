-- AscensionLFM: core/RaidMarks.lua
-- Auto-assigns WoW raid target icons to whoever is currently slotted as
-- tank/healer in core/Slots.lua, so the raid markers above their heads
-- match the roles the host actually assigned instead of being set by hand.
-- Pure planning helpers are WoW-free for unit tests; only AutoMark() and
-- FindUnitToken() touch WoW globals (SetRaidTarget, roster APIs).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local RaidMarks = {}
AscensionLFM.RaidMarks = RaidMarks

-- SetRaidTarget icon indices: 1=Star 2=Circle 3=Diamond 4=Triangle 5=Moon
-- 6=Square 7=Cross 8=Skull. Skull/Cross for tanks is close to a universal
-- WoW convention (every raider already reads "skull = main tank" on
-- sight), so tanks get first claim on those two; healers take the next
-- distinct icons. Only the first N of each role get marked once the
-- reserved icons for that role run out - 8 markers total is a hard game
-- limit, not something this addon can raise.
RaidMarks.TANK_ICONS = { 8, 7 }        -- Skull, Cross
RaidMarks.HEALER_ICONS = { 6, 5, 4 }   -- Square, Moon, Triangle

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

--- Pure: builds { nameLower = { icon=, role= } } from ordered tank/healer
-- name lists (oldest-assigned first - see Slots.GetNamesForRole). If the
-- same person is somehow slotted as both, the earlier role in call order
-- wins rather than being overwritten, since tanks are passed first.
function RaidMarks.BuildPlan(tankNames, healerNames)
    local plan = {}
    for i, name in ipairs(tankNames or {}) do
        local icon = RaidMarks.TANK_ICONS[i]
        if icon and type(name) == "string" and name ~= "" then
            plan[LowerName(name)] = { icon = icon, role = "tank" }
        end
    end
    for i, name in ipairs(healerNames or {}) do
        local icon = RaidMarks.HEALER_ICONS[i]
        if icon and type(name) == "string" and name ~= "" then
            local key = LowerName(name)
            if not plan[key] then
                plan[key] = { icon = icon, role = "healer" }
            end
        end
    end
    return plan
end

--- Live raid/party unit token for a name, nil if not currently a member.
function RaidMarks.FindUnitToken(name)
    local target = LowerName(name)
    if target == "" then
        return nil
    end
    if type(GetNumRaidMembers) == "function" and type(GetRaidRosterInfo) == "function" then
        local n = GetNumRaidMembers() or 0
        for i = 1, n do
            local rn = GetRaidRosterInfo(i)
            if type(rn) == "string" and LowerName(rn) == target then
                return "raid" .. i
            end
        end
    end
    if type(GetNumPartyMembers) == "function" and type(UnitName) == "function" then
        local n = GetNumPartyMembers() or 0
        for i = 1, n do
            local pn = UnitName("party" .. i)
            if type(pn) == "string" and LowerName(pn) == target then
                return "party" .. i
            end
        end
        if type(UnitName) == "function" then
            local me = UnitName("player")
            if type(me) == "string" and LowerName(me) == target then
                return "player"
            end
        end
    end
    return nil
end

function RaidMarks.CanMark()
    if type(IsRaidLeader) == "function" and IsRaidLeader() then
        return true
    end
    if type(IsRaidOfficer) == "function" and IsRaidOfficer() then
        return true
    end
    if type(IsPartyLeader) == "function" and IsPartyLeader() then
        return true
    end
    return false
end

--- Clears every one of the 8 raid target icons currently in use (not just
-- the ones AutoMark would set) - useful before a re-mark so a tank who
-- got reassigned to dps doesn't keep an old Skull.
function RaidMarks.ClearAllMarks()
    if type(SetRaidTarget) ~= "function" or type(GetNumRaidMembers) ~= "function" then
        return 0
    end
    local n = GetNumRaidMembers() or 0
    if n == 0 then
        return 0
    end
    local cleared = 0
    for i = 1, n do
        local ok = pcall(SetRaidTarget, "raid" .. i, 0)
        if ok then
            cleared = cleared + 1
        end
    end
    return cleared
end

--- Applies raid target icons to current tank/healer assignments.
-- @return marked, skipped, errorReason (errorReason set only on a hard
--   stop before anything ran - e.g. no privilege)
function RaidMarks.AutoMark()
    if type(SetRaidTarget) ~= "function" then
        return 0, 0, "SetRaidTarget unavailable on this client"
    end
    if not RaidMarks.CanMark() then
        return 0, 0, "need lead/assist to set raid markers"
    end
    local Slots = AscensionLFM.Slots
    if not Slots or type(Slots.GetNamesForRole) ~= "function" then
        return 0, 0, "Slots module unavailable"
    end
    -- Raid-only feature: SetRaidTarget on a plain party has no group-wide
    -- meaning the same way, and Slots' tank/healer counts are meant for a
    -- raid-scale group in the first place.
    if type(GetNumRaidMembers) ~= "function" or (GetNumRaidMembers() or 0) == 0 then
        return 0, 0, "only works in a raid, not a party"
    end

    local tankNames = Slots.GetNamesForRole("tank")
    local healerNames = Slots.GetNamesForRole("healer")
    local plan = RaidMarks.BuildPlan(tankNames, healerNames)

    local marked, skipped = 0, 0
    for key, entry in pairs(plan) do
        local unit = RaidMarks.FindUnitToken(key)
        if unit then
            local ok = pcall(SetRaidTarget, unit, entry.icon)
            if ok then
                marked = marked + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end
    return marked, skipped
end
