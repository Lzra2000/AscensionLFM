-- AscensionLFM: core/Parser.lua
-- Pure Lua 5.1 Manastorm LFM/LFG line parser (no WoW APIs).
-- Detects LFM/LFG + Manastorm/MS and extracts role slot counts when present.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Parser = {}
AscensionLFM.Parser = Parser

-- Role keyword patterns (lowercase, Lua patterns). Order within a role matters
-- for slot capture; OT/MT/HPS/Aura-of-Exp variants included for hosting whispers.
local ROLE_PATTERNS = {
    tank = { "tanks?", "tn?ks?", "%f[%w]ot%f[%W]", "%f[%w]mt%f[%W]", "%f[%w]ot$", "%f[%w]mt$" },
    healer = {
        "healers?",
        "heals?",
        "heal",
        "heiler", -- DE
        "hps",
        "%f[%w]h%f[%W]",
        "%f[%w]h$",
    },
    aura = {
        "aura%s*of%s*exp[%w]*",
        "exp%s*aura",
        "aoe%s*aura",
        "aura%s*exp",
        "auras?",
        "aura",
    },
    dps = { "dps", "%f[%w]dd%f[%W]", "%f[%w]dd$", "damage", "dmg" },
}

local function Lower(s)
    return tostring(s or ""):lower()
end

local function HasLFM(text)
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

local function HasLFG(text)
    if text:find("lfg", 1, true) then
        return true
    end
    if text:find("looking for group", 1, true) then
        return true
    end
    if text:find("looking for a group", 1, true) then
        return true
    end
    return false
end

local function HasManastorm(text)
    if text:find("manastorm", 1, true) then
        return true
    end
    -- "mana storm" / "mana-storm" / "Mana  Storm"
    if text:find("mana[%s%-_]*storm", 1) then
        return true
    end
    -- Word-boundary-ish MS (avoid matching "dms", "msg", etc.)
    if text:find("%f[%w]ms%f[%W]") or text:find("%f[%w]ms$") or text:find("^ms%f[%W]") then
        return true
    end
    -- Glued level tags: MS15 / ms60 (common Ascension LFG shorthand)
    if text:find("%f[%w]ms%d") then
        return true
    end
    return false
end

local function PatternMentions(text, rp)
    -- Anchored / boundary patterns already encode edges; plain find for others.
    if rp:find("%%f", 1, true) or rp:find("^", 1, true) or rp:find("$", 1, true) then
        return text:find(rp) ~= nil
    end
    return text:find(rp) ~= nil
end

-- Find "N/M ROLE" or "ROLE N/M" near a role keyword.
local function FindSlotNear(text, roleKey)
    local patterns = ROLE_PATTERNS[roleKey]
    if not patterns then
        return nil
    end
    local mentioned = false
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
        if PatternMentions(text, rp) then
            mentioned = true
        end
    end
    if mentioned then
        return nil, nil, true
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

local function CollectRoles(text)
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
                local label = roleKey == "healer" and "H"
                    or (roleKey == "tank" and "T" or (roleKey == "aura" and "A" or "D"))
                table.insert(parts, string.format("%d/%d %s", f, t, label))
            elseif mentioned or open then
                table.insert(parts, "need " .. roleKey)
            end
        end
    end
    return roles, parts
end

-- Exact single-word role phrases for the "bare role" whisper check below.
-- NOTE: this used to be one Lua pattern with "|" as separator, but Lua patterns
-- have no alternation operator - "|" only matches a literal pipe character, so
-- that pattern could never match anything and the whole bareRole branch was
-- dead code. Table lookup + a couple of explicit multi-word patterns instead.
local BARE_ROLE_WORDS = {
    tank = true, tanks = true, ot = true, mt = true,
    healer = true, healers = true, heal = true, heals = true, heiler = true, hps = true,
    aura = true, auras = true,
    dd = true, damage = true, dmg = true, dps = true,
}

local function IsBareRolePhrase(s)
    if BARE_ROLE_WORDS[s] then
        return true
    end
    if s:match("^aura%s+of%s+exp[%w]*$") or s:match("^exp%s+aura$") or s:match("^aoe%s+aura$") then
        return true
    end
    return false
end

local function SoftRoleRequest(text, raw, ms)
    local invish = text:find("inv", 1, true) or text:find("invite", 1, true)
    local hasRoleWord = text:find("tank") or text:find("heal") or text:find("dps")
        or text:find("aura") or text:find("%f[%w]dd%f[%W]")
        or text:find("%f[%w]ot%f[%W]") or text:find("%f[%w]mt%f[%W]")
        or text:find("hps") or text:find("damage") or text:find("dmg", 1, true)
        or text:find("heiler", 1, true)
        or text:find("exp%s*aura") or text:find("aoe%s*aura")
    -- Strip trailing punctuation for bare / letter matches ("healers!", "H?")
    local stripped = text:gsub("[!%?%.%,%;%:]+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local bareRole = IsBareRolePhrase(stripped) and stripped or nil
    local letterRole = stripped:match("^([thad])$")
    -- Live whispers are often long: "53 / dps / looms / prestige 20 / ... / no aura"
    local allow = bareRole or letterRole or (hasRoleWord and (ms or invish or #text <= 120))
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
    -- Letter-only whispers: map t/h/a/d when pattern scan found nothing
    if not any and letterRole then
        local map = { t = "tank", h = "healer", a = "aura", d = "dps" }
        local role = map[letterRole]
        if role then
            roles[role] = { open = true, filled = nil, total = nil, mentioned = true }
            any = true
        end
    end
    if not any then
        return nil
    end
    return {
        isManastormLFM = false,
        isManastormLFG = false,
        isManastormListing = ms and true or false,
        listingKind = nil,
        isRoleRequest = true,
        roles = roles,
        summary = raw,
        raw = raw,
    }
end

--- Parse a chat/whisper line.
-- @return table|nil match with fields:
--   isManastormLFM / isManastormLFG / isManastormListing, listingKind,
--   roles { tank={open,filled,total}, ... }, summary (string)
function Parser.Parse(message)
    local raw = tostring(message or "")
    local text = Lower(raw)
    if text == "" then
        return nil
    end

    local lfm = HasLFM(text)
    local lfg = HasLFG(text)
    local ms = HasManastorm(text)

    if not ((lfm or lfg) and ms) then
        -- Soft / hosting path: role whispers without a full public LFM/LFG+MS line.
        if lfm or lfg then
            return nil -- e.g. LFM ICC / LFG ICC without Manastorm
        end
        return SoftRoleRequest(text, raw, ms)
    end

    local roles, parts = CollectRoles(text)

    -- If listing+MS but no role keywords at all, still treat as match (generic need).
    local hasAnyRole = false
    for _ in pairs(roles) do
        hasAnyRole = true
        break
    end
    local genericNeed = false
    if not hasAnyRole then
        roles.dps = { open = true, filled = nil, total = nil, mentioned = true }
        table.insert(parts, "need any")
        -- Flag so hosting LFG auto-invite can require an explicit role keyword.
        genericNeed = true
    end

    local kind = lfm and "lfm" or "lfg"
    -- Prefer LFM if both somehow present
    if lfm and lfg then
        kind = "lfm"
    end

    local summary
    if #parts > 0 then
        summary = "MS " .. table.concat(parts, " * ")
    else
        summary = kind == "lfg" and "MS LFG" or "MS LFM"
    end
    if kind == "lfg" then
        summary = "LFG " .. summary
    end

    return {
        isManastormLFM = kind == "lfm",
        isManastormLFG = kind == "lfg",
        isManastormListing = true,
        listingKind = kind,
        isRoleRequest = false,
        genericNeed = genericNeed,
        roles = roles,
        summary = summary,
        raw = raw,
    }
end

--- True if parsed LFM/LFG still needs any of the given role flags.
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

--- Roles that still have open slots in a listing (and optionally filtered by wantRoles).
-- @return { tank=true, ... }
function Parser.NeededRoles(parsed, wantRoles)
    local out = {}
    if type(parsed) ~= "table" or type(parsed.roles) ~= "table" then
        return out
    end
    for role, info in pairs(parsed.roles) do
        if info and (info.open or (info.mentioned and info.open ~= false)) then
            if not wantRoles or wantRoles[role] then
                out[role] = true
            end
        end
    end
    return out
end

--- Detect which single role a whisper is requesting (hosting).
-- Prefers explicit keywords; returns nil if ambiguous/none.
-- When the original message is available on parsed.raw / parsed.message,
-- negated roles ("no aura") are excluded. Combat roles beat pure aura
-- when both are mentioned without negation.
function Parser.RequestedRole(parsed)
    if type(parsed) ~= "table" or type(parsed.roles) ~= "table" then
        return nil
    end
    local raw = parsed.raw or parsed.message or parsed.text or ""
    local negated = (raw ~= "" and Parser.NegatedRoles(raw)) or {}
    local found = nil
    local count = 0
    for role, info in pairs(parsed.roles) do
        if info and (info.mentioned or info.open) and not negated[role] then
            count = count + 1
            found = role
        end
    end
    if count == 1 then
        return found
    end
    -- Prefer tank > healer > dps > aura if multiple (combat seats first;
    -- "dps with aura" should land as dps, not steal an aura slot by accident).
    for _, role in ipairs({ "tank", "healer", "dps", "aura" }) do
        local info = parsed.roles[role]
        if info and (info.mentioned or info.open) and not negated[role] then
            return role
        end
    end
    return nil
end

--- Roles explicitly negated in the message ("dps no aura", "tank without aura").
-- Returns a set { aura=true, ... } of roles the sender does NOT want to fill.
function Parser.NegatedRoles(message)
    local t = Lower(message)
    local out = {}
    local roleSpecs = {
        { "aura", "auras?" },
        { "tank", "tanks?" },
        { "healer", "healers?" },
        { "healer", "heals?" },
        { "healer", "heal" },
        { "healer", "heiler" },
        { "healer", "hps" },
        { "dps", "dps" },
        { "dps", "dd" },
        { "dps", "damage" },
        { "dps", "dmg" },
    }
    for _, spec in ipairs(roleSpecs) do
        local role, pat = spec[1], spec[2]
        if t:find("no%s+" .. pat)
            or t:find("not%s+a?%s*" .. pat)
            or t:find("without%s+" .. pat)
            or t:find("w/?o%s+" .. pat)
            or t:find("no%s*%-%s*" .. pat)
            -- Common German applicant phrasing: "DPS ohne Aura" / "keine
            -- Aura" / "keinen Heiler" (masculine accusative, e.g. Tank/
            -- Heiler). Three explicit endings rather than an optional
            -- single character, so "keinerlei" still correctly does not
            -- match (no space directly after kein/keine/keinen there).
            or t:find("ohne%s+" .. pat)
            or t:find("kein%s+" .. pat)
            or t:find("keine%s+" .. pat)
            or t:find("keinen%s+" .. pat) then
            out[role] = true
        end
    end
    return out
end

--- All non-negated roles mentioned in a whisper (for dual-role fallback).
-- Example: "dps with aura" -> { dps=true, aura=true }; "dps no aura" -> { dps=true }.
function Parser.OfferedRoles(message)
    local t = Lower(message)
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then
        return {}
    end
    local negated = Parser.NegatedRoles(t)
    local out = {}
    if (t:find("heiler", 1, true) or t:find("healer", 1, true) or t:find("healers", 1, true)
        or t:find("heals", 1, true) or t:find("heal", 1, true) or t:find("hps", 1, true))
        and not negated.healer then
        out.healer = true
    end
    if (t:find("tank", 1, true) or t:find("tanj", 1, true)
        or t:find("%f[%w]ot%f[%W]") or t:find("%f[%w]mt%f[%W]"))
        and not negated.tank then
        out.tank = true
    end
    if (t:find("dps", 1, true) or t:find("damage", 1, true) or t:find("dmg", 1, true)
        or t:find("%f[%w]dd%f[%W]"))
        and not negated.dps then
        out.dps = true
    end
    if (t:find("aura", 1, true) or t:find("arua", 1, true) or t:find("exp%s*aura") or t:find("aoe%s*aura") or t:find("arua", 1, true))
        and not negated.aura then
        out.aura = true
    end
    return out
end

--- Aggressive fallback role guess for hosting whispers / Role Check replies.
-- Accepts T/H/A/D letters, plurals, DE "heiler", trailing punctuation, short phrases.
-- Honors negations: "dps no aura" -> dps (not aura); "tank without aura" -> tank.
function Parser.GuessRole(message)
    local t = Lower(message)
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    t = t:gsub("[!%?%.%,%;%:]+$", ""):gsub("^[!%?%.%,%;%:]+", "")
    if t == "" then
        return nil
    end

    local negated = Parser.NegatedRoles(t)

    -- Whole-message / first-token exact map (common typos included)
    local token = t:match("^(%S+)") or t
    token = token:gsub("[!%?%.%,%;%:]+$", "")
    local exact = {
        t = "tank",
        tank = "tank",
        tanks = "tank",
        tanj = "tank", -- common typo seen live
        tnk = "tank",
        ot = "tank",
        mt = "tank",
        h = "healer",
        heal = "healer",
        heals = "healer",
        healer = "healer",
        healers = "healer",
        heiler = "healer",
        hps = "healer",
        a = "aura",
        aura = "aura",
        auras = "aura",
        arua = "aura", -- common typo
        d = "dps",
        dps = "dps",
        dd = "dps",
        damage = "dps",
        dmg = "dps",
    }
    if exact[t] and not negated[exact[t]] then
        return exact[t]
    end
    -- First-token exact only when the rest of the message does not clearly
    -- name another role (so "aura dps" is not locked to aura by the token).
    if exact[token] and not negated[exact[token]] then
        local rest = t:sub(#token + 1)
        local restHasOther = false
        if rest ~= "" then
            if exact[token] ~= "tank" and (rest:find("tank", 1, true) or rest:find("tanj", 1, true)) then restHasOther = true end
            if exact[token] ~= "healer" and (rest:find("heal", 1, true) or rest:find("hps", 1, true) or rest:find("heiler", 1, true)) then restHasOther = true end
            if exact[token] ~= "dps" and (rest:find("dps", 1, true) or rest:find("damage", 1, true) or rest:find("dmg", 1, true)) then restHasOther = true end
            if exact[token] ~= "aura" and rest:find("aura", 1, true) and not negated.aura then restHasOther = true end
        end
        if not restHasOther then
            return exact[token]
        end
    end

    -- Detect which roles are positively mentioned (ignoring negated ones).
    local mentioned = {}
    if (t:find("heiler", 1, true) or t:find("healer", 1, true) or t:find("healers", 1, true)
        or t:find("heals", 1, true) or t:find("heal", 1, true) or t:find("hps", 1, true))
        and not negated.healer then
        mentioned.healer = true
    end
    if (t:find("tank", 1, true) or t:find("tanj", 1, true) or t == "ot" or t == "mt"
        or t:find("%f[%w]ot%f[%W]") or t:find("%f[%w]mt%f[%W]"))
        and not negated.tank then
        mentioned.tank = true
    end
    if (t:find("dps", 1, true) or t:find("damage", 1, true) or t:find("dmg", 1, true)
        or t:find("%f[%w]dd%f[%W]") or t == "dd")
        and not negated.dps then
        mentioned.dps = true
    end
    -- Aura only if not negated AND (only-aura message OR explicit aura offer without a combat role)
    if (t:find("aura", 1, true) or t:find("exp%s*aura") or t:find("aoe%s*aura") or t:find("arua", 1, true))
        and not negated.aura then
        mentioned.aura = true
    end

    -- Prefer combat roles over pure aura when both are offered:
    -- "dps with aura" / "aura dps" -> dps (they can still be moved to aura later if host needs it)
    -- "aura" alone -> aura
    for _, role in ipairs({ "tank", "healer", "dps", "aura" }) do
        if mentioned[role] then
            return role
        end
    end
    return nil
end

--- Extract slot totals from a parsed listing (for host caps).
-- @return table|nil { tank=n, healer=n, aura=n, dps=n } only keys with totals
function Parser.SlotTotals(parsed)
    if type(parsed) ~= "table" or type(parsed.roles) ~= "table" then
        return nil
    end
    local out = {}
    local any = false
    for role, info in pairs(parsed.roles) do
        if info and info.total ~= nil then
            out[role] = info.total
            any = true
        end
    end
    if not any then
        return nil
    end
    return out
end

-- Expose for unit tests without WoW.
if not _G.AscensionLFM then
    _G.AscensionLFM = AscensionLFM
end

return Parser
