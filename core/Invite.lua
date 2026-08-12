-- AscensionLFM: core/Invite.lua
-- Hosting auto-invite via InviteUnit; slots + party fullness + rate limits + ignore.
-- On rejectable failures, optionally Reject.TryRewhisper; always queues applicants.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Invite = {}
AscensionLFM.Invite = Invite

-- Session memory: last assigned role per player (survives leave for re-inv).
local lastKnownRoles = {} -- [nameLower] = role

local lastInviteAt = {} -- [nameLower] = GetTime()
local lastInviteGlobal = 0
-- { sender=, message=, retryAt= } - cooldown-blocked applicants to retry
-- once the (global or per-name) invite cooldown has passed.
local pendingRetries = {}
local RETRY_STAGGER = 0.4
local MAX_RETRY_ATTEMPTS = 3

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

-- Once the host is actually inside the Manastorm instance, continuing to
-- auto-invite doesn't accomplish much - a fresh invite can't meaningfully
-- join a run already underway (they'd just sit outside waiting to be
-- summoned, if that's even possible). Both invite paths (direct whisper
-- and public LFG-chat scan) pause here by default; db.pauseInviteInInstance
-- lets a host explicitly opt back in if they genuinely want mid-run
-- whisper invites to keep working.
local function IsHostInsideInstance()
    if type(IsInInstance) ~= "function" then
        return false
    end
    local ok, inInstance = pcall(IsInInstance)
    return ok and inInstance and true or false
end

local function IsIgnoredName(name)
    if type(IsIgnored) == "function" then
        local ok, result = pcall(IsIgnored, name)
        if ok and result then
            return true
        end
    end
    return false
end

--- Current group size including the player.
function Invite.GetGroupSize()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        return raid
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    return (party or 0) + 1 -- party members exclude player
end

function Invite.IsGroupFull(maxSize)
    maxSize = tonumber(maxSize) or 15
    if maxSize < 2 then
        maxSize = 2
    end
    if maxSize > 40 then
        maxSize = 40
    end
    return Invite.GetGroupSize() >= maxSize
end

local function CanInvite(name, db)
    if type(name) ~= "string" or name == "" then
        return false, "bad name"
    end
    if IsIgnoredName(name) then
        return false, "ignored"
    end
    if Invite.IsGroupFull(db and db.maxPartySize) then
        return false, "full"
    end
    -- In raid, only leader/assist can invite; in party, leader. Soft-check.
    if type(IsPartyLeader) == "function" or type(IsRaidLeader) == "function" then
        local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
        if raid and raid > 0 then
            local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
            local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
            if not lead and not assist then
                return false, "not raid lead/assist"
            end
        else
            local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
            if party and party > 0 then
                if type(IsPartyLeader) == "function" and not IsPartyLeader() then
                    return false, "not party leader"
                end
            end
        end
    end
    local cd = tonumber(db and db.inviteCooldown) or 3
    local key = LowerName(name)
    local last = lastInviteAt[key]
    if last and (Now() - last) < cd then
        return false, "per-name cooldown"
    end
    if (Now() - lastInviteGlobal) < cd then
        return false, "global cooldown"
    end
    return true
end

local function PlayApplicantSound(db)
    if not db or not db.soundOnApplicant then
        return
    end
    if type(PlaySound) == "function" then
        pcall(PlaySound, "TellMessage")
    end
end

-- WoW caps a party at 5; inviting a 6th person while still a plain party
-- (not yet a raid) fails client-side even though the addon's own slot
-- tracking allows far more (slotMax defaults total up to 15). Auto-convert
-- right when the party is full and about to grow past it, so hosting
-- larger groups (the whole point of Manastorm-scale slotMax) doesn't hit
-- an invisible 5-person wall.
local function EnsureRaidIfNeeded()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid > 0 then
        return -- already a raid
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    if party >= 4 and type(ConvertToRaid) == "function" then
        pcall(ConvertToRaid)
    end
end

function Invite.RememberRole(name, role)
    if type(name) == "string" and name ~= "" and type(role) == "string" and role ~= "" then
        lastKnownRoles[LowerName(name)] = role
    end
end

function Invite.InvitePlayer(name, role)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local ok, reason = CanInvite(name, db)
    if not ok then
        return false, reason
    end
    if type(InviteUnit) ~= "function" then
        return false, "InviteUnit missing"
    end
    EnsureRaidIfNeeded()
    local success, err = pcall(InviteUnit, name)
    if not success then
        return false, tostring(err)
    end
    lastInviteAt[LowerName(name)] = Now()
    lastInviteGlobal = Now()
    if role and AscensionLFM.Slots and AscensionLFM.Slots.Assign then
        AscensionLFM.Slots.Assign(name, role)
    end
    if role then
        lastKnownRoles[LowerName(name)] = role
    end
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("invite", tostring(name) .. (role and (" as " .. role) or ""), {
            name = name,
            role = role,
        })
    end
    if AscensionLFM.Print then
        local roleBit = role and (" as " .. role) or ""
        AscensionLFM.Print("invited " .. tostring(name) .. roleBit)
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshSlots then
        AscensionLFM.MainWindow.RefreshSlots()
    end
    return true
end

-- "no role"/"no parse" means Parser found NO role-related content at all in
-- the message - that alone doesn't tell us whether this was a failed
-- application ("inv ms please" - clearly trying to apply, just forgot a
-- role, a clarifying reply is genuinely useful) or an unrelated whisper
-- (trade, a question, someone complaining) where an automatic "please
-- whisper a role" reply reads as a bizarre unprompted message and can
-- spiral (they reply confused, that reply also doesn't parse as a role,
-- triggers another auto-reply...). So for these two reasons specifically,
-- only auto-reply if the message itself has some minimal ms/invite signal.
-- Genuine detected-but-unfulfillable requests ("slot full"/"full"/
-- "role filtered") always get the automatic reply - a role WAS recognized
-- there, so we're already confident it was a real application. The host can
-- still manually Reject+whisper any queued entry regardless of reason.
local NO_AUTO_REJECT_REASONS = {
    ["no role"] = true,
    ["no parse"] = true,
}

local function LooksLikeApplicationAttempt(message)
    local text = tostring(message or ""):lower()
    if text:find("manastorm", 1, true) then
        return true
    end
    if text:find("%f[%w]ms%f[%W]") or text:find("%f[%w]ms$") or text:find("^ms%f[%W]") then
        return true
    end
    if text:find("inv", 1, true) then
        return true
    end
    return false
end

local function AfterHostResult(sender, message, role, ok, reason)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local status = ok and "invited" or "blocked"
    if AscensionLFM.Queue and AscensionLFM.Queue.Push then
        AscensionLFM.Queue.Push(sender, role, message, status, reason)
    end
    local skipAutoReject = NO_AUTO_REJECT_REASONS[tostring(reason or "")]
        and not LooksLikeApplicationAttempt(message)
    if not ok and not skipAutoReject and AscensionLFM.Reject and AscensionLFM.Reject.TryRewhisper then
        AscensionLFM.Reject.TryRewhisper(sender, reason, role)
    end
end

-- Moved above TryHostInvite (Lua locals aren't visible before their
-- declaration) so both TryHostInvite and TryLfgInvite can share the same
-- "save the last seats for support roles" policy - this used to only exist
-- in TryLfgInvite, so a whisper applicant asking for dps in the last 1-2
-- raid seats got auto-invited immediately while an LFG-chat dps applicant
-- in the exact same situation got held back. Same policy, same code path now.
local function FirstOpenHostRole(db, preferSupport)
    local order = { "tank", "healer", "aura", "dps" }
    if preferSupport then
        order = { "tank", "healer", "aura" }
    end
    for _, role in ipairs(order) do
        if db.roles and db.roles[role] then
            if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
                if AscensionLFM.Slots.HasOpenSlot(role) then
                    return role
                end
            else
                return role
            end
        end
    end
    return nil
end

local function SeatsLeft(db)
    local maxSize = tonumber(db and db.maxPartySize) or 15
    local size = Invite.GetGroupSize()
    return maxSize - size, maxSize, size
end

--- True when the applicant asked for DPS, only 1-2 raid seats remain, an
-- accepted support role still has room, AND a support applicant is already
-- waiting in the queue (otherwise empty seats were wasted while nobody was
-- actually applying as tank/heal/aura).
local function QueueHasPendingSupport()
    if not (AscensionLFM.Queue and AscensionLFM.Queue.Recent) then
        return false
    end
    local list = AscensionLFM.Queue.Recent(12) or {}
    for _, q in ipairs(list) do
        local st = tostring(q.status or "")
        if st == "pending" or st == "blocked" then
            local r = q.role
            if r == "tank" or r == "healer" or r == "aura" then
                return true
            end
            local lab = tostring(q.roleLabel or "")
            if lab:find("tank", 1, true) or lab:find("heal", 1, true) or lab:find("aura", 1, true) then
                return true
            end
        end
    end
    return false
end

local function ShouldPreferSupportOverDps(db, role)
    if role ~= "dps" then
        return false
    end
    local left = SeatsLeft(db)
    if left > 2 then
        return false
    end
    if not FirstOpenHostRole(db, true) then
        return false
    end
    return QueueHasPendingSupport()
end

-- Reported live: a busy hosting session has many applicants whispering
-- within the same few seconds; the per-name/global invite cooldown
-- (CanInvite, default 3s) then silently swallows a genuinely acceptable
-- role request - "global cooldown"/"per-name cooldown" are deliberately
-- NOT in Reject.REJECTABLE (a cooldown isn't a real rejection, replying
-- would be misleading), so the applicant got zero feedback and had to
-- notice nothing happened and re-whisper themselves. Auto-retry instead:
-- once the cooldown window has passed, re-attempt the exact same
-- application automatically.
local function ScheduleRetry(kind, sender, message, now, previousAttempts)
    local attempts = (tonumber(previousAttempts) or 0) + 1
    if attempts > MAX_RETRY_ATTEMPTS then
        if AscensionLFM.Print then
            AscensionLFM.Print("invite retry gave up for " .. tostring(sender) .. " after " .. MAX_RETRY_ATTEMPTS .. " attempts")
        end
        return false
    end

    -- CHAT_MSG events can be duplicated before the first retry executes.
    -- Keep one deferred attempt per applicant/path to prevent double invites
    -- and an ever-growing retry queue.
    local key = LowerName(sender)
    for _, pending in ipairs(pendingRetries) do
        if pending.kind == kind and LowerName(pending.sender) == key then
            return false
        end
    end
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local cd = tonumber(db and db.inviteCooldown) or 3
    -- Stagger multiple queued retries so a burst of cooldown-blocked
    -- applicants doesn't all re-trigger the global cooldown simultaneously
    -- again on retry.
    local retryAt = now + cd + 0.2
    for _, p in ipairs(pendingRetries) do
        if p.retryAt >= retryAt then
            retryAt = p.retryAt + RETRY_STAGGER
        end
    end
    table.insert(pendingRetries, {
        kind = kind,
        sender = sender,
        message = message,
        retryAt = retryAt,
        attempts = attempts,
    })
    return true
end

--- Hosting path: parse whisper for a role we accept + open slot, then invite.
function Invite.TryHostInvite(sender, message, retryAttempts)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" then
        return false, "disabled"
    end
    if AscensionLFM.Kick and AscensionLFM.Kick.IsSessionIgnored
        and AscensionLFM.Kick.IsSessionIgnored(sender) then
        if AscensionLFM.Queue and AscensionLFM.Queue.Push then
            AscensionLFM.Queue.Push(sender, nil, message, "blocked", "session ignore (kicked 59)")
        end
        return false, "session ignore"
    end
    -- Queue + sound even when auto-invite is off (manual Queue actions)
    local parsed = AscensionLFM.Parser.Parse(message)
    local role = parsed and AscensionLFM.Parser.RequestedRole(parsed) or nil
    if not role and AscensionLFM.Parser.GuessRole then
        role = AscensionLFM.Parser.GuessRole(message)
    end

    PlayApplicantSound(db)

    if not db.autoInvite then
        if AscensionLFM.Queue and AscensionLFM.Queue.Push then
            AscensionLFM.Queue.Push(sender, role, message, "pending", "auto-invite off")
        end
        return false, "disabled"
    end
    if db.pauseInviteInInstance ~= false and IsHostInsideInstance() then
        if AscensionLFM.Queue and AscensionLFM.Queue.Push then
            AscensionLFM.Queue.Push(sender, role, message, "pending", "host in instance")
        end
        return false, "in instance"
    end

    -- Bare re-inv / inv with no role: reuse last known role from this session
    -- (player left and wants back in without re-stating the role).
    if not role then
        local bare = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        bare = bare:gsub("[!%?%.%,%;%:]+$", "")
        if bare == "inv" or bare == "invite" or bare == "re-inv" or bare == "reinv"
            or bare == "re inv" or bare == "inv me" or bare == "invite me" then
            local remembered = lastKnownRoles[LowerName(sender)]
            if remembered then
                role = remembered
            end
        end
    end

    if not role then
        local why = parsed and "no role" or "no parse"
        if db.requireRoleWhisper ~= false then
            AfterHostResult(sender, message, nil, false, why)
            return false, why
        end
        AfterHostResult(sender, message, nil, false, why)
        return false, why
    end
    -- Last 1-2 seats: do not burn them on DPS while tank/heal/aura still
    -- open - same policy TryLfgInvite already applies to LFG-chat applicants.
    if ShouldPreferSupportOverDps(db, role) then
        AfterHostResult(sender, message, role, false, "prefer support seat")
        return false, "prefer support seat"
    end
    if not (db.roles and db.roles[role]) then
        AfterHostResult(sender, message, role, false, "role filtered")
        return false, "role filtered"
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
        if not AscensionLFM.Slots.HasOpenSlot(role) then
            -- Dual-role fallback: "dps with aura" / "got aura dps" when DPS is
            -- full but an offered support role still has a seat.
            local alt = nil
            local offered = AscensionLFM.Parser and AscensionLFM.Parser.OfferedRoles
                and AscensionLFM.Parser.OfferedRoles(message) or {}
            for _, r in ipairs({ "tank", "healer", "aura", "dps" }) do
                if r ~= role and offered[r] and db.roles and db.roles[r]
                    and AscensionLFM.Slots.HasOpenSlot(r) then
                    alt = r
                    break
                end
            end
            if alt then
                if AscensionLFM.Print then
                    AscensionLFM.Print(string.format(
                        "%s: %s full - inviting as %s (also offered)",
                        tostring(sender), role, alt))
                end
                role = alt
            else
                AfterHostResult(sender, message, role, false, "slot full")
                return false, "slot full"
            end
        end
    end
    -- NOTE: this used to compute a "msHint" (ms/manastorm/inv keywords, or
    -- isRoleRequest, or a resolved role) and reject when none of that held.
    -- But `role` is already guaranteed non-nil at this point (we returned
    -- above whenever role == nil), so "or role ~= nil" made the check always
    -- true and the "not ms-related" branch was unreachable dead code.
    -- Actually enforcing that filter would reject plain role whispers like
    -- "tank" that don't mention ms/manastorm/inv, which is the accepted,
    -- tested hosting flow (a private reply to your LFM) - so the correct fix
    -- is to drop the dead gate rather than start enforcing it. Any recognized
    -- role is accepted here, matching the behavior this always actually had.
    local ok, reason = Invite.InvitePlayer(sender, role)
    AfterHostResult(sender, message, role, ok, reason)
    if not ok and (reason == "global cooldown" or reason == "per-name cooldown") then
        ScheduleRetry("whisper", sender, message, Now(), retryAttempts)
    end
    return ok, reason
end

local function FirstOpenAcceptedRole(db, parsed)
    local order = { "tank", "healer", "aura", "dps" }
    for _, role in ipairs(order) do
        if db.roles and db.roles[role] then
            local info = parsed and parsed.roles and parsed.roles[role]
            local mentioned = info and (info.mentioned or info.open)
            if mentioned then
                if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
                    if AscensionLFM.Slots.HasOpenSlot(role) then
                        return role
                    end
                else
                    return role
                end
            end
        end
    end
    return nil
end

--- Hosting: public LFG MS poster -> InviteUnit if role matches an open accepted slot.
function Invite.TryLfgInvite(leader, message, parsed, retryAttempts)
    if AscensionLFM.Kick and AscensionLFM.Kick.IsSessionIgnored
        and AscensionLFM.Kick.IsSessionIgnored(leader) then
        return false, "session ignore"
    end
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" then
        return false, "disabled"
    end
    if not db.autoInvite or db.autoInviteLfg == false then
        return false, "lfg invite off"
    end
    -- Public LFG-chat scan reaches out to whoever posted "LFG MS ..." even
    -- though they never whispered/applied to YOU specifically - that's fine
    -- while actively recruiting in the open world, but once you're already
    -- inside your own Manastorm instance, General/Trade chat still relays
    -- OTHER unrelated players' own "LFG MS" posts (for entirely different
    -- groups) and this used to auto-reply to them ("Sorry, tank is full")
    -- as if they had applied to you - confusing strangers who never
    -- whispered you at all.
    -- Direct whispers (TryHostInvite) pause here too now, by the same
    -- db.pauseInviteInInstance toggle - a fresh invite while deep inside a
    -- run already underway can't meaningfully be joined anyway.
    if db.pauseInviteInInstance ~= false and IsHostInsideInstance() then
        return false, "in instance"
    end
    if type(leader) ~= "string" or leader == "" then
        return false, "bad name"
    end
    parsed = parsed or (AscensionLFM.Parser and AscensionLFM.Parser.Parse and AscensionLFM.Parser.Parse(message))
    -- GuessRole fallback when Parse misses glued tags / odd phrasing
    if not parsed or not parsed.isManastormLFG then
        local text = tostring(message or ""):lower()
        local looksLfg = text:find("lfg", 1, true) or text:find("looking for group", 1, true)
        local looksMs = text:find("manastorm", 1, true) or text:find("%f[%w]ms%f[%W]")
            or text:find("%f[%w]ms%d") or text:find("%f[%w]ms$")
        local guess = AscensionLFM.Parser and AscensionLFM.Parser.GuessRole
            and AscensionLFM.Parser.GuessRole(message)
        if looksLfg and looksMs and guess then
            parsed = {
                isManastormLFG = true,
                isManastormLFM = false,
                isManastormListing = true,
                listingKind = "lfg",
                roles = {
                    [guess] = { open = true, mentioned = true },
                },
                genericNeed = false,
                summary = tostring(message or ""),
                raw = tostring(message or ""),
            }
        else
            return false, "not lfg"
        end
    end
    -- Pure LFM hosts are not LFG seekers
    if parsed.isManastormLFM and not parsed.isManastormLFG then
        return false, "not lfg"
    end

    local role = AscensionLFM.Parser and AscensionLFM.Parser.RequestedRole and AscensionLFM.Parser.RequestedRole(parsed)
    if parsed.genericNeed and not db.lfgInviteWithoutRole then
        role = nil
    elseif not role then
        role = FirstOpenAcceptedRole(db, parsed)
    end
    if not role then
        if db.lfgInviteWithoutRole then
            role = FirstOpenHostRole(db, false)
        end
    end
    if not role then
        local guess = AscensionLFM.Parser and AscensionLFM.Parser.GuessRole
            and AscensionLFM.Parser.GuessRole(message)
        if guess then
            role = guess
        end
    end
    if not role then
        if AscensionLFM.Queue and AscensionLFM.Queue.Push then
            AscensionLFM.Queue.Push(leader, nil, message, "blocked", "no role")
        end
        return false, "no role"
    end

    -- Last 1-2 seats: do not burn them on DPS while tank/heal/aura still open
    -- (shared with TryHostInvite via ShouldPreferSupportOverDps)
    if ShouldPreferSupportOverDps(db, role) then
        AfterHostResult(leader, message, role, false, "prefer support seat")
        return false, "prefer support seat"
    end

    if not (db.roles and db.roles[role]) then
        AfterHostResult(leader, message, role, false, "role filtered")
        return false, "role filtered"
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
        if not AscensionLFM.Slots.HasOpenSlot(role) then
            local alt = nil
            local offered = AscensionLFM.Parser and AscensionLFM.Parser.OfferedRoles
                and AscensionLFM.Parser.OfferedRoles(message) or {}
            for _, r in ipairs({ "tank", "healer", "aura", "dps" }) do
                if r ~= role and offered[r] and db.roles and db.roles[r]
                    and AscensionLFM.Slots.HasOpenSlot(r) then
                    alt = r
                    break
                end
            end
            if alt then
                role = alt
            else
                AfterHostResult(leader, message, role, false, "slot full")
                return false, "slot full"
            end
        end
    end

    PlayApplicantSound(db)
    local ok, reason = Invite.InvitePlayer(leader, role)
    AfterHostResult(leader, message, role, ok, reason)
    if not ok and (reason == "global cooldown" or reason == "per-name cooldown") then
        ScheduleRetry("lfg", leader, message, Now(), retryAttempts)
    end
    if ok and AscensionLFM.Print then
        AscensionLFM.Print("LFG auto-invite " .. tostring(leader) .. " as " .. role)
    end
    return ok, reason
end

Invite._CanInvite = CanInvite
Invite._FirstOpenAcceptedRole = FirstOpenAcceptedRole
Invite._ResetCooldowns = function()
    lastInviteAt = {}
    lastInviteGlobal = 0
end

--- Process due cooldown-retry applicants. Processes all whose retryAt has
-- passed (they're already time-staggered by ScheduleRetry, so normally at
-- most one is due per tick); each retried call re-runs the full
-- TryHostInvite/TryLfgInvite logic, so a still-cooling-down retry simply
-- re-queues itself again rather than looping.
-- @return number processed this call
function Invite.Tick(now)
    now = tonumber(now) or Now()
    local processed = 0
    local i = 1
    while i <= #pendingRetries do
        local p = pendingRetries[i]
        if now >= (tonumber(p.retryAt) or 0) then
            table.remove(pendingRetries, i)
            if p.kind == "lfg" then
                Invite.TryLfgInvite(p.sender, p.message, nil, p.attempts)
            else
                Invite.TryHostInvite(p.sender, p.message, p.attempts)
            end
            processed = processed + 1
        else
            i = i + 1
        end
    end
    return processed
end

local frame
local lastTickAt = 0

--- Start the retry ticker. Safe to call multiple times (no-ops after first).
function Invite.Start()
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
        Invite.Tick(Now())
    end)
end

function Invite._GetPendingRetries()
    return pendingRetries
end

function Invite._ResetForTests()
    lastInviteAt = {}
    lastInviteGlobal = 0
    pendingRetries = {}
    lastKnownRoles = {}
    lastTickAt = 0
end
