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

local lastInviteAt = {} -- [nameLower] = GetTime()
local lastInviteGlobal = 0

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
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

function Invite.InvitePlayer(name, role)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local ok, reason = CanInvite(name, db)
    if not ok then
        return false, reason
    end
    if type(InviteUnit) ~= "function" then
        return false, "InviteUnit missing"
    end
    local success, err = pcall(InviteUnit, name)
    if not success then
        return false, tostring(err)
    end
    lastInviteAt[LowerName(name)] = Now()
    lastInviteGlobal = Now()
    if role and AscensionLFM.Slots and AscensionLFM.Slots.Assign then
        AscensionLFM.Slots.Assign(name, role)
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

local function AfterHostResult(sender, message, role, ok, reason)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local status = ok and "invited" or "blocked"
    if AscensionLFM.Queue and AscensionLFM.Queue.Push then
        AscensionLFM.Queue.Push(sender, role, message, status, reason)
    end
    if not ok and AscensionLFM.Reject and AscensionLFM.Reject.TryRewhisper then
        AscensionLFM.Reject.TryRewhisper(sender, reason, role)
    end
end

-- Moved above TryHostInvite (Lua locals aren't visible before their
-- declaration) so both TryHostInvite and TryLfgInvite can share the same
-- "save the last seats for support roles" policy — this used to only exist
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

--- True when the applicant asked for DPS, only 1-2 raid seats remain, and an
-- accepted support role (tank/heal/aura) still has room — in that case the
-- seat should be held for support rather than burned on another DPS.
local function ShouldPreferSupportOverDps(db, role)
    if role ~= "dps" then
        return false
    end
    local left = SeatsLeft(db)
    if left > 2 then
        return false
    end
    return FirstOpenHostRole(db, true) ~= nil
end

--- Hosting path: parse whisper for a role we accept + open slot, then invite.
function Invite.TryHostInvite(sender, message)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" then
        return false, "disabled"
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

    if not role then
        local why = parsed and "no role" or "no parse"
        if db.requireRoleWhisper ~= false then
            AfterHostResult(sender, message, nil, false, why)
            return false, why
        end
        AfterHostResult(sender, message, nil, false, why)
        return false, why
    end
    -- Last 1–2 seats: do not burn them on DPS while tank/heal/aura still
    -- open — same policy TryLfgInvite already applies to LFG-chat applicants.
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
            AfterHostResult(sender, message, role, false, "slot full")
            return false, "slot full"
        end
    end
    -- NOTE: this used to compute a "msHint" (ms/manastorm/inv keywords, or
    -- isRoleRequest, or a resolved role) and reject when none of that held.
    -- But `role` is already guaranteed non-nil at this point (we returned
    -- above whenever role == nil), so "or role ~= nil" made the check always
    -- true and the "not ms-related" branch was unreachable dead code.
    -- Actually enforcing that filter would reject plain role whispers like
    -- "tank" that don't mention ms/manastorm/inv, which is the accepted,
    -- tested hosting flow (a private reply to your LFM) — so the correct fix
    -- is to drop the dead gate rather than start enforcing it. Any recognized
    -- role is accepted here, matching the behavior this always actually had.
    local ok, reason = Invite.InvitePlayer(sender, role)
    AfterHostResult(sender, message, role, ok, reason)
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

--- Hosting: public LFG MS poster → InviteUnit if role matches an open accepted slot.
function Invite.TryLfgInvite(leader, message, parsed)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" then
        return false, "disabled"
    end
    if not db.autoInvite or db.autoInviteLfg == false then
        return false, "lfg invite off"
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

    -- Last 1–2 seats: do not burn them on DPS while tank/heal/aura still open
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
            AfterHostResult(leader, message, role, false, "slot full")
            return false, "slot full"
        end
    end

    PlayApplicantSound(db)
    local ok, reason = Invite.InvitePlayer(leader, role)
    AfterHostResult(leader, message, role, ok, reason)
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
