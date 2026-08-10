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
            return { SetAllPoints = function() end, SetPoint = function() end, SetTexture = function() end, SetVertexColor = function() end }
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

check("default miniHudShow on", AscensionLFM.Database.Get().miniHudShow == true)
check("default wipe msg", AscensionLFM.Database.Get().wipeAnnounceMessage == "WIPE")
check("default shield msg", AscensionLFM.Database.Get().shieldAnnounceMessage == MiniHUD.DEFAULT_SHIELD)

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

MiniHUD._ResetForTests()
_G._chats = {}
ok = MiniHUD.ActionNeed("tank")
check("need posts via Poster", ok == true)

MiniHUD.Ensure()
check("frame created", MiniHUD.IsShown() == true)
MiniHUD.SetShown(false)
check("hide works", MiniHUD.IsShown() == false)
MiniHUD.SetShown(true)
check("show works", MiniHUD.IsShown() == true)

io.write(string.format("mini_hud tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
