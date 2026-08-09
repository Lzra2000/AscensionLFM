-- AscensionLFM: core/Parser.lua
-- Pure Lua 5.1 Manastorm LFM line parser (no WoW APIs).
-- Detects LFM + Manastorm/MS and extracts role slot counts when present.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Parser = {}
AscensionLFM.Parser = Parser

local ROLE_PATTERNS = {
    tank = { "tanks?", "tn?ks?" },
    healer = { "healers?", "heals?", "heal" },
    aura = { "auras?", "aura" },
    dps = { "dps", "dd", "damage" },
}

local function Lower(s)
    return tostring(s or ""):lower()
end

local function HasLFM(text)
    -- LFM / LF#M / "looking for more" / "need" with group context handled loosely
    if text:find("lfm", 1, true) then
        return true
    end
    if text:find("looking for more", 1, true) then
        return true
    end
    -- LF2M / LF3M style
    if text:find("lf%d+m") then
        return true
    end
    return false
end

local function HasManastorm(text)
    if text:find("manastorm", 1, true) then
        return true
    end
    -- Word-boundary-ish MS (avoid matching "dms", "msg", etc.)
    if text:find("%f[%w]ms%f[%W]") or text:find("%f[%w]ms$") or text:find("^ms%f[%W]") then
        return true
    end
    return false
end

-- Find "N/M ROLE" or "ROLE N/M" near a role keyword.
local function FindSlotNear(text, roleKey)
    local patterns = ROLE_PATTERNS[roleKey]
    if not patterns then
        return nil
    end
    for _, rp in ipairs(patterns) do
        -- filled/total ROLE
        local a, b = text:match("(%d+)%s*/%s*(%d+)%s*" .. rp)
        if a and b then
            return tonumber(a), tonumber(b)
        end
        -- ROLE filled/total
        a, b = text:match(rp .. "%s*(%d+)%s*/%s*(%d+)")
        if a and b then
            return tonumber(a), tonumber(b)
        end
        -- need ROLE / looking for ROLE (no counts)
        if text:find(rp) then
            return nil, nil, true -- mentioned without counts
        end
    end
    return nil
end

local function RoleOpen(filled, total, mentioned)
    if filled ~= nil and total ~= nil then
        return filled < total, filled, total
    end
    if mentioned then
        return true, nil, nil
    end
    return false, nil, nil
end

--- Parse a chat/whisper line.
-- @return table|nil match with fields:
--   isManastormLFM (bool), roles { tank={open,filled,total}, ... }, summary (string)
function Parser.Parse(message)
    local raw = tostring(message or "")
    local text = Lower(raw)
    if text == "" then
        return nil
    end

    local lfm = HasLFM(text)
    local ms = HasManastorm(text)
    if not (lfm and ms) then
        -- Soft / hosting path: role whispers without a full public LFM+MS line.
        if lfm then
            return nil -- e.g. LFM ICC without Manastorm
        end
        local invish = text:find("inv", 1, true) or text:find("invite", 1, true)
        local hasRoleWord = text:find("tank") or text:find("heal") or text:find("dps")
            or text:find("aura") or text:find("%f[%w]dd%f[%W]")
        local bareRole = text:match("^%s*(tanks?|healers?|heals?|heal|dps|auras?|aura|dd)%s*$")
        local allow = bareRole or (hasRoleWord and (ms or invish or #text <= 24))
        if not allow then
            return nil
        end
        local roles = {}
        local any = false
        for roleKey, _ in pairs(ROLE_PATTERNS) do
            local filled, total, mentioned = FindSlotNear(text, roleKey)
            local open, f, t = RoleOpen(filled, total, mentioned)
            if open or mentioned then
                roles[roleKey] = {
                    open = open or mentioned,
                    filled = f,
                    total = t,
                    mentioned = mentioned and true or false,
                }
                any = true
            end
        end
        if not any then
            return nil
        end
        return {
            isManastormLFM = ms and true or false,
            isRoleRequest = true,
            roles = roles,
            summary = raw,
            raw = raw,
        }
    end

    local roles = {}
    local parts = {}
    for _, roleKey in ipairs({ "tank", "healer", "aura", "dps" }) do
        local filled, total, mentioned = FindSlotNear(text, roleKey)
        local open, f, t = RoleOpen(filled, total, mentioned)
        if open or mentioned or (f ~= nil) then
            roles[roleKey] = {
                open = open,
                filled = f,
                total = t,
                mentioned = mentioned and true or (f ~= nil),
            }
            if f ~= nil and t ~= nil then
                local label = roleKey == "healer" and "H" or (roleKey == "tank" and "T" or (roleKey == "aura" and "A" or "D"))
                table.insert(parts, string.format("%d/%d %s", f, t, label))
            elseif mentioned or open then
                local label = roleKey
                table.insert(parts, "need " .. label)
            end
        end
    end

    -- If LFM+MS but no role keywords at all, still treat as match (generic need).
    local hasAnyRole = false
    for _ in pairs(roles) do
        hasAnyRole = true
        break
    end
    if not hasAnyRole then
        roles.dps = { open = true, filled = nil, total = nil, mentioned = true }
        table.insert(parts, "need any")
    end

    local summary
    if #parts > 0 then
        summary = "MS " .. table.concat(parts, " · ")
    else
        summary = "MS LFM"
    end

    return {
        isManastormLFM = true,
        isRoleRequest = false,
        roles = roles,
        summary = summary,
        raw = raw,
    }
end

--- True if parsed LFM still needs any of the given role flags.
-- @param parsed table from Parser.Parse
-- @param wantRoles { tank=bool, healer=bool, aura=bool, dps=bool }
function Parser.NeedsAnyRole(parsed, wantRoles)
    if type(parsed) ~= "table" or type(parsed.roles) ~= "table" or type(wantRoles) ~= "table" then
        return false
    end
    for role, want in pairs(wantRoles) do
        if want then
            local info = parsed.roles[role]
            if info and info.open then
                return true
            end
            -- If role mentioned without counts, treat as open
            if info and info.mentioned and info.open ~= false then
                return true
            end
        end
    end
    return false
end

--- Detect which single role a whisper is requesting (hosting).
-- Prefers explicit keywords; returns nil if ambiguous/none.
function Parser.RequestedRole(parsed)
    if type(parsed) ~= "table" or type(parsed.roles) ~= "table" then
        return nil
    end
    local found = nil
    local count = 0
    for role, info in pairs(parsed.roles) do
        if info and (info.mentioned or info.open) then
            count = count + 1
            found = role
        end
    end
    if count == 1 then
        return found
    end
    -- Prefer tank > healer > aura > dps if multiple (first they typed often tank)
    for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        local info = parsed.roles[role]
        if info and (info.mentioned or info.open) then
            return role
        end
    end
    return nil
end

-- Expose for unit tests without WoW.
if not _G.AscensionLFM then
    _G.AscensionLFM = AscensionLFM
end

return Parser
