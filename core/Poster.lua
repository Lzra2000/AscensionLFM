-- AscensionLFM: core/Poster.lua
-- LFM message builder, one-shot post, and opt-in auto-repost.
-- Pure helpers are WoW-free for unit tests.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Poster = {}
AscensionLFM.Poster = Poster

local MIN_INTERVAL = 30
local DEFAULT_INTERVAL = 60
-- Aura label is plural "Auras" = coverage count (tag), not a combat seat.
-- Parser still matches via ROLE_PATTERNS.aura ("auras?").
local ROLE_LABELS = {
    tank = "Tanks",
    healer = "Healers",
    aura = "Auras",
    dps = "DPS",
}
local ROLE_ORDER = { "tank", "healer", "aura", "dps" }

-- Same logic as Invite.lua — AscensionLFM.API.IsHostInsideInstance
-- (C_Manastorm.IsInManastorm when present, else IsInInstance).
local function IsHostInsideInstance()
    local api = AscensionLFM.API
    if api and api.IsHostInsideInstance then
        return api.IsHostInsideInstance() and true or false
    end
    if type(C_Manastorm) == "table" and type(C_Manastorm.IsInManastorm) == "function" then
        local ok, inManastorm = pcall(C_Manastorm.IsInManastorm)
        if ok then
            return inManastorm and true or false
        end
    end
    if type(IsInInstance) ~= "function" then
        return false
    end
    local ok, inInstance = pcall(IsInInstance)
    return ok and inInstance and true or false
end
local CHANNELS = { YELL = true, SAY = true, GUILD = true, CHANNEL = true }

local frame
local lastPostAt = 0
local nextPostAt = 0
local lastTickAt = 0
local lastStatus = "idle"
local lastMessage = ""

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function DB()
    if AscensionLFM.Database and AscensionLFM.Database.Get then
        return AscensionLFM.Database.Get()
    end
    return nil
end

--- Pure: clamp repost interval (seconds). Min 30, default 60, max 600.
function Poster.ClampInterval(n)
    n = tonumber(n)
    if not n then
        return DEFAULT_INTERVAL
    end
    if n < MIN_INTERVAL then
        return MIN_INTERVAL
    end
    if n > 600 then
        return 600
    end
    return math.floor(n + 0.5)
end

--- Pure: build LFM string from a Slots.Snapshot()-style table.
-- Format: LFM MS {t}/{tmax} Tanks {h}/{hmax} Healers {a}/{amax} Aura {d}/{dmax} DPS
--- Prefix used when a Mythic+ dungeon/level is set - e.g. "[Deadmines +14] "
-- in front of the usual "LFM MS ..." role bits. Pure so it's testable
-- without touching the DB directly.
function Poster.MPlusPrefix(dungeon, level)
    dungeon = type(dungeon) == "string" and dungeon:match("^%s*(.-)%s*$") or ""
    level = tonumber(level) or 0
    if dungeon == "" or level <= 0 then
        return ""
    end
    return string.format("[%s +%d] ", dungeon, level)
end

--- Content-type prefix for the LFM post: "raid" always tags [RAID],
-- "mplus" uses the dungeon+level tag (or nothing if either is unset),
-- "ms"/anything else adds nothing. contentType is optional - omitting it
-- keeps the pre-0.4.103 behavior (mplus-prefix-if-set) so existing
-- BuildMessage(snap, showAll, dungeon, level) callers are unaffected.
function Poster.ContentPrefix(contentType, mplusDungeon, mplusLevel)
    if contentType == "raid" then
        return "[RAID] "
    elseif contentType == "ms" then
        return ""
    end
    -- "mplus" or omitted (nil) - same as the plain M+ prefix.
    return Poster.MPlusPrefix(mplusDungeon, mplusLevel)
end

function Poster.BuildMessage(snapshot, showAll, mplusDungeon, mplusLevel, contentType)
    snapshot = snapshot or {}
    local bits = { "LFM MS" }
    for _, role in ipairs(ROLE_ORDER) do
        local s = snapshot[role] or {}
        local filled = tonumber(s.filled) or 0
        local max = tonumber(s.max) or 0
        if filled < 0 then filled = 0 end
        if max < 0 then max = 0 end
        -- Default: only open roles. showAll=true keeps filled lines too
        -- (e.g. "2/2 Tanks | 1/3 Healers") so readers see composition.
        if max > 0 and (showAll or filled < max) then
            table.insert(bits, string.format("%d/%d %s", filled, max, ROLE_LABELS[role]))
        end
    end
    local prefix = Poster.ContentPrefix(contentType, mplusDungeon, mplusLevel)
    if #bits == 1 then
        return prefix .. "LFM MS - full"
    end
    return prefix .. table.concat(bits, " | ")
end

--- Pure: true when every role cap is filled (max>0 roles only) OR group size >= maxPartySize.
-- Optional unassignedCount: near-full raid with people lacking T/H/A/D pauses LFM spam
-- until RW sync (avoids forever posting "Aura 0/3" at 14/15).
function Poster.IsFull(snapshot, groupSize, maxPartySize, unassignedCount)
    groupSize = tonumber(groupSize) or 0
    maxPartySize = tonumber(maxPartySize) or 15
    unassignedCount = tonumber(unassignedCount) or 0
    if maxPartySize > 0 and groupSize >= maxPartySize then
        return true, "maxPartySize"
    end
    -- Nearly full + unassigned bodies: seats are taken; roles just unknown -> stop repost
    if unassignedCount > 0 and maxPartySize > 0 and groupSize >= (maxPartySize - 1) then
        return true, "unassigned"
    end
    snapshot = snapshot or {}
    local anyCap = false
    for _, role in ipairs(ROLE_ORDER) do
        local s = snapshot[role]
        if s then
            local max = tonumber(s.max) or 0
            local filled = tonumber(s.filled) or 0
            if max > 0 then
                anyCap = true
                if filled < max then
                    return false, nil
                end
            end
        end
    end
    if anyCap then
        return true, "slots"
    end
    return false, nil
end

--- Pure: whether an auto-repost tick should fire a message.
function Poster.ShouldRepost(now, lastAt, interval, enabled, mode, isFull)
    if not enabled then
        return false, "disabled"
    end
    if mode ~= "hosting" then
        return false, "not hosting"
    end
    if isFull then
        return false, "full"
    end
    now = tonumber(now) or 0
    lastAt = tonumber(lastAt) or 0
    interval = Poster.ClampInterval(interval)
    if lastAt > 0 and (now - lastAt) < interval then
        return false, "waiting"
    end
    return true, nil
end

local function NormalizeChannel(ch)
    ch = string.upper(tostring(ch or "YELL"))
    if not CHANNELS[ch] then
        return "YELL"
    end
    return ch
end

local function ResolveChannelIndex(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil
    end
    if type(GetChannelName) == "function" then
        -- GetChannelName(name) -> id, name, ...  (3.3.5a). Guard with pcall:
        -- an unrecognized/malformed name should just mean "not found", not
        -- an uncaught error that silently breaks the whole resolution.
        local ok, id = pcall(GetChannelName, name)
        if ok then
            id = tonumber(id)
            if id and id > 0 then
                return id
            end
        end
    end
    -- Numeric channel id typed directly - also accept a copy-pasted "N."
    -- prefix like the channel tab shows ("1. General"), e.g. "1." -> 1.
    local asNum = tonumber(name) or tonumber(name:match("^(%d+)%."))
    if asNum and asNum > 0 then
        return asNum
    end
    return nil
end

--- Whether the resolved channel id is one the player has actually joined.
-- SendChatMessage to a CHANNEL type the player hasn't joined doesn't throw
-- a Lua error - it just silently fails client-side (a system message the
-- addon never sees), the same "no error != it worked" trap already fixed
-- for Kick59's UninviteUnit (v0.4.28). Defaults to true (assume joined)
-- if GetChannelList is unavailable, errors, or returns nothing - this
-- check should never itself become a new reason posting silently breaks.
local function IsChannelJoined(id)
    if type(GetChannelList) ~= "function" then
        return true
    end
    local ok, results = pcall(function() return { GetChannelList() } end)
    if not ok or type(results) ~= "table" or #results == 0 then
        return true
    end
    for idx = 1, #results, 3 do
        if tonumber(results[idx]) == id then
            return true
        end
    end
    return false
end

--- Snapshot helper that prefers live Slots.Snapshot.
local function LiveSnapshot()
    if AscensionLFM.Slots and AscensionLFM.Slots.Snapshot then
        return AscensionLFM.Slots.Snapshot()
    end
    return {}
end

local function LiveGroupSize()
    if AscensionLFM.Invite and AscensionLFM.Invite.GetGroupSize then
        return AscensionLFM.Invite.GetGroupSize()
    end
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        return raid
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    return (party or 0) + 1
end

local function LiveUnassignedCount()
    if AscensionLFM.Slots and AscensionLFM.Slots.UnassignedMembers then
        local _, n = AscensionLFM.Slots.UnassignedMembers()
        return tonumber(n) or 0
    end
    return 0
end

--- Zero out a role's filled/max/open when the host has turned off accepting
-- it (db.roles[role] == false), even if db.slotMax still has a leftover
-- positive cap left over from before it was disabled. Without this, the
-- posted LFM text could advertise e.g. "0/3 Healers" for a role nobody can
-- actually get invited for (TryHostInvite/TryLfgInvite already reject via
-- db.roles separately with "role filtered" - so the ad and the reply would
-- contradict each other), and Poster.IsFull's "slots" full-check could
-- never resolve since that role's cap could never be met by anyone.
local function FilterAcceptedRoles(snapshot, db)
    if type(snapshot) ~= "table" then
        return snapshot
    end
    local roles = db and db.roles
    if type(roles) ~= "table" then
        return snapshot
    end
    local out = {}
    for role, s in pairs(snapshot) do
        if type(s) == "table" and roles[role] == false then
            out[role] = { filled = 0, max = 0, open = false }
        else
            out[role] = s
        end
    end
    return out
end

--- Build (or refresh) the current LFM text from slots.
function Poster.RefreshMessage()
    local db = DB()
    lastMessage = Poster.BuildMessage(FilterAcceptedRoles(LiveSnapshot(), db), db and db.postShowAllRoles,
        db and db.mplusDungeon, db and db.mplusLevel, db and db.contentType)
    return lastMessage
end

function Poster.GetMessage()
    if lastMessage == "" then
        return Poster.RefreshMessage()
    end
    return lastMessage
end

function Poster.SetMessage(msg)
    lastMessage = tostring(msg or "")
end

--- Send one LFM post via SendChatMessage. Uses msg or live rebuild.
-- @return ok, err
--- Escape literal "|" for SendChatMessage. WoW's chat system reserves "|"
-- as the start of an escape/color/link code (|cAARRGGBB..., |H...|h, |T...|t);
-- a raw "|" not followed by a recognized code throws "Invalid escape code
-- in chat message" and the whole send fails. "||" is the standard WoW
-- escape for a literal pipe - it renders as a single "|" to readers, so
-- the visible " | " role separator (v0.4.29) looks identical once
-- escaped. Only applied right before the actual SendChatMessage call -
-- BuildMessage()'s output, the UI preview box, and Parser.Parse() (which
-- reads other hosts' raw posts) all keep the clean, single-pipe text.
local function EscapeForSend(s)
    return tostring(s or ""):gsub("|", "||")
end

function Poster.PostOnce(msg, channel, channelName, nowOverride, skipAdState)
    local db = DB()
    channel = NormalizeChannel(channel or (db and db.postChannel) or "YELL")
    channelName = channelName or (db and db.postChannelName) or ""
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        msg = Poster.RefreshMessage()
    end
    if msg == "" then
        return false, "empty message"
    end
    if type(SendChatMessage) ~= "function" then
        return false, "SendChatMessage missing"
    end
    local sendMsg = EscapeForSend(msg)

    local ok, err
    if channel == "CHANNEL" then
        local id = ResolveChannelIndex(channelName)
        if not id then
            -- Do NOT silently fall back to YELL - that's a completely
            -- different, much shorter-range broadcast than the configured
            -- channel, and posting there instead without the host
            -- realizing means the LFM silently reaches almost nobody
            -- while looking like it worked. Fail loudly instead so the
            -- host notices and fixes the channel name/number.
            local reason = "channel not found: " .. tostring(channelName)
            lastStatus = "post failed: bad channel"
            if AscensionLFM.Print then
                AscensionLFM.Print("Post failed - " .. reason
                    .. ". Check the Channel name field (try the number shown in your chat tab, e.g. \"1\").")
            end
            return false, reason
        end
        if not IsChannelJoined(id) then
            -- Same fail-loud philosophy: resolving to a real channel id
            -- that the player hasn't joined (e.g. "3.Zone" unchecked in
            -- the channel config) would otherwise post nothing while
            -- looking successful, since SendChatMessage doesn't error for
            -- this case either.
            local reason = "channel " .. tostring(id) .. " not joined"
            lastStatus = "post failed: channel not joined"
            if AscensionLFM.Print then
                AscensionLFM.Print("Post failed - you haven't joined channel " .. tostring(id)
                    .. ". Right-click a chat tab -> Channels to join it, or check the number in the Post tab.")
            end
            return false, reason
        end
        ok, err = pcall(SendChatMessage, sendMsg, "CHANNEL", nil, id)
    else
        ok, err = pcall(SendChatMessage, sendMsg, channel)
    end
    if not ok then
        return false, tostring(err)
    end

    local now = tonumber(nowOverride) or Now()
    -- skipAdState: one-off broadcasts (MiniHUD FULL/Need buttons) send
    -- unrelated text through this same function and must not clobber the
    -- LFM ad's own repost timing/preview state.
    if not skipAdState then
        lastPostAt = now
        local interval = Poster.ClampInterval(db and db.repostInterval)
        nextPostAt = now + interval
        lastMessage = msg
    end
    lastStatus = "posted"
    if db then
        db.postChannel = channel
        db.lastPostAt = (type(time) == "function" and time()) or 0
    end
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("post", channel .. ": " .. msg)
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("posted LFM (" .. channel .. "): " .. msg)
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshPost then
        AscensionLFM.MainWindow.RefreshPost()
    end
    return true
end

function Poster.GetStatus()
    local db = DB()
    local enabled = db and db.autoRepost and true or false
    local mode = (db and db.mode) or "off"
    local interval = Poster.ClampInterval(db and db.repostInterval)
    local now = Now()
    local snap = FilterAcceptedRoles(LiveSnapshot(), db)
    local full, fullReason = Poster.IsFull(snap, LiveGroupSize(), db and db.maxPartySize, LiveUnassignedCount())
    local countdown = 0
    if nextPostAt > now then
        countdown = math.floor(nextPostAt - now + 0.5)
    end
    return {
        enabled = enabled,
        mode = mode,
        interval = interval,
        lastPostAt = lastPostAt,
        nextPostAt = nextPostAt,
        countdown = countdown,
        isFull = full,
        fullReason = fullReason,
        status = lastStatus,
        message = lastMessage ~= "" and lastMessage or Poster.BuildMessage(snap, false, db and db.mplusDungeon, db and db.mplusLevel, db and db.contentType),
        channel = NormalizeChannel(db and db.postChannel),
        channelName = (db and db.postChannelName) or "",
    }
end

--- One auto-repost tick. Returns status string.
function Poster.Tick(now)
    now = tonumber(now) or Now()
    local db = DB()
    if not db then
        lastStatus = "no db"
        return lastStatus
    end

    local snap = FilterAcceptedRoles(LiveSnapshot(), db)
    lastMessage = Poster.BuildMessage(snap, false, db.mplusDungeon, db.mplusLevel, db.contentType)
    local full, fullReason = Poster.IsFull(snap, LiveGroupSize(), db.maxPartySize, LiveUnassignedCount())
    local ok, reason = Poster.ShouldRepost(
        now,
        lastPostAt,
        db.repostInterval,
        db.autoRepost and true or false,
        db.mode,
        full
    )
    if ok and db.pauseRepostInInstance ~= false and IsHostInsideInstance() then
        ok = false
        reason = "in instance"
    end
    if not ok then
        if reason == "in instance" then
            lastStatus = "paused: in instance"
            if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshPost then
                AscensionLFM.MainWindow.RefreshPost()
            end
            return lastStatus
        end
        if reason == "full" and fullReason == "unassigned" then
            lastStatus = "need RW (unassigned)"
            return lastStatus
        end
        if reason == "full" then
            lastStatus = "full (" .. tostring(fullReason or "slots") .. ")"
            -- Stop auto-repost when full so it does not keep ticking posts later
            if db.autoRepost then
                db.autoRepost = false
                lastStatus = "stopped: full"
                if db.announceFull then
                    local fullMsg = tostring(db.fullAnnounceMessage or "LFM MS FULL - thanks!")
                    if fullMsg ~= "" and type(SendChatMessage) == "function" then
                        local sendFullMsg = EscapeForSend(fullMsg)
                        local ch = NormalizeChannel(db.postChannel)
                        if ch == "CHANNEL" then
                            local id = ResolveChannelIndex(db.postChannelName)
                            if id then
                                pcall(SendChatMessage, sendFullMsg, "CHANNEL", nil, id)
                            end
                        else
                            pcall(SendChatMessage, sendFullMsg, ch)
                        end
                    end
                    lastStatus = "stopped: full (announced)"
                end
                if AscensionLFM.Activity and AscensionLFM.Activity.Push then
                    AscensionLFM.Activity.Push("full", "auto-repost stopped (" .. tostring(fullReason or "slots") .. ")")
                end
            end
        elseif reason == "waiting" then
            lastStatus = "waiting"
            nextPostAt = lastPostAt + Poster.ClampInterval(db.repostInterval)
        else
            lastStatus = reason or "idle"
        end
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshPost then
            AscensionLFM.MainWindow.RefreshPost()
        end
        return lastStatus
    end

    local posted, err = Poster.PostOnce(lastMessage, db.postChannel, db.postChannelName, now)
    if not posted then
        lastStatus = "error: " .. tostring(err)
        return lastStatus
    end
    lastStatus = "reposted"
    return lastStatus
end

function Poster.Start()
    if frame then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(_, elapsed)
        lastTickAt = lastTickAt + (elapsed or 0)
        if lastTickAt < 0.5 then
            return
        end
        lastTickAt = 0
        local db = DB()
        if not db or not db.autoRepost then
            return
        end
        Poster.Tick(Now())
    end)
end

function Poster.OnRosterChanged()
    -- Rebuild preview text when roster changes while posting/hosting.
    local db = DB()
    if not db then
        return
    end
    if db.mode == "hosting" or db.autoRepost then
        Poster.RefreshMessage()
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshPost then
            AscensionLFM.MainWindow.RefreshPost()
        end
    end
end

function Poster._ResetForTests()
    lastPostAt = 0
    nextPostAt = 0
    lastTickAt = 0
    lastStatus = "idle"
    lastMessage = ""
end

function Poster._SetLastPostAt(t)
    lastPostAt = tonumber(t) or 0
end

Poster.MIN_INTERVAL = MIN_INTERVAL
Poster.DEFAULT_INTERVAL = DEFAULT_INTERVAL
Poster.ROLE_ORDER = ROLE_ORDER
