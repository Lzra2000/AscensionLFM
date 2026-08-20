-- AscensionLFM: ui/LfmChatTab.lua
-- Optional dedicated chat tab that only receives copies of matched
-- Manastorm LFM/LFG lines - opposite direction from ChatFilter.lua
-- (which hides matches from the normal chat frames): this ADDS a
-- separate place to see just the feed, inspired by GroupBulletinBoard's
-- "/gbb chat organize" dedicated tab.
--
-- Off by default. Every WoW chat-window API call here (FCF_OpenNewWindow,
-- GetChatWindowInfo, NUM_CHAT_WINDOWS) is guarded and pcall-wrapped -
-- this couldn't be verified against a live 3.3.5a client this session,
-- so if anything about the API doesn't match, this module just silently
-- does nothing (LfmChatTab.Post becomes a no-op) instead of erroring or
-- breaking the rest of the addon.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local LfmChatTab = {}
AscensionLFM.LfmChatTab = LfmChatTab

local TAB_NAME = "AscensionLFM"
local tabFrame

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

--- Look for a chat window already named TAB_NAME (e.g. left over from a
-- previous session - Blizzard's chat window layout persists across
-- reloads/relogs on its own, independent of this addon).
local function FindExistingTab()
    if type(GetChatWindowInfo) ~= "function" or type(NUM_CHAT_WINDOWS) ~= "number" then
        return nil
    end
    for i = 1, NUM_CHAT_WINDOWS do
        local ok, name = pcall(GetChatWindowInfo, i)
        if ok and name == TAB_NAME then
            local frame = _G["ChatFrame" .. i]
            if type(frame) == "table" then
                return frame
            end
        end
    end
    return nil
end

function LfmChatTab.IsEnabled()
    local db = DB()
    return db and db.lfmChatTabEnabled == true
end

function LfmChatTab.SetEnabled(on)
    local db = DB()
    if db then
        db.lfmChatTabEnabled = on and true or false
    end
    if on then
        LfmChatTab.Ensure()
    end
end

--- Find or create the dedicated tab. Never errors - returns nil if
-- anything about this client's chat-window API doesn't match what's
-- expected, or if the feature is off.
function LfmChatTab.Ensure()
    if tabFrame then
        return tabFrame
    end
    if not LfmChatTab.IsEnabled() then
        return nil
    end
    tabFrame = FindExistingTab()
    if tabFrame then
        return tabFrame
    end
    if type(FCF_OpenNewWindow) ~= "function" then
        return nil
    end
    local ok = pcall(FCF_OpenNewWindow, TAB_NAME)
    if not ok then
        return nil
    end
    tabFrame = FindExistingTab()
    return tabFrame
end

--- Post a match line into the dedicated tab. Safe/no-op if disabled or
-- if the tab couldn't be created - callers don't need to check
-- IsEnabled() themselves first.
function LfmChatTab.Post(text, r, g, b)
    if not LfmChatTab.IsEnabled() then
        return
    end
    local frame = LfmChatTab.Ensure()
    if not frame or type(frame.AddMessage) ~= "function" then
        return
    end
    pcall(frame.AddMessage, frame, tostring(text or ""), r or 1, g or 0.82, b or 0.24)
end

SLASH_ALFMCHATTAB1 = "/alfmchattab"
if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMCHATTAB"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "on" then
            LfmChatTab.SetEnabled(true)
        elseif msg == "off" then
            LfmChatTab.SetEnabled(false)
        else
            LfmChatTab.SetEnabled(not LfmChatTab.IsEnabled())
        end
        if AscensionLFM.Print then
            AscensionLFM.Print("Dedicated LFM/LFG chat tab: " .. (LfmChatTab.IsEnabled() and "ON" or "OFF"))
        end
    end
end

--- Called from Bootstrap at login - no-ops immediately unless the
-- setting is already on (e.g. from a previous session).
function LfmChatTab.Start()
    LfmChatTab.Ensure()
end

return LfmChatTab
