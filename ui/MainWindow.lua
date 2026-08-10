-- AscensionLFM: ui/MainWindow.lua
-- Native DialogFrame settings with Categories sidebar (General / Seeking /
-- Hosting / Post / Kick / Log). Matches docs/sketch/ascension-lfm-mockup.html.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local MainWindow = {}
AscensionLFM.MainWindow = MainWindow

local FRAME_NAME = "AscensionLFMFrame"
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 540
local SIDEBAR_WIDTH = 148

local CAT_GENERAL = "general"
local CAT_SEEKING = "seeking"
local CAT_HOSTING = "hosting"
local CAT_POST = "post"
local CAT_KICK = "kick"
local CAT_LOG = "log"

local CATEGORIES = {
    { id = CAT_GENERAL, label = "General",
      title = "General",
      sub = "Mode and status. Default Notify = Listening ON (Log fills; no auto-invite)." },
    { id = CAT_SEEKING, label = "Seeking",
      title = "Seeking",
      sub = "Roles you play and optional auto-whisper when an LFM still needs you." },
    { id = CAT_HOSTING, label = "Hosting",
      title = "Hosting",
      sub = "Accept roles, invite rules, and Manastorm slot caps (default 2/3/3/7)." },
    { id = CAT_POST, label = "Post",
      title = "Post",
      sub = "Compose LFM from slots, scan raid fills, post once, or opt-in auto-repost." },
    { id = CAT_KICK, label = "Kick",
      title = "Kick",
      sub = "Opt-in level-59 auto-kick with raid warning. Dangerous — default OFF." },
    { id = CAT_LOG, label = "Log",
      title = "Log",
      sub = "Recent Manastorm LFM/LFG matches from public chat and whispers." },
}

local TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TOOLTIP_BACKDROP_TIGHT = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local INK = { 0.20, 0.14, 0.06, 1 }
local GOLD = { 1.00, 0.82, 0.20, 1 }
local MUTED = { 0.35, 0.28, 0.18, 1 }
local TITLE_INK = { 0.30, 0.20, 0.04, 1 }
local SECTION = { 0.42, 0.30, 0.10, 1 }
local DANGER = { 0.55, 0.18, 0.08, 1 }

local frame
local activeCategory = CAT_GENERAL
local categoryButtons = {}
local categoryPages = {}
local categoryHeadTitle
local categoryHeadSub
local footerStatus
local clearBtn
local statusFS
local slotsFS
local matchFS = {}
local kickFS = {}
local widgets = {
    modeButtons = {},
    roleButtons = {},
    roleButtonsHost = {},
    slotEdits = {},
    channelButtons = {},
}
local postStatusFS
local postPreviewEdit
local _syncingPost = false

local function ApplyBackdrop(f, template, r, g, b, a, br, bg, bb, ba)
    if type(f) ~= "table" or type(f.SetBackdrop) ~= "function" then
        return
    end
    f:SetBackdrop(template)
    if f.SetBackdropColor then
        f:SetBackdropColor(r, g, b, a)
    end
    if f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(br, bg, bb, ba)
    end
end

local function ApplyParchment(f)
    ApplyBackdrop(f, TOOLTIP_BACKDROP, 0.78, 0.70, 0.50, 0.92, 0.45, 0.35, 0.14, 1)
end

local function ApplySidebar(f)
    ApplyBackdrop(f, TOOLTIP_BACKDROP, 0.12, 0.09, 0.04, 0.95, 0.45, 0.35, 0.14, 1)
end

local function ApplyInset(f)
    ApplyBackdrop(f, TOOLTIP_BACKDROP, 0.95, 0.90, 0.72, 0.55, 0.55, 0.45, 0.18, 0.9)
end

local function ApplyToggleRow(f)
    ApplyBackdrop(f, TOOLTIP_BACKDROP_TIGHT, 0.95, 0.90, 0.72, 0.55, 0.55, 0.45, 0.18, 0.9)
end

local function ApplyNavButton(f, selected)
    ApplyBackdrop(f, TOOLTIP_BACKDROP_TIGHT,
        selected and 0.85 or 0.22,
        selected and 0.70 or 0.16,
        selected and 0.28 or 0.08,
        selected and 1 or 0.95,
        selected and 0.94 or 0.45,
        selected and 0.82 or 0.35,
        selected and 0.38 or 0.14,
        1)
end

local function SetInk(fs, rgba)
    if fs and fs.SetTextColor then
        fs:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end
end

-- WotLK 3.3.5a CheckButton:GetChecked() returns 1 / nil, not true / false.
local function CheckButtonIsOn(check)
    if type(check) ~= "table" or type(check.GetChecked) ~= "function" then
        return false
    end
    local value = check:GetChecked()
    return value == 1 or value == true
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

local function CategoryInfo(id)
    for i = 1, #CATEGORIES do
        if CATEGORIES[i].id == id then
            return CATEGORIES[i]
        end
    end
    return CATEGORIES[1]
end

local function RefreshStatus()
    if not statusFS then
        return
    end
    local db = AscensionLFM.Database.Get()
    local listeningOn = db.mode ~= "off"
    local listening = listeningOn and "|cff2a7a3aListening ON|r" or "|cff802020Listening OFF|r"
    local last = ""
    if db.matchHistory and db.matchHistory[1] then
        local m = db.matchHistory[1]
        last = string.format("\nLast: %s — %s", tostring(m.leader), tostring(m.summary or m.text or ""))
    end
    local kickBit = db.autoKickLevel59 and " · |cffff6060Kick59 ON|r" or ""
    statusFS:SetText(string.format("Status: %s  ·  Mode: |cffc8a03c%s|r%s%s",
        listening, ModeLabel(db.mode), kickBit, last))

    if footerStatus then
        local kick = db.autoKickLevel59 and "Kick59 ON" or "Kick59 off"
        if activeCategory == CAT_KICK then
            footerStatus:SetText("Kick log · Clear removes kick history")
        elseif activeCategory == CAT_LOG then
            footerStatus:SetText("Match log · Clear removes match history")
        else
            footerStatus:SetText(string.format("%s · Mode %s · %s",
                listeningOn and "Listening ON" or "Listening OFF",
                ModeLabel(db.mode), kick))
        end
        SetInk(footerStatus, MUTED)
    end
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

local function FormatLastPostWall()
    local db = AscensionLFM.Database.Get()
    local t = tonumber(db.lastPostAt) or 0
    if t <= 0 then
        return "never"
    end
    if type(date) == "function" then
        return date("%H:%M:%S", t)
    end
    return tostring(t)
end

function MainWindow.RefreshPost()
    if not AscensionLFM.Poster then
        return
    end
    local st = AscensionLFM.Poster.GetStatus and AscensionLFM.Poster.GetStatus()
    if not st then
        return
    end
    _syncingPost = true
    if postPreviewEdit and postPreviewEdit.SetText and not (postPreviewEdit.HasFocus and postPreviewEdit:HasFocus()) then
        postPreviewEdit:SetText(st.message or "")
    end
    if postStatusFS then
        local bits = {}
        if st.enabled then
            if st.isFull then
                table.insert(bits, "Auto-repost STOPPED (full)")
            elseif st.mode ~= "hosting" then
                table.insert(bits, "Auto-repost idle (set Mode=Hosting)")
            elseif st.countdown and st.countdown > 0 then
                table.insert(bits, string.format("Next repost in %ds", st.countdown))
            else
                table.insert(bits, "Next repost soon")
            end
        else
            table.insert(bits, "Auto-repost OFF")
        end
        table.insert(bits, "Last post: " .. FormatLastPostWall())
        table.insert(bits, "Channel: " .. tostring(st.channel or "YELL"))
        postStatusFS:SetText(table.concat(bits, "  ·  "))
    end
    if widgets.autoRepost and widgets.autoRepost.SetChecked then
        widgets.autoRepost:SetChecked(st.enabled and true or false)
    end
    if widgets.repostInterval and widgets.repostInterval.SetText then
        widgets.repostInterval:SetText(tostring(st.interval or 60))
    end
    local db = AscensionLFM.Database.Get()
    local ch = string.upper(tostring(db.postChannel or "YELL"))
    for key, btn in pairs(widgets.channelButtons or {}) do
        if btn and btn.SetChecked then
            btn:SetChecked(key == ch)
        end
    end
    if widgets.channelName and widgets.channelName.SetText then
        widgets.channelName:SetText(tostring(db.postChannelName or ""))
    end
    _syncingPost = false
end

function MainWindow.RefreshMatches()
    local db = AscensionLFM.Database.Get()
    local history = db.matchHistory or {}
    for i = 1, 6 do
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
    for i = 1, 6 do
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
        local edit = widgets.slotEdits[role]
        if edit and edit.SetText then
            local n = (db.slotMax and db.slotMax[role]) or 0
            edit:SetText(tostring(n))
        end
    end
end

local function SyncRoleGroup(group, db)
    for role, btn in pairs(group or {}) do
        if btn and btn.SetChecked then
            btn:SetChecked(db.roles and db.roles[role] and true or false)
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
    SyncRoleGroup(widgets.roleButtons, db)
    SyncRoleGroup(widgets.roleButtonsHost, db)
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
    if widgets.autoRepost and widgets.autoRepost.SetChecked then
        widgets.autoRepost:SetChecked(db.autoRepost and true or false)
    end
    if widgets.repostInterval and widgets.repostInterval.SetText then
        local n = 60
        if AscensionLFM.Poster and AscensionLFM.Poster.ClampInterval then
            n = AscensionLFM.Poster.ClampInterval(db.repostInterval)
        else
            n = tonumber(db.repostInterval) or 60
        end
        widgets.repostInterval:SetText(tostring(n))
    end
    SyncSlotEdits()
    RefreshStatus()
    MainWindow.RefreshSlots()
    MainWindow.RefreshPost()
    MainWindow.RefreshMatches()
    MainWindow.RefreshKicks()
end

local function SetRole(role, on)
    local db = AscensionLFM.Database.Get()
    if type(db.roles) ~= "table" then
        db.roles = {}
    end
    db.roles[role] = on and true or false
    SyncRoleGroup(widgets.roleButtons, db)
    SyncRoleGroup(widgets.roleButtonsHost, db)
end

local function CreateSectionLabel(parent, text, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 4, y)
    label:SetText(string.upper(text))
    SetInk(label, SECTION)
    return label
end

local function CreateToggleRow(parent, y, title, description, danger, onToggle)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:SetHeight(44)
    ApplyToggleRow(row)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 4, -8)
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetScript("OnClick", function(self)
        onToggle(CheckButtonIsOn(self))
    end)

    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, -2)
    titleFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetText(title)
    if danger then
        SetInk(titleFs, DANGER)
    else
        SetInk(titleFs, { 0.42, 0.24, 0.04, 1 })
    end

    local descFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
    descFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetText(description)
    SetInk(descFs, MUTED)

    return check
end

local function MakeRoleCheck(parent, role, label, x, y, group)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(24, 24)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", btn, "RIGHT", 2, 0)
    fs:SetText(label)
    SetInk(fs, INK)
    btn:SetScript("OnClick", function(self)
        SetRole(role, CheckButtonIsOn(self))
    end)
    group[role] = btn
    return btn
end

local function MakeSlotEdit(parent, role)
    local edit = CreateFrame("EditBox", "AscensionLFMSlot_" .. role, parent, "InputBoxTemplate")
    edit:SetSize(32, 18)
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

local function BuildCategoryPage(parent, id)
    local page = CreateFrame("Frame", FRAME_NAME .. "Cat_" .. id, parent)
    page:SetAllPoints(parent)
    page:Hide()
    categoryPages[id] = page
    return page
end

local function SetCategoryHighlight(id)
    for catId, button in pairs(categoryButtons) do
        if button then
            local selected = (catId == id)
            ApplyNavButton(button, selected)
            if button._label then
                if selected then
                    button._label:SetTextColor(0.12, 0.08, 0.02, 1)
                else
                    button._label:SetTextColor(0.92, 0.85, 0.65, 1)
                end
            end
        end
    end
end

function MainWindow.GetActiveCategory()
    return activeCategory
end

function MainWindow.SelectCategory(id)
    if not categoryPages[id] then
        id = CAT_GENERAL
    end
    activeCategory = id
    SetCategoryHighlight(id)

    for catId, page in pairs(categoryPages) do
        if page then
            if catId == id then
                page:Show()
            else
                page:Hide()
            end
        end
    end

    local info = CategoryInfo(id)
    if categoryHeadTitle then
        categoryHeadTitle:SetText(info.title)
    end
    if categoryHeadSub then
        categoryHeadSub:SetText(info.sub)
    end

    if clearBtn then
        if id == CAT_LOG or id == CAT_KICK then
            clearBtn:Show()
        else
            clearBtn:Hide()
        end
    end

    RefreshStatus()
end

function MainWindow.Init()
    if frame then
        return
    end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "UIPanelDialogTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, FRAME_NAME)

    local title = _G[FRAME_NAME .. "Title"] or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not _G[FRAME_NAME .. "Title"] then
        title:SetPoint("TOP", frame, "TOP", 0, -10)
    end
    title:SetText("AscensionLFM")
    SetInk(title, GOLD)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("Manastorm Level Run LFM/LFG · v" .. tostring(AscensionLFM.VERSION or "0.3.0"))
    SetInk(sub, MUTED)

    local shell = CreateFrame("Frame", FRAME_NAME .. "Shell", frame)
    shell:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -40)
    shell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 14)

    local sidebar = CreateFrame("Frame", FRAME_NAME .. "Sidebar", shell)
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    ApplySidebar(sidebar)

    local sideLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("TOPLEFT", 10, -10)
    sideLabel:SetText("CATEGORIES")
    SetInk(sideLabel, { 0.78, 0.62, 0.24, 1 })

    local y = -28
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        local btn = CreateFrame("Button", FRAME_NAME .. "Nav_" .. cat.id, sidebar)
        btn:SetHeight(28)
        btn:SetPoint("TOPLEFT", 8, y)
        btn:SetPoint("TOPRIGHT", -8, y)
        ApplyNavButton(btn, false)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetText(cat.label)
        lbl:SetTextColor(0.92, 0.85, 0.65, 1)
        btn._label = lbl
        btn:SetScript("OnClick", function()
            MainWindow.SelectCategory(cat.id)
        end)
        categoryButtons[cat.id] = btn
        y = y - 32
    end

    local main = CreateFrame("Frame", FRAME_NAME .. "Main", shell)
    main:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    main:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 30)
    ApplyParchment(main)

    categoryHeadTitle = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryHeadTitle:SetPoint("TOPLEFT", 12, -10)
    categoryHeadTitle:SetText("General")
    SetInk(categoryHeadTitle, TITLE_INK)

    categoryHeadSub = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    categoryHeadSub:SetPoint("TOPLEFT", categoryHeadTitle, "BOTTOMLEFT", 0, -2)
    categoryHeadSub:SetPoint("RIGHT", main, "RIGHT", -12, 0)
    categoryHeadSub:SetJustifyH("LEFT")
    SetInk(categoryHeadSub, { 0.28, 0.22, 0.12, 1 })

    local pageHost = CreateFrame("Frame", FRAME_NAME .. "PageHost", main)
    pageHost:SetPoint("TOPLEFT", 10, -48)
    pageHost:SetPoint("BOTTOMRIGHT", -10, 8)

    local footer = CreateFrame("Frame", FRAME_NAME .. "Footer", shell)
    footer:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -4)
    footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)

    footerStatus = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerStatus:SetPoint("LEFT", 4, 0)
    footerStatus:SetWidth(320)
    footerStatus:SetJustifyH("LEFT")
    SetInk(footerStatus, MUTED)

    local closeBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    closeBtn:SetSize(72, 22)
    closeBtn:SetPoint("RIGHT", 0, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    clearBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    clearBtn:SetSize(72, 22)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear")
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        if activeCategory == CAT_KICK then
            AscensionLFM.Database.ClearKicks()
            MainWindow.RefreshKicks()
        else
            AscensionLFM.Database.ClearMatches()
            MainWindow.RefreshMatches()
        end
        RefreshStatus()
    end)

    --------------------------------------------------------------------
    -- General
    --------------------------------------------------------------------
    local general = BuildCategoryPage(pageHost, CAT_GENERAL)

    local statusBox = CreateFrame("Frame", nil, general)
    statusBox:SetPoint("TOPLEFT", 0, 0)
    statusBox:SetPoint("TOPRIGHT", 0, 0)
    statusBox:SetHeight(48)
    ApplyInset(statusBox)
    statusFS = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFS:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 8, -8)
    statusFS:SetPoint("TOPRIGHT", statusBox, "TOPRIGHT", -8, -8)
    statusFS:SetJustifyH("LEFT")
    SetInk(statusFS, INK)

    CreateSectionLabel(general, "Mode", -58)

    local modeRow = CreateFrame("Frame", nil, general)
    modeRow:SetPoint("TOPLEFT", 0, -76)
    modeRow:SetPoint("TOPRIGHT", 0, -76)
    modeRow:SetHeight(28)

    local modes = {
        { "off", "Off", 0 },
        { "notify", "Notify only", 70 },
        { "seeking", "Seeking", 190 },
        { "hosting", "Hosting", 280 },
    }
    for _, m in ipairs(modes) do
        local key, label, x = m[1], m[2], m[3]
        local btn = CreateFrame("CheckButton", nil, modeRow, "UICheckButtonTemplate")
        btn:SetPoint("TOPLEFT", modeRow, "TOPLEFT", x, 0)
        btn:SetSize(24, 24)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "RIGHT", 2, 0)
        fs:SetText(label)
        SetInk(fs, INK)
        btn:SetScript("OnClick", function()
            AscensionLFM.Database.SetMode(key)
            SyncWidgetsFromDB()
        end)
        widgets.modeButtons[key] = btn
    end

    local modeHint = general:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeHint:SetPoint("TOPLEFT", 4, -116)
    modeHint:SetPoint("RIGHT", -4, 0)
    modeHint:SetJustifyH("LEFT")
    modeHint:SetText("|cff5a4010Off|r — Listening OFF (no chat scan).\n"
        .. "|cff5a4010Notify|r — Listening ON: print MS LFM/LFG to chat + Log (default).\n"
        .. "|cff5a4010Seeking|r — match open roles; optional auto-whisper LFM leaders.\n"
        .. "|cff5a4010Hosting|r — role whispers → invite only if accepted role + open slot.")
    SetInk(modeHint, MUTED)

    --------------------------------------------------------------------
    -- Seeking
    --------------------------------------------------------------------
    local seeking = BuildCategoryPage(pageHost, CAT_SEEKING)
    CreateSectionLabel(seeking, "My roles", -4)

    local seekRoles = CreateFrame("Frame", nil, seeking)
    seekRoles:SetPoint("TOPLEFT", 0, -22)
    seekRoles:SetPoint("TOPRIGHT", 0, -22)
    seekRoles:SetHeight(28)
    MakeRoleCheck(seekRoles, "tank", "Tank", 0, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "healer", "Healer", 90, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "aura", "Aura", 190, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "dps", "DPS", 280, 0, widgets.roleButtons)

    CreateSectionLabel(seeking, "Seeking options", -58)
    widgets.scanLfg = CreateToggleRow(seeking, -76,
        "Scan LFG MS lines",
        "Also notify on LFG Manastorm seekers (no auto-whisper to them).",
        false,
        function(on)
            AscensionLFM.Database.Get().scanLfg = on and true or false
        end)
    widgets.autoWhisper = CreateToggleRow(seeking, -128,
        "Auto-whisper LFM leader",
        "Rate-limited whisper when a listing still needs one of your roles. Off by default.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoWhisper = on and true or false
        end)

    local msgLabel = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgLabel:SetPoint("TOPLEFT", 4, -186)
    msgLabel:SetText("Whisper message")
    SetInk(msgLabel, INK)

    local edit = CreateFrame("EditBox", "AscensionLFMWhisperEdit", seeking, "InputBoxTemplate")
    edit:SetSize(220, 20)
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

    --------------------------------------------------------------------
    -- Hosting
    --------------------------------------------------------------------
    local hosting = BuildCategoryPage(pageHost, CAT_HOSTING)
    CreateSectionLabel(hosting, "Accept roles", -4)

    local hostRoles = CreateFrame("Frame", nil, hosting)
    hostRoles:SetPoint("TOPLEFT", 0, -22)
    hostRoles:SetPoint("TOPRIGHT", 0, -22)
    hostRoles:SetHeight(28)
    MakeRoleCheck(hostRoles, "tank", "Tank", 0, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "healer", "Healer", 90, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "aura", "Aura", 190, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "dps", "DPS", 280, 0, widgets.roleButtonsHost)

    CreateSectionLabel(hosting, "Invite", -58)
    widgets.autoInvite = CreateToggleRow(hosting, -76,
        "Auto-invite matching role whispers",
        "InviteUnit only when the whisper role is accepted and that slot is open.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoInvite = on and true or false
        end)
    widgets.requireRole = CreateToggleRow(hosting, -128,
        "Require role in whisper",
        "Default-deny whispers with no tank/heal/aura/dps cue. No blind invites.",
        false,
        function(on)
            AscensionLFM.Database.Get().requireRoleWhisper = on and true or false
        end)

    CreateSectionLabel(hosting, "Slots", -180)

    local slotRow = CreateFrame("Frame", nil, hosting)
    slotRow:SetPoint("TOPLEFT", 0, -200)
    slotRow:SetPoint("TOPRIGHT", 0, -200)
    slotRow:SetHeight(24)

    local maxLabel = slotRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLabel:SetPoint("LEFT", 4, 0)
    maxLabel:SetText("Max size")
    SetInk(maxLabel, INK)

    local maxEdit = CreateFrame("EditBox", "AscensionLFMMaxPartyEdit", slotRow, "InputBoxTemplate")
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

    local labels = { tank = "T", healer = "H", aura = "A", dps = "D" }
    local roles = { "tank", "healer", "aura", "dps" }
    local anchor = maxEdit
    for i, role in ipairs(roles) do
        local lbl = slotRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 14 or 8, 0)
        lbl:SetText(labels[role])
        SetInk(lbl, INK)
        local e = MakeSlotEdit(slotRow, role)
        e:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        widgets.slotEdits[role] = e
        anchor = e
    end

    slotsFS = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slotsFS:SetPoint("TOPLEFT", 4, -232)
    slotsFS:SetPoint("RIGHT", -4, 0)
    slotsFS:SetJustifyH("LEFT")
    SetInk(slotsFS, MUTED)

    local hostHint = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hostHint:SetPoint("TOPLEFT", 4, -252)
    hostHint:SetPoint("RIGHT", -4, 0)
    hostHint:SetJustifyH("LEFT")
    hostHint:SetText("Whisper roles: tank/OT/MT · heal/HPS · Aura of Exp / exp aura · dps/DD.")
    SetInk(hostHint, MUTED)

    --------------------------------------------------------------------
    -- Post (LFM compose / scan / repost)
    --------------------------------------------------------------------
    local post = BuildCategoryPage(pageHost, CAT_POST)
    CreateSectionLabel(post, "LFM message", -4)

    local previewBox = CreateFrame("Frame", nil, post)
    previewBox:SetPoint("TOPLEFT", 0, -22)
    previewBox:SetPoint("TOPRIGHT", 0, -22)
    previewBox:SetHeight(52)
    ApplyInset(previewBox)

    postPreviewEdit = CreateFrame("EditBox", "AscensionLFMPostPreview", previewBox, "InputBoxTemplate")
    postPreviewEdit:SetPoint("TOPLEFT", 8, -8)
    postPreviewEdit:SetPoint("BOTTOMRIGHT", -8, 8)
    postPreviewEdit:SetAutoFocus(false)
    postPreviewEdit:SetMaxLetters(255)
    postPreviewEdit:SetMultiLine(false)
    postPreviewEdit:SetScript("OnEnterPressed", function(self)
        if AscensionLFM.Poster and AscensionLFM.Poster.SetMessage then
            AscensionLFM.Poster.SetMessage(self:GetText() or "")
        end
        self:ClearFocus()
    end)
    postPreviewEdit:SetScript("OnEditFocusLost", function(self)
        if _syncingPost then
            return
        end
        if AscensionLFM.Poster and AscensionLFM.Poster.SetMessage then
            AscensionLFM.Poster.SetMessage(self:GetText() or "")
        end
    end)

    CreateSectionLabel(post, "Channel", -84)

    local chRow = CreateFrame("Frame", nil, post)
    chRow:SetPoint("TOPLEFT", 0, -102)
    chRow:SetPoint("TOPRIGHT", 0, -102)
    chRow:SetHeight(28)

    local channels = {
        { "YELL", "Yell", 0 },
        { "SAY", "Say", 70 },
        { "GUILD", "Guild", 140 },
        { "CHANNEL", "Channel", 220 },
    }
    for _, c in ipairs(channels) do
        local key, label, x = c[1], c[2], c[3]
        local btn = CreateFrame("CheckButton", nil, chRow, "UICheckButtonTemplate")
        btn:SetPoint("TOPLEFT", chRow, "TOPLEFT", x, 0)
        btn:SetSize(24, 24)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "RIGHT", 2, 0)
        fs:SetText(label)
        SetInk(fs, INK)
        btn:SetScript("OnClick", function()
            AscensionLFM.Database.Get().postChannel = key
            for k, b in pairs(widgets.channelButtons) do
                if b and b.SetChecked then
                    b:SetChecked(k == key)
                end
            end
        end)
        widgets.channelButtons[key] = btn
    end

    local chNameLbl = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chNameLbl:SetPoint("TOPLEFT", 4, -136)
    chNameLbl:SetText("Channel name")
    SetInk(chNameLbl, INK)

    local chNameEdit = CreateFrame("EditBox", "AscensionLFMPostChannelName", post, "InputBoxTemplate")
    chNameEdit:SetSize(140, 20)
    chNameEdit:SetPoint("LEFT", chNameLbl, "RIGHT", 8, 0)
    chNameEdit:SetAutoFocus(false)
    chNameEdit:SetMaxLetters(31)
    chNameEdit:SetScript("OnEnterPressed", function(self)
        AscensionLFM.Database.Get().postChannelName = self:GetText() or ""
        self:ClearFocus()
    end)
    chNameEdit:SetScript("OnEditFocusLost", function(self)
        AscensionLFM.Database.Get().postChannelName = self:GetText() or ""
    end)
    widgets.channelName = chNameEdit

    local btnRow = CreateFrame("Frame", nil, post)
    btnRow:SetPoint("TOPLEFT", 0, -164)
    btnRow:SetPoint("TOPRIGHT", 0, -164)
    btnRow:SetHeight(26)

    local rebuildBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    rebuildBtn:SetSize(110, 22)
    rebuildBtn:SetPoint("LEFT", 0, 0)
    rebuildBtn:SetText("Rebuild")
    rebuildBtn:SetScript("OnClick", function()
        if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
            AscensionLFM.Poster.RefreshMessage()
        end
        MainWindow.RefreshPost()
    end)

    local scanBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    scanBtn:SetSize(120, 22)
    scanBtn:SetPoint("LEFT", rebuildBtn, "RIGHT", 6, 0)
    scanBtn:SetText("Scan raid/party")
    scanBtn:SetScript("OnClick", function()
        if AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
            AscensionLFM.Slots.ScanRaid()
        end
        if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
            AscensionLFM.Poster.RefreshMessage()
        end
        MainWindow.RefreshSlots()
        MainWindow.RefreshPost()
        if AscensionLFM.Print then
            AscensionLFM.Print("scanned raid/party fills")
        end
    end)

    local postBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    postBtn:SetSize(90, 22)
    postBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)
    postBtn:SetText("Post once")
    postBtn:SetScript("OnClick", function()
        local msg = postPreviewEdit and postPreviewEdit.GetText and postPreviewEdit:GetText() or ""
        local db = AscensionLFM.Database.Get()
        if AscensionLFM.Poster and AscensionLFM.Poster.PostOnce then
            AscensionLFM.Poster.PostOnce(msg, db.postChannel, db.postChannelName)
        end
        MainWindow.RefreshPost()
    end)

    CreateSectionLabel(post, "Auto-repost", -200)
    widgets.autoRepost = CreateToggleRow(post, -218,
        "Enable auto-repost (Hosting only)",
        "Rebuild LFM from slots each tick. Stops when full or disabled. Default OFF.",
        false,
        function(on)
            local db = AscensionLFM.Database.Get()
            db.autoRepost = on and true or false
            if on and AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
                AscensionLFM.Poster.RefreshMessage()
            end
            MainWindow.RefreshPost()
        end)

    local intLbl = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intLbl:SetPoint("TOPLEFT", 4, -272)
    intLbl:SetText("Interval (sec, min 30)")
    SetInk(intLbl, INK)

    local intEdit = CreateFrame("EditBox", "AscensionLFMRepostInterval", post, "InputBoxTemplate")
    intEdit:SetSize(40, 20)
    intEdit:SetPoint("LEFT", intLbl, "RIGHT", 8, 0)
    intEdit:SetAutoFocus(false)
    intEdit:SetMaxLetters(3)
    intEdit:SetNumeric(true)
    intEdit:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText()) or 60
        if AscensionLFM.Poster and AscensionLFM.Poster.ClampInterval then
            n = AscensionLFM.Poster.ClampInterval(n)
        elseif n < 30 then
            n = 30
        end
        AscensionLFM.Database.Get().repostInterval = n
        self:SetText(tostring(n))
        self:ClearFocus()
        MainWindow.RefreshPost()
    end)
    intEdit:SetScript("OnEditFocusLost", function(self)
        local n = tonumber(self:GetText()) or 60
        if AscensionLFM.Poster and AscensionLFM.Poster.ClampInterval then
            n = AscensionLFM.Poster.ClampInterval(n)
        elseif n < 30 then
            n = 30
        end
        AscensionLFM.Database.Get().repostInterval = n
        self:SetText(tostring(n))
        MainWindow.RefreshPost()
    end)
    widgets.repostInterval = intEdit

    postStatusFS = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postStatusFS:SetPoint("TOPLEFT", 4, -300)
    postStatusFS:SetPoint("RIGHT", -4, 0)
    postStatusFS:SetJustifyH("LEFT")
    SetInk(postStatusFS, MUTED)

    local postHint = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postHint:SetPoint("TOPLEFT", 4, -320)
    postHint:SetPoint("RIGHT", -4, 0)
    postHint:SetJustifyH("LEFT")
    postHint:SetText("Example: LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS — filled from Hosting slots + Scan.")
    SetInk(postHint, MUTED)

    --------------------------------------------------------------------
    -- Kick
    --------------------------------------------------------------------
    local kick = BuildCategoryPage(pageHost, CAT_KICK)
    CreateSectionLabel(kick, "Level-59 auto-kick", -4)
    widgets.autoKick = CreateToggleRow(kick, -22,
        "Enable kick at level 59 + raid warning every 10s",
        "Hosting only · leader/assist · ignores self · RW then UninviteUnit. Default OFF.",
        true,
        function(on)
            AscensionLFM.Database.Get().autoKickLevel59 = on and true or false
            RefreshStatus()
        end)

    CreateSectionLabel(kick, "Recent kicks", -80)
    local kickBox = CreateFrame("Frame", nil, kick)
    kickBox:SetPoint("TOPLEFT", 0, -98)
    kickBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ApplyInset(kickBox)
    local ky = -10
    for i = 1, 6 do
        local fs = kickBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", kickBox, "TOPLEFT", 8, ky)
        fs:SetPoint("TOPRIGHT", kickBox, "TOPRIGHT", -8, ky)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        kickFS[i] = fs
        ky = ky - 16
    end

    --------------------------------------------------------------------
    -- Log
    --------------------------------------------------------------------
    local log = BuildCategoryPage(pageHost, CAT_LOG)
    CreateSectionLabel(log, "Recent Manastorm LFM/LFG matches", -4)
    local matchBox = CreateFrame("Frame", nil, log)
    matchBox:SetPoint("TOPLEFT", 0, -22)
    matchBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ApplyInset(matchBox)
    local my = -10
    for i = 1, 6 do
        local fs = matchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", matchBox, "TOPLEFT", 8, my)
        fs:SetPoint("TOPRIGHT", matchBox, "TOPRIGHT", -8, my)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        matchFS[i] = fs
        my = my - 36
    end

    frame:SetScript("OnShow", function()
        SyncWidgetsFromDB()
        MainWindow.SelectCategory(activeCategory)
    end)

    SyncWidgetsFromDB()
    MainWindow.SelectCategory(CAT_GENERAL)
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

function MainWindow.GetFrame()
    return frame
end
