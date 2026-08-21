-- AscensionLFM: ui/MiniHUD.lua
-- Compact floating quick-action bar (no /alfm needed mid-run).
-- Button labels are hardcoded English (same HUD-family exception as Wishlist).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local MiniHUD = {}
AscensionLFM.MiniHUD = MiniHUD

local FRAME_NAME = "AscensionLFMMiniHUD"
local DEFAULT_WIPE = "WIPE"
local DEFAULT_SHIELD = "KILL MOBS - boss shield still up!"
local DEFAULT_REGROUP = "REGROUP - accept invite"
local ANNOUNCE_GAP = 2
local RW_ANNOUNCE_GAP = 15 -- Role Check re-warn; was 2s and got spam-clicked mid-run
local REGROUP_MAX = 40
local REGROUP_INVITE_CAP = 15
-- Each re-invite is fired this many times back-to-back (see the comment
-- at the call site) instead of once, since an invite occasionally just
-- doesn't land (brief connectivity hiccup, server hiccup) and a single
-- shot has no way to notice or retry once the synchronous click is over.
local REGROUP_INVITE_ATTEMPTS = 10

local frame
local expanded = true
local buttons = {}
local lastAnnounceAt = {} -- [kind] = GetTime()
local statusFS

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

local function DB()
    if AscensionLFM.Database and AscensionLFM.Database.Get then
        return AscensionLFM.Database.Get()
    end
    return nil
end

local function Print(msg)
    if AscensionLFM.Print then
        AscensionLFM.Print(msg)
    end
end

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

--- Pure: short need-line for a role.
function MiniHUD.BuildNeedMessage(role)
    role = tostring(role or ""):lower()
    if role == "tank" then
        return "LFM MS need Tank"
    end
    if role == "healer" then
        return "LFM MS need Healer"
    end
    if role == "aura" then
        return "LFM MS need Aura"
    end
    if role == "dps" then
        return "LFM MS need DPS"
    end
    return nil
end

--- Pure: wipe raid-warning text.
function MiniHUD.BuildWipeMessage(custom)
    local msg = tostring(custom or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        msg = DEFAULT_WIPE
    end
    if #msg > 255 then
        msg = msg:sub(1, 255)
    end
    return msg
end

--- Pure: kill-mobs / boss-shield warning text.
function MiniHUD.BuildShieldMessage(custom)
    local msg = tostring(custom or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        msg = DEFAULT_SHIELD
    end
    if #msg > 255 then
        msg = msg:sub(1, 255)
    end
    return msg
end

--- Pure: regroup invite warning text.
function MiniHUD.BuildRegroupMessage(custom)
    local msg = tostring(custom or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        msg = DEFAULT_REGROUP
    end
    if #msg > 255 then
        msg = msg:sub(1, 255)
    end
    return msg
end

--- Pure: remember a display name in the regroup watch list (unique, newest last).
-- @return newList
function MiniHUD.RememberName(list, name, maxN)
    maxN = tonumber(maxN) or REGROUP_MAX
    if maxN < 1 then
        maxN = 1
    end
    local out = {}
    if type(list) == "table" then
        for _, n in ipairs(list) do
            if type(n) == "string" and n ~= "" then
                table.insert(out, n)
            end
        end
    end
    if type(name) ~= "string" or name == "" then
        return out
    end
    local key = LowerName(name)
    local filtered = {}
    for _, n in ipairs(out) do
        if LowerName(n) ~= key then
            table.insert(filtered, n)
        end
    end
    table.insert(filtered, name)
    while #filtered > maxN do
        table.remove(filtered, 1)
    end
    return filtered
end

--- Pure: names from watch list that are not currently present (and not self).
-- @param roster string[] display names
-- @param presentSet { [nameLower]=true }
-- @param selfName string|nil
-- @param cap number|nil
function MiniHUD.SelectMissing(roster, presentSet, selfName, cap)
    presentSet = presentSet or {}
    cap = tonumber(cap) or REGROUP_INVITE_CAP
    if cap < 1 then
        cap = 1
    end
    local selfKey = selfName and LowerName(selfName) or nil
    local out = {}
    local seen = {}
    if type(roster) ~= "table" then
        return out
    end
    for _, name in ipairs(roster) do
        if type(name) == "string" and name ~= "" then
            local key = LowerName(name)
            if key ~= "" and not seen[key] and (not selfKey or key ~= selfKey) and not presentSet[key] then
                seen[key] = true
                table.insert(out, name)
                if #out >= cap then
                    break
                end
            end
        end
    end
    return out
end

local function CanRaidWarn()
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.CanRaidWarn then
        return AscensionLFM.RoleCheck.CanRaidWarn()
    end
    if AscensionLFM.Kick and AscensionLFM.Kick.CanKick then
        return AscensionLFM.Kick.CanKick()
    end
    return false, "none"
end

local function AutoGroupAnnounce(msg)
    if type(SendChatMessage) ~= "function" or not msg or msg == "" then
        return false, "no chat"
    end
    local can, groupKind = CanRaidWarn()
    if groupKind == "raid" and can then
        local ok = pcall(SendChatMessage, msg, "RAID_WARNING")
        if ok then
            return true, "RAID_WARNING"
        end
        ok = pcall(SendChatMessage, msg, "RAID")
        if ok then
            return true, "RAID"
        end
    elseif groupKind == "raid" then
        -- Not lead/assist: still hit raid chat before yell so the MS group hears it
        local ok = pcall(SendChatMessage, msg, "RAID")
        if ok then
            return true, "RAID"
        end
    elseif groupKind == "party" and can then
        local ok = pcall(SendChatMessage, msg, "PARTY")
        if ok then
            return true, "PARTY"
        end
    elseif groupKind == "party" then
        -- Not lead: try party anyway, then yell
        local ok = pcall(SendChatMessage, msg, "PARTY")
        if ok then
            return true, "PARTY"
        end
    end
    local ok = pcall(SendChatMessage, msg, "YELL")
    if ok then
        return true, "YELL"
    end
    return false, "send failed"
end

--- Route a group-wide announcement (Wipe/Shield/Regroup/RW-trigger) per the
-- host's configured delivery for this message `kind` - "auto" (default)
-- uses the existing smart cascade (RAID_WARNING if privileged, else raid/
-- party chat, else yell); "raidwarning" forces RW only (fails if not
-- privileged, rather than silently falling back to a different channel);
-- "raid" forces raid/party chat, skipping RW even when privileged;
-- "local" doesn't broadcast at all, just notes it in the host's own chat;
-- "disabled" sends nothing for that message kind.
local function SendGroupAnnounce(msg, kind)
    local db = DB()
    local route = kind and db and type(db.messageRouting) == "table" and db.messageRouting[kind]
    if route == "disabled" then
        return false, "disabled"
    end
    if route == "local" then
        if AscensionLFM.Print then
            AscensionLFM.Print("(local only) " .. tostring(msg))
        end
        return true, "LOCAL"
    end
    if route == "raidwarning" then
        if type(SendChatMessage) ~= "function" or not msg or msg == "" then
            return false, "no chat"
        end
        local can, groupKind = CanRaidWarn()
        if groupKind == "raid" and can then
            local ok = pcall(SendChatMessage, msg, "RAID_WARNING")
            if ok then
                return true, "RAID_WARNING"
            end
        end
        return false, "no privilege"
    end
    if route == "raid" then
        if type(SendChatMessage) ~= "function" or not msg or msg == "" then
            return false, "no chat"
        end
        local _, groupKind = CanRaidWarn()
        local chatType = groupKind == "party" and "PARTY" or "RAID"
        local ok = pcall(SendChatMessage, msg, chatType)
        if ok then
            return true, chatType
        end
        ok = pcall(SendChatMessage, msg, "YELL")
        if ok then
            return true, "YELL"
        end
        return false, "send failed"
    end
    return AutoGroupAnnounce(msg)
end

-- Solo can InviteUnit (forms a party). In a group, need lead/assist.
local function CanInviteOthers()
    local can, groupKind = CanRaidWarn()
    if can then
        return true, groupKind
    end
    if groupKind == "none" then
        return true, "none"
    end
    return false, groupKind
end

-- Peek without consuming; stamp only after a successful send.
local function RateBlocked(kind)
    kind = tostring(kind or "default")
    local now = Now()
    local last = tonumber(lastAnnounceAt[kind]) or 0
    local gap = ANNOUNCE_GAP
    if kind == "rw" then
        gap = RW_ANNOUNCE_GAP
    end
    return (now - last) < gap
end

local function RateStamp(kind)
    lastAnnounceAt[tostring(kind or "default")] = Now()
end

-- Back-compat for tests / callers that still use RateOk
local function RateOk(kind)
    if RateBlocked(kind) then
        return false
    end
    RateStamp(kind)
    return true
end

local function HostingHint()
    local db = DB()
    if db and (db.mode == "hosting" or db.fullAutoHosting) then
        return "HOST"
    end
    local mode = (db and db.mode) or "notify"
    if mode == "seeking" then
        return "SEEK"
    end
    if mode == "off" then
        return "OFF"
    end
    return "LISTEN"
end

--------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------

function MiniHUD.ActionRoster()
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Show then
        AscensionLFM.MainWindow.Show()
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.SelectCategory then
        AscensionLFM.MainWindow.SelectCategory("roster")
    end
    return true, "roster"
end

function MiniHUD.ActionReadyCheck()
    if AscensionLFM.RosterPanel and AscensionLFM.RosterPanel.DoReadyCheck then
        AscensionLFM.RosterPanel.DoReadyCheck()
        return true, "ready"
    end
    if type(DoReadyCheck) == "function" then
        pcall(DoReadyCheck)
        return true, "ready"
    end
    return false, "no ready API"
end

--- Marks current tank/healer assignments with raid target icons
-- (Skull/Cross for tanks, Square/Moon/Triangle for healers - see
-- core/RaidMarks.lua). Clears existing markers first so a reassigned
-- member doesn't keep a stale icon from an earlier mark pass.
function MiniHUD.ActionAutoMark()
    if not AscensionLFM.RaidMarks or type(AscensionLFM.RaidMarks.AutoMark) ~= "function" then
        Print("Mark: RaidMarks module missing")
        return false, "module missing"
    end
    AscensionLFM.RaidMarks.ClearAllMarks()
    local marked, skipped, err = AscensionLFM.RaidMarks.AutoMark()
    if err then
        Print("Mark: " .. tostring(err))
        return false, err
    end
    if marked == 0 and skipped == 0 then
        Print("Mark: no tanks/healers assigned yet")
        return true, 0
    end
    Print(string.format("Mark: %d marked%s", marked,
        skipped > 0 and (", " .. skipped .. " skipped (not in raid?)") or ""))
    return true, marked
end

function MiniHUD.ActionOpenSettings()
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
        local ok, err = pcall(AscensionLFM.MainWindow.Toggle)
        if not ok then
            Print("settings UI error: " .. tostring(err))
            return false, tostring(err)
        end
        return true
    end
    Print("settings UI missing - /alfm")
    return false, "no ui"
end

function MiniHUD.ActionPostLfm()
    local db = DB()
    if not AscensionLFM.Poster or not AscensionLFM.Poster.PostOnce then
        Print("LFM failed: poster missing")
        return false, "no poster"
    end
    if AscensionLFM.Poster.RefreshMessage then
        AscensionLFM.Poster.RefreshMessage()
    end
    local msg = AscensionLFM.Poster.GetMessage and AscensionLFM.Poster.GetMessage() or nil
    local ok, err = AscensionLFM.Poster.PostOnce(msg, db and db.postChannel, db and db.postChannelName)
    if not ok then
        Print("LFM failed: " .. tostring(err or "?"))
    end
    return ok, err
end

function MiniHUD.ActionRoleCheck()
    local db = DB()
    local msg
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.BuildMessage then
        msg = AscensionLFM.RoleCheck.BuildMessage(db and db.roleCheckMessage)
    else
        msg = "ROLE CHECK - whisper or party: tank/heal/aura/dps (T/H/A/D)"
    end

    -- Full listen-window when Hosting / Full Auto
    local hosting = db and (db.mode == "hosting" or db.fullAutoHosting)
    if hosting and AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.StartCheck then
        local ok, reason = AscensionLFM.RoleCheck.StartCheck()
        if ok then
            RateStamp("rw") -- share MiniHUD gap with StartCheck so spam-clicks stop
            return true, reason
        end
        -- Fall through: still yell/party the RW text (same as Wipe/Mobs UX)
        if reason == "rate limited" then
            -- Re-announce only; keep existing listen window
            if RateBlocked("rw") then
                Print("RW rate limited - wait a moment")
                return false, "rate limited"
            end
            local sent, ch = SendGroupAnnounce(msg, "rw")
            if sent then
                RateStamp("rw")
                Print("RW (re-warn) -> " .. tostring(ch))
            else
                Print("RW re-warn failed: " .. tostring(ch))
            end
            return sent, ch or reason
        end
        if reason == "no privilege" or reason == "not hosting" then
            -- announce fallback below
        else
            Print("RW blocked: " .. tostring(reason))
            return false, reason
        end
    end

    -- Not hosting, or StartCheck blocked: still send the warn like Wipe does
    if RateBlocked("rw") then
        Print("RW rate limited - wait a moment")
        return false, "rate limited"
    end
    local sent, ch = SendGroupAnnounce(msg, "rw")
    if sent then
        RateStamp("rw")
        Print("RW -> " .. tostring(ch) .. ": " .. msg)
        if not hosting then
            Print("RW listen window needs Hosting / Full Auto - warn sent anyway")
        end
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("rolecheck", "RW announce (" .. tostring(ch) .. ")")
        end
    else
        Print("RW failed: " .. tostring(ch))
    end
    return sent, ch
end

function MiniHUD.ActionResync()
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ResyncNow then
        local ok = AscensionLFM.RoleCheck.ResyncNow()
        if AscensionLFM.Slots and AscensionLFM.Slots.UnassignedMembers then
            local names, n = AscensionLFM.Slots.UnassignedMembers()
            if n and n > 0 then
                Print(string.format("Sync: %d without role - click RW (e.g. %s)", n, tostring(names[1])))
            end
        end
        return ok
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
        local _, _, unassigned = AscensionLFM.Slots.ScanRaid()
        Print("Sync: scanned raid/party roster")
        if unassigned and unassigned > 0 then
            Print(string.format("Sync: %d without role - click RW so they reply T/H/A/D", unassigned))
        end
        return true
    end
    Print("Sync failed: no resync module")
    return false, "no resync"
end

function MiniHUD.ActionWipe()
    if RateBlocked("wipe") then
        Print("Wipe rate limited - wait a moment")
        return false, "rate limited"
    end
    local db = DB()
    local msg = MiniHUD.BuildWipeMessage(db and db.wipeAnnounceMessage)
    local ok, ch = SendGroupAnnounce(msg, "wipe")
    if ok then
        RateStamp("wipe")
        Print("Wipe -> " .. tostring(ch) .. ": " .. msg)
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("wipe", msg)
        end
    else
        Print("Wipe failed: " .. tostring(ch))
    end
    return ok, ch
end

function MiniHUD.ActionShield()
    if RateBlocked("shield") then
        Print("Mobs rate limited - wait a moment")
        return false, "rate limited"
    end
    local db = DB()
    local msg = MiniHUD.BuildShieldMessage(db and db.shieldAnnounceMessage)
    local ok, ch = SendGroupAnnounce(msg, "shield")
    if ok then
        RateStamp("shield")
        Print("Mobs -> " .. tostring(ch) .. ": " .. msg)
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("shield", msg)
        end
    else
        Print("Mobs failed: " .. tostring(ch))
    end
    return ok, ch
end

local function PlayerName()
    if type(UnitName) == "function" then
        return UnitName("player")
    end
    return nil
end

local function CollectPresentSet()
    local present = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local name
            if type(GetRaidRosterInfo) == "function" then
                name = GetRaidRosterInfo(i)
            end
            if (type(name) ~= "string" or name == "") and type(UnitName) == "function" then
                name = UnitName("raid" .. i)
            end
            if type(name) == "string" and name ~= "" then
                present[LowerName(name)] = name
            end
        end
        return present
    end
    local me = PlayerName()
    if me then
        present[LowerName(me)] = me
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    for i = 1, party do
        if type(UnitName) == "function" then
            local name = UnitName("party" .. i)
            if type(name) == "string" and name ~= "" then
                present[LowerName(name)] = name
            end
        end
    end
    return present
end

--- regroupDisplay (case-preserving name lookup) has no cap of its own - it's
-- meant to mirror regroupRoster, which IS capped (FIFO evicted) at
-- REGROUP_MAX. Without pruning, every name ever seen present stays in
-- regroupDisplay forever even after RememberName evicts it from the roster
-- list, growing SavedVariables unboundedly over months of play. Call this
-- after any regroupRoster update to keep the two in sync.
local function PruneDisplayToRoster(db)
    if not db or type(db.regroupRoster) ~= "table" or type(db.regroupDisplay) ~= "table" then
        return
    end
    local keep = {}
    for _, n in ipairs(db.regroupRoster) do
        if type(n) == "string" and n ~= "" then
            keep[LowerName(n)] = true
        end
    end
    for key in pairs(db.regroupDisplay) do
        if not keep[key] then
            db.regroupDisplay[key] = nil
        end
    end
    if type(db.regroupSeenAt) == "table" then
        for key in pairs(db.regroupSeenAt) do
            if not keep[key] then
                db.regroupSeenAt[key] = nil
            end
        end
    end
    if type(db.regroupLevel) == "table" then
        for key in pairs(db.regroupLevel) do
            if not keep[key] then
                db.regroupLevel[key] = nil
            end
        end
    end
end

-- How long a name stays on the regroup watch list without being seen
-- present again. Long enough to survive a DC or a dinner break mid-raid,
-- short enough that people from an unrelated earlier raid don't linger
-- for days and get invited into today's group by mistake.
local REGROUP_STALE_SECONDS = 6 * 3600

--- Drops any regroupRoster entry not seen present within
-- REGROUP_STALE_SECONDS. This is what keeps the watch list meaning
-- "people who were actually in THIS raid" instead of an ever-growing
-- history capped only by REGROUP_MAX slots.
local function PruneStaleRegroup(db)
    if not db or type(db.regroupRoster) ~= "table" then
        return
    end
    if type(db.regroupSeenAt) ~= "table" then
        db.regroupSeenAt = {}
    end
    local now = Now()
    local kept = {}
    for _, n in ipairs(db.regroupRoster) do
        if type(n) == "string" and n ~= "" then
            local seenAt = db.regroupSeenAt[LowerName(n)]
            -- No timestamp (pre-upgrade entry) counts as stale rather than
            -- immortal, so old SavedVariables data ages out too.
            if type(seenAt) == "number" and (now - seenAt) <= REGROUP_STALE_SECONDS then
                table.insert(kept, n)
            end
        end
    end
    db.regroupRoster = kept
    PruneDisplayToRoster(db)
end

--- Regroup watch list should only ever hold people from the CURRENT
-- group, not carry over from a previous one that happened to be within
-- the staleness window. wasGrouped starts as nil (unknown - e.g. addon
-- just loaded mid-raid) on purpose: a reload while already in an ongoing
-- raid must NOT look like "just formed a new group" and wipe a list that
-- may still matter for that same raid. Only an actually OBSERVED
-- solo -> grouped transition during this session counts as "new group".
local wasGrouped = nil

local function IsCurrentlyGrouped()
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        return true
    end
    local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
    return (party or 0) > 0
end

--- Snapshot current party/raid into the regroup watch list (survives leavers).
-- Call BEFORE Slots.ScanRaid/SyncFromRoster so leavers are still known this tick
-- only via the existing watch list (present set is already without them).
function MiniHUD.RememberPresent()
    local db = DB()
    if not db then
        return 0
    end
    if type(db.regroupRoster) ~= "table" then
        db.regroupRoster = {}
    end
    if type(db.regroupDisplay) ~= "table" then
        db.regroupDisplay = {}
    end
    if type(db.regroupSeenAt) ~= "table" then
        db.regroupSeenAt = {}
    end
    if type(db.regroupLevel) ~= "table" then
        db.regroupLevel = {}
    end

    local nowGrouped = IsCurrentlyGrouped()
    if nowGrouped and wasGrouped == false then
        -- Went solo -> grouped during this session: this is a brand new
        -- group, so the watch list starts empty instead of dragging in
        -- whoever happened to still be within the staleness window from
        -- the last one.
        db.regroupRoster = {}
        db.regroupDisplay = {}
        db.regroupSeenAt = {}
        db.regroupLevel = {}
        Print("Regroup: new group started, watch list reset")
    end
    wasGrouped = nowGrouped

    -- Level lookup for the level-cap re-invite filter below (Kick.lua's
    -- own hardened UnitLevel/roster-level resolver, reused rather than
    -- duplicated).
    local levelByKey = {}
    if AscensionLFM.Kick and AscensionLFM.Kick.BuildRoster then
        for _, m in ipairs(AscensionLFM.Kick.BuildRoster()) do
            if type(m.name) == "string" and m.name ~= "" then
                levelByKey[LowerName(m.name)] = tonumber(m.level)
            end
        end
    end

    local list = db.regroupRoster
    local present = CollectPresentSet()
    local now = Now()
    local n = 0
    for key, name in pairs(present) do
        local me = PlayerName()
        if not me or key ~= LowerName(me) then
            list = MiniHUD.RememberName(list, name, REGROUP_MAX)
            db.regroupDisplay[key] = name
            db.regroupSeenAt[key] = now
            -- Only overwrite with a freshly-resolved level (> 0) - keep the
            -- last known one rather than clobbering it with "unknown" on a
            -- tick where the roster scan came up empty.
            local lvl = levelByKey[key]
            if type(lvl) == "number" and lvl > 0 then
                db.regroupLevel[key] = lvl
            end
            n = n + 1
        end
    end
    db.regroupRoster = list
    PruneStaleRegroup(db)
    return n
end

--- Remember a player for regroup (keeps original casing for InviteUnit).
function MiniHUD.RememberPlayer(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local db = DB()
    if not db then
        return false
    end
    if type(db.regroupRoster) ~= "table" then
        db.regroupRoster = {}
    end
    if type(db.regroupDisplay) ~= "table" then
        db.regroupDisplay = {}
    end
    if type(db.regroupSeenAt) ~= "table" then
        db.regroupSeenAt = {}
    end
    db.regroupRoster = MiniHUD.RememberName(db.regroupRoster, name, REGROUP_MAX)
    db.regroupDisplay[LowerName(name)] = name
    db.regroupSeenAt[LowerName(name)] = Now()
    PruneStaleRegroup(db)
    return true
end

--- Uninvites every other raid/party member (never self). Used by
-- ActionRegroup to fully tear the group down before re-inviting from a
-- fresh snapshot, instead of leaving stale slots/subgroups behind.
-- Returns the number of UninviteUnit calls that didn't error - same
-- "no error != it worked" caveat as everywhere else this addon calls
-- Uninvite/SetRaidSubgroup, so callers shouldn't treat this as a
-- guaranteed-empty group, only as "the kick calls went out".

local function DisbandGroup()
    if type(UninviteUnit) ~= "function" then
        return 0, "UninviteUnit missing"
    end
    local me = PlayerName()
    local meKey = me and LowerName(me)
    local targets = {}
    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local name
            if type(GetRaidRosterInfo) == "function" then
                name = GetRaidRosterInfo(i)
            end
            if type(name) == "string" and name ~= "" and (not meKey or LowerName(name) ~= meKey) then
                table.insert(targets, name)
            end
        end
    else
        local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
        for i = 1, party do
            if type(UnitName) == "function" then
                local name = UnitName("party" .. i)
                if type(name) == "string" and name ~= "" then
                    table.insert(targets, name)
                end
            end
        end
    end
    local n = 0
    for _, name in ipairs(targets) do
        local ok = pcall(UninviteUnit, name)
        if ok then
            n = n + 1
        end
    end
    return n
end

local REGROUP_CONFIRM_WINDOW = 6 -- seconds to click again to confirm
local regroupConfirmArmedAt = nil

--- True if this name's last-known level (from RememberPresent's snapshot)
-- is at/above the kick-level cap (db.kickLevel, default 59 - same
-- threshold Kick.lua's own auto-kick uses). Regroup's re-invite step
-- shouldn't drag level-capped players back in right after Kick59 (or a
-- host manually removing them) got rid of them. Unknown level (never
-- resolved, e.g. a name only ever seen via chat) is NOT excluded - this
-- only blocks names we actually observed at/above the cap.
local function IsLevelCapped(db, key)
    if not db or type(db.regroupLevel) ~= "table" then
        return false
    end
    local lvl = tonumber(db.regroupLevel[key])
    if not lvl then
        return false
    end
    local cap = (AscensionLFM.Kick and tonumber(db.kickLevel or AscensionLFM.Kick.DEFAULT_LEVEL)) or 59
    return lvl >= cap
end

--- Full regroup: warn -> disband the whole current group -> re-invite
-- everyone from a freshly pruned snapshot (people actually seen in THIS
-- raid within REGROUP_STALE_SECONDS, not old names from an unrelated
-- earlier raid). This is destructive - it kicks the entire group,
-- including people currently present - so it requires two clicks: the
-- first prints exactly what would happen and arms a confirm window, the
-- second (within REGROUP_CONFIRM_WINDOW seconds) actually does it. Only
-- the confirmed click sends the warning, disbands, or invites - a single
-- misclick on the button no longer kicks the raid.
function MiniHUD.ActionRegroup()
    if RateBlocked("regroup") then
        Print("Regrp rate limited - wait a moment")
        return false, "rate limited"
    end
    -- Snapshot BEFORE disbanding: this is the only chance to see who was
    -- actually present this tick, and it also ages out stale entries
    -- from earlier, unrelated raids (PruneStaleRegroup runs inside it).
    MiniHUD.RememberPresent()
    local db = DB()
    local roster = (db and db.regroupRoster) or {}
    local display = (db and db.regroupDisplay) or {}

    -- Snapshot each member's assigned role BEFORE disbanding. Without this,
    -- Slots.SyncFromRoster() (fired by the very roster-update events
    -- DisbandGroup()'s UninviteUnit calls trigger) sees everyone as "not
    -- present" mid-regroup and drops their db.assignedRoles entry entirely -
    -- so a full Tank/Heal/Aura roster comes back from a regroup with every
    -- role forgotten. Restored below via Slots.Assign() (not a raw table
    -- write) specifically so it also refreshes each name's
    -- RecentlyAssigned grace timestamp - the same protection
    -- SyncFromRoster already gives a freshly-invited applicant - covering
    -- the gap between "re-invited" and "actually back in the roster".
    local savedRoles = {}
    if AscensionLFM.Slots and AscensionLFM.Slots.GetAssigned then
        for _, name in ipairs(roster) do
            local role = AscensionLFM.Slots.GetAssigned(name)
            if role then
                savedRoles[LowerName(name)] = role
            end
        end
    end

    local canInvite, invKind = CanInviteOthers()
    if not canInvite then
        -- No disband/invite to gate behind a confirm - this click can
        -- only ever warn, so just send it, same as before the confirm
        -- step existed. Someone with raid-warn but not assign/invite
        -- rights can still rally the raid to regroup manually.
        regroupConfirmArmedAt = nil
        local msg = MiniHUD.BuildRegroupMessage(db and db.regroupAnnounceMessage)
        local ok, ch = SendGroupAnnounce(msg, "regroup")
        if ok then
            RateStamp("regroup")
            Print("Regroup -> " .. tostring(ch) .. ": " .. msg)
            if AscensionLFM.Activity and AscensionLFM.Activity.Push then
                AscensionLFM.Activity.Push("regroup", msg)
            end
        else
            Print("Regroup warn failed: " .. tostring(ch))
        end
        Print("Regroup: need lead/assist to disband/re-invite (warn still sent)")
        if ok then
            return true, 0
        end
        return false, "no invite privilege"
    end
    if #roster == 0 then
        Print("Regroup: watch list empty - group up first so names are remembered")
        regroupConfirmArmedAt = nil
        return true, 0
    end

    local now = Now()
    local isConfirming = regroupConfirmArmedAt and (now - regroupConfirmArmedAt) < REGROUP_CONFIRM_WINDOW
    if not isConfirming then
        regroupConfirmArmedAt = now
        local meKey = LowerName(PlayerName() or "")
        local n, capped = 0, 0
        for _, name in ipairs(roster) do
            local key = LowerName(name)
            if meKey == "" or key ~= meKey then
                if IsLevelCapped(db, key) then
                    capped = capped + 1
                else
                    n = n + 1
                end
            end
        end
        n = math.min(n, REGROUP_INVITE_CAP)
        Print(string.format(
            "Regroup: will disband the group and re-invite %d%s - click Regrp again within %ds to confirm",
            n, capped > 0 and (" (" .. capped .. " skipped, level-capped)") or "", REGROUP_CONFIRM_WINDOW))
        return true, 0
    end
    regroupConfirmArmedAt = nil

    -- Confirmed: warn, then disband + re-invite.
    local msg = MiniHUD.BuildRegroupMessage(db and db.regroupAnnounceMessage)
    local ok, ch = SendGroupAnnounce(msg, "regroup")
    if ok then
        RateStamp("regroup")
        Print("Regroup -> " .. tostring(ch) .. ": " .. msg)
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("regroup", msg)
        end
    else
        Print("Regroup warn failed: " .. tostring(ch))
    end

    if type(InviteUnit) ~= "function" then
        Print("Regroup: InviteUnit missing")
        return false, "InviteUnit missing"
    end

    local kicked = DisbandGroup()
    if kicked > 0 then
        Print("Regroup: disbanded " .. tostring(kicked) .. " member(s), re-inviting fresh...")
    end

    -- Group is (meant to be) empty now, so everyone on the fresh roster
    -- gets invited fresh - no "already present" filtering needed like the
    -- old invite-only flow had.
    --
    -- IMPORTANT: this whole block must run synchronously, inside this
    -- same click handler - InviteUnit/UninviteUnit/ConvertToRaid are
    -- protected-adjacent APIs that WoW's secure-execution model only
    -- allows when called directly in response to a real hardware event.
    -- An earlier version of this paced re-invites out one per MiniHUD
    -- ticker tick; that got blocked in practice ("prevented the call of
    -- the secure function 'UNKNOWN()'") because OnUpdate isn't a hardware
    -- event. Raw InviteUnit (not Invite.InvitePlayer) is used here on
    -- purpose too - InvitePlayer's per-name/global cooldown exists to
    -- stop invite spam from chat parsing, not to throttle a deliberate
    -- one-off admin bulk-reinvite, and pacing it out to respect that
    -- cooldown is exactly what broke the secure-call requirement above.
    --
    -- Explicitly convert to raid BEFORE inviting if the fresh roster needs
    -- raid-scale capacity: DisbandGroup() just dropped the group back to
    -- solo, and InviteUnit from solo only ever forms a plain 5-person
    -- party. Without this, invite #5+ would silently fail to join at all.
    local cap = REGROUP_INVITE_CAP
    local toInvite = {}
    local skippedCapped = {}
    local meKey = LowerName(PlayerName() or "")
    for i, name in ipairs(roster) do
        if #toInvite >= cap then
            break
        end
        local key = LowerName(name)
        -- Defensive: never invite yourself, even if the persisted roster
        -- somehow contains your own name (RememberPresent won't add it,
        -- but old SavedVariables data or a manual edit could).
        if meKey == "" or key ~= meKey then
            if IsLevelCapped(db, key) then
                table.insert(skippedCapped, display[key] or name)
            else
                table.insert(toInvite, display[key] or name)
            end
        end
    end
    if #skippedCapped > 0 then
        Print("Regroup: not re-inviting (level-capped): " .. table.concat(skippedCapped, ", "))
    end
    if #toInvite > 4 and type(GetNumRaidMembers) == "function"
        and (GetNumRaidMembers() or 0) == 0 and type(ConvertToRaid) == "function" then
        pcall(ConvertToRaid)
    end

    local invited, failed = 0, 0
    -- Fire each invite REGROUP_INVITE_ATTEMPTS times back-to-back, all
    -- still synchronously inside this same click - a spread-out retry
    -- (waiting between attempts to see if the first landed) would need a
    -- timer/OnUpdate, which is exactly what triggered the "prevented the
    -- call of the secure function" block earlier this session. A tight
    -- burst has no such delay, so it stays inside WoW's requirement that
    -- these calls happen synchronously in the click's call stack.
    -- InviteUnit on someone already-invited just re-sends/refreshes their
    -- popup, so repeating it is harmless, not spammy toward them.
    for _, inviteName in ipairs(toInvite) do
        local anySuccess = false
        for attempt = 1, REGROUP_INVITE_ATTEMPTS do
            local success = pcall(InviteUnit, inviteName)
            if success then
                anySuccess = true
            end
        end
        if anySuccess then
            invited = invited + 1
        else
            failed = failed + 1
        end
    end

    -- Restore each re-invited member's role now that invites are out -
    -- see the savedRoles comment above. Only for people actually being
    -- re-invited (never for a level-capped name we deliberately skipped).
    if AscensionLFM.Slots and AscensionLFM.Slots.Assign then
        for _, name in ipairs(toInvite) do
            local role = savedRoles[LowerName(name)]
            if role then
                AscensionLFM.Slots.Assign(name, role)
            end
        end
    end

    if invited > 0 then
        Print(string.format("Regroup: re-invited %d (privilege=%s)%s", invited, tostring(invKind),
            #roster > cap and (" - " .. tostring(#roster - cap) .. " more queued, click Regroup again") or ""))
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("regroup", "disbanded+invited " .. tostring(invited))
        end
    elseif failed > 0 then
        Print("Regroup: all re-invites failed")
    end
    if ok or invited > 0 then
        return true, invited
    end
    return false, tostring(ch or "warn failed")
end

function MiniHUD.ActionFull()
    if RateBlocked("full") then
        Print("FULL rate limited - wait a moment")
        return false, "rate limited"
    end
    local db = DB()
    local msg = tostring((db and db.fullAnnounceMessage) or "LFM MS FULL - thanks!")
    local channel = (db and db.postChannel) or "YELL"
    if AscensionLFM.Poster and AscensionLFM.Poster.PostOnce then
        local sent, err = AscensionLFM.Poster.PostOnce(msg, channel, db and db.postChannelName, nil, true)
        if sent then
            RateStamp("full")
        else
            Print("FULL failed: " .. tostring(err))
        end
        return sent, err or channel
    end
    local sent, ch = SendGroupAnnounce(msg, "full")
    if sent then
        RateStamp("full")
        Print("FULL -> " .. tostring(ch) .. ": " .. msg)
    else
        Print("FULL failed: " .. tostring(ch))
    end
    return sent, ch
end

function MiniHUD.ActionNeed(role)
    local kind = "need:" .. tostring(role or "")
    if RateBlocked(kind) then
        Print("Need rate limited - wait a moment")
        return false, "rate limited"
    end
    local msg = MiniHUD.BuildNeedMessage(role)
    if not msg then
        Print("Need failed: bad role")
        return false, "bad role"
    end
    local db = DB()
    local channel = (db and db.postChannel) or "YELL"
    if AscensionLFM.Poster and AscensionLFM.Poster.PostOnce then
        local sent, err = AscensionLFM.Poster.PostOnce(msg, channel, db and db.postChannelName, nil, true)
        if sent then
            RateStamp(kind)
        else
            Print("Need failed: " .. tostring(err))
        end
        return sent, err or channel
    end
    local sent, ch = SendGroupAnnounce(msg, "need")
    if sent then
        RateStamp(kind)
        Print("Need -> " .. tostring(ch) .. ": " .. msg)
    else
        Print("Need failed: " .. tostring(ch))
    end
    return sent, ch
end

function MiniHUD.ActionClearRoles()
    if AscensionLFM.Slots and AscensionLFM.Slots.ClearAll then
        AscensionLFM.Slots.ClearAll()
        Print("cleared role assignments")
        if AscensionLFM.MainWindow then
            if AscensionLFM.MainWindow.RefreshSlots then
                AscensionLFM.MainWindow.RefreshSlots()
            end
            if AscensionLFM.MainWindow.RefreshPost then
                AscensionLFM.MainWindow.RefreshPost()
            end
        end
        MiniHUD.Refresh()
        return true
    end
    return false, "no slots"
end

--------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------

local function SavePosition()
    local db = DB()
    if not db or not frame then
        return
    end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    db.miniHudPoint = point or "CENTER"
    db.miniHudRelPoint = relPoint or "CENTER"
    db.miniHudX = x or 0
    db.miniHudY = y or 180
end

local function ApplyPosition()
    if not frame then
        return
    end
    local db = DB()
    frame:ClearAllPoints()
    local point = (db and db.miniHudPoint) or "CENTER"
    local rel = (db and db.miniHudRelPoint) or "CENTER"
    local x = (db and tonumber(db.miniHudX)) or 0
    local y = (db and tonumber(db.miniHudY)) or 180
    frame:SetPoint(point, UIParent, rel, x, y)
end

local function SetExpanded(on)
    expanded = on and true or false
    local db = DB()
    if db then
        db.miniHudExpanded = expanded
    end
    if not frame then
        return
    end
    if expanded then
        frame:SetWidth(440)
        frame:SetHeight(100)
        if frame.titleFS then
            frame.titleFS:SetText("AscensionLFM")
            frame.titleFS:Show()
        end
        if frame.chipFS then
            frame.chipFS:Show()
        end
        if frame.collapsedIconTex then
            frame.collapsedIconTex:Hide()
        end
        for _, b in pairs(buttons) do
            if b and b.Show then
                b:Show()
            end
        end
        if frame.collapseBtn then
            frame.collapseBtn:SetText("x")
            frame.collapseBtn:Show()
        end
        if statusFS then
            statusFS:Show()
        end
        if frame.chromeBorderPieces then
            for _, piece in ipairs(frame.chromeBorderPieces) do
                if piece.Show then piece:Show() end
            end
        end
        if frame.hitBtn then
            frame.hitBtn:SetSize(120, 18)
        end
    else
        frame:SetWidth(56)
        frame:SetHeight(28)
        -- Icon instead of the abbreviated "ALFM" text label - hide
        -- both text elements, show just the leader-icon texture.
        if frame.titleFS then
            frame.titleFS:Hide()
        end
        if frame.chipFS then
            frame.chipFS:Hide()
        end
        if frame.collapsedIconTex then
            frame.collapsedIconTex:Show()
        end
        for _, b in pairs(buttons) do
            if b and b.Hide then
                b:Hide()
            end
        end
        if frame.collapseBtn then
            frame.collapseBtn:Hide()
        end
        if statusFS then
            statusFS:Hide()
        end
        if frame.chromeBorderPieces then
            for _, piece in ipairs(frame.chromeBorderPieces) do
                if piece.Hide then piece:Hide() end
            end
        end
        if frame.hitBtn then
            -- Collapsed frame is only 56px wide - keep the click-catcher
            -- inside its visible bounds instead of the expanded 120px width.
            frame.hitBtn:SetSize(48, 18)
        end
    end
    MiniHUD.Refresh()
end

local function MakeBtn(parent, label, width, onClick, danger, tooltipFn)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(btn) end
    btn:SetSize(width or 40, 20)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        local okCall, ok, err = pcall(onClick)
        if not okCall then
            if AscensionLFM.Print then
                AscensionLFM.Print("MiniHUD " .. tostring(label) .. " error: " .. tostring(ok))
            end
            MiniHUD.Refresh()
            return
        end
        -- Actions Print their own success/fail; surface remaining silent failures
        if ok ~= true and AscensionLFM.Print then
            local e = err and tostring(err) or "failed"
            if e ~= "rate limited" and e ~= "no privilege" and e ~= "not hosting" then
                AscensionLFM.Print("MiniHUD " .. tostring(label) .. ": " .. e)
            end
        end
        MiniHUD.Refresh()
    end)
    if danger and btn.GetFontString then
        local fs = btn:GetFontString()
        if fs and fs.SetTextColor then
            fs:SetTextColor(1, 0.55, 0.45)
        end
    end
    if type(tooltipFn) == "function" then
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local ok, lines = pcall(tooltipFn)
            if ok and type(lines) == "table" then
                for i, line in ipairs(lines) do
                    if i == 1 then
                        GameTooltip:SetText(line, 1, 0.82, 0.24)
                    else
                        GameTooltip:AddLine(line, 0.85, 0.8, 0.7, true)
                    end
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    return btn
end

local function BuildFrame()
    if frame or type(CreateFrame) ~= "function" then
        return frame
    end
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetWidth(440)
    -- 86 wasn't tall enough for both button rows plus statusFS at the
    -- bottom: row 2's buttons (y -53 to -73) overlapped statusFS's top
    -- edge (86-21=65) by 8px - the two button rows plus the status line
    -- simply don't fit in 86px of height no matter how the internal gaps
    -- are tuned (confirmed via exact arithmetic this session). 100 gives
    -- real clearance.
    f:SetHeight(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- DragonUI chrome via shared helper (ui/Chrome.lua). Compact profile
    -- scaled for this HUD's ~86px height. chromeBorderPieces is stored so
    -- SetExpanded() can hide the fixed-size border textures on collapse
    -- (collapsed frame is 56x28; 30x30 corners would overflow).
    local borderPieces = AscensionLFM.Chrome and AscensionLFM.Chrome.ApplyMetalChrome(f, "compact")
    f.chromeBorderPieces = borderPieces or {}

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("AscensionLFM")
    title:SetTextColor(1, 0.82, 0.24)
    f.titleFS = title

    local chip = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip:SetPoint("LEFT", title, "RIGHT", 8, 0)
    chip:SetText("HOST")
    chip:SetTextColor(0.92, 0.84, 0.50)
    f.chipFS = chip

    -- Collapsed-state icon shown instead of the abbreviated "ALFM" text
    -- label when collapsed - hidden while expanded, where the full
    -- title/chip text is shown instead. Was the generic raid-leader
    -- crown; now Ascension's own Manastorm queue window's portrait icon
    -- (confirmed via extracted client source, Ascension_Manastorm/
    -- ManastormQueue.lua) - matches ui/MinimapButton.lua's icon too, so
    -- both of this addon's minimap-adjacent icons are consistent.
    local collapsedIcon = f:CreateTexture(nil, "OVERLAY")
    collapsedIcon:SetTexture("Interface\\LFGFrame\\lfgicon-arcanevaults")
    collapsedIcon:SetSize(18, 18)
    collapsedIcon:SetPoint("LEFT", f, "LEFT", 8, 0)
    collapsedIcon:Hide()
    f.collapsedIconTex = collapsedIcon

    -- Click brand / collapsed chip -> settings (expanded) or expand (collapsed)
    local hit = CreateFrame("Button", nil, f)
    hit:SetPoint("TOPLEFT", 4, -2)
    hit:SetSize(120, 18)
    f.hitBtn = hit
    hit:SetScript("OnClick", function()
        if not expanded then
            SetExpanded(true)
            return
        end
        MiniHUD.ActionOpenSettings()
    end)

    local collapse = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(collapse) end
    collapse:SetSize(20, 18)
    collapse:SetPoint("TOPRIGHT", -4, -4)
    collapse:SetText("x")
    collapse:SetScript("OnClick", function()
        SetExpanded(false)
    end)
    f.collapseBtn = collapse

    local y = -28
    local x = 6
    local function place(btn)
        btn:SetPoint("TOPLEFT", x, y)
        x = x + (btn:GetWidth() or 40) + 4
    end
    local function newRow()
        y = y - 25
        x = 6
    end

    buttons.lfm = MakeBtn(f, "LFM", 42, function()
        return MiniHUD.ActionPostLfm()
    end)
    place(buttons.lfm)

    buttons.rw = MakeBtn(f, "RW", 36, function()
        return MiniHUD.ActionRoleCheck()
    end)
    place(buttons.rw)

    buttons.sync = MakeBtn(f, "Sync", 42, function()
        return MiniHUD.ActionResync()
    end)
    place(buttons.sync)

    buttons.wipe = MakeBtn(f, "Wipe", 44, function()
        return MiniHUD.ActionWipe()
    end, true)
    place(buttons.wipe)

    buttons.mobs = MakeBtn(f, "Mobs", 50, function()
        return MiniHUD.ActionShield()
    end, true)
    place(buttons.mobs)

    buttons.full = MakeBtn(f, "FULL", 46, function()
        return MiniHUD.ActionFull()
    end)
    place(buttons.full)

    buttons.regrp = MakeBtn(f, "Regrp", 52, function()
        return MiniHUD.ActionRegroup()
    end, false, function()
        local db = DB()
        local roster = (db and db.regroupRoster) or {}
        return {
            "Regroup",
            "Disbands the whole group and re-invites everyone on the watch list ("
                .. #roster .. " remembered).",
            "Click twice within " .. REGROUP_CONFIRM_WINDOW .. "s to confirm - the first click only previews it.",
        }
    end)
    place(buttons.regrp)

    newRow()

    buttons.t = MakeBtn(f, "T", 24, function()
        return MiniHUD.ActionNeed("tank")
    end)
    place(buttons.t)

    buttons.h = MakeBtn(f, "H", 24, function()
        return MiniHUD.ActionNeed("healer")
    end)
    place(buttons.h)

    buttons.a = MakeBtn(f, "A", 24, function()
        return MiniHUD.ActionNeed("aura")
    end)
    place(buttons.a)

    buttons.d = MakeBtn(f, "D", 24, function()
        return MiniHUD.ActionNeed("dps")
    end)
    place(buttons.d)

    buttons.rost = MakeBtn(f, "Rost", 40, function()
        return MiniHUD.ActionRoster()
    end)
    place(buttons.rost)

    buttons.ready = MakeBtn(f, "RC", 28, function()
        return MiniHUD.ActionReadyCheck()
    end)
    place(buttons.ready)

    buttons.mark = MakeBtn(f, "Mark", 44, function()
        return MiniHUD.ActionAutoMark()
    end)
    place(buttons.mark)

    statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    -- Pushed further in than the original 8px: the DragonUI bottom
    -- corner chrome pieces (16x16, positioned slightly outside the
    -- frame edge) occupy roughly the first ~10px near each bottom
    -- corner, both horizontally and vertically - 8px wasn't enough
    -- clearance and the text visibly overlapped the corner art
    -- (confirmed via a live screenshot this session).
    statusFS:SetPoint("BOTTOMLEFT", 18, 5)
    statusFS:SetPoint("BOTTOMRIGHT", -18, 5)
    statusFS:SetJustifyH("LEFT")
    if statusFS.SetHeight then statusFS:SetHeight(16) end
    if statusFS.SetWordWrap then statusFS:SetWordWrap(false) end
    statusFS:SetText("T-/H-/A-/D-")
    statusFS:SetTextColor(0.85, 0.78, 0.55)

    frame = f
    ApplyPosition()
    local db = DB()
    local wantExpand = not (db and db.miniHudExpanded == false)
    SetExpanded(wantExpand)
    -- Periodic slot-line refresh while visible
    local acc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + (elapsed or 0)
        if acc < 1.5 then
            return
        end
        acc = 0
        if expanded and statusFS then
            MiniHUD.Refresh()
        end
    end)
    MiniHUD.Refresh()
    return frame
end

--- Pure: compact slot line for the Mini HUD footer (T 2/2 H 1/3 A 2/3 D 7/7).
function MiniHUD.BuildSlotLine(snapshot)
    snapshot = snapshot or {}
    local order = { "tank", "healer", "aura", "dps" }
    local short = { tank = "T", healer = "H", aura = "A", dps = "D" }
    local parts = {}
    for _, role in ipairs(order) do
        local s = snapshot[role]
        local filled = 0
        local max = 0
        if type(s) == "table" then
            filled = tonumber(s.filled) or 0
            max = tonumber(s.max) or 0
        end
        if max > 0 then
            table.insert(parts, string.format("%s %d/%d", short[role], filled, max))
        end
    end
    if #parts == 0 then
        return "slots off"
    end
    return table.concat(parts, "  ")
end

function MiniHUD.Refresh()
    if not frame then
        return
    end
    if frame.chipFS then
        frame.chipFS:SetText(HostingHint())
    end
    if statusFS then
        local snap = nil
        if AscensionLFM.Slots and AscensionLFM.Slots.Snapshot then
            snap = AscensionLFM.Slots.Snapshot()
        end
        local line = MiniHUD.BuildSlotLine(snap)
        statusFS:SetText(line)
        statusFS:SetTextColor(0.85, 0.75, 0.45)
    end
    local db = DB()
    if db and db.miniHudShow == false then
        frame:Hide()
    else
        frame:Show()
    end
end

function MiniHUD.SetShown(on)
    local db = DB()
    if db then
        db.miniHudShow = on and true or false
    end
    if on then
        MiniHUD.Ensure()
        if frame then
            frame:Show()
            local wantExpand = not (db and db.miniHudExpanded == false)
            SetExpanded(wantExpand)
        end
    elseif frame then
        frame:Hide()
    end
end

function MiniHUD.IsShown()
    return frame and frame:IsShown() and true or false
end

function MiniHUD.GetFrame()
    return frame
end

function MiniHUD.Ensure()
    if frame then
        MiniHUD.Refresh()
        return frame
    end
    BuildFrame()
    MiniHUD.Refresh()
    return frame
end

function MiniHUD.Start()
    local db = DB()
    if db and db.miniHudShow == false then
        return
    end
    MiniHUD.Ensure()
    MiniHUD.RememberPresent()
end

function MiniHUD._ResetForTests()
    lastAnnounceAt = {}
    expanded = true
    regroupConfirmArmedAt = nil
end

--- Live debug snapshot for /alfm status (and tests).
function MiniHUD.GetDebugStatus()
    local db = DB()
    local can, groupKind = CanRaidWarn()
    local canInv = CanInviteOthers()
    local watch = (db and type(db.regroupRoster) == "table" and #db.regroupRoster) or 0
    local hosting = db and (db.mode == "hosting" or db.fullAutoHosting) and true or false
    return {
        shown = MiniHUD.IsShown and MiniHUD.IsShown() or false,
        expanded = expanded and true or false,
        mode = (db and db.mode) or "?",
        hosting = hosting,
        canWarn = can and true or false,
        group = groupKind or "none",
        canInvite = canInv and true or false,
        watch = watch,
        postChannel = (db and db.postChannel) or "YELL",
    }
end

MiniHUD.DEFAULT_WIPE = DEFAULT_WIPE
MiniHUD.DEFAULT_SHIELD = DEFAULT_SHIELD
MiniHUD.DEFAULT_REGROUP = DEFAULT_REGROUP
MiniHUD.ANNOUNCE_GAP = ANNOUNCE_GAP
MiniHUD.REGROUP_MAX = REGROUP_MAX
MiniHUD.REGROUP_INVITE_CAP = REGROUP_INVITE_CAP
MiniHUD.REGROUP_INVITE_ATTEMPTS = REGROUP_INVITE_ATTEMPTS
-- Test hooks
MiniHUD._RateBlocked = RateBlocked
MiniHUD._RateStamp = RateStamp
MiniHUD._SendGroupAnnounce = SendGroupAnnounce
MiniHUD._CanInviteOthers = CanInviteOthers
MiniHUD._SetExpanded = SetExpanded
MiniHUD._GetFrame = function() return frame end
MiniHUD._IsCurrentlyGrouped = IsCurrentlyGrouped
MiniHUD._ResetGroupTrackingForTests = function() wasGrouped = nil end

-- ============================================================================
-- Diagnostic: /alfmhuddebug
-- ============================================================================
-- Atlas identification lives in ui/Chrome.lua (shared with MainWindow).
local function IdentifyPiece(tex, left, right, top, bottom)
    if AscensionLFM.Chrome and AscensionLFM.Chrome.IdentifyPiece then
        return AscensionLFM.Chrome.IdentifyPiece(tex, left, right, top, bottom)
    end
    return nil
end

SLASH_ALFMHUDDEBUG1 = "/alfmhuddebug"
if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMHUDDEBUG"] = function()
    if type(frame) ~= "table" or not frame.GetRegions then
        print("AscensionLFM: MiniHUD frame isn't built yet - open it first.")
        return
    end

    print("AscensionLFM MiniHUD debug:")
    print(string.format("  Frame size: %.0f x %.0f", frame:GetWidth(), frame:GetHeight()))

    local i = 0
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            i = i + 1
            local tex = region.GetTexture and region:GetTexture()
            local w, h = region:GetWidth(), region:GetHeight()
            local okPoint, rPoint, rRel, rRelPoint, rX, rY = pcall(region.GetPoint, region, 1)
            local shown = (region.IsShown and region:IsShown()) and " shown" or " hidden"

            local coordLine, identified = "", ""
            if region.GetTexCoord then
                local okC, v1, v2, v3, v4, v5 = pcall(region.GetTexCoord, region)
                if okC and v1 then
                    local l, r, t, b
                    if v5 == nil then
                        l, r, t, b = v1, v2, v3, v4
                    else
                        l, r, t, b = v1, v5, v2, v4
                    end
                    coordLine = string.format("  texcoord=%.6f,%.6f,%.6f,%.6f", l or 0, r or 0, t or 0, b or 0)
                    local name = IdentifyPiece(tex, l, r, t, b)
                    if name then identified = "  -> " .. name end
                end
            end

            if okPoint then
                print(string.format("  [%d] %.0fx%.0f%s  point=%s rel=%s,%s off=%.0f,%.0f  tex=%s%s%s",
                    i, w or 0, h or 0, shown,
                    rPoint or "?", rRel and (rRel.GetName and rRel:GetName() or "?") or "?", rRelPoint or "?",
                    rX or 0, rY or 0, tostring(tex), coordLine, identified))
            else
                print(string.format("  [%d] %.0fx%.0f%s  (no point)  tex=%s%s%s", i, w or 0, h or 0, shown, tostring(tex), coordLine, identified))
            end
        end
    end
    print(string.format("  Total texture regions: %d", i))
    print("Copy this output (or a screenshot of the HUD) back for a more precise pass.")
    end
end

