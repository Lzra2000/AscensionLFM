-- AscensionLFM: core/ManastormTracker.lua
-- Feeds Manastorm level-clear/fail events into the session Activity log
-- (v0.4.73's Session Summary), so a hosting session shows not just
-- invite/kick/match counts but how the run itself actually went.
--
-- Events confirmed real via Ascension's own AscensionLogsCompanion source
-- (Capture/ManastormScan.lua, provided directly): MANASTORM_LEVEL_COMPLETED
-- fires once per level cleared (a1 = level number); MANASTORM_FAILED fires
-- on a wipe/ejection. That same source notes "C_Manastorm is absent on
-- Bronzebeard/Epoch" (CoA-only) - registering these events is harmless on
-- other server variants, they simply never fire there, so this module
-- doesn't need its own server-variant gate.
--
-- Pure helpers are WoW-free for unit tests; only the bottom event-wiring
-- section touches WoW globals.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local ManastormTracker = {}
AscensionLFM.ManastormTracker = ManastormTracker

--- Pure: build the Activity log text for a cleared level.
function ManastormTracker.FormatCleared(level)
    if level then
        return "Manastorm level " .. tostring(level) .. " cleared"
    end
    return "Manastorm level cleared"
end

--- Pure: build the Activity log text for a failed/wiped level.
function ManastormTracker.FormatFailed(level)
    if level then
        return "Manastorm level " .. tostring(level) .. " failed"
    end
    return "Manastorm run failed"
end

--- Handlers take the Activity module as a parameter (defaults to
-- AscensionLFM.Activity) so they're testable without touching globals.
function ManastormTracker.HandleLevelCompleted(level, activityModule)
    local mod = activityModule or AscensionLFM.Activity
    if not mod or not mod.Push then
        return false
    end
    return mod.Push("manastorm_cleared", ManastormTracker.FormatCleared(level), { detail = level })
end

function ManastormTracker.HandleFailed(level, activityModule)
    local mod = activityModule or AscensionLFM.Activity
    if not mod or not mod.Push then
        return false
    end
    return mod.Push("manastorm_failed", ManastormTracker.FormatFailed(level), { detail = level })
end

-- ============================================================================
-- WoW event wiring
-- ============================================================================

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("MANASTORM_LEVEL_COMPLETED")
    frame:RegisterEvent("MANASTORM_FAILED")
    frame:SetScript("OnEvent", function(_, event, a1)
        if event == "MANASTORM_LEVEL_COMPLETED" then
            ManastormTracker.HandleLevelCompleted(a1)
        elseif event == "MANASTORM_FAILED" then
            -- MANASTORM_FAILED's own payload isn't confirmed to include
            -- the level, so fall back to C_Manastorm.GetActiveLevel() if
            -- it's available (per ManastormScan.lua's own gotcha: read
            -- Manastorm state at event time, never poll afterward - the
            -- API zeroes the instant you're ejected, so this must happen
            -- synchronously inside this same handler, not deferred).
            local level = a1
            if not level then
                local api = AscensionLFM.API
                if api and api.GetActiveLevel then
                    level = api.GetActiveLevel()
                elseif type(_G.C_Manastorm) == "table" and type(_G.C_Manastorm.GetActiveLevel) == "function" then
                    local ok, lvl = pcall(_G.C_Manastorm.GetActiveLevel)
                    if ok then
                        level = lvl
                    end
                end
            end
            ManastormTracker.HandleFailed(level)
        end
    end)
end
