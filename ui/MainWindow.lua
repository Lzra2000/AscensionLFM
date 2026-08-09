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
local slotsFS
local matchFS = {}
local kickFS = {}
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
    local kickBit = db.autoKickLevel59 and " · |cffff6060Kick59 ON|r" or ""
    statusFS:SetText(string.format("Status: |cff2a7a3a%s|r  ·  Mode: |cffc8a03c%s|r%s%s",
        listening, ModeLabel(db.mode), kickBit, last))
end

function MainWindow.RefreshSlots()
    if not slotsFS then
        return
    end
    local snap = AscensionLFM.Slots and AscensionLFM.Slots.Snapshot and AscensionLFM.Slots.Snapshot()
    if not snap then
        slotsFS:SetText("")
        return
    end
    local bits = {}
    for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        local s = snap[role]
        if s then
            local label = role == "healer" and "H" or (role == "tank" and "T" or (role == "aura" and "A" or "D"))
            table.insert(bits, string.format("%s %d/%d", label, s.filled, s.max))
        end
    end
    slotsFS:SetText("Filled: " .. table.concat(bits, "  ·  "))
    RefreshStatus()
end

function MainWindow.RefreshMatches()
    local db = AscensionLFM.Database.Get()
    local history = db.matchHistory or {}
    for i = 1, 4 do
        local fs = matchFS[i]
        if fs then
            local m = history[i]
            if m then
                local kind = m.kind and ("/" .. tostring(m.kind)) or ""
                fs:SetText(string.format("|cff4a3010%s|r  |cff5a4a30(%s%s)|r\n%s",
                    tostring(m.leader or "?"),
                    tostring(m.source or "chat"),
                    kind,
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

function MainWindow.RefreshKicks()
    local db = AscensionLFM.Database.Get()
    local history = db.kickHistory or {}
    for i = 1, 3 do
        local fs = kickFS[i]
        if fs then
            local k = history[i]
            if k then
                fs:SetText(string.format("|cff4a3010%s|r at level |cff802020%s|r",
                    tostring(k.name or "?"), tostring(k.level or "?")))
                fs:Show()
            else
                fs:SetText("")
                if i == 1 then
                    fs:SetText("|cff5a4a30No kicks yet.|r")
                    fs:Show()
                else
                    fs:Hide()
                end
            end
        end
    end
end

local function SyncSlotEdits()
    local db = AscensionLFM.Database.Get()
    for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        local edit = widgets.slotEdits and widgets.slotEdits[role]
        if edit and edit.SetText then
            local n = (db.slotMax and db.slotMax[role]) or 0
            edit:SetText(tostring(n))
        end
    end
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
    if widgets.scanLfg and widgets.scanLfg.SetChecked then
        widgets.scanLfg:SetChecked(db.scanLfg ~= false)
    end
    if widgets.autoWhisper and widgets.autoWhisper.SetChecked then
        widgets.autoWhisper:SetChecked(db.autoWhisper and true or false)
    end
    if widgets.autoInvite and widgets.autoInvite.SetChecked then
        widgets.autoInvite:SetChecked(db.autoInvite and true or false)
    end
    if widgets.requireRole and widgets.requireRole.SetChecked then
        widgets.requireRole:SetChecked(db.requireRoleWhisper ~= false)
    end
    if widgets.autoKick and widgets.autoKick.SetChecked then
        widgets.autoKick:SetChecked(db.autoKickLevel59 and true or false)
    end
    if widgets.whisperEdit and widgets.whisperEdit.SetText then
        widgets.whisperEdit:SetText(tostring(db.whisperMessage or ""))
    end
    if widgets.maxParty and widgets.maxParty.SetText then
        widgets.maxParty:SetText(tostring(db.maxPartySize or 15))
    end
    SyncSlotEdits()
    RefreshStatus()
    MainWindow.RefreshSlots()
    MainWindow.RefreshMatches()
    MainWindow.RefreshKicks()
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

local function MakeSlotEdit(parent, role, x, y)
    local edit = CreateFrame("EditBox", "AscensionLFMSlot_" .. role, parent, "InputBoxTemplate")
    edit:SetSize(28, 18)
    edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(2)
    edit:SetNumeric(true)
    edit:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText()) or 0
        AscensionLFM.Slots.SetMax(role, n)
        self:SetText(tostring(AscensionLFM.Slots.GetMax(role)))
        MainWindow.RefreshSlots()
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText()) or 0
        AscensionLFM.Slots.SetMax(role, n)
        self:SetText(tostring(AscensionLFM.Slots.GetMax(role)))
        MainWindow.RefreshSlots()
    end)
    return edit
end

function MainWindow.Init()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "AscensionLFMFrame", UIParent, "UIPanelDialogTemplate")
    frame:SetSize(540, 720)
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
    sub:SetText("Manastorm Level Run LFM/LFG · v" .. tostring(AscensionLFM.VERSION or "0.2.0"))
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
        local btn = MakeCheck(modeBox, label, x, -28, function()
            AscensionLFM.Database.SetMode(key)
            SyncWidgetsFromDB()
        end)
        widgets.modeButtons[key] = btn
    end
    local modeHint = modeBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeHint:SetPoint("TOPLEFT", modeBox, "TOPLEFT", 8, -54)
    modeHint:SetPoint("RIGHT", modeBox, "RIGHT", -8, 0)
    modeHint:SetJustifyH("LEFT")
    modeHint:SetText("Seeking: LFM/LFG MS scan + optional whisper. Hosting: role whispers → invite if slot open.")
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
    seekBox:SetHeight(72)
    ApplyInset(seekBox)
    local seekTitle = seekBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    seekTitle:SetPoint("TOPLEFT", seekBox, "TOPLEFT", 8, -6)
    seekTitle:SetText("Seeking options")
    SetInk(seekTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.scanLfg = MakeCheck(seekBox, "Scan LFG MS lines", 8, -22, function(self)
        AscensionLFM.Database.Get().scanLfg = self:GetChecked() and true or false
    end)
    widgets.autoWhisper = MakeCheck(seekBox, "Auto-whisper LFM leader", 160, -22, function(self)
        AscensionLFM.Database.Get().autoWhisper = self:GetChecked() and true or false
    end)

    local msgLabel = seekBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgLabel:SetPoint("TOPLEFT", seekBox, "TOPLEFT", 12, -50)
    msgLabel:SetText("Whisper msg")
    SetInk(msgLabel, INK)

    local edit = CreateFrame("EditBox", "AscensionLFMWhisperEdit", seekBox, "InputBoxTemplate")
    edit:SetSize(200, 20)
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

    -- Hosting / slots
    local hostBox = CreateFrame("Frame", nil, frame)
    hostBox:SetPoint("TOPLEFT", seekBox, "BOTTOMLEFT", 0, -8)
    hostBox:SetPoint("TOPRIGHT", seekBox, "BOTTOMRIGHT", 0, -8)
    hostBox:SetHeight(110)
    ApplyInset(hostBox)
    local hostTitle = hostBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hostTitle:SetPoint("TOPLEFT", hostBox, "TOPLEFT", 8, -6)
    hostTitle:SetText("Hosting · role slots")
    SetInk(hostTitle, { 0.35, 0.25, 0.06, 1 })

    widgets.autoInvite = MakeCheck(hostBox, "Auto-invite matching role whispers", 8, -22, function(self)
        AscensionLFM.Database.Get().autoInvite = self:GetChecked() and true or false
    end)
    widgets.requireRole = MakeCheck(hostBox, "Require role in whisper", 260, -22, function(self)
        AscensionLFM.Database.Get().requireRoleWhisper = self:GetChecked() and true or false
    end)

    local maxLabel = hostBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLabel:SetPoint("TOPLEFT", hostBox, "TOPLEFT", 12, -50)
    maxLabel:SetText("Max size")
    SetInk(maxLabel, INK)

    local maxEdit = CreateFrame("EditBox", "AscensionLFMMaxPartyEdit", hostBox, "InputBoxTemplate")
    maxEdit:SetSize(36, 20)
    maxEdit:SetPoint("LEFT", maxLabel, "RIGHT", 6, 0)
    maxEdit:SetAutoFocus(false)
    maxEdit:SetMaxLetters(2)
    maxEdit:SetNumeric(true)
    maxEdit:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText()) or 15
        if n < 2 then n = 2 end
        if n > 40 then n = 40 end
        AscensionLFM.Database.Get().maxPartySize = n
        self:SetText(tostring(n))
        self:ClearFocus()
    end)
    maxEdit:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText()) or 15
        if n < 2 then n = 2 end
        if n > 40 then n = 40 end
        AscensionLFM.Database.Get().maxPartySize = n
        self:SetText(tostring(n))
    end)
    widgets.maxParty = maxEdit

    local slotLabel = hostBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotLabel:SetPoint("LEFT", maxEdit, "RIGHT", 16, 0)
    slotLabel:SetText("Max T/H/A/D")
    SetInk(slotLabel, INK)

    widgets.slotEdits = {}
    local slotAnchor = CreateFrame("Frame", nil, hostBox)
    slotAnchor:SetPoint("LEFT", slotLabel, "RIGHT", 8, 0)
    slotAnchor:SetSize(1, 1)
    for i, role in ipairs({ "tank", "healer", "aura", "dps" }) do
        local e = MakeSlotEdit(hostBox, role, 0, 0)
        e:ClearAllPoints()
        e:SetPoint("LEFT", slotAnchor, "LEFT", (i - 1) * 34, 0)
        widgets.slotEdits[role] = e
    end

    slotsFS = hostBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotsFS:SetPoint("TOPLEFT", hostBox, "TOPLEFT", 12, -78)
    slotsFS:SetPoint("RIGHT", hostBox, "RIGHT", -8, 0)
    slotsFS:SetJustifyH("LEFT")
    SetInk(slotsFS, MUTED)

    -- Level-59 kick
    local kickBox = CreateFrame("Frame", nil, frame)
    kickBox:SetPoint("TOPLEFT", hostBox, "BOTTOMLEFT", 0, -8)
    kickBox:SetPoint("TOPRIGHT", hostBox, "BOTTOMRIGHT", 0, -8)
    kickBox:SetHeight(88)
    ApplyInset(kickBox)
    local kickTitle = kickBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kickTitle:SetPoint("TOPLEFT", kickBox, "TOPLEFT", 8, -6)
    kickTitle:SetText("Level-59 auto-kick (opt-in · dangerous)")
    SetInk(kickTitle, { 0.55, 0.18, 0.08, 1 })

    widgets.autoKick = MakeCheck(kickBox, "Enable kick at level 59 + raid warning every 10s", 8, -24, function(self)
        AscensionLFM.Database.Get().autoKickLevel59 = self:GetChecked() and true or false
        RefreshStatus()
    end)

    local kickHint = kickBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    kickHint:SetPoint("TOPLEFT", kickBox, "TOPLEFT", 12, -52)
    kickHint:SetPoint("RIGHT", kickBox, "RIGHT", -8, 0)
    kickHint:SetJustifyH("LEFT")
    kickHint:SetText("Hosting only · leader/assist · ignores self · RW then UninviteUnit. Default OFF.")
    SetInk(kickHint, MUTED)

    -- Recent kicks (compact)
    local kickLogBox = CreateFrame("Frame", nil, frame)
    kickLogBox:SetPoint("TOPLEFT", kickBox, "BOTTOMLEFT", 0, -8)
    kickLogBox:SetPoint("TOPRIGHT", kickBox, "BOTTOMRIGHT", 0, -8)
    kickLogBox:SetHeight(64)
    ApplyInset(kickLogBox)
    local kickLogTitle = kickLogBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kickLogTitle:SetPoint("TOPLEFT", kickLogBox, "TOPLEFT", 8, -6)
    kickLogTitle:SetText("Recent kicks")
    SetInk(kickLogTitle, { 0.35, 0.25, 0.06, 1 })
    local ky = -24
    for i = 1, 3 do
        local fs = kickLogBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", kickLogBox, "TOPLEFT", 8, ky)
        fs:SetPoint("TOPRIGHT", kickLogBox, "TOPRIGHT", -8, ky)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        kickFS[i] = fs
        ky = ky - 12
    end

    -- Matches
    local matchBox = CreateFrame("Frame", nil, frame)
    matchBox:SetPoint("TOPLEFT", kickLogBox, "BOTTOMLEFT", 0, -8)
    matchBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 42)
    ApplyInset(matchBox)
    local matchTitle = matchBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    matchTitle:SetPoint("TOPLEFT", matchBox, "TOPLEFT", 8, -6)
    matchTitle:SetText("Recent Manastorm LFM/LFG matches")
    SetInk(matchTitle, { 0.35, 0.25, 0.06, 1 })

    local y = -24
    for i = 1, 4 do
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
        AscensionLFM.Database.ClearKicks()
        MainWindow.RefreshMatches()
        MainWindow.RefreshKicks()
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
