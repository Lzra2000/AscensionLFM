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
local ROLE_LABELS = {
    tank = "Tanks",
    healer = "Healers",
    aura = "Aura",
    dps = "DPS",
}
local ROLE_ORDER = { "tank", "healer", "aura", "dps" }
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
function Poster.BuildMessage(snapshot)
    snapshot = snapshot or {}
    local bits = { "LFM MS" }
    for _, role in ipairs(ROLE_ORDER) do
        local s = snapshot[role] or {}
        local filled = tonumber(s.filled) or 0
        local max = tonumber(s.max) or 0
        if filled < 0 then filled = 0 end
        if max < 0 then max = 0 end
        table.insert(bits, string.format("%d/%d %s", filled, max, ROLE_LABELS[role]))
    end
    return table.concat(bits, " ")
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
    -- Nearly full + unassigned bodies: seats are taken; roles just unknown → stop repost
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
    if type(GetChannelName) ~= "function" then
        return nil
    end
    -- GetChannelName(name) → id, name, ...  (3.3.5a)
    local id = GetChannelName(name)
    id = tonumber(id)
    if id and id > 0 then
        return id
    end
    -- Numeric channel id typed directly
    local asNum = tonumber(name)
    if asNum and asNum > 0 then
        return asNum
    end
    return nil
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

--- Build (or refresh) the current LFM text from slots.
function Poster.RefreshMessage()
    lastMessage = Poster.BuildMessage(LiveSnapshot())
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
function Poster.PostOnce(msg, channel, channelName, nowOverride)
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

    local ok, err
    if channel == "CHANNEL" then
        local id = ResolveChannelIndex(channelName)
        if not id then
            if AscensionLFM.Print then
                AscensionLFM.Print("bad channel name — falling back to YELL")
            end
            channel = "YELL"
            ok, err = pcall(SendChatMessage, msg, "YELL")
        else
            ok, err = pcall(SendChatMessage, msg, "CHANNEL", nil, id)
        end
    else
        ok, err = pcall(SendChatMessage, msg, channel)
    end
    if not ok then
        return false, tostring(err)
    end

    local now = tonumber(nowOverride) or Now()
    lastPostAt = now
    local interval = Poster.ClampInterval(db and db.repostInterval)
    nextPostAt = now + interval
    lastMessage = msg
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
    local snap = LiveSnapshot()
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
        message = lastMessage ~= "" and lastMessage or Poster.BuildMessage(snap),
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

    local snap = LiveSnapshot()
    lastMessage = Poster.BuildMessage(snap)
    local full, fullReason = Poster.IsFull(snap, LiveGroupSize(), db.maxPartySize, LiveUnassignedCount())
    local ok, reason = Poster.ShouldRepost(
        now,
        lastPostAt,
        db.repostInterval,
        db.autoRepost and true or false,
        db.mode,
        full
    )
    if not ok then
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
                    local fullMsg = tostring(db.fullAnnounceMessage or "LFM MS FULL — thanks!")
                    if fullMsg ~= "" and type(SendChatMessage) == "function" then
                        local ch = NormalizeChannel(db.postChannel)
                        if ch == "CHANNEL" then
                            local id = ResolveChannelIndex(db.postChannelName)
                            if id then
                                pcall(SendChatMessage, fullMsg, "CHANNEL", nil, id)
                            end
                        else
                            pcall(SendChatMessage, fullMsg, ch)
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
