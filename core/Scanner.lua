-- AscensionLFM: core/Scanner.lua
-- Chat + whisper event listeners, dedupe, dispatch to notify / whisper / invite.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Scanner = {}
AscensionLFM.Scanner = Scanner

local recent = {} -- [leaderLower] = { t=, fingerprint= }
local whisperSent = {} -- [leaderLower] = lastSendTime

local CHAT_EVENTS = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_WHISPER",
}

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function PlayerName()
    if type(UnitName) == "function" then
        return UnitName("player")
    end
    return nil
end

local function IsIgnoredName(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if type(IsIgnored) == "function" then
        local ok, result = pcall(IsIgnored, name)
        if ok and result then
            return true
        end
    end
    return false
end

local function Fingerprint(parsed)
    if type(parsed) ~= "table" then
        return ""
    end
    local bits = {}
    for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        local info = parsed.roles and parsed.roles[role]
        if info then
            table.insert(bits, string.format("%s:%s/%s", role, tostring(info.filled), tostring(info.total)))
        end
    end
    return table.concat(bits, "|")
end

local function IsDupe(leader, parsed, window)
    local key = LowerName(leader)
    local entry = recent[key]
    if not entry then
        return false
    end
    local fp = Fingerprint(parsed)
    if entry.fingerprint == fp and (Now() - entry.t) < window then
        return true
    end
    return false
end

local function Remember(leader, parsed)
    recent[LowerName(leader)] = { t = Now(), fingerprint = Fingerprint(parsed) }
end

local function SourceLabel(event)
    if event == "CHAT_MSG_WHISPER" then
        return "whisper"
    elseif event == "CHAT_MSG_YELL" then
        return "yell"
    elseif event == "CHAT_MSG_SAY" then
        return "say"
    elseif event == "CHAT_MSG_GUILD" then
        return "guild"
    elseif event == "CHAT_MSG_CHANNEL" then
        return "channel"
    elseif event and event:find("PARTY") then
        return "party"
    elseif event and event:find("RAID") then
        return "raid"
    end
    return "chat"
end

local function NotifyMatch(leader, parsed, source)
    local line = string.format("%s — %s (%s)", tostring(leader), parsed.summary or "MS LFM", source)
    if AscensionLFM.Print then
        AscensionLFM.Print(line)
    end
    if AscensionLFM.Database and AscensionLFM.Database.PushMatch then
        AscensionLFM.Database.PushMatch({
            leader = leader,
            text = parsed.raw or parsed.summary,
            summary = parsed.summary,
            source = source,
            t = time and time() or 0,
        })
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshMatches then
        AscensionLFM.MainWindow.RefreshMatches()
    end
end

local function MaybeAutoWhisper(leader, parsed, db)
    if not db.autoWhisper then
        return
    end
    if type(SendChatMessage) ~= "function" then
        return
    end
    if IsIgnoredName(leader) then
        return
    end
    local me = PlayerName()
    if me and LowerName(me) == LowerName(leader) then
        return
    end
    if not AscensionLFM.Parser.NeedsAnyRole(parsed, db.roles) then
        return
    end
    local key = LowerName(leader)
    local last = whisperSent[key]
    local cd = tonumber(db.whisperCooldown) or 30
    if last and (Now() - last) < cd then
        return
    end
    local msg = tostring(db.whisperMessage or "inv ms"):sub(1, 120)
    if msg == "" then
        return
    end
    pcall(SendChatMessage, msg, "WHISPER", nil, leader)
    whisperSent[key] = Now()
    if AscensionLFM.Print then
        AscensionLFM.Print("whispered " .. tostring(leader) .. ": " .. msg)
    end
end

local function ShouldNotify(db, parsed)
    if db.mode == "notify" or db.mode == "hosting" then
        return true
    end
    if db.mode == "seeking" then
        return AscensionLFM.Parser.NeedsAnyRole(parsed, db.roles)
    end
    return false
end

local function HandlePublicLFM(leader, message, event)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode == "off" then
        return
    end
    local parsed = AscensionLFM.Parser.Parse(message)
    if not parsed or not parsed.isManastormLFM then
        return
    end
    local window = tonumber(db.dedupeSeconds) or 45
    if IsDupe(leader, parsed, window) then
        return
    end
    Remember(leader, parsed)

    if ShouldNotify(db, parsed) then
        NotifyMatch(leader, parsed, SourceLabel(event))
    end

    if db.mode == "seeking" and AscensionLFM.Parser.NeedsAnyRole(parsed, db.roles) then
        MaybeAutoWhisper(leader, parsed, db)
    end
end

local function HandleWhisper(sender, message)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        return
    end

    if db.mode == "notify" or db.mode == "seeking" then
        local parsed = AscensionLFM.Parser.Parse(message)
        if parsed and parsed.isManastormLFM then
            local window = tonumber(db.dedupeSeconds) or 45
            if not IsDupe(sender, parsed, window) then
                Remember(sender, parsed)
                if ShouldNotify(db, parsed) then
                    NotifyMatch(sender, parsed, "whisper")
                end
                if db.mode == "seeking" then
                    MaybeAutoWhisper(sender, parsed, db)
                end
            end
            return
        end
    end

    if db.mode == "hosting" and db.autoInvite then
        if AscensionLFM.Invite and AscensionLFM.Invite.TryHostInvite then
            AscensionLFM.Invite.TryHostInvite(sender, message)
        end
    end
end

local frame

function Scanner.Start()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    for _, ev in ipairs(CHAT_EVENTS) do
        frame:RegisterEvent(ev)
    end
    frame:SetScript("OnEvent", function(_, event, message, sender)
        if type(message) ~= "string" or message == "" then
            return
        end
        if type(sender) ~= "string" or sender == "" then
            return
        end
        local me = PlayerName()
        if me and LowerName(me) == LowerName(sender) then
            return
        end
        if IsIgnoredName(sender) then
            return
        end
        if event == "CHAT_MSG_WHISPER" then
            HandleWhisper(sender, message)
        else
            HandlePublicLFM(sender, message, event)
        end
    end)
end

function Scanner.GetRecent()
    return recent
end

Scanner._HandlePublicLFM = HandlePublicLFM
Scanner._HandleWhisper = HandleWhisper
Scanner._Fingerprint = Fingerprint
