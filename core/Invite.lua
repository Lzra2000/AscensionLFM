-- AscensionLFM: core/Invite.lua
-- Hosting auto-invite via InviteUnit; slots + party fullness + rate limits + ignore.

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
    if AscensionLFM.Print then
        local roleBit = role and (" as " .. role) or ""
        AscensionLFM.Print("invited " .. tostring(name) .. roleBit)
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshSlots then
        AscensionLFM.MainWindow.RefreshSlots()
    end
    return true
end

--- Hosting path: parse whisper for a role we accept + open slot, then invite.
function Invite.TryHostInvite(sender, message)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db or db.mode ~= "hosting" or not db.autoInvite then
        return false, "disabled"
    end
    local parsed = AscensionLFM.Parser.Parse(message)
    if not parsed then
        return false, "no parse"
    end
    local role = AscensionLFM.Parser.RequestedRole(parsed)
    if not role then
        if db.requireRoleWhisper ~= false then
            return false, "no role"
        end
        return false, "no role"
    end
    if not (db.roles and db.roles[role]) then
        return false, "role filtered"
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.HasOpenSlot then
        if not AscensionLFM.Slots.HasOpenSlot(role) then
            return false, "slot full"
        end
    end
    -- Soft Manastorm hint: accept pure role whispers while hosting MS runs
    local text = tostring(message or ""):lower()
    local msHint = text:find("ms", 1, true) or text:find("manastorm", 1, true)
        or text:find("inv", 1, true) or parsed.isRoleRequest or parsed.isManastormLFM
        or parsed.isManastormLFG
    if not msHint then
        local bare = text:match(
            "^%s*(tank[s]?|ot|mt|heal[ers]*|heals?|hps|dps|aura[s]?|dd|damage|aura%s+of%s+exp[%w]*|exp%s+aura|aoe%s+aura)%s*$"
        )
        if not bare then
            return false, "not ms-related"
        end
    end
    return Invite.InvitePlayer(sender, role)
end

Invite._CanInvite = CanInvite
Invite._ResetCooldowns = function()
    lastInviteAt = {}
    lastInviteGlobal = 0
end
