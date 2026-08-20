-- AscensionLFM: core/ChatFilter.lua
-- Optional declutter: hides public Manastorm LFM/LFG listings from chat
-- once they're already captured in the Log tab. Off by default - only
-- active once the user opts in via Settings -> General or /alfmchatfilter.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local ChatFilter = {}
AscensionLFM.ChatFilter = ChatFilter

-- Same channel set Scanner.lua already listens on for public listings
-- (party/raid/whisper are intentionally excluded - those aren't spam).
local FILTERED_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD",
}

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

function ChatFilter.IsEnabled()
    local db = DB()
    return db and db.chatFilterEnabled == true
end

function ChatFilter.SetEnabled(on)
    local db = DB()
    if db then
        db.chatFilterEnabled = on and true or false
    end
end

local function ShouldHide(msg)
    if not ChatFilter.IsEnabled() then
        return false
    end
    if type(AscensionLFM.Parser) ~= "table" or type(AscensionLFM.Parser.Parse) ~= "function" then
        return false
    end
    local parsed = AscensionLFM.Parser.Parse(msg)
    return type(parsed) == "table" and parsed.isManastormListing == true
end

-- ChatFrame_AddMessageEventFilter passes (frame, event, msg, ...); returning
-- true swallows the message for that chat frame. pcall-wrapped so a Parser
-- error never breaks the player's chat entirely.
local function Filter(_, _, msg)
    local ok, hide = pcall(ShouldHide, msg)
    return ok and hide == true
end

local installed = false
function ChatFilter.Install()
    if installed then
        return
    end
    if type(ChatFrame_AddMessageEventFilter) ~= "function" then
        return
    end
    for _, ev in ipairs(FILTERED_EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, Filter)
    end
    installed = true
end

SLASH_ALFMCHATFILTER1 = "/alfmchatfilter"
if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMCHATFILTER"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "on" then
            ChatFilter.SetEnabled(true)
        elseif msg == "off" then
            ChatFilter.SetEnabled(false)
        else
            ChatFilter.SetEnabled(not ChatFilter.IsEnabled())
        end
        if AscensionLFM.Print then
            AscensionLFM.Print("Chat declutter filter: " .. (ChatFilter.IsEnabled() and "ON" or "OFF"))
        end
    end
end

return ChatFilter
