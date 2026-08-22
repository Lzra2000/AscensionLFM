-- AscensionLFM: core/AscensionAPI.lua
-- Read-only Safe wrappers for Ascension Manastorm / LFG surfaces.
--
-- Evidence: AscensionLuaExtract patch-B.MPQ (Ascension_Manastorm/*,
-- FrameXML/Util/C_LFG.lua, ManastormUtil.lua) + live AscensionLogsCompanion
-- Capture/ManastormScan.lua. Do not invent APIs or return values.
--
-- Hard rules:
--   - Every call goes through AscensionLFM.Safe (pcall). Missing namespace /
--     missing method / Lua error => nil (or false for Is* predicates).
--   - pcall success does NOT mean the server acted (mutate APIs are not wrapped).
--   - C_Manastorm is CoA-only (absent on Bronzebeard/Epoch).
--   - C_Wildcard roll/mutate surface is out of scope for this addon (see NOTES).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

-- Ascension APIs can be missing per realm. Never hard-call them.
-- Same pattern as AscBuildschmiede BS.Safe — pcall success ≠ server acted.
function AscensionLFM.Safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c, d, e
end

local Safe = AscensionLFM.Safe

local function NS(name)
    local t = _G[name]
    if type(t) == "table" then
        return t
    end
    return nil
end

local function Meth(nsName, method)
    local ns = NS(nsName)
    if not ns then
        return nil
    end
    local fn = ns[method]
    if type(fn) == "function" then
        return fn
    end
    return nil
end

local API = {}
AscensionLFM.API = API

--- True when C_Manastorm exists with IsInManastorm (CoA gate).
function API.HasManastorm()
    return Meth("C_Manastorm", "IsInManastorm") ~= nil
end

--- C_Manastorm.IsInManastorm() — in an active Manastorm run.
function API.IsInManastorm()
    local v = Safe(Meth("C_Manastorm", "IsInManastorm"))
    return v and true or false
end

--- C_Manastorm.GetActiveLevel() — current level while in-run (zeroes on eject).
function API.GetActiveLevel()
    return Safe(Meth("C_Manastorm", "GetActiveLevel"))
end

--- C_Manastorm.GetActiveManastormID() — id for GetRewardModifier / reward visibility.
function API.GetActiveManastormID()
    return Safe(Meth("C_Manastorm", "GetActiveManastormID"))
end

--- C_Manastorm.GetActiveManastormType() — "SOLO"|"DUO"|"TRIO"|"GROUP" while in-run.
function API.GetActiveManastormType()
    return Safe(Meth("C_Manastorm", "GetActiveManastormType"))
end

--- Snapshot used by ALC ManastormScan.readActiveManastorm — nil when not in-run.
function API.ReadActiveManastorm()
    if not API.IsInManastorm() then
        return nil
    end
    return {
        is_active = true,
        level = API.GetActiveLevel(),
        manastorm_id = API.GetActiveManastormID(),
        manastorm_type = API.GetActiveManastormType(),
    }
end

--- C_Manastorm.GetRewardModifier(manastormID) ->
--- endReward, encounterReward, groupEndReward, groupEncounterReward
--- Ascension tracker shows group bonus only when max(group*) > 1.
function API.GetRewardModifier(manastormID)
    if manastormID == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "GetRewardModifier"), manastormID)
end

--- Group reward bonus percent above baseline (nil if none / not in run).
--- Mirrors Ascension_Manastorm objective tracker gate; does not invent values.
function API.GetGroupRewardBonusPercent()
    local id = API.GetActiveManastormID()
    if not id then
        return nil
    end
    local _, _, groupEnd, groupEnc = API.GetRewardModifier(id)
    local groupMulti = math.max(tonumber(groupEnd) or 1, tonumber(groupEnc) or 1)
    if groupMulti > 1 then
        return (groupMulti - 1) * 100
    end
    return nil
end

--- C_Manastorm.GetStageBonusExperience() — in-run XP stage bonus multiplier.
function API.GetStageBonusExperience()
    return Safe(Meth("C_Manastorm", "GetStageBonusExperience"))
end

--- C_Manastorm.GetExperienceModifier(difficulty, level) — queue XP preview.
--- difficulty: 0 normal / 2 when a max-level player is in group (client usage).
function API.GetExperienceModifier(difficulty, level)
    if level == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "GetExperienceModifier"), difficulty or 0, level)
end

--- C_Manastorm.GetMaxCompletedLevels(unit) -> ?, solo, duo, trio, group
--- Requires a unit token ("player"). No-arg calls fail server validation (ALC).
function API.GetMaxCompletedLevels(unit)
    unit = unit or "player"
    return Safe(Meth("C_Manastorm", "GetMaxCompletedLevels"), unit)
end

--- C_Manastorm.GetEnterableLevels() — levels offered in the enter queue UI.
function API.GetEnterableLevels()
    return Safe(Meth("C_Manastorm", "GetEnterableLevels"))
end

--- C_Manastorm.CanEnter(level) -> canEnter, reasons, ineligibleUnits
function API.CanEnter(level)
    if level == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "CanEnter"), level)
end

--- C_Manastorm.CanLeave() -> canLeave, reasons
function API.CanLeave()
    return Safe(Meth("C_Manastorm", "CanLeave"))
end

--- C_Manastorm.GetBoss() -> encounterID, stacks, healthPct, dmgPct (in-run).
function API.GetBoss()
    return Safe(Meth("C_Manastorm", "GetBoss"))
end

--- C_Manastorm.GetManastormCacheInfo() -> numCaches, additionalCacheChance, itemID
function API.GetManastormCacheInfo()
    return Safe(Meth("C_Manastorm", "GetManastormCacheInfo"))
end

--- C_Manastorm.GetRewardVisibility(context, itemID)
function API.GetRewardVisibility(context, itemID)
    if context == nil or itemID == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "GetRewardVisibility"), context, itemID)
end

--- C_Manastorm.GetRewardLimitProgress(context, itemID)
function API.GetRewardLimitProgress(context, itemID)
    if context == nil or itemID == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "GetRewardLimitProgress"), context, itemID)
end

--- Loadout reads (CONFIG_MANASTORM_LOADOUTS_ENABLED gate is client-side).
function API.GetNumLoadoutSlots()
    return Safe(Meth("C_Manastorm", "GetNumLoadoutSlots"))
end

function API.GetLoadoutSpellAtIndex(index)
    if index == nil then
        return nil
    end
    return Safe(Meth("C_Manastorm", "GetLoadoutSpellAtIndex"), index)
end

function API.GetAvailableLoadoutSpells()
    return Safe(Meth("C_Manastorm", "GetAvailableLoadoutSpells"))
end

--- C_LFG:CanUseManastorm() -> ok, reasonKey (level/config gate for Manastorm tab).
function API.CanUseManastorm()
    local ns = NS("C_LFG")
    if not ns then
        return nil
    end
    local fn = ns.CanUseManastorm
    if type(fn) ~= "function" then
        return nil
    end
    -- Client uses method call (self); pass ns as self.
    return Safe(fn, ns)
end

--- C_LFG:CanUseGroupFinder() -> ok, reason
function API.CanUseGroupFinder()
    local ns = NS("C_LFG")
    if not ns then
        return nil
    end
    local fn = ns.CanUseGroupFinder
    if type(fn) ~= "function" then
        return nil
    end
    return Safe(fn, ns)
end

--- C_GameMode:IsGameModeActive(mode) — ManastormQueue gates wildcard reward slots.
function API.IsGameModeActive(mode)
    if mode == nil then
        return nil
    end
    local ns = NS("C_GameMode")
    if not ns then
        return nil
    end
    local fn = ns.IsGameModeActive
    if type(fn) ~= "function" then
        return nil
    end
    return Safe(fn, ns, mode)
end

--- Prefer Manastorm-in-run over generic IsInInstance (Invite/Poster/MiniHUD).
function API.IsHostInsideInstance()
    if API.HasManastorm() then
        return API.IsInManastorm()
    end
    if type(_G.IsInInstance) ~= "function" then
        return false
    end
    local inInstance = Safe(_G.IsInInstance)
    return inInstance and true or false
end

--- Average item level for a unit token.
-- Ascension native (extract): UnitAverageItemLevel(unit) — used by
-- PaperDollFrame_SetItemLevel and CallBoardRender. C_Player:GetAverageItemLevel
-- and GetAverageItemLevel() are thin player-only wrappers around the same.
-- Returns nil when the API is missing, errors, or reports <= 0 (no invent).
-- Chat LFM leaders / whisper applicants without a unit token cannot be read.
function API.GetAverageItemLevel(unit)
    unit = unit or "player"
    local fn = _G.UnitAverageItemLevel
    if type(fn) == "function" then
        local v = tonumber(Safe(fn, unit))
        if v and v > 0 then
            return v
        end
    end
    if unit == "player" then
        local g = _G.GetAverageItemLevel
        if type(g) == "function" then
            local v = tonumber(Safe(g))
            if v and v > 0 then
                return v
            end
        end
        local ns = NS("C_Player")
        if ns and type(ns.GetAverageItemLevel) == "function" then
            local v = tonumber(Safe(ns.GetAverageItemLevel, ns))
            if v and v > 0 then
                return v
            end
        end
    end
    return nil
end

return API
