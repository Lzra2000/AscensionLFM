-- AscensionLFM: light UI smoke test (sandbox frames + category helpers).
-- Does not exercise real WoW widgets; verifies Init/SelectCategory seams.

package.path = "./?.lua;./core/?.lua;./ui/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

local function Noop() end

local function NewFrame()
    local frame = {
        _scripts = {},
        _shown = false,
        _width = 64,
        _height = 64,
        _checked = nil,
        _text = "",
        _points = {},
        _children = {},
    }

    local function Index(_, key)
        if key == "SetScript" then
            return function(self, event, fn)
                self._scripts[event] = fn
            end
        elseif key == "GetScript" then
            return function(self, event)
                return self._scripts[event]
            end
        elseif key == "Show" then
            return function(self) self._shown = true end
        elseif key == "Hide" then
            return function(self) self._shown = false end
        elseif key == "IsShown" then
            return function(self) return self._shown end
        elseif key == "SetSize" then
            return function(self, w, h)
                self._width, self._height = w, h
            end
        elseif key == "SetWidth" then
            return function(self, w) self._width = w end
        elseif key == "SetHeight" then
            return function(self, h) self._height = h end
        elseif key == "GetWidth" then
            return function(self) return self._width end
        elseif key == "GetHeight" then
            return function(self) return self._height end
        elseif key == "GetChecked" then
            return function(self) return self._checked end
        elseif key == "SetChecked" then
            return function(self, value)
                if value == true or value == 1 then
                    self._checked = 1
                else
                    self._checked = nil
                end
            end
        elseif key == "SetText" then
            return function(self, value) self._text = value or "" end
        elseif key == "GetText" then
            return function(self) return self._text or "" end
        elseif key == "CreateTexture" then
            return function()
                return {
                    SetAllPoints = Noop, SetPoint = Noop, SetTexture = Noop,
                    SetTexCoord = Noop, SetWidth = Noop, SetHeight = Noop,
                    Show = Noop, Hide = Noop, SetVertexColor = Noop,
                }
            end
        elseif key == "CreateFontString" then
            return function()
                local text = ""
                return {
                    SetPoint = Noop,
                    SetText = function(_, value) text = value or "" end,
                    GetText = function() return text end,
                    SetJustifyH = Noop,
                    SetTextColor = Noop,
                    SetWidth = Noop,
                    Show = Noop,
                    Hide = Noop,
                }
            end
        elseif key == "CreateFrame" then
            return function(_, childName, parent, template)
                local child = NewFrame()
                child._name = childName
                child._parent = parent
                child._template = template
                if parent and parent._children then
                    table.insert(parent._children, child)
                end
                return child
            end
        elseif key == "SetPoint" then
            return function(self, ...)
                table.insert(self._points, { ... })
            end
        elseif key == "SetAllPoints" then
            return function(self)
                self._allPoints = true
            end
        elseif key == "ClearAllPoints"
            or key == "EnableMouse" or key == "RegisterForDrag" or key == "SetMovable"
            or key == "StartMoving" or key == "StopMovingOrSizing"
            or key == "SetAutoFocus" or key == "ClearFocus"
            or key == "SetNumeric" or key == "SetMaxLetters"
            or key == "SetJustifyH" or key == "SetTextColor"
            or key == "SetBackdrop" or key == "SetBackdropColor" or key == "SetBackdropBorderColor"
            or key == "SetFrameStrata" or key == "SetFrameLevel" or key == "SetID"
            or key == "RegisterForClicks" then
            return Noop
        end
        return Noop
    end

    return setmetatable(frame, { __index = Index })
end

CreateFrame = function(kind, name, parent, template)
    local frame = NewFrame()
    frame._kind = kind
    frame._name = name
    frame._parent = parent
    frame._template = template
    if name then
        _G[name] = frame
    end
    return frame
end

UIParent = NewFrame()
UISpecialFrames = {}
tinsert = table.insert
DEFAULT_CHAT_FRAME = { AddMessage = Noop }
SlashCmdList = SlashCmdList or {}

-- Load Database + MainWindow (no Scanner/Invite needed for UI smoke).
dofile("core/Database.lua")
AscensionLFM.VERSION = "0.2.2"
AscensionLFM.Slots = {
    Snapshot = function()
        return {
            tank = { filled = 0, max = 2 },
            healer = { filled = 0, max = 3 },
            aura = { filled = 0, max = 3 },
            dps = { filled = 0, max = 7 },
        }
    end,
    SetMax = function(role, n)
        local db = AscensionLFM.Database.Get()
        db.slotMax[role] = n
    end,
    GetMax = function(role)
        local db = AscensionLFM.Database.Get()
        return db.slotMax[role]
    end,
}

AscensionLFM.Database.Init()
dofile("ui/MainWindow.lua")

local MW = assert(AscensionLFM.MainWindow)
check("MainWindow table", type(MW) == "table")
check("Init exists", type(MW.Init) == "function")
check("SelectCategory exists", type(MW.SelectCategory) == "function")
check("GetActiveCategory exists", type(MW.GetActiveCategory) == "function")
check("GetFrame exists", type(MW.GetFrame) == "function")

MW.Init()
local f = MW.GetFrame()
check("frame created", type(f) == "table")
check("frame named", f._name == "AscensionLFMFrame")
check("frame size width", f._width == 720)
check("frame size height", f._height == 520)
check("default category general", MW.GetActiveCategory() == "general")
check("UISpecialFrames registered", UISpecialFrames[1] == "AscensionLFMFrame")

local cats = { "general", "seeking", "hosting", "kick", "log" }
for i = 1, #cats do
    MW.SelectCategory(cats[i])
    check("select " .. cats[i], MW.GetActiveCategory() == cats[i])
end

MW.SelectCategory("not-a-real-category")
check("unknown category falls back to general", MW.GetActiveCategory() == "general")

-- Toggle show/hide
check("starts hidden", f:IsShown() == false)
MW.Show()
check("Show shows frame", f:IsShown() == true)
MW.Toggle()
check("Toggle hides", f:IsShown() == false)
MW.Toggle()
check("Toggle shows", f:IsShown() == true)

-- Mode wiring still updates DB from UI mode buttons
AscensionLFM.Database.SetMode("hosting")
MW.SelectCategory("general")
check("mode hosting persisted", AscensionLFM.Database.Get().mode == "hosting")

-- Kick default remains off
check("kick default off", AscensionLFM.Database.Get().autoKickLevel59 == false)
-- Fresh Init default mode is notify (Listening ON)
_G.AscensionLFMDB = nil
AscensionLFM.Database.Init()
check("default mode notify", AscensionLFM.Database.Get().mode == "notify")

if failed > 0 then
    io.stderr:write(string.format("test_ui_smoke: %d failed, %d passed\n", failed, passed))
    os.exit(1)
end
print(string.format("test_ui_smoke: %d passed", passed))
