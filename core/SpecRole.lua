-- AscensionLFM: core/SpecRole.lua
-- Optional host-role from Ascension SpecializationUtil (SpecMenu pattern).
-- Fail-soft: if API missing, returns nil.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local SpecRole = {}
AscensionLFM.SpecRole = SpecRole

-- Keyword -> role. Order: tank/heal/aura before generic dps.
local RULES = {
    { role = "tank", keys = { "tank", "prot", "protection", "blood", "guardian", "defensive" } },
    { role = "healer", keys = { "heal", "holy", "disc", "discipline", "resto", "restoration", "mist" } },
    { role = "aura", keys = { "aura", "experience" } },
    { role = "dps", keys = { "dps", "arms", "fury", "frost", "unholy", "fire", "arcane", "affliction",
        "destruction", "demonology", "assassin", "combat", "subtlety", "balance", "feral", "enhancement",
        "elemental", "shadow", "ret", "retribution", "survival", "marksmanship", "beast", "windwalker" } },
}

local function MatchRole(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local low = text:lower()
    for _, rule in ipairs(RULES) do
        for _, k in ipairs(rule.keys) do
            if low:find(k, 1, true) then
                return rule.role
            end
        end
    end
    return nil
end

--- Best-effort role from active Ascension specialization.
function SpecRole.GuessFromActiveSpec()
    -- Ascension SpecMenu path
    if type(SpecializationUtil) == "table" then
        local su = SpecializationUtil
        if type(su.GetActiveSpecialization) == "function" then
            local ok, info = pcall(su.GetActiveSpecialization)
            if ok and type(info) == "table" then
                local name = info.name or info.Name or info.specName
                local role = MatchRole(tostring(name or ""))
                if role then return role, name end
            elseif ok and type(info) == "number" then
                if type(su.GetSpecializationInfo) == "function" then
                    local ok2, a, b, c = pcall(su.GetSpecializationInfo, info)
                    if ok2 then
                        local name = type(a) == "string" and a or (type(b) == "string" and b) or tostring(info)
                        local role = MatchRole(tostring(name))
                        if role then return role, name end
                    end
                end
            end
        end
        if type(su.GetSpecializationInfo) == "function" then
            for i = 1, 12 do
                local ok, a, b = pcall(su.GetSpecializationInfo, i)
                if ok and a then
                    -- cannot know which is active without GetActive - skip
                    break
                end
            end
        end
        if type(su.GetSpecializationSpell) == "function" then
            -- no role from spell alone without more context
        end
    end
    -- Fallback: talent tree names (classic 3.3.5)
    if type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function" then
        local bestPts, bestName = -1, nil
        local n = GetNumTalentTabs() or 0
        for i = 1, n do
            local ok, name, _, points = pcall(GetTalentTabInfo, i)
            if ok and type(points) == "number" and points > bestPts then
                bestPts = points
                bestName = name
            end
        end
        local role = MatchRole(tostring(bestName or ""))
        if role then
            return role, bestName
        end
    end
    return nil, nil
end

--- Assign guessed role to player in Slots (hosting helper).
function SpecRole.ApplyToSelf()
    local role, src = SpecRole.GuessFromActiveSpec()
    if not role then
        if AscensionLFM.Print then
            AscensionLFM.Print("SpecRole: could not guess role from active spec/talents")
        end
        return nil
    end
    local me = type(UnitName) == "function" and UnitName("player") or nil
    if me and AscensionLFM.Slots and AscensionLFM.Slots.Assign then
        AscensionLFM.Slots.Assign(me, role)
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(string.format("SpecRole: you -> %s (%s)", role, tostring(src or "?")))
    end
    if AscensionLFM.RosterPanel and AscensionLFM.RosterPanel.Refresh then
        AscensionLFM.RosterPanel.Refresh()
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshSlots then
        AscensionLFM.MainWindow.RefreshSlots()
    end
    return role, src
end

SpecRole._MatchRole = MatchRole
