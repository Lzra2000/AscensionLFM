-- AscensionLFM: core/RoleCheck.lua
-- Raid Warning role-check → whisper roles → resync T/H/A/D slot places.
-- Pure helpers are WoW-free for unit tests.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local RoleCheck = {}
AscensionLFM.RoleCheck = RoleCheck

local DEFAULT_MSG = "ROLE CHECK — whisper or party: tank/heal/aura/dps (T/H/A/D)"
local DEFAULT_DURATION = 60
local MIN_RW_GAP = 30
local MIN_DURATION = 15
local MAX_DURATION = 300

local activeUntil = 0
local lastRwAt = 0
local responses = {} -- [nameLower] = role
local lastResponseCount = 0
local frame
local endedResyncDone = false
local lastStartReason = "idle"
local lastReplyAt = 0

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

local function PlayerName()
    if type(UnitName) == "function" then
        return UnitName("player")
    end
    return nil
end

--- Pure: build RW message.
function RoleCheck.BuildMessage(custom)
    local msg = tostring(custom or "")
    if msg == "" then
        msg = DEFAULT_MSG
    end
    if #msg > 255 then
        msg = msg:sub(1, 255)
    end
    return msg
end

--- Pure: clamp listen window seconds (alias ClampDuration).
function RoleCheck.ClampDuration(n)
    n = tonumber(n) or DEFAULT_DURATION
    if n < MIN_DURATION then
        n = MIN_DURATION
    end
    if n > MAX_DURATION then
        n = MAX_DURATION
    end
    return n
end
RoleCheck.ClampWindow = RoleCheck.ClampDuration

--- Pure: min seconds between RWs (floor 30).
function RoleCheck.ClampMinInterval(n)
    n = tonumber(n) or MIN_RW_GAP
    if n < MIN_RW_GAP then
        n = MIN_RW_GAP
    end
    if n > 600 then
        n = 600
    end
    return n
end

--- Pure: rate-limit gate.
function RoleCheck.ShouldAllowRW(now, lastAt, minInterval)
    now = tonumber(now) or 0
    lastAt = tonumber(lastAt) or 0
    minInterval = RoleCheck.ClampMinInterval(minInterval)
    if lastAt <= 0 then
        return true
    end
    return (now - lastAt) >= minInterval
end

--- Pure: membership against presentSet ([nameLower]=true).
function RoleCheck.IsGroupMemberName(name, presentSet)
    if type(name) ~= "string" or name == "" or type(presentSet) ~= "table" then
        return false
    end
    return presentSet[LowerName(name)] == true
end

--- Pure: extract role from whisper text (Parser when available).
function RoleCheck.ParseWhisperRole(message)
    if AscensionLFM.Parser and AscensionLFM.Parser.Parse then
        local parsed = AscensionLFM.Parser.Parse(message)
        if parsed and AscensionLFM.Parser.RequestedRole then
            local role = AscensionLFM.Parser.RequestedRole(parsed)
            if role then
                return role
            end
        end
    end
    if AscensionLFM.Parser and AscensionLFM.Parser.GuessRole then
        local role = AscensionLFM.Parser.GuessRole(message)
        if role then
            return role
        end
    end
    local t = tostring(message or ""):lower()
    t = t:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[!%?%.%,%;%:]+$", "")
    if t == "" then
        return nil
    end
    if t == "t" or t == "tank" or t == "tanks" or t == "ot" or t == "mt"
        or t:find("tank", 1, true) or t:find("%f[%w]ot%f[%W]") or t:find("%f[%w]mt%f[%W]") then
        return "tank"
    end
    if t == "h" or t == "heal" or t == "heals" or t == "healer" or t == "healers" or t == "heiler" or t == "hps"
        or t:find("heal", 1, true) or t:find("hps", 1, true) or t:find("heiler", 1, true) then
        return "healer"
    end
    if t == "a" or t == "aura" or t == "auras"
        or t:find("aura", 1, true) or t:find("exp%s*aura") or t:find("aoe%s*aura") then
        return "aura"
    end
    if t == "d" or t == "dps" or t == "dd" or t == "damage" or t == "dmg"
        or t:find("dps", 1, true) or t:find("%f[%w]dd%f[%W]") or t:find("damage", 1, true) then
        return "dps"
    end
    return nil
end

--- Pure: prune leavers then overlay role-check responses for present members.
-- @return newMap, removedCount, appliedCount
function RoleCheck.ResyncAssigned(assignedMap, responseMap, presentSet)
    presentSet = presentSet or {}
    local base = {}
    local removed = 0
    if type(assignedMap) == "table" then
        for name, role in pairs(assignedMap) do
            if presentSet[name] then
                base[name] = role
            else
                removed = removed + 1
            end
        end
    end
    local applied = 0
    if type(responseMap) == "table" then
        for name, roleOrInfo in pairs(responseMap) do
            if presentSet[name] then
                local role = roleOrInfo
                if type(roleOrInfo) == "table" then
                    role = roleOrInfo.role
                end
                if type(role) == "string" and role ~= "" then
                    base[name] = role
                    applied = applied + 1
                end
            end
        end
    end
    return base, removed, applied
end

--- Pure: status line for UI.
function RoleCheck.BuildStatusText(isActive, remaining, count, autoMoveAura)
    count = tonumber(count) or 0
    remaining = tonumber(remaining) or 0
    if remaining < 0 then
        remaining = 0
    end
    if isActive then
        return string.format("Role check active — %ds left · %d responses", remaining, count)
    end
    local auraBit = ""
    if autoMoveAura ~= nil then
        auraBit = string.format(" · Aura auto-move %s", autoMoveAura and "ON" or "OFF")
    end
    if count > 0 then
        return string.format("Role check idle · last window %d responses%s", count, auraBit)
    end
    return "Role check idle" .. auraBit
end

function RoleCheck.IsActive(now)
    now = tonumber(now) or Now()
    return activeUntil > now
end

function RoleCheck.SecondsLeft(now)
    now = tonumber(now) or Now()
    local left = activeUntil - now
    if left < 0 then
        left = 0
    end
    return math.floor(left + 0.5)
end

function RoleCheck.ResponseCount()
    local n = 0
    for _ in pairs(responses) do
        n = n + 1
    end
    return n
end

function RoleCheck.GetResponses()
    return responses
end

--- Live privilege check (same hardened path as Kick.CanKick).
function RoleCheck.CanRaidWarn()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    local groupKind = "none"
    if raid and raid > 0 then
        groupKind = "raid"
    elseif party and party > 0 then
        groupKind = "party"
    else
        return false, "none"
    end

    -- Most reliable on 3.3.5a / Ascension for both party and raid lead.
    if type(UnitIsPartyLeader) == "function" and UnitIsPartyLeader("player") then
        return true, groupKind
    end

    if groupKind == "raid" then
        local lead = (type(IsRaidLeader) == "function" and IsRaidLeader()) or false
        local assist = (type(IsRaidOfficer) == "function" and IsRaidOfficer()) or false
        return lead or assist, "raid"
    end

    if type(IsPartyLeader) == "function" then
        return IsPartyLeader() and true or false, "party"
    end
    return false, "party"
end

local function RosterNameAt(i, unit)
    local name
    if type(GetRaidRosterInfo) == "function" then
        name = GetRaidRosterInfo(i)
    end
    if (type(name) ~= "string" or name == "") and type(UnitName) == "function" and unit then
        name = UnitName(unit)
    end
    return name
end

local function IsGroupMember(name)
    local key = LowerName(name)
    if key == "" then
        return false
    end
    local me = PlayerName()
    if me and LowerName(me) == key then
        return true
    end
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local n = RosterNameAt(i, "raid" .. i)
            if type(n) == "string" and LowerName(n) == key then
                return true
            end
        end
        return false
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        if type(UnitName) == "function" then
            local n = UnitName("party" .. i)
            if type(n) == "string" and LowerName(n) == key then
                return true
            end
        end
    end
    return false
end

--- Live membership (UnitName fallback when GetRaidRosterInfo name is empty).
function RoleCheck.IsLiveGroupMember(name)
    return IsGroupMember(name)
end

local function SendWarn(msg, groupKind)
    if type(SendChatMessage) ~= "function" or not msg or msg == "" then
        return false
    end
    if groupKind == "raid" then
        local ok = pcall(SendChatMessage, msg, "RAID_WARNING")
        if ok then
            return true
        end
        ok = pcall(SendChatMessage, msg, "RAID")
        if ok then
            return true
        end
        pcall(SendChatMessage, msg, "YELL")
        return true
    end
    local ok = pcall(SendChatMessage, msg, "PARTY")
    if not ok then
        pcall(SendChatMessage, msg, "YELL")
    end
    return true
end

local function IsHosting(db)
    return db and (db.mode == "hosting" or db.fullAutoHosting)
end

local function CollectPresent()
    local present = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local n = RosterNameAt(i, "raid" .. i)
            if type(n) == "string" and n ~= "" then
                present[LowerName(n)] = true
            end
        end
        return present
    end
    local me = PlayerName()
    if me then
        present[LowerName(me)] = true
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        if type(UnitName) == "function" then
            local n = UnitName("party" .. i)
            if type(n) == "string" and n ~= "" then
                present[LowerName(n)] = true
            end
        end
    end
    return present
end

local function RefreshUI()
    if AscensionLFM.MainWindow then
        if AscensionLFM.MainWindow.RefreshRoleCheck then
            AscensionLFM.MainWindow.RefreshRoleCheck()
        end
        if AscensionLFM.MainWindow.RefreshSlots then
            AscensionLFM.MainWindow.RefreshSlots()
        end
        if AscensionLFM.MainWindow.RefreshPost then
            AscensionLFM.MainWindow.RefreshPost()
        end
    end
end

--- Resync all role places: prune leavers, re-apply responses, ScanRaid, aura-balance, UI.
function RoleCheck.Resync()
    local db = DB()
    local present = CollectPresent()
    local groupSize = 0
    for _ in pairs(present) do
        groupSize = groupSize + 1
    end

    local assignedMap = {}
    if db and type(db.assignedRoles) == "table" then
        for k, v in pairs(db.assignedRoles) do
            assignedMap[k] = v
        end
    end

    local removed, applied = 0, 0
    if groupSize > 0 then
        local newMap, rem, app = RoleCheck.ResyncAssigned(assignedMap, responses, present)
        removed, applied = rem, app
        if AscensionLFM.Slots and AscensionLFM.Slots.ClearAll then
            AscensionLFM.Slots.ClearAll()
        end
        for name, role in pairs(newMap) do
            if AscensionLFM.Slots and AscensionLFM.Slots.Assign then
                AscensionLFM.Slots.Assign(name, role)
            end
        end
    else
        -- No roster APIs: still re-apply buffered responses
        for name, role in pairs(responses) do
            if AscensionLFM.Slots and AscensionLFM.Slots.Assign then
                AscensionLFM.Slots.Assign(name, role)
                applied = applied + 1
            end
        end
    end

    if AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
        local _, rem = AscensionLFM.Slots.ScanRaid()
        if groupSize > 0 and rem and rem > removed then
            removed = rem
        end
    elseif AscensionLFM.Slots and AscensionLFM.Slots.SyncFromRoster then
        removed = AscensionLFM.Slots.SyncFromRoster() or removed
    end

    local moved = 0
    if AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.Balance then
        moved = AscensionLFM.AuraBalance.Balance() or 0
    end

    lastResponseCount = RoleCheck.ResponseCount()
    local line = string.format(
        "roles resynced (pruned %d, applied %d, aura moves %d, replies %d)",
        removed, applied, moved, lastResponseCount
    )
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("match", line)
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(line)
    end
    RefreshUI()
    return true, removed, applied
end
RoleCheck.ResyncNow = RoleCheck.Resync

--- Start RW role check (Hosting / Full Auto only). Does NOT run on login.
-- @param msgOrNow optional message string, OR number timestamp for tests
function RoleCheck.StartCheck(msgOrNow)
    local db = DB()
    local msgOverride, nowOverride
    if type(msgOrNow) == "number" then
        nowOverride = msgOrNow
    else
        msgOverride = msgOrNow
    end
    if not IsHosting(db) then
        lastStartReason = "not hosting"
        if AscensionLFM.Print then
            AscensionLFM.Print("Role Check needs Hosting mode (or Full Auto)")
        end
        return false, "not hosting"
    end
    local now = nowOverride or Now()
    local minGap = RoleCheck.ClampMinInterval(db and db.roleCheckMinInterval)
    if not RoleCheck.ShouldAllowRW(now, lastRwAt, minGap) then
        lastStartReason = "rate limited"
        if AscensionLFM.Print then
            AscensionLFM.Print("Role Check: wait before the next raid warning")
        end
        return false, "rate limited"
    end
    local can, groupKind = RoleCheck.CanRaidWarn()
    if not can then
        lastStartReason = "no privilege"
        if AscensionLFM.Print then
            AscensionLFM.Print("Role Check: need raid lead/assist (or party lead)")
        end
        return false, "no privilege"
    end

    local msg = RoleCheck.BuildMessage(msgOverride or (db and db.roleCheckMessage))
    local dur = RoleCheck.ClampDuration(db and (db.roleCheckWindow or db.roleCheckDuration))
    if db then
        db.roleCheckMessage = msg
    end
    responses = {}
    lastResponseCount = 0
    endedResyncDone = false
    activeUntil = now + dur
    lastRwAt = now
    lastStartReason = "started:" .. tostring(groupKind)
    SendWarn(msg, groupKind)
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("rolecheck", "RW role check started (" .. dur .. "s)")
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(
            "Role Check open — whisper or party/raid chat: tank / heal / aura / dps (" .. dur .. "s)"
        )
    end
    RoleCheck.EnsureTicker()
    RefreshUI()
    return true, groupKind
end

-- Back-compat: Start() begins a role check (UI buttons). Use EnsureTicker on login.
function RoleCheck.Start(msgOverride)
    return RoleCheck.StartCheck(msgOverride)
end

--- Accept a role reply (whisper or party/raid chat) from a group member.
function RoleCheck.HandleWhisper(sender, message)
    if not RoleCheck.IsActive() then
        return false
    end
    if type(sender) ~= "string" or sender == "" then
        return false
    end
    if not IsGroupMember(sender) then
        return false
    end
    local role = RoleCheck.ParseWhisperRole(message)
    if not role then
        return false
    end
    responses[LowerName(sender)] = role
    lastReplyAt = Now()
    if AscensionLFM.Slots and AscensionLFM.Slots.Assign then
        AscensionLFM.Slots.Assign(sender, role)
    end
    if AscensionLFM.Print then
        AscensionLFM.Print("Role Check: " .. tostring(sender) .. " → " .. role)
    end
    RefreshUI()
    return true, role
end
RoleCheck.OnWhisper = RoleCheck.HandleWhisper
RoleCheck.HandleRoleReply = RoleCheck.HandleWhisper

function RoleCheck.GetStatus()
    local db = DB()
    local active = RoleCheck.IsActive()
    local left = RoleCheck.SecondsLeft()
    local count = active and RoleCheck.ResponseCount() or lastResponseCount
    local autoMove = db and db.autoMoveAura ~= false
    local can, groupKind = RoleCheck.CanRaidWarn()
    return {
        active = active,
        remaining = left,
        left = left,
        responses = count,
        status = RoleCheck.BuildStatusText(active, left, count, autoMove),
        lastRwAt = lastRwAt,
        lastStart = lastStartReason,
        lastReplyAt = lastReplyAt,
        canWarn = can and true or false,
        group = groupKind,
        hosting = IsHosting(db) and true or false,
    }
end

function RoleCheck.Status()
    return RoleCheck.GetStatus()
end

function RoleCheck.Tick(now)
    now = tonumber(now) or Now()
    if activeUntil <= 0 then
        return "idle"
    end
    if RoleCheck.IsActive(now) then
        return "listening"
    end
    if endedResyncDone then
        return "ended"
    end
    endedResyncDone = true
    lastResponseCount = RoleCheck.ResponseCount()
    local db = DB()
    local auto = not (db and db.roleCheckAutoResync == false)
    if auto then
        RoleCheck.Resync()
        if AscensionLFM.Print then
            AscensionLFM.Print("Role Check ended — roles resynced")
        end
    end
    activeUntil = 0
    RefreshUI()
    return "ended"
end

function RoleCheck.EnsureTicker()
    if frame then
        return
    end
    if type(CreateFrame) ~= "function" then
        return
    end
    frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + (elapsed or 0)
        if self._t < 0.5 then
            return
        end
        self._t = 0
        RoleCheck.Tick(Now())
        if RoleCheck.IsActive() and AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshRoleCheck then
            AscensionLFM.MainWindow.RefreshRoleCheck()
        end
    end)
end

function RoleCheck._ResetForTests()
    activeUntil = 0
    lastRwAt = 0
    responses = {}
    lastResponseCount = 0
    endedResyncDone = false
    lastStartReason = "idle"
    lastReplyAt = 0
end

function RoleCheck._SetLastRwAt(t)
    lastRwAt = tonumber(t) or 0
end

RoleCheck.DEFAULT_MESSAGE = DEFAULT_MSG
RoleCheck.DEFAULT_WINDOW = DEFAULT_DURATION
RoleCheck.DEFAULT_MIN_INTERVAL = MIN_RW_GAP
RoleCheck.MIN_WINDOW = MIN_DURATION
RoleCheck.MAX_WINDOW = MAX_DURATION
RoleCheck.ClampWindow = RoleCheck.ClampDuration
RoleCheck.IsGroupMember = RoleCheck.IsGroupMemberName
