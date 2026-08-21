-- AscensionLFM MiniHUD pure helpers + action smoke tests.
package.path = "./?.lua;./core/?.lua;./ui/?.lua;" .. (package.path or "")

_G.AscensionLFM = nil
_G.AscensionLFMDB = nil
_G.GetTime = function() return 1000 end
_G.CreateFrame = function(kind, name, parent, template)
    local f = {
        _points = {},
        _shown = true,
        _w = 0,
        _h = 0,
        SetFrameStrata = function() end,
        SetWidth = function(self, w) self._w = w end,
        SetHeight = function(self, h) self._h = h end,
        SetSize = function(self, w, h) self._w = w; self._h = h end,
        GetWidth = function(self) return self._w end,
        GetHeight = function(self) return self._h end,
        SetMovable = function() end,
        EnableMouse = function() end,
        RegisterForDrag = function() end,
        SetClampedToScreen = function() end,
        SetScript = function() end,
        SetPoint = function(self, ...) table.insert(self._points, { ... }) end,
        SetAllPoints = function(self) end,
        ClearAllPoints = function(self) self._points = {} end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 180 end,
        SetFrameLevel = function(self, lvl) self._level = lvl end,
        GetFrameLevel = function(self) return self._level or 0 end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        HookScript = function() end,
        SetNormalTexture = function() end,
        SetPushedTexture = function() end,
        SetDisabledTexture = function() end,
        GetHighlightTexture = function() return nil end,
        CreateTexture = function()
            local tex = {
                SetAllPoints = function() end,
                SetPoint = function() end,
                SetTexture = function() end,
                SetVertexColor = function() end,
                SetAlpha = function() end,
                SetSize = function() end,
                SetTexCoord = function() end,
                SetWidth = function() end,
                SetHeight = function() end,
                GetWidth = function() return 0 end,
                GetHeight = function() return 0 end,
                GetPoint = function() return nil end,
                GetObjectType = function() return "Texture" end,
                GetTexture = function() return nil end,
                _shown = true,
            }
            tex.IsShown = function(self) return self._shown end
            tex.Show = function(self) self._shown = true end
            tex.Hide = function(self) self._shown = false end
            return tex
        end,
        CreateFontString = function()
            local fs = {
                SetPoint = function() end,
                SetTextColor = function() end,
                SetJustifyH = function() end,
                _shown = true,
            }
            fs.SetText = function(self, t) self._text = t end
            fs.GetText = function(self) return self._text end
            fs.Show = function(self) self._shown = true end
            fs.Hide = function(self) self._shown = false end
            fs.IsShown = function(self) return self._shown end
            return fs
        end,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        SetText = function(self, t) self._text = t end,
        GetFontString = function() return nil end,
        GetRegions = function() return end,
    }
    return f
end
_G.UIParent = {}
_G.SendChatMessage = function(msg, ch)
    table.insert(_G._chats or {}, { msg = msg, ch = ch })
end

dofile("core/Database.lua")
dofile("core/Kick.lua")
dofile("core/Slots.lua")
dofile("core/Poster.lua")
dofile("ui/Chrome.lua")
dofile("ui/MiniHUD.lua")
-- Chrome.HasDragonUI() caches its result after the first check, so this
-- must be set before ANYTHING that could trigger chrome application
-- (MiniHUD.Ensure() below) - these tests assert on the DragonUI metal
-- nineslice path specifically (8 pieces), not the classic fallback.
_G.IsAddOnLoaded = function(name) return name == "DragonUI" end

AscensionLFM.Database.Init()
local MiniHUD = assert(AscensionLFM.MiniHUD)

local failed, passed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

--- Regroup fires each invite REGROUP_INVITE_ATTEMPTS times (retry burst,
-- see 0.4.101), so raw call-list length is an implementation detail -
-- count distinct names actually targeted instead.
local function uniqueCount(list)
    local seen, n = {}, 0
    for _, v in ipairs(list) do
        local key = tostring(v):lower()
        if not seen[key] then
            seen[key] = true
            n = n + 1
        end
    end
    return n
end

check("need tank", MiniHUD.BuildNeedMessage("tank") == "LFM MS need Tank")
check("need healer", MiniHUD.BuildNeedMessage("healer") == "LFM MS need Healer")
check("need aura", MiniHUD.BuildNeedMessage("aura") == "LFM MS need Aura")
check("need dps", MiniHUD.BuildNeedMessage("dps") == "LFM MS need DPS")
check("need bad nil", MiniHUD.BuildNeedMessage("x") == nil)

check("wipe default", MiniHUD.BuildWipeMessage(nil) == "WIPE")
check("wipe custom", MiniHUD.BuildWipeMessage("  WIPE NOW  ") == "WIPE NOW")
check("wipe truncate", #MiniHUD.BuildWipeMessage(string.rep("W", 300)) == 255)

check("shield default", MiniHUD.BuildShieldMessage(nil) == MiniHUD.DEFAULT_SHIELD)
check("shield custom", MiniHUD.BuildShieldMessage("  KILL ADDS  ") == "KILL ADDS")
check("shield has mobs", tostring(MiniHUD.DEFAULT_SHIELD):find("MOBS", 1, true) ~= nil)
check("shield has shield", tostring(MiniHUD.DEFAULT_SHIELD):lower():find("shield", 1, true) ~= nil)

check("regroup default", MiniHUD.BuildRegroupMessage(nil) == MiniHUD.DEFAULT_REGROUP)
check("regroup custom", MiniHUD.BuildRegroupMessage("  REGROUP NOW  ") == "REGROUP NOW")

local list = MiniHUD.RememberName({}, "Alice", 3)
list = MiniHUD.RememberName(list, "Bob", 3)
list = MiniHUD.RememberName(list, "Alice", 3) -- move to end, unique
check("remember unique", #list == 2 and list[2] == "Alice")
list = MiniHUD.RememberName(list, "Carl", 3)
list = MiniHUD.RememberName(list, "Dana", 3)
check("remember trims", #list == 3 and list[1] == "Alice")

local missing = MiniHUD.SelectMissing({ "Alice", "Bob", "Host" }, { alice = true }, "Host", 10)
check("select missing bob", #missing == 1 and missing[1] == "Bob")
check("select skips present+self", true)

check("default miniHudShow on", AscensionLFM.Database.Get().miniHudShow == true)
check("default wipe msg", AscensionLFM.Database.Get().wipeAnnounceMessage == "WIPE")
check("default shield msg", AscensionLFM.Database.Get().shieldAnnounceMessage == MiniHUD.DEFAULT_SHIELD)
check("default regroup msg", AscensionLFM.Database.Get().regroupAnnounceMessage == MiniHUD.DEFAULT_REGROUP)

-- Action wipe with stubs
MiniHUD._ResetForTests()
_G._chats = {}
_G.GetNumRaidMembers = function() return 2 end
_G.GetNumPartyMembers = function() return 0 end
_G.IsRaidLeader = function() return true end
_G.IsRaidOfficer = function() return false end
_G.UnitIsPartyLeader = function() return true end
AscensionLFM.RoleCheck = AscensionLFM.RoleCheck or {}
AscensionLFM.RoleCheck.CanRaidWarn = function() return true, "raid" end

local ok, ch = MiniHUD.ActionWipe()
check("wipe sends", ok == true, tostring(ok) .. "/" .. tostring(ch))
check("wipe RW channel", _G._chats[1] and _G._chats[1].ch == "RAID_WARNING")
check("wipe text", _G._chats[1] and _G._chats[1].msg == "WIPE")

ok = MiniHUD.ActionWipe()
check("wipe rate limited", ok == false)

MiniHUD._ResetForTests()
_G._chats = {}
ok, ch = MiniHUD.ActionShield()
check("shield sends", ok == true, tostring(ok) .. "/" .. tostring(ch))
check("shield text", _G._chats[1] and tostring(_G._chats[1].msg):find("MOBS", 1, true) ~= nil)
check("shield mentions shield", _G._chats[1] and tostring(_G._chats[1].msg):lower():find("shield", 1, true) ~= nil)

-- Regroup: announce + invite missing
MiniHUD._ResetForTests()
_G._chats = {}
local invited = {}
_G.InviteUnit = function(name) table.insert(invited, name) end
_G.GetNumRaidMembers = function() return 1 end
_G.GetRaidRosterInfo = function(i)
    if i == 1 then return "Host" end
    return nil
end
_G.UnitName = function(u)
    if u == "player" or u == "raid1" then return "Host" end
    return nil
end
AscensionLFM.Database.Get().regroupRoster = { "Alice", "Bob", "Host" }
-- PruneStaleRegroup (added this session) drops any entry without a
-- regroupSeenAt timestamp - real code always sets one via
-- RememberPresent/RememberPlayer, so mirror that here instead of
-- seeding regroupRoster directly with no timestamp.
AscensionLFM.Database.Get().regroupSeenAt = { alice = 1000, bob = 1000, host = 1000 }
AscensionLFM.Database.Get().regroupSeenAt = { alice = 1000, bob = 1000, host = 1000 }
MiniHUD.ActionRegroup() -- first click: preview only, arms the confirm window
local ok2, nInv = MiniHUD.ActionRegroup() -- second click: confirmed, actually runs
check("regroup ok", ok2 == true, tostring(ok2))
check("regroup announced", _G._chats[1] and tostring(_G._chats[1].msg):find("REGROUP", 1, true) ~= nil)
check("regroup invited missing", uniqueCount(invited) == 2, table.concat(invited, ","))
check("regroup retries each invite", #invited == 2 * MiniHUD.REGROUP_INVITE_ATTEMPTS, tostring(#invited))

-- Regression: a single click must never disband/invite by itself - only
-- preview + arm the confirm window. This is the actual point of the
-- confirm step (a misclick on Regrp used to kick the whole raid instantly).
MiniHUD._ResetForTests()
_G._chats = {}
local invited3 = {}
_G.InviteUnit = function(name) table.insert(invited3, name) end
local uninvited3 = {}
_G.UninviteUnit = function(name) table.insert(uninvited3, name) end
AscensionLFM.Database.Get().regroupRoster = { "Alice", "Bob", "Host" }
AscensionLFM.Database.Get().regroupSeenAt = { alice = 1000, bob = 1000, host = 1000 }
MiniHUD.ActionRegroup() -- single click only
check("single click sends no warn", #_G._chats == 0, tostring(#_G._chats))
check("single click disbands nobody", #uninvited3 == 0, tostring(#uninvited3))
check("single click invites nobody", #invited3 == 0, tostring(#invited3))
MiniHUD.ActionRegroup() -- confirm click
check("confirm click actually invites", uniqueCount(invited3) == 2, table.concat(invited3, ","))

-- Regression: after a full disband (see 0.4.99's ActionRegroup rewrite),
-- the group is back to solo - re-inviting past 4 people must explicitly
-- ConvertToRaid() first, or invite #5+ silently fails to join at all
-- (a plain party caps at 5). Confirmed as a real bug via live testing
-- this session before this fix.
MiniHUD._ResetForTests()
_G._chats = {}
local invited2 = {}
local convertCalled = false
_G.InviteUnit = function(name) table.insert(invited2, name) end
_G.ConvertToRaid = function() convertCalled = true end
_G.GetNumRaidMembers = function() return 0 end -- disbanded down to solo
_G.GetNumPartyMembers = function() return 0 end
_G.GetRaidRosterInfo = function() return nil end
_G.UnitName = function(u)
    if u == "player" then return "Host" end
    return nil
end
local db = AscensionLFM.Database.Get()
db.regroupRoster = { "Alice", "Bob", "Carol", "Dave", "Eve" }
db.regroupSeenAt = { alice = 1000, bob = 1000, carol = 1000, dave = 1000, eve = 1000 }
MiniHUD.ActionRegroup() -- preview click
MiniHUD.ActionRegroup() -- confirm click
check("regroup converts to raid past 5", convertCalled == true)
check("regroup invites all 5 after conversion", uniqueCount(invited2) == 5, table.concat(invited2, ","))

-- Shared rate limit must not block different actions
MiniHUD._ResetForTests()
_G._chats = {}
ok = MiniHUD.ActionWipe()
check("wipe ok", ok == true)
ok = MiniHUD.ActionShield()
check("shield not blocked by wipe rate", ok == true)
ok = MiniHUD.ActionWipe()
check("same-kind wipe rate limited", ok == false)

-- RememberPlayer keeps casing
MiniHUD._ResetForTests()
AscensionLFM.Database.Get().regroupRoster = {}
AscensionLFM.Database.Get().regroupDisplay = {}
check("RememberPlayer", MiniHUD.RememberPlayer("BobTheTank") == true)
check("display casing", AscensionLFM.Database.Get().regroupDisplay.bobthetank == "BobTheTank")

-- Regression: regroupDisplay must not grow unboundedly past what
-- regroupRoster (FIFO-capped at REGROUP_MAX) actually keeps.
MiniHUD._ResetForTests()
AscensionLFM.Database.Get().regroupRoster = {}
AscensionLFM.Database.Get().regroupDisplay = {}
for i = 1, MiniHUD.REGROUP_MAX + 10 do
    MiniHUD.RememberPlayer("Player" .. i)
end
local rosterCount = #AscensionLFM.Database.Get().regroupRoster
local displayCount = 0
for _ in pairs(AscensionLFM.Database.Get().regroupDisplay) do
    displayCount = displayCount + 1
end
check("roster capped at REGROUP_MAX", rosterCount == MiniHUD.REGROUP_MAX, tostring(rosterCount))
check("display pruned to match roster (no unbounded growth)", displayCount == rosterCount,
    string.format("roster=%d display=%d", rosterCount, displayCount))
check("evicted player1 dropped from display", AscensionLFM.Database.Get().regroupDisplay.player1 == nil)
check("recent player is still in display",
    AscensionLFM.Database.Get().regroupDisplay["player" .. (MiniHUD.REGROUP_MAX + 10)] == "Player" .. (MiniHUD.REGROUP_MAX + 10))

-- RW works without Hosting (announce fallback like Wipe)
MiniHUD._ResetForTests()
_G._chats = {}
AscensionLFM.Database.Get().mode = "notify"
AscensionLFM.Database.Get().fullAutoHosting = false
-- Clear wipe-test CanRaidWarn stub so solo path is real
AscensionLFM.RoleCheck = AscensionLFM.RoleCheck or {}
AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "none" end
AscensionLFM.RoleCheck.StartCheck = nil -- must not require hosting for announce
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
_G.UnitIsPartyLeader = function() return false end
_G.IsRaidLeader = function() return false end
_G.IsRaidOfficer = function() return false end
_G.IsPartyLeader = function() return false end
_G.SendChatMessage = function(msg, ch)
    table.insert(_G._chats, { msg = msg, ch = ch })
end
ok = MiniHUD.ActionRoleCheck()
check("rw without hosting sends", ok == true, tostring(ok))
check("rw yell fallback", _G._chats[1] and _G._chats[1].ch == "YELL",
    _G._chats[1] and tostring(_G._chats[1].ch) or ("n=" .. tostring(#_G._chats)))

-- Raid member (not lead): announce via RAID, not only YELL
MiniHUD._ResetForTests()
_G._chats = {}
AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "raid" end
ok = MiniHUD.ActionWipe()
check("raid non-lead wipe ok", ok == true)
check("raid non-lead uses RAID", _G._chats[1] and _G._chats[1].ch == "RAID",
    _G._chats[1] and tostring(_G._chats[1].ch))

-- Failed send must not burn rate limit
MiniHUD._ResetForTests()
_G._chats = {}
AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "none" end
local boom = true
_G.SendChatMessage = function(msg, ch)
    if boom then
        boom = false
        error("chat blocked")
    end
    table.insert(_G._chats, { msg = msg, ch = ch })
end
ok = MiniHUD.ActionWipe()
check("wipe fail first", ok == false)
ok = MiniHUD.ActionWipe()
check("wipe retry after fail not rate-limited", ok == true, tostring(ok))
check("wipe retry yelled", _G._chats[1] and _G._chats[1].ch == "YELL")

-- Regrp without invite privilege still warns
MiniHUD._ResetForTests()
_G._chats = {}
_G.SendChatMessage = function(msg, ch)
    table.insert(_G._chats, { msg = msg, ch = ch })
end
local invitedN = 0
_G.InviteUnit = function() invitedN = invitedN + 1 end
AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "party" end
AscensionLFM.Database.Get().regroupRoster = { "Alice" }
AscensionLFM.Database.Get().regroupDisplay = { alice = "Alice" }
ok = MiniHUD.ActionRegroup()
check("regrp warn without invite power", ok == true)
check("regrp no invites without privilege", invitedN == 0, tostring(invitedN))
check("regrp still announced", _G._chats[1] ~= nil)

local st = MiniHUD.GetDebugStatus()
check("debug status table", type(st) == "table" and st.group ~= nil)

MiniHUD._ResetForTests()
_G._chats = {}
AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "none" end
ok = MiniHUD.ActionNeed("tank")
check("need posts via Poster", ok == true)

MiniHUD.Ensure()
check("frame created", MiniHUD.IsShown() == true)
MiniHUD.SetShown(false)
check("hide works", MiniHUD.IsShown() == false)
MiniHUD.SetShown(true)
check("show works", MiniHUD.IsShown() == true)

--------------------------------------------------------------------
-- Chrome border pieces (v0.4.79's DragonUI reskin) must hide when
-- collapsed and show when expanded - the collapsed HUD actually
-- resizes the frame to 56x28, and these are fixed-size (30x30 etc.)
-- textures that don't auto-shrink with it; left visible at that size
-- they'd be wider than the whole collapsed HUD. Confirmed as a real
-- bug via a live /alfmhuddebug report this session before this fix.
--------------------------------------------------------------------
local hudFrame = MiniHUD._GetFrame()
check("chromeBorderPieces exists", type(hudFrame.chromeBorderPieces) == "table")
check("chromeBorderPieces has all 8 pieces", #hudFrame.chromeBorderPieces == 8,
    tostring(#hudFrame.chromeBorderPieces))

MiniHUD._SetExpanded(false)
local allHidden = true
for _, piece in ipairs(hudFrame.chromeBorderPieces) do
    if piece:IsShown() then allHidden = false end
end
check("chrome border pieces hidden when collapsed", allHidden == true)

MiniHUD._SetExpanded(true)
local allShown = true
for _, piece in ipairs(hudFrame.chromeBorderPieces) do
    if not piece:IsShown() then allShown = false end
end
check("chrome border pieces shown when expanded", allShown == true)

--------------------------------------------------------------------
-- Collapsed-state leader icon (this session): shown instead of the
-- abbreviated "ALFM" text when collapsed, hidden (title/chip text
-- shown instead) when expanded.
--------------------------------------------------------------------
check("collapsedIconTex exists", type(hudFrame.collapsedIconTex) == "table")

MiniHUD._SetExpanded(false)
check("icon shown when collapsed", hudFrame.collapsedIconTex:IsShown() == true)
check("title text hidden when collapsed", hudFrame.titleFS:IsShown() == false)
check("chip text hidden when collapsed", hudFrame.chipFS:IsShown() == false)

MiniHUD._SetExpanded(true)
check("icon hidden when expanded", hudFrame.collapsedIconTex:IsShown() == false)
check("title text shown when expanded", hudFrame.titleFS:IsShown() == true)
check("chip text shown when expanded", hudFrame.chipFS:IsShown() == true)

--------------------------------------------------------------------
-- New: per-message routing (Message Studio style). db.messageRouting[kind]
-- overrides the default smart-cascade delivery for that message kind.
--------------------------------------------------------------------
AscensionLFM.RoleCheck.CanRaidWarn = function() return true, "raid" end
local db = AscensionLFM.Database.Get()
db.messageRouting = {}

-- "auto"/unset: unchanged smart cascade (RW since privileged+raid).
_G._chats = {}
local sentA, chA = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("auto route uses smart cascade (RW)", sentA == true and chA == "RAID_WARNING", tostring(chA))

-- "raidwarning": forces RW; fails (no fallback) if not privileged.
db.messageRouting.wipe = "raidwarning"
_G._chats = {}
local sentB, chB = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("raidwarning route forces RW when privileged", sentB == true and chB == "RAID_WARNING", tostring(chB))

AscensionLFM.RoleCheck.CanRaidWarn = function() return false, "raid" end
_G._chats = {}
local sentB2, chB2 = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("raidwarning route fails (no fallback) without privilege", sentB2 == false, tostring(sentB2))
check("raidwarning route sends nothing without privilege", #_G._chats == 0, tostring(#_G._chats))

-- "raid": forces raid/party chat, skipping RW even when privileged.
AscensionLFM.RoleCheck.CanRaidWarn = function() return true, "raid" end
db.messageRouting.wipe = "raid"
_G._chats = {}
local sentC, chC = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("raid route skips RW even when privileged", sentC == true and chC == "RAID", tostring(chC))

-- "local": never broadcasts, just a local note; other message kinds
-- (unset) are unaffected by this override.
db.messageRouting.wipe = "local"
_G._chats = {}
local sentD, chD = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("local route sends no chat message", #_G._chats == 0, tostring(#_G._chats))
check("local route still reports success", sentD == true and chD == "LOCAL", tostring(chD))
local sentD2, chD2 = MiniHUD._SendGroupAnnounce("hello", "shield")
check("other kinds unaffected by wipe's override", sentD2 == true and chD2 == "RAID_WARNING", tostring(chD2))

-- "disabled": sends nothing at all, reports failure.
db.messageRouting.wipe = "disabled"
_G._chats = {}
local sentE, chE = MiniHUD._SendGroupAnnounce("hello", "wipe")
check("disabled route sends nothing", sentE == false and chE == "disabled" and #_G._chats == 0,
    tostring(sentE) .. "/" .. tostring(chE))

db.messageRouting = {}

-- Regression: Regroup's re-invite step must not drag level-capped players
-- (Kick.lua's own threshold, db.kickLevel/DEFAULT_LEVEL=59) back into the
-- group right after Kick59 (or a manual removal) got rid of them.
-- RememberPresent() (called at the top of every ActionRegroup click) now
-- also snapshots each present member's level via Kick.BuildRoster(), and
-- the confirmed re-invite step skips anyone at/above the cap.
MiniHUD._ResetForTests()
_G._chats = {}
local invitedLvl = {}
_G.InviteUnit = function(name) table.insert(invitedLvl, name) end
_G.UninviteUnit = function() end
_G.ConvertToRaid = function() end
_G.GetNumRaidMembers = function() return 3 end
_G.GetNumPartyMembers = function() return 0 end
_G.GetRaidRosterInfo = function(i)
    local rows = {
        { "Host", nil, 1, 60 },
        { "Alice", nil, 1, 59 }, -- at the cap, must NOT be re-invited
        { "Bob", nil, 1, 45 },
    }
    local r = rows[i]
    if not r then return end
    return r[1], r[2], r[3], r[4]
end
_G.UnitName = function(u)
    if u == "player" or u == "raid1" then return "Host" end
    if u == "raid2" then return "Alice" end
    if u == "raid3" then return "Bob" end
    return nil
end
_G.UnitLevel = function(u)
    if u == "raid1" then return 60 end
    if u == "raid2" then return 59 end
    if u == "raid3" then return 45 end
    return 0
end
local dbLvl = AscensionLFM.Database.Get()
dbLvl.regroupRoster = {}
dbLvl.regroupDisplay = {}
dbLvl.regroupSeenAt = {}
dbLvl.regroupLevel = {}
MiniHUD.ActionRegroup() -- preview click: snapshots present members + levels, arms confirm
MiniHUD.ActionRegroup() -- confirm click: disband + re-invite
check("level-capped Alice not re-invited", uniqueCount(invitedLvl) == 1 and invitedLvl[1] == "Bob",
    table.concat(invitedLvl, ","))

-- Regression: Regroup must preserve assigned roles (tank/healer/aura)
-- across the disband+reinvite cycle, and specifically must survive a
-- SyncFromRoster() pass that runs AFTER the click returns (as it would
-- live, once WoW's event loop dispatches the roster-update event(s)
-- DisbandGroup()'s UninviteUnit calls trigger) while the re-invited
-- people haven't actually rejoined yet. Slots.Assign() (not a raw table
-- write) is what protects them, via the same RecentlyAssigned grace
-- period a freshly-invited applicant already gets.
MiniHUD._ResetForTests()
AscensionLFM.Slots.ClearAll()
_G._chats = {}
_G.InviteUnit = function() end
_G.UninviteUnit = function() end
_G.ConvertToRaid = function() end
_G.GetNumRaidMembers = function() return 3 end
_G.GetNumPartyMembers = function() return 0 end
_G.GetRaidRosterInfo = function(i)
    local rows = { "Host", "Alice", "Bob" }
    return rows[i]
end
_G.UnitName = function(u)
    if u == "player" or u == "raid1" then return "Host" end
    if u == "raid2" then return "Alice" end
    if u == "raid3" then return "Bob" end
    return nil
end
_G.UnitLevel = function() return 30 end
local dbRoles = AscensionLFM.Database.Get()
dbRoles.regroupRoster = {}
dbRoles.regroupDisplay = {}
dbRoles.regroupSeenAt = {}
dbRoles.regroupLevel = {}
-- Pre-existing assignments, aged well past the RecentlyAssigned grace
-- window (assigned "long ago" mid-run, not moments before the regroup).
_G.GetTime = function() return 100 end
AscensionLFM.Slots.Assign("Alice", "tank")
AscensionLFM.Slots.Assign("Bob", "healer")
_G.GetTime = function() return 5000 end -- far past that assignedAt

MiniHUD.ActionRegroup() -- preview click: snapshots present members, arms confirm
MiniHUD.ActionRegroup() -- confirm click: disband + re-invite + restore roles

-- Simulate the roster-update event(s) DisbandGroup()'s UninviteUnit calls
-- trigger, dispatched by WoW's event loop AFTER this click handler
-- returns - the re-invited Alice/Bob haven't actually rejoined yet, so
-- "present" only shows the host.
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
AscensionLFM.Slots.SyncFromRoster()

check("regroup restores tank role across the disband/reinvite gap",
    AscensionLFM.Slots.GetAssigned("Alice") == "tank", tostring(AscensionLFM.Slots.GetAssigned("Alice")))
check("regroup restores healer role across the disband/reinvite gap",
    AscensionLFM.Slots.GetAssigned("Bob") == "healer", tostring(AscensionLFM.Slots.GetAssigned("Bob")))

io.write(string.format("mini_hud tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
