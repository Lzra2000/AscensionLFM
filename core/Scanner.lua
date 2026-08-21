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
local followUpSent = {} -- [leaderLower] = last automated follow-up reply

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

local ROSTER_EVENTS = {
    "PARTY_MEMBERS_CHANGED",
    "RAID_ROSTER_UPDATE",
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
    local bits = { tostring(parsed.listingKind or "") }
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
    recent[LowerName(leader)] = {
        t = Now(),
        fingerprint = Fingerprint(parsed),
        -- Kept for PARTY_INVITE_REQUEST context (see HandleInviteRequest) -
        -- lets a seeker see which LFM/LFG line an incoming invite traces
        -- back to, instead of just an unexplained group invite popup.
        summary = parsed and parsed.summary,
        isLFM = parsed and parsed.isManastormLFM and true or false,
    }
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

local function IsListing(parsed)
    return parsed and (parsed.isManastormLFM or parsed.isManastormLFG or parsed.isManastormListing)
end

local function PlayMatchSound(db)
    if not db or not db.soundOnMatch then
        return
    end
    if type(PlaySound) == "function" then
        pcall(PlaySound, "RaidWarning")
    end
end

local function NextWhisperMessage(db, preferredRole)
    preferredRole = tostring(preferredRole or "tank")
    if db.useWhisperVariants ~= false and type(db.whisperVariants) == "table" and #db.whisperVariants > 0 then
        local idx = tonumber(db.whisperVariantIndex) or 1
        if idx < 1 then idx = 1 end
        if idx > #db.whisperVariants then idx = 1 end
        local tmpl = tostring(db.whisperVariants[idx] or "")
        db.whisperVariantIndex = (idx % #db.whisperVariants) + 1
        if tmpl ~= "" then
            return (tmpl:gsub("{role}", preferredRole)):sub(1, 120)
        end
    end
    local msg = tostring(db.whisperMessage or "inv ms"):sub(1, 120)
    if msg:find("{role}", 1, true) then
        msg = msg:gsub("{role}", preferredRole)
    end
    return msg
end

local function PreferredSeekRole(parsed, roles)
    if AscensionLFM.Parser and AscensionLFM.Parser.NeededRoles then
        local needed = AscensionLFM.Parser.NeededRoles(parsed, roles)
        if type(needed) == "table" then
            for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
                if needed[role] then
                    return role
                end
            end
        end
    end
    for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        if roles and roles[role] then
            return role
        end
    end
    return "tank"
end

local function NotifyMatch(leader, parsed, source)
    local kind = parsed.isManastormLFG and "LFG" or "LFM"
    local line = string.format("%s - %s (%s)", tostring(leader), parsed.summary or ("MS " .. kind), source)
    if AscensionLFM.Print then
        AscensionLFM.Print(line)
    end
    if AscensionLFM.LfmChatTab and AscensionLFM.LfmChatTab.Post then
        AscensionLFM.LfmChatTab.Post(line)
    end
    if AscensionLFM.Database and AscensionLFM.Database.PushMatch then
        AscensionLFM.Database.PushMatch({
            leader = leader,
            text = parsed.raw or parsed.summary,
            summary = parsed.summary,
            source = source,
            kind = parsed.listingKind or (parsed.isManastormLFG and "lfg" or "lfm"),
            -- Kept so the Log tab can highlight entries that still need
            -- one of the player's own configured roles (MainWindow.
            -- RefreshMatches -> Parser.NeedsAnyRole), instead of every
            -- entry looking equally relevant in a flat chronological list.
            roles = parsed.roles,
            t = time and time() or 0,
        })
    end
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        local kind = parsed.isManastormLFG and "LFG" or "LFM"
        AscensionLFM.Activity.Push("match", string.format("%s - %s (%s)", tostring(leader), parsed.summary or ("MS " .. kind), source), { name = leader })
    end
    PlayMatchSound(db)
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshMatches then
        AscensionLFM.MainWindow.RefreshMatches()
    end
end

local function MaybeAutoWhisper(leader, parsed, db)
    if not db.autoWhisper then
        return
    end
    -- Auto-whisper leaders of LFM listings; LFG seekers are not hosts
    if parsed.isManastormLFG and not parsed.isManastormLFM then
        return
    end
    if type(SendChatMessage) ~= "function" then
        return
    end
    if IsIgnoredName(leader) then
        return
    end
    if AscensionLFM.Database and AscensionLFM.Database.IsLeaderBlacklisted
        and AscensionLFM.Database.IsLeaderBlacklisted(leader) then
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
    local role = PreferredSeekRole(parsed, db.roles)
    local msg = NextWhisperMessage(db, role)
    if msg == "" then
        return
    end
    pcall(SendChatMessage, msg, "WHISPER", nil, leader)
    whisperSent[key] = Now()
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("match", "whispered " .. tostring(leader) .. ": " .. msg, {
            name = leader, role = role,
        })
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("whispered " .. tostring(leader) .. ": " .. msg)
    end
end

local function ShouldNotify(db, parsed, leader)
    if leader and AscensionLFM.Database and AscensionLFM.Database.IsLeaderBlacklisted
        and AscensionLFM.Database.IsLeaderBlacklisted(leader) and db.mode == "seeking" then
        return false
    end
    if parsed.isManastormLFG and db.scanLfg == false then
        return false
    end
    if db.mode == "hosting" then
        -- Hosting: LFG noise only when we still need that role
        if parsed.isManastormLFG and not parsed.isManastormLFM then
            local role = AscensionLFM.Parser and AscensionLFM.Parser.RequestedRole
                and AscensionLFM.Parser.RequestedRole(parsed)
            if role and AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
                local accepted = db.roles and db.roles[role]
                return (accepted and AscensionLFM.Slots.HasOpenSlot(role)) and true or false
            end
            -- Generic / ambiguous LFG: notify only if any accepted role has room
            if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot and db.roles then
                for _, r in ipairs({ "tank", "healer", "aura", "dps" }) do
                    if db.roles[r] and AscensionLFM.Slots.HasOpenSlot(r) then
                        return true
                    end
                end
                return false
            end
        end
        return true
    end
    if db.mode == "notify" then
        return true
    end
    if db.mode == "seeking" then
        -- LFG: notify seekers of other seekers only if scanLfg; role filter soft
        if parsed.isManastormLFG and not parsed.isManastormLFM then
            return db.scanLfg ~= false
        end
        return AscensionLFM.Parser.NeedsAnyRole(parsed, db.roles)
    end
    return false
end

local function HandlePublicListing(leader, message, event)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode == "off" then
        return
    end
    local parsed = AscensionLFM.Parser.Parse(message)
    if not IsListing(parsed) then
        return
    end
    if parsed.isManastormLFG and not parsed.isManastormLFM and db.scanLfg == false then
        return
    end
    -- Keystone filter only applies to posts that explicitly carry a
    -- "[Dungeon +N]" tag - most Manastorm LFM/LFG posts have no keystone
    -- content at all, and hiding those too would gut the addon's core
    -- function for the majority of hosts who never use the M+ tag.
    local minKs = tonumber(db.minKeystoneLevel) or 0
    if minKs > 0 and AscensionLFM.Parser.ExtractKeystoneLevel then
        local ksLevel = AscensionLFM.Parser.ExtractKeystoneLevel(message)
        if ksLevel and ksLevel < minKs then
            return
        end
    end
    local window = tonumber(db.dedupeSeconds) or 45
    if IsDupe(leader, parsed, window) then
        return
    end
    Remember(leader, parsed)

    if ShouldNotify(db, parsed, leader) then
        NotifyMatch(leader, parsed, SourceLabel(event))
    end

    if db.mode == "seeking" and parsed.isManastormLFM and AscensionLFM.Parser.NeedsAnyRole(parsed, db.roles) then
        MaybeAutoWhisper(leader, parsed, db)
    end

    -- Hosting: auto-invite players who post LFG MS (looking for a group)
    if db.mode == "hosting" and parsed.isManastormLFG and AscensionLFM.Invite and AscensionLFM.Invite.TryLfgInvite then
        AscensionLFM.Invite.TryLfgInvite(leader, message, parsed)
    end
end

-- Group-chat classification for role-check-reply routing. RAID_WARNING was
-- checked here before but never registered in CHAT_EVENTS (players can't
-- reply "in raid warning" - that channel is a one-way leader/assist
-- broadcast) so the check was unreachable dead code; dropped for clarity.
local function IsGroupChatEvent(event)
    return event == "CHAT_MSG_PARTY"
        or event == "CHAT_MSG_PARTY_LEADER"
        or event == "CHAT_MSG_RAID"
        or event == "CHAT_MSG_RAID_LEADER"
end

local function TryRoleCheckReply(sender, message)
    if not AscensionLFM.RoleCheck then
        return false
    end
    if not AscensionLFM.RoleCheck.IsActive or not AscensionLFM.RoleCheck.IsActive() then
        return false
    end
    local fn = AscensionLFM.RoleCheck.HandleRoleReply or AscensionLFM.RoleCheck.OnWhisper
    if type(fn) ~= "function" then
        return false
    end
    return fn(sender, message) and true or false
end

-- Fallback for when no formal Role Check is active (or it didn't match):
-- passively catch exact bare-word role replies ("heal", "tank", "dps",
-- "aura") in party/raid chat while hosting. Deliberately exact-only via
-- RoleCheck.ParseBareRoleWord - see its comment for why.
local function TryPassiveGroupRoleReply(sender, message)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" then
        return false
    end
    if db.passiveRoleDetect == false then
        return false
    end
    if not AscensionLFM.RoleCheck or not AscensionLFM.RoleCheck.HandlePassiveGroupChat then
        return false
    end
    return AscensionLFM.RoleCheck.HandlePassiveGroupChat(sender, message) and true or false
end

local function PrimarySeekRoleExcludingAura(roles)
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        if roles and roles[role] then
            return role
        end
    end
    return "dps" -- no clear primary configured; still answer rather than stay silent
end

-- Follow-up replies from a host's OWN registration bot (e.g. "What level
-- are you?", "Please whisper your role and aura as: Tank/Heal/DPS + Aura
-- yes/no.") after we already whispered them via MaybeAutoWhisper. Level is
-- unambiguous (always just a number). Role/aura phrasing varies a lot
-- between different hosts' bots, so this is inherently best-effort - it
-- mirrors the "{role} + aura yes/no" convention from Hasan's own manual
-- replies, not a universal standard.
local FOLLOWUP_WINDOW = 300 -- 5 min: only reply to hosts we recently applied to
local FOLLOWUP_COOLDOWN = 3 -- prevent a chatty bot from causing whisper spam

local function DetectFollowUpKind(text)
    local lower = tostring(text or ""):lower()
    -- Require the message to actually look like a question/request, not a
    -- status update - e.g. a bot's own confirmation "Registered as DPS -
    -- Aura: Yes. Waiting for invite." contains "aura" as a whole word too,
    -- and without this gate we'd fire ANOTHER unsolicited reply to that,
    -- right back at the bot that just confirmed us.
    local looksLikeQuestion = lower:find("?", 1, true) ~= nil
        or lower:find("%f[%w]please%f[%W]") ~= nil
    if not looksLikeQuestion then
        return nil
    end
    local hasLevel = lower:find("%f[%w]level%f[%W]") ~= nil
    local hasRole = lower:find("%f[%w]role%f[%W]") ~= nil
    local hasAura = lower:find("%f[%w]aura%f[%W]") ~= nil
    if hasLevel then
        return "level"
    end
    if hasRole and hasAura then
        return "role_aura"
    end
    if hasRole then
        return "role"
    end
    if hasAura then
        return "aura"
    end
    return nil
end

local function BuildFollowUpReply(kind, db)
    if kind == "level" then
        local lvl = type(UnitLevel) == "function" and tonumber(UnitLevel("player")) or nil
        if not lvl or lvl <= 0 then
            return nil
        end
        return tostring(lvl)
    end
    local roles = (db and db.roles) or {}
    local primary = PrimarySeekRoleExcludingAura(roles)
    local label = primary == "tank" and "tank" or primary == "healer" and "heal" or "dps"
    local auraYes = roles.aura and true or false
    if kind == "role_aura" then
        return string.format("%s + aura %s", label, auraYes and "yes" or "no")
    elseif kind == "role" then
        return label
    elseif kind == "aura" then
        return auraYes and "aura yes" or "aura no"
    end
    return nil
end

local function TryFollowUpReply(sender, message, db)
    if not db.autoWhisper then
        return false
    end
    if type(SendChatMessage) ~= "function" then
        return false
    end
    local key = LowerName(sender)
    local last = whisperSent[key]
    if not last or (Now() - last) > FOLLOWUP_WINDOW then
        return false -- never applied to this host, or too long ago - don't guess
    end
    local lastFollowUp = followUpSent[key]
    if lastFollowUp and (Now() - lastFollowUp) < FOLLOWUP_COOLDOWN then
        return false
    end
    local kind = DetectFollowUpKind(message)
    if not kind then
        return false
    end
    local reply = BuildFollowUpReply(kind, db)
    if not reply or reply == "" then
        return false
    end
    pcall(SendChatMessage, reply, "WHISPER", nil, sender)
    followUpSent[key] = Now()
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("match",
            string.format("auto-replied %s (%s): %s", tostring(sender), kind, reply),
            { name = sender })
    end
    return true
end

local function HandleWhisper(sender, message)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        return
    end

    if db.mode == "notify" or db.mode == "seeking" then
        local parsed = AscensionLFM.Parser.Parse(message)
        if IsListing(parsed) then
            if parsed.isManastormLFG and not parsed.isManastormLFM and db.scanLfg == false then
                return
            end
            local window = tonumber(db.dedupeSeconds) or 45
            if not IsDupe(sender, parsed, window) then
                Remember(sender, parsed)
                if ShouldNotify(db, parsed, sender) then
                    NotifyMatch(sender, parsed, "whisper")
                end
                if db.mode == "seeking" and parsed.isManastormLFM then
                    MaybeAutoWhisper(sender, parsed, db)
                end
            end
            return
        end
        if db.mode == "seeking" then
            TryFollowUpReply(sender, message, db)
        end
    end

    if db.mode == "hosting" then
        -- Role Check consumes whispers only from current group members.
        -- Outside applicants must still reach auto-invite / Queue.
        local consumed = TryRoleCheckReply(sender, message)
        if not consumed and AscensionLFM.Invite and AscensionLFM.Invite.TryHostInvite then
            AscensionLFM.Invite.TryHostInvite(sender, message)
        end
    end
end

local function HandleRoster()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    -- Snapshot names BEFORE ScanRaid/SyncFromRoster drops leavers from assignedRoles.
    if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.RememberPresent then
        AscensionLFM.MiniHUD.RememberPresent()
    end
    local hostingOrPosting = db and (db.mode == "hosting" or db.autoRepost or db.fullAutoHosting)
    if hostingOrPosting and AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
        AscensionLFM.Slots.ScanRaid()
    elseif AscensionLFM.Slots and AscensionLFM.Slots.SyncFromRoster then
        AscensionLFM.Slots.SyncFromRoster()
        -- Deliberately does NOT auto-trigger AuraBalance here anymore -
        -- this handler runs off a roster-update event, where
        -- SetRaidSubgroup is not allowed to fire (see Slots.Assign's
        -- comment). Group sorting is now the host-triggered "Sort Groups"
        -- button.
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshSlots then
            AscensionLFM.MainWindow.RefreshSlots()
        end
    end
    if AscensionLFM.Poster and AscensionLFM.Poster.OnRosterChanged then
        AscensionLFM.Poster.OnRosterChanged()
    end
end

-- How long a seen LFM/LFG listing stays "recent" enough to explain/accept
-- an incoming invite from that same leader (10 min - long enough to cover
-- the walk-to-instance/whisper-back-and-forth delay, short enough that an
-- invite from someone whose post you saw an hour ago still gets no context).
local INVITE_CONTEXT_WINDOW = 600

-- db.autoAcceptInvite existed as a saved setting since early versions but
-- was never actually wired to anything - no PARTY_INVITE_REQUEST handler
-- existed at all. Deliberately scoped narrower than "accept every invite
-- that arrives": only auto-accepts (and only ever shows context for) an
-- invite from someone whose LFM/LFG post was actually seen recently, via
-- the same `recent` table NotifyMatch/Remember already populate - a bare
-- "accept anything" toggle would be reckless for a seeking-mode player to
-- leave on.
local function HandleInviteRequest(inviter)
    if type(inviter) ~= "string" or inviter == "" then
        return
    end
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        return
    end
    local entry = recent[LowerName(inviter)]
    if not entry or (Now() - (entry.t or 0)) > INVITE_CONTEXT_WINDOW then
        return
    end
    if AscensionLFM.Print and entry.summary then
        AscensionLFM.Print("Invite from " .. tostring(inviter) .. " - they posted: " .. tostring(entry.summary))
    end
    if db.mode == "seeking" and db.autoAcceptInvite and entry.isLFM
        and type(_G.AcceptGroup) == "function" then
        pcall(_G.AcceptGroup)
        if AscensionLFM.Print then
            AscensionLFM.Print("auto-accepted invite from " .. tostring(inviter))
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
    for _, ev in ipairs(ROSTER_EVENTS) do
        frame:RegisterEvent(ev)
    end
    frame:RegisterEvent("PARTY_INVITE_REQUEST")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    frame:SetScript("OnEvent", function(_, event, message, sender)
        if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
            HandleRoster()
            return
        end
        if event == "PARTY_INVITE_REQUEST" then
            -- This event's own 2nd arg is the inviter's name, not a chat
            -- message - `message` here IS that name (only the dispatcher's
            -- shared parameter names are chat-shaped, not this event).
            HandleInviteRequest(message)
            return
        end
        if event == "CHAT_MSG_SYSTEM" then
            -- No `sender` for system messages - "X declines your group
            -- invitation.", "Cannot find player 'X'.", etc. Lets a failed
            -- invite free its slot immediately instead of waiting out
            -- Invite.lua's 5s verify-delay fallback.
            if AscensionLFM.Invite and AscensionLFM.Invite.HandleSystemMessage then
                AscensionLFM.Invite.HandleSystemMessage(message)
            end
            return
        end
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
            -- During Role Check, party/raid chat role replies count too
            -- (players often answer the RW in party instead of whispering).
            if IsGroupChatEvent(event) then
                if TryRoleCheckReply(sender, message) then
                    return
                end
                if TryPassiveGroupRoleReply(sender, message) then
                    return
                end
            end
            HandlePublicListing(sender, message, event)
        end
    end)
    if AscensionLFM.Kick and AscensionLFM.Kick.Start then
        AscensionLFM.Kick.Start()
    end
end

function Scanner.GetRecent()
    return recent
end

Scanner._HandlePublicLFM = HandlePublicListing
Scanner._HandlePublicListing = HandlePublicListing
Scanner._HandleWhisper = HandleWhisper
Scanner._TryRoleCheckReply = TryRoleCheckReply
Scanner._TryPassiveGroupRoleReply = TryPassiveGroupRoleReply
Scanner._IsGroupChatEvent = IsGroupChatEvent
Scanner._Fingerprint = Fingerprint
Scanner._NextWhisperMessage = NextWhisperMessage
Scanner._PreferredSeekRole = PreferredSeekRole
Scanner._HandleInviteRequest = HandleInviteRequest
