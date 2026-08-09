-- AscensionLFM: ui/MainWindow.lua
-- Native DialogFrame / parchment settings UI (matches docs/sketch mockup).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local MainWindow = {}
AscensionLFM.MainWindow = MainWindow

local TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local INK = { 0.20, 0.14, 0.06, 1 }
local GOLD = { 1.00, 0.82, 0.20, 1 }
local MUTED = { 0.35, 0.28, 0.18, 1 }

local frame
local statusFS
local matchFS = {}
local widgets = {}

local function ApplyInset(f)
    if f.SetBackdrop then
        f:SetBackdrop(TOOLTIP_BACKDROP)
        f:SetBackdropColor(0.95, 0.90, 0.72, 0.55)
        f:SetBackdropBorderColor(0.55, 0.45, 0.18, 0.9)
    end
end

local function SetInk(fs, rgba)
    if fs and fs.SetTextColor then
        fs:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end
end

local function ModeLabel(mode)
    if mode == "notify" then
        return "Notify only"
    elseif mode == "seeking" then
        return "Seeking"
    elseif mode == "hosting" then
        return "Hosting"
    end
    return "Off"
end

local function RefreshStatus()
    if not statusFS then
        return
    end
    local db = AscensionLFM.Database.Get()
    local listening = db.mode ~= "off" and "Listening" or "Idle"
    local last = ""
    if db.matchHistory and db.matchHistory[1] then
        local m = db.matchHistory[1]
        last = string.format("\nLast: %s — %s", tostring(m.leader), tostring(m.summary or m.text or ""))
    end
    statusFS:SetText(string.format("Status: |cff2a7a3a%s|r  ·  Mode: |cffc8a03c%s|r%s",
        listening, ModeLabel(db.mode), last))
end

function MainWindow.RefreshMatches()
    local db = AscensionLFM.Database.Get()
    local history = db.matchHistory or {}
    for i = 1, 6 do
        local fs = matchFS[i]
        if fs then
            local m = history[i]
            if m then
                fs:SetText(string.format("|cff4a3010%s|r  |cff5a4a30(%s)|r\n%s",
                    tostring(m.leader or "?"),
                    tostring(m.source or "chat"),
                    tostring(m.text or m.summary or "")))
                fs:Show()
            else
                fs:SetText("")
                if i == 1 then
                    fs:SetText("|cff5a4a30No matches yet.|r")
                    fs:Show()
                else
                    fs:Hide()
                end
            end
        end
    end
    RefreshStatus()
end

local function SyncWidgetsFromDB()
    local db = AscensionLFM.Database.Get()
    for mode, btn in pairs(widgets.modeButtons or {}) do
        if btn and btn.SetChecked then
            btn:SetChecked(db.mode == mode)
        end
    end
    for role, btn in pairs(widgets.roleButtons or {}) do
        if btn and btn.SetChecked then
            btn:SetChecked(db.roles and db.roles[role] and true or false)
        end
    end
    if widgets.autoWhisper and widgets.autoWhisper.SetChecked then
        widgets.autoWhisper:SetChecked(db.autoWhisper and true or false)
    end
    if widgets.autoInvite and widgets.autoInvite.SetChecked then
        widgets.autoInvite:SetChecked(db.autoInvite and true or false)
    end
    if widgets.whisperEdit and widgets.whisperEdit.SetText then
        widgets.whisperEdit:SetText(tostring(db.whisperMessage or ""))
    end
    if widgets.maxParty and widgets.maxParty.SetText then
        widgets.maxParty:SetText(tostring(db.maxPartySize or 5))
    end
    RefreshStatus()
    MainWindow.RefreshMatches()
end

local function MakeCheck(parent, label, x, y, onClick)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(24, 24)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", btn, "RIGHT", 2, 0)
    fs:SetText(label)
    SetInk(fs, INK)
    btn:SetScript("OnClick", onClick)
    return btn
end

function MainWindow.Init()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "AscensionLFMFrame", UIParent, "UIPanelDialogTemplate")
    frame:SetSize(520, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "AscensionLFMFrame")

    local title = _G["AscensionLFMFrameTitle"] or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not _G["AscensionLFMFrameTitle"] then
        title:SetPoint("TOP", frame, "TOP", 0, -10)
    end
    title:SetText("AscensionLFM")
    SetInk(title, GOLD)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("Manastorm Level Run LFM · v" .. tostring(AscensionLFM.VERSION or "0.1.0"))
    SetInk(sub, MUTED)

    -- Status
    local statusBox = CreateFrame("Frame", nil, frame)
    statusBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -42)
    statusBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -42)
    statusBox:SetHeight(48)
    ApplyInset(statusBox)
    statusFS = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFS:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 8, -8)
    statusFS:SetPoint("TOPRIGHT", statusBox, "TOPRIGHT", -8, -8)
    statusFS:SetJustifyH("LEFT")
    SetInk(statusFS, INK)

    -- Mode section
    local modeBox = CreateFrame("Frame", nil, frame)
    modeBox:SetPoint("TOPLEFT", statusBox, "BOTTOMLEFT", 0, -8)
    modeBox:SetPoint("TOPRIGHT", statusBox, "BOTTOMRIGHT", 0, -8)
    modeBox:SetHeight(78)
    ApplyInset(modeBox)
    local modeTitle = modeBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeTitle:SetPoint("TOPLEFT", modeBox, "TOPLEFT", 8, -6)
    modeTitle:SetText("Mode")
    SetInk(modeTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.modeButtons = {}
    local modes = {
        { "off", "Off", 8 },
        { "notify", "Notify only", 70 },
        { "seeking", "Seeking", 180 },
        { "hosting", "Hosting", 270 },
    }
    for _, m in ipairs(modes) do
        local key, label, x = m[1], m[2], m[3]
        local btn = MakeCheck(modeBox, label, x, -28, function(self)
            AscensionLFM.Database.SetMode(key)
            SyncWidgetsFromDB()
        end)
        widgets.modeButtons[key] = btn
    end
    local modeHint = modeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeHint:SetPoint("TOPLEFT", modeBox, "TOPLEFT", 8, -54)
    modeHint:SetPoint("RIGHT", modeBox, "RIGHT", -8, 0)
    modeHint:SetJustifyH("LEFT")
    modeHint:SetText("Seeking: scan chat, optional auto-whisper. Hosting: auto-invite role whispers.")
    SetInk(modeHint, MUTED)

    -- Roles
    local roleBox = CreateFrame("Frame", nil, frame)
    roleBox:SetPoint("TOPLEFT", modeBox, "BOTTOMLEFT", 0, -8)
    roleBox:SetPoint("TOPRIGHT", modeBox, "BOTTOMRIGHT", 0, -8)
    roleBox:SetHeight(52)
    ApplyInset(roleBox)
    local roleTitle = roleBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleTitle:SetPoint("TOPLEFT", roleBox, "TOPLEFT", 8, -6)
    roleTitle:SetText("My roles (seeking) / Accept roles (hosting)")
    SetInk(roleTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.roleButtons = {}
    local roles = {
        { "tank", "Tank", 8 },
        { "healer", "Healer", 90 },
        { "aura", "Aura", 180 },
        { "dps", "DPS", 260 },
    }
    for _, r in ipairs(roles) do
        local key, label, x = r[1], r[2], r[3]
        local btn = MakeCheck(roleBox, label, x, -24, function(self)
            local db = AscensionLFM.Database.Get()
            db.roles[key] = self:GetChecked() and true or false
        end)
        widgets.roleButtons[key] = btn
    end

    -- Seeking options
    local seekBox = CreateFrame("Frame", nil, frame)
    seekBox:SetPoint("TOPLEFT", roleBox, "BOTTOMLEFT", 0, -8)
    seekBox:SetPoint("TOPRIGHT", roleBox, "BOTTOMRIGHT", 0, -8)
    seekBox:SetHeight(56)
    ApplyInset(seekBox)
    local seekTitle = seekBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    seekTitle:SetPoint("TOPLEFT", seekBox, "TOPLEFT", 8, -6)
    seekTitle:SetText("Seeking options")
    SetInk(seekTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.autoWhisper = MakeCheck(seekBox, "Auto-whisper leader", 8, -24, function(self)
        AscensionLFM.Database.Get().autoWhisper = self:GetChecked() and true or false
    end)

    local msgLabel = seekBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgLabel:SetPoint("LEFT", widgets.autoWhisper, "RIGHT", 120, 0)
    msgLabel:SetText("Message")
    SetInk(msgLabel, INK)

    local edit = CreateFrame("EditBox", "AscensionLFMWhisperEdit", seekBox, "InputBoxTemplate")
    edit:SetSize(160, 20)
    edit:SetPoint("LEFT", msgLabel, "RIGHT", 8, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(80)
    edit:SetScript("OnEnterPressed", function(self)
        AscensionLFM.Database.Get().whisperMessage = self:GetText() or ""
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        AscensionLFM.Database.Get().whisperMessage = self:GetText() or ""
    end)
    widgets.whisperEdit = edit

    -- Hosting options
    local hostBox = CreateFrame("Frame", nil, frame)
    hostBox:SetPoint("TOPLEFT", seekBox, "BOTTOMLEFT", 0, -8)
    hostBox:SetPoint("TOPRIGHT", seekBox, "BOTTOMRIGHT", 0, -8)
    hostBox:SetHeight(52)
    ApplyInset(hostBox)
    local hostTitle = hostBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hostTitle:SetPoint("TOPLEFT", hostBox, "TOPLEFT", 8, -6)
    hostTitle:SetText("Hosting options")
    SetInk(hostTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.autoInvite = MakeCheck(hostBox, "Auto-invite matching whispers", 8, -24, function(self)
        AscensionLFM.Database.Get().autoInvite = self:GetChecked() and true or false
    end)

    local maxLabel = hostBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLabel:SetPoint("LEFT", widgets.autoInvite, "RIGHT", 180, 0)
    maxLabel:SetText("Max size")
    SetInk(maxLabel, INK)

    local maxEdit = CreateFrame("EditBox", "AscensionLFMMaxPartyEdit", hostBox, "InputBoxTemplate")
    maxEdit:SetSize(36, 20)
    maxEdit:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0)
    maxEdit:SetAutoFocus(false)
    maxEdit:SetMaxLetters(2)
    maxEdit:SetNumeric(true)
    maxEdit:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText()) or 5
        if n < 2 then n = 2 end
        if n > 40 then n = 40 end
        AscensionLFM.Database.Get().maxPartySize = n
        self:SetText(tostring(n))
        self:ClearFocus()
    end)
    maxEdit:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText()) or 5
        if n < 2 then n = 2 end
        if n > 40 then n = 40 end
        AscensionLFM.Database.Get().maxPartySize = n
        self:SetText(tostring(n))
    end)
    widgets.maxParty = maxEdit

    -- Matches
    local matchBox = CreateFrame("Frame", nil, frame)
    matchBox:SetPoint("TOPLEFT", hostBox, "BOTTOMLEFT", 0, -8)
    matchBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 42)
    ApplyInset(matchBox)
    local matchTitle = matchBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    matchTitle:SetPoint("TOPLEFT", matchBox, "TOPLEFT", 8, -6)
    matchTitle:SetText("Recent Manastorm LFM matches")
    SetInk(matchTitle, { 0.35, 0.25, 0.06, 1 })

    local y = -24
    for i = 1, 6 do
        local fs = matchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", matchBox, "TOPLEFT", 8, y)
        fs:SetPoint("TOPRIGHT", matchBox, "TOPRIGHT", -8, y)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        matchFS[i] = fs
        y = y - 28
    end

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(88, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -110, 14)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        AscensionLFM.Database.ClearMatches()
        MainWindow.RefreshMatches()
    end)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(88, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetScript("OnShow", function()
        SyncWidgetsFromDB()
    end)

    SyncWidgetsFromDB()
end

function MainWindow.Toggle()
    if not frame then
        MainWindow.Init()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function MainWindow.Show()
    if not frame then
        MainWindow.Init()
    end
    frame:Show()
end
