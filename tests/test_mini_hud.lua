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
        ClearAllPoints = function(self) self._points = {} end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 180 end,
        CreateTexture = function()
            return {
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
                IsShown = function() return true end,
                Show = function() end,
                Hide = function() end,
            }
        end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function(self, t) self._text = t end,
                SetTextColor = function() end,
                SetJustifyH = function() end,
                Show = function() end,
                Hide = function() end,
            }
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
dofile("core/Slots.lua")
dofile("core/Poster.lua")
dofile("ui/MiniHUD.lua")

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
local ok2, nInv = MiniHUD.ActionRegroup()
check("regroup ok", ok2 == true, tostring(ok2))
check("regroup announced", _G._chats[1] and tostring(_G._chats[1].msg):find("REGROUP", 1, true) ~= nil)
check("regroup invited missing", #invited == 2, table.concat(invited, ","))

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

io.write(string.format("mini_hud tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
