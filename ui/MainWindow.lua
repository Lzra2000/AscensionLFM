-- AscensionLFM: ui/MainWindow.lua
-- Native DialogFrame settings with Categories sidebar (General / Seeking /
-- Hosting / Post / Queue / Kick / Log). Matches docs/sketch/ascension-lfm-mockup.html.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local MainWindow = {}
AscensionLFM.MainWindow = MainWindow

local FRAME_NAME = "AscensionLFMFrame"
local FRAME_WIDTH = 720
-- Dialog height fits common 768+ screens; tall category pages scroll.
local FRAME_HEIGHT = 560
local SIDEBAR_WIDTH = 148
-- Toggle rows: title + 2-line desc must fit without spilling into the next control.
local TOGGLE_ROW_H = 58
local TOGGLE_STEP = 68 -- row height + 10px gap

local CAT_GENERAL = "general"
local CAT_SEEKING = "seeking"
local CAT_HOSTING = "hosting"
local CAT_POST = "post"
local CAT_QUEUE = "queue"
local CAT_KICK = "kick"
local CAT_LOG = "log"

local CATEGORIES = {
    { id = CAT_GENERAL, label = "General",
      title = "General",
      sub = "Mode and status. Default Notify = Listening ON. Full Auto Hosting is opt-in OFF." },
    { id = CAT_SEEKING, label = "Seeking",
      title = "Seeking",
      sub = "Roles, rotating whisper variants, leader blacklist, optional match sound." },
    { id = CAT_HOSTING, label = "Hosting",
      title = "Hosting",
      sub = "Full Auto, slots, RW Role Check, reject re-whisper, presets, invite rules." },
    { id = CAT_POST, label = "Post",
      title = "Post",
      sub = "LFM compose, scan fills, RW Role Check, auto-repost + optional FULL announce." },
    { id = CAT_QUEUE, label = "Queue",
      title = "Queue",
      sub = "Recent applicant whispers — Invite or Reject+rewhisper." },
    { id = CAT_KICK, label = "Kick",
      title = "Kick",
      sub = "Opt-in level-59 auto-kick with raid warning. Dangerous — default OFF." },
    { id = CAT_LOG, label = "Log",
      title = "Log",
      sub = "Match history + activity (posts, invites, rejects, matches)." },
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
local roleCheckStatusFS
local postRoleCheckStatusFS
local matchFS = {}
local kickFS = {}
local activityFS = {}
local queueRows = {}
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
local presetLabelFS

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
    local fullBit = db.fullAutoHosting and " · |cff2a7a3aFull Auto ON|r" or ""
    statusFS:SetText(string.format("Status: %s  ·  Mode: |cffc8a03c%s|r%s%s%s",
        listening, ModeLabel(db.mode), fullBit, kickBit, last))

    if footerStatus then
        local kick = db.autoKickLevel59 and "Kick59 ON" or "Kick59 off"
        if activeCategory == CAT_KICK then
            footerStatus:SetText("Kick log · Clear removes kick history")
        elseif activeCategory == CAT_LOG then
            footerStatus:SetText("Match + activity · Clear removes both")
        elseif activeCategory == CAT_QUEUE then
            footerStatus:SetText("Applicant queue · Clear empties queue")
        else
            local fa = db.fullAutoHosting and "FullAuto ON" or "FullAuto off"
            footerStatus:SetText(string.format("%s · Mode %s · %s · %s",
                listeningOn and "Listening ON" or "Listening OFF",
                ModeLabel(db.mode), fa, kick))
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
    MainWindow.RefreshRoleCheck()
end

function MainWindow.RefreshRoleCheck()
    local text = "Role check idle"
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.GetStatus then
        local st = AscensionLFM.RoleCheck.GetStatus()
        if st and st.status then
            text = st.status
        end
    end
    if widgets.roleCheckStatus and widgets.roleCheckStatus.SetText then
        widgets.roleCheckStatus:SetText(text)
    end
    if roleCheckStatusFS and roleCheckStatusFS.SetText then
        roleCheckStatusFS:SetText(text)
    end
    if postRoleCheckStatusFS and postRoleCheckStatusFS.SetText then
        postRoleCheckStatusFS:SetText(text)
    end
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
    for i = 1, 5 do
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

function MainWindow.RefreshActivity()
    local db = AscensionLFM.Database.Get()
    local history = db.activityLog or {}
    for i = 1, 6 do
        local fs = activityFS[i]
        if fs then
            local a = history[i]
            if a then
                fs:SetText(string.format("|cff6a4a10[%s]|r %s",
                    tostring(a.kind or "?"), tostring(a.text or "")))
                fs:Show()
            else
                fs:SetText("")
                if i == 1 then
                    fs:SetText("|cff5a4a30No activity yet.|r")
                    fs:Show()
                else
                    fs:Hide()
                end
            end
        end
    end
end

function MainWindow.RefreshQueue()
    local list = AscensionLFM.Queue and AscensionLFM.Queue.Recent and AscensionLFM.Queue.Recent(5) or {}
    for i = 1, 5 do
        local row = queueRows[i]
        if row then
            local q = list[i]
            if q then
                local role = q.role and tostring(q.role) or "?"
                local st = tostring(q.status or "pending")
                row.label:SetText(string.format("|cff4a3010%s|r  |cff5a4a30[%s]|r  %s\n%s",
                    tostring(q.name or "?"), role, st, tostring(q.message or ""):sub(1, 60)))
                row.name = q.name
                row:Show()
                if row.inviteBtn then row.inviteBtn:Show() end
                if row.rejectBtn then row.rejectBtn:Show() end
            else
                row.name = nil
                row.label:SetText(i == 1 and "|cff5a4a30No applicants yet.|r" or "")
                if i == 1 then row:Show() else row:Hide() end
                if row.inviteBtn then row.inviteBtn:Hide() end
                if row.rejectBtn then row.rejectBtn:Hide() end
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
    if widgets.hostRoleButtons then
        for r, btn in pairs(widgets.hostRoleButtons) do
            if btn and btn.SetChecked then
                btn:SetChecked(db.hostRole == r)
            end
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
    if widgets.autoInviteLfg and widgets.autoInviteLfg.SetChecked then
        widgets.autoInviteLfg:SetChecked(db.autoInviteLfg ~= false)
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
    if widgets.autoMoveAura and widgets.autoMoveAura.SetChecked then
        widgets.autoMoveAura:SetChecked(db.autoMoveAura ~= false)
    end
    if widgets.fullAuto and widgets.fullAuto.SetChecked then
        widgets.fullAuto:SetChecked(db.fullAutoHosting and true or false)
    end
    if widgets.rejectRewhisper and widgets.rejectRewhisper.SetChecked then
        widgets.rejectRewhisper:SetChecked(db.rejectRewhisper and true or false)
    end
    if widgets.announceFull and widgets.announceFull.SetChecked then
        widgets.announceFull:SetChecked(db.announceFull and true or false)
    end
    if widgets.miniHud and widgets.miniHud.SetChecked then
        widgets.miniHud:SetChecked(db.miniHudShow ~= false)
    end
    if widgets.useVariants and widgets.useVariants.SetChecked then
        widgets.useVariants:SetChecked(db.useWhisperVariants ~= false)
    end
    if widgets.soundMatch and widgets.soundMatch.SetChecked then
        widgets.soundMatch:SetChecked(db.soundOnMatch and true or false)
    end
    if widgets.soundApplicant and widgets.soundApplicant.SetChecked then
        widgets.soundApplicant:SetChecked(db.soundOnApplicant and true or false)
    end
    if widgets.rejectTemplate and widgets.rejectTemplate.SetText then
        widgets.rejectTemplate:SetText(tostring(db.rejectTemplate or ""))
    end
    if widgets.roleCheckMsg and widgets.roleCheckMsg.SetText then
        widgets.roleCheckMsg:SetText(tostring(db.roleCheckMessage or ""))
    end
    if widgets.roleCheckWindow and widgets.roleCheckWindow.SetText then
        local w = 60
        local raw = db.roleCheckWindow or db.roleCheckDuration
        if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ClampWindow then
            w = AscensionLFM.RoleCheck.ClampWindow(raw)
        else
            w = tonumber(raw) or 60
        end
        widgets.roleCheckWindow:SetText(tostring(w))
    end
    if widgets.roleCheckAutoResync and widgets.roleCheckAutoResync.SetChecked then
        widgets.roleCheckAutoResync:SetChecked(db.roleCheckAutoResync ~= false)
    end
    if widgets.variant1 and widgets.variant1.SetText then
        local v = db.whisperVariants or {}
        widgets.variant1:SetText(tostring(v[1] or ""))
        if widgets.variant2 then widgets.variant2:SetText(tostring(v[2] or "")) end
        if widgets.variant3 then widgets.variant3:SetText(tostring(v[3] or "")) end
    end
    if presetLabelFS then
        local names = AscensionLFM.Presets and AscensionLFM.Presets.List and AscensionLFM.Presets.List() or {}
        presetLabelFS:SetText("Presets: " .. table.concat(names, ", "))
    end
    SyncSlotEdits()
    RefreshStatus()
    MainWindow.RefreshSlots()
    MainWindow.RefreshPost()
    MainWindow.RefreshMatches()
    MainWindow.RefreshKicks()
    MainWindow.RefreshActivity()
    MainWindow.RefreshQueue()
    MainWindow.RefreshRoleCheck()
end

function MainWindow.SyncFromDB()
    SyncWidgetsFromDB()
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
    row:SetHeight(TOGGLE_ROW_H)
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
    descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -3)
    descFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    if descFs.SetHeight then
        descFs:SetHeight(30)
    end
    descFs:SetJustifyH("LEFT")
    if descFs.SetJustifyV then
        descFs:SetJustifyV("TOP")
    end
    if descFs.SetNonSpaceWrap then
        descFs:SetNonSpaceWrap(true)
    end
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

-- Returns the scroll child where widgets are parented. Tall pages scroll
-- inside a UIPanelScrollFrame instead of clipping / overlapping.
local function BuildCategoryPage(parent, id, contentHeight)
    local page = CreateFrame("Frame", FRAME_NAME .. "Cat_" .. id, parent)
    page:SetAllPoints(parent)
    page:Hide()
    categoryPages[id] = page

    local scroll = CreateFrame("ScrollFrame", FRAME_NAME .. "Scroll_" .. id, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -28, 0)
    if scroll.EnableMouseWheel then
        scroll:EnableMouseWheel(true)
    end
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local max = 0
        if self.GetVerticalScrollRange then
            max = self:GetVerticalScrollRange() or 0
        end
        local nxt = cur - ((delta or 0) * 36)
        if nxt < 0 then nxt = 0 end
        if nxt > max then nxt = max end
        self:SetVerticalScroll(nxt)
    end)

    local child = CreateFrame("Frame", FRAME_NAME .. "Content_" .. id, scroll)
    child:SetWidth(480)
    child:SetHeight(contentHeight or 420)
    scroll:SetScrollChild(child)

    page:SetScript("OnShow", function()
        local w = scroll:GetWidth()
        if type(w) == "number" and w > 40 then
            child:SetWidth(w)
        end
        if scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(0)
        end
    end)

    return child
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
        if id == CAT_LOG or id == CAT_KICK or id == CAT_QUEUE then
            clearBtn:Show()
        else
            clearBtn:Hide()
        end
    end

    RefreshStatus()
end

local function CreateMainFrame()
    -- Prefer native dialog chrome; fall back if the template is missing on a client.
    local ok, f = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "UIPanelDialogTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", FRAME_NAME, UIParent)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true,
                tileSize = 32,
                edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
            f:SetBackdropColor(0, 0, 0, 1)
        end
    end
    return f
end

function MainWindow.Init()
    if frame then
        return
    end

    frame = CreateMainFrame()
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    if type(UISpecialFrames) == "table" then
        tinsert(UISpecialFrames, FRAME_NAME)
    end

    local title = _G[FRAME_NAME .. "Title"] or frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not _G[FRAME_NAME .. "Title"] then
        title:SetPoint("TOP", frame, "TOP", 0, -10)
    end
    title:SetText("AscensionLFM")
    SetInk(title, GOLD)

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("Manastorm Level Run LFM/LFG · v" .. tostring(AscensionLFM.VERSION or "0.4.16"))
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
        y = y - 28
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
    categoryHeadSub:SetPoint("TOPLEFT", categoryHeadTitle, "BOTTOMLEFT", 0, -3)
    categoryHeadSub:SetPoint("RIGHT", main, "RIGHT", -12, 0)
    if categoryHeadSub.SetHeight then
        categoryHeadSub:SetHeight(28)
    end
    categoryHeadSub:SetJustifyH("LEFT")
    if categoryHeadSub.SetJustifyV then
        categoryHeadSub:SetJustifyV("TOP")
    end
    if categoryHeadSub.SetNonSpaceWrap then
        categoryHeadSub:SetNonSpaceWrap(true)
    end
    SetInk(categoryHeadSub, { 0.28, 0.22, 0.12, 1 })

    local pageHost = CreateFrame("Frame", FRAME_NAME .. "PageHost", main)
    pageHost:SetPoint("TOPLEFT", 10, -54)
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
        elseif activeCategory == CAT_QUEUE then
            if AscensionLFM.Queue and AscensionLFM.Queue.Clear then
                AscensionLFM.Queue.Clear()
            end
            MainWindow.RefreshQueue()
        elseif activeCategory == CAT_LOG then
            AscensionLFM.Database.ClearMatches()
            if AscensionLFM.Activity and AscensionLFM.Activity.Clear then
                AscensionLFM.Activity.Clear()
            end
            MainWindow.RefreshMatches()
            MainWindow.RefreshActivity()
        else
            AscensionLFM.Database.ClearMatches()
            MainWindow.RefreshMatches()
        end
        RefreshStatus()
    end)

    --------------------------------------------------------------------
    -- General
    --------------------------------------------------------------------
    local general = BuildCategoryPage(pageHost, CAT_GENERAL, 320)

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
        .. "|cff5a4010Hosting|r — role whispers → invite only if accepted role + open slot.\n"
        .. "|cff5a4010Full Auto|r — Hosting category master (default OFF): invite + scan + repost + reject.")
    SetInk(modeHint, MUTED)

    CreateSectionLabel(general, "Mini Quick HUD", -210)
    widgets.miniHud = CreateToggleRow(general, -228,
        "Show floating quick bar",
        "LFM / RW / Sync / Wipe / Mobs / FULL / Regrp / Need — no /alfm. Drag to move. Default ON.",
        false,
        function(on)
            if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.SetShown then
                AscensionLFM.MiniHUD.SetShown(on)
            else
                AscensionLFM.Database.Get().miniHudShow = on and true or false
            end
        end)

    --------------------------------------------------------------------
    -- Seeking
    --------------------------------------------------------------------
    local seeking = BuildCategoryPage(pageHost, CAT_SEEKING, 520)
    CreateSectionLabel(seeking, "My roles", -4)

    local seekRoles = CreateFrame("Frame", nil, seeking)
    seekRoles:SetPoint("TOPLEFT", 0, -22)
    seekRoles:SetPoint("TOPRIGHT", 0, -22)
    seekRoles:SetHeight(28)
    MakeRoleCheck(seekRoles, "tank", "Tank", 0, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "healer", "Healer", 90, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "aura", "Aura", 190, 0, widgets.roleButtons)
    MakeRoleCheck(seekRoles, "dps", "DPS", 280, 0, widgets.roleButtons)

    CreateSectionLabel(seeking, "Seeking options", -62)
    widgets.scanLfg = CreateToggleRow(seeking, -80,
        "Scan LFG MS lines",
        "Also notify on LFG Manastorm seekers (no auto-whisper to them).",
        false,
        function(on)
            AscensionLFM.Database.Get().scanLfg = on and true or false
        end)
    widgets.autoWhisper = CreateToggleRow(seeking, -80 - TOGGLE_STEP,
        "Auto-whisper LFM leader",
        "Rate-limited whisper when a listing still needs one of your roles. Off by default.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoWhisper = on and true or false
        end)

    local msgLabel = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgLabel:SetPoint("TOPLEFT", 4, -228)
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

    widgets.useVariants = CreateToggleRow(seeking, -256,
        "Rotate whisper variants ({role})",
        "Cycles 2–3 templates below. {role} becomes tank/healer/aura/dps. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().useWhisperVariants = on and true or false
        end)

    local v1l = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v1l:SetPoint("TOPLEFT", 4, -326)
    v1l:SetText("V1")
    SetInk(v1l, INK)
    local v1 = CreateFrame("EditBox", "AscensionLFMVariant1", seeking, "InputBoxTemplate")
    v1:SetSize(200, 18)
    v1:SetPoint("LEFT", v1l, "RIGHT", 6, 0)
    v1:SetAutoFocus(false)
    v1:SetMaxLetters(80)
    local function saveVariant(idx, box)
        local db = AscensionLFM.Database.Get()
        if type(db.whisperVariants) ~= "table" then db.whisperVariants = {} end
        db.whisperVariants[idx] = box:GetText() or ""
    end
    v1:SetScript("OnEnterPressed", function(self) saveVariant(1, self); self:ClearFocus() end)
    v1:SetScript("OnEditFocusLost", function(self) saveVariant(1, self) end)
    widgets.variant1 = v1

    local v2l = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v2l:SetPoint("TOPLEFT", 4, -352)
    v2l:SetText("V2")
    SetInk(v2l, INK)
    local v2 = CreateFrame("EditBox", "AscensionLFMVariant2", seeking, "InputBoxTemplate")
    v2:SetSize(200, 18)
    v2:SetPoint("LEFT", v2l, "RIGHT", 6, 0)
    v2:SetAutoFocus(false)
    v2:SetMaxLetters(80)
    v2:SetScript("OnEnterPressed", function(self) saveVariant(2, self); self:ClearFocus() end)
    v2:SetScript("OnEditFocusLost", function(self) saveVariant(2, self) end)
    widgets.variant2 = v2

    local v3l = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v3l:SetPoint("TOPLEFT", 4, -378)
    v3l:SetText("V3")
    SetInk(v3l, INK)
    local v3 = CreateFrame("EditBox", "AscensionLFMVariant3", seeking, "InputBoxTemplate")
    v3:SetSize(200, 18)
    v3:SetPoint("LEFT", v3l, "RIGHT", 6, 0)
    v3:SetAutoFocus(false)
    v3:SetMaxLetters(80)
    v3:SetScript("OnEnterPressed", function(self) saveVariant(3, self); self:ClearFocus() end)
    v3:SetScript("OnEditFocusLost", function(self) saveVariant(3, self) end)
    widgets.variant3 = v3

    widgets.soundMatch = CreateToggleRow(seeking, -406,
        "Sound on new match",
        "Play a sound when a Manastorm listing is logged. Opt-in OFF.",
        false,
        function(on)
            AscensionLFM.Database.Get().soundOnMatch = on and true or false
        end)

    local blLbl = seeking:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    blLbl:SetPoint("TOPLEFT", 4, -480)
    blLbl:SetText("Blacklist leader")
    SetInk(blLbl, INK)
    local blEdit = CreateFrame("EditBox", "AscensionLFMBlacklistEdit", seeking, "InputBoxTemplate")
    blEdit:SetSize(120, 18)
    blEdit:SetPoint("LEFT", blLbl, "RIGHT", 6, 0)
    blEdit:SetAutoFocus(false)
    blEdit:SetMaxLetters(24)
    widgets.blacklistEdit = blEdit
    local blAdd = CreateFrame("Button", nil, seeking, "UIPanelButtonTemplate")
    blAdd:SetSize(50, 20)
    blAdd:SetPoint("LEFT", blEdit, "RIGHT", 4, 0)
    blAdd:SetText("Add")
    blAdd:SetScript("OnClick", function()
        local name = blEdit:GetText() or ""
        if AscensionLFM.Database.AddLeaderBlacklist(name) then
            blEdit:SetText("")
            if AscensionLFM.Print then AscensionLFM.Print("blacklisted " .. name) end
        end
    end)
    local blRem = CreateFrame("Button", nil, seeking, "UIPanelButtonTemplate")
    blRem:SetSize(64, 20)
    blRem:SetPoint("LEFT", blAdd, "RIGHT", 4, 0)
    blRem:SetText("Remove")
    blRem:SetScript("OnClick", function()
        local name = blEdit:GetText() or ""
        AscensionLFM.Database.RemoveLeaderBlacklist(name)
        blEdit:SetText("")
    end)

    --------------------------------------------------------------------
    -- Hosting
    --------------------------------------------------------------------
    local hosting = BuildCategoryPage(pageHost, CAT_HOSTING, 1120)
    CreateSectionLabel(hosting, "Full Auto", -4)
    widgets.fullAuto = CreateToggleRow(hosting, -22,
        "Full Auto Hosting (master)",
        "ON: Hosting + accept T/H/A/D + whisper invite + LFG invite + scan + repost + reject-rewhisper. Default OFF.",
        false,
        function(on)
            AscensionLFM.Database.SetFullAutoHosting(on)
        end)

    CreateSectionLabel(hosting, "Accept roles", -96)
    local hostRoles = CreateFrame("Frame", nil, hosting)
    hostRoles:SetPoint("TOPLEFT", 0, -114)
    hostRoles:SetPoint("TOPRIGHT", 0, -114)
    hostRoles:SetHeight(24)
    MakeRoleCheck(hostRoles, "tank", "Tank", 0, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "healer", "Healer", 90, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "aura", "Aura", 190, 0, widgets.roleButtonsHost)
    MakeRoleCheck(hostRoles, "dps", "DPS", 280, 0, widgets.roleButtonsHost)

    -- My host role: which role YOU take (Slots.EnsureHostAssigned picks this
    -- when set, instead of guessing). Applies to your own slot immediately —
    -- not just a preference for the next auto-assign. "Auto" clears it and
    -- lets the host auto-pick an open accepted role again (default).
    CreateSectionLabel(hosting, "My host role", -156)
    local hostRoleRow = CreateFrame("Frame", nil, hosting)
    hostRoleRow:SetPoint("TOPLEFT", 0, -174)
    hostRoleRow:SetPoint("TOPRIGHT", 0, -174)
    hostRoleRow:SetHeight(24)
    widgets.hostRoleButtons = {}

    local function SyncHostRoleButtons(activeRole)
        for r, btn in pairs(widgets.hostRoleButtons) do
            if btn and btn.SetChecked then
                btn:SetChecked(r == activeRole)
            end
        end
    end

    local function SetHostRole(role)
        local hdb = AscensionLFM.Database.Get()
        hdb.hostRole = role
        if role and type(UnitName) == "function" then
            local me = UnitName("player")
            if me and AscensionLFM.Slots and AscensionLFM.Slots.Assign then
                AscensionLFM.Slots.Assign(me, role)
            end
        end
        SyncHostRoleButtons(role)
        MainWindow.RefreshSlots()
    end

    local function ClearHostRole()
        local hdb = AscensionLFM.Database.Get()
        hdb.hostRole = nil
        if type(UnitName) == "function" then
            local me = UnitName("player")
            if me and AscensionLFM.Slots and AscensionLFM.Slots.ClearName then
                AscensionLFM.Slots.ClearName(me)
            end
        end
        SyncHostRoleButtons(nil)
        MainWindow.RefreshSlots()
    end

    local function MakeHostRoleCheck(parent, role, label, x, y)
        local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        btn:SetSize(24, 24)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "RIGHT", 2, 0)
        fs:SetText(label)
        SetInk(fs, INK)
        btn:SetScript("OnClick", function(self)
            if CheckButtonIsOn(self) then
                SetHostRole(role)
            else
                ClearHostRole()
            end
        end)
        widgets.hostRoleButtons[role] = btn
        return btn
    end

    MakeHostRoleCheck(hostRoleRow, "tank", "Tank", 0, 0)
    MakeHostRoleCheck(hostRoleRow, "healer", "Healer", 90, 0)
    MakeHostRoleCheck(hostRoleRow, "aura", "Aura", 190, 0)
    MakeHostRoleCheck(hostRoleRow, "dps", "DPS", 280, 0)

    local hostRoleAutoBtn = CreateFrame("Button", nil, hostRoleRow, "UIPanelButtonTemplate")
    hostRoleAutoBtn:SetSize(56, 20)
    hostRoleAutoBtn:SetPoint("LEFT", hostRoleRow, "LEFT", 380, 0)
    hostRoleAutoBtn:SetText("Auto")
    hostRoleAutoBtn:SetScript("OnClick", ClearHostRole)

    local hostRoleHint = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hostRoleHint:SetPoint("TOPLEFT", 4, -210)
    hostRoleHint:SetPoint("RIGHT", -4, 0)
    hostRoleHint:SetJustifyH("LEFT")
    hostRoleHint:SetText("Sets your own slot immediately.\n"
        .. "Auto lets the host auto-pick an open accepted role again (default).")
    SetInk(hostRoleHint, MUTED)

    CreateSectionLabel(hosting, "Invite + reject", -258)
    local hy = -276
    widgets.autoInvite = CreateToggleRow(hosting, hy,
        "Auto-invite matching role whispers",
        "InviteUnit when role accepted + slot open. Full Auto turns this on.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoInvite = on and true or false
        end)
    hy = hy - TOGGLE_STEP
    widgets.autoInviteLfg = CreateToggleRow(hosting, hy,
        "Auto-invite LFG seekers (chat)",
        "When someone posts LFG MS with a role you need + open slot → InviteUnit. Default ON while Hosting.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoInviteLfg = on and true or false
        end)
    hy = hy - TOGGLE_STEP
    widgets.requireRole = CreateToggleRow(hosting, hy,
        "Require role in whisper / LFG",
        "Default-deny whispers/LFG lines with no tank/heal/aura/dps cue.",
        false,
        function(on)
            AscensionLFM.Database.Get().requireRoleWhisper = on and true or false
        end)
    hy = hy - TOGGLE_STEP
    widgets.rejectRewhisper = CreateToggleRow(hosting, hy,
        "Reject re-whisper (slot/group full / no role)",
        "Whisper templates with {role} {filled} {max}. Rate-limited; ignore list. Default OFF.",
        false,
        function(on)
            AscensionLFM.Database.Get().rejectRewhisper = on and true or false
        end)

    local rtY = hy - TOGGLE_ROW_H - 12
    local rtLbl = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rtLbl:SetPoint("TOPLEFT", 4, rtY)
    rtLbl:SetText("Reject tmpl")
    SetInk(rtLbl, INK)
    local rtEdit = CreateFrame("EditBox", "AscensionLFMRejectTmpl", hosting, "InputBoxTemplate")
    rtEdit:SetSize(320, 18)
    rtEdit:SetPoint("LEFT", rtLbl, "RIGHT", 6, 0)
    rtEdit:SetAutoFocus(false)
    rtEdit:SetMaxLetters(120)
    rtEdit:SetScript("OnEnterPressed", function(self)
        AscensionLFM.Database.Get().rejectTemplate = self:GetText() or ""
        self:ClearFocus()
    end)
    rtEdit:SetScript("OnEditFocusLost", function(self)
        AscensionLFM.Database.Get().rejectTemplate = self:GetText() or ""
    end)
    widgets.rejectTemplate = rtEdit

    hy = rtY - 28
    widgets.soundApplicant = CreateToggleRow(hosting, hy,
        "Sound on applicant whisper",
        "Play TellMessage when a hosting whisper arrives. Opt-in OFF.",
        false,
        function(on)
            AscensionLFM.Database.Get().soundOnApplicant = on and true or false
        end)

    local presetSecY = hy - TOGGLE_ROW_H - 16
    CreateSectionLabel(hosting, "Presets", presetSecY)
    local presetRow = CreateFrame("Frame", nil, hosting)
    presetRow:SetPoint("TOPLEFT", 0, presetSecY - 18)
    presetRow:SetPoint("TOPRIGHT", 0, presetSecY - 18)
    presetRow:SetHeight(24)
    local load2337 = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    load2337:SetSize(100, 20)
    load2337:SetPoint("LEFT", 0, 0)
    load2337:SetText("MS 2/3/3/7")
    load2337:SetScript("OnClick", function()
        if AscensionLFM.Presets then AscensionLFM.Presets.Load("MS 2/3/3/7") end
        SyncWidgetsFromDB()
    end)
    local load2255 = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    load2255:SetSize(100, 20)
    load2255:SetPoint("LEFT", load2337, "RIGHT", 4, 0)
    load2255:SetText("MS 2/2/2/5")
    load2255:SetScript("OnClick", function()
        if AscensionLFM.Presets then AscensionLFM.Presets.Load("MS 2/2/2/5") end
        SyncWidgetsFromDB()
    end)
    local pName = CreateFrame("EditBox", "AscensionLFMPresetName", presetRow, "InputBoxTemplate")
    pName:SetSize(80, 18)
    pName:SetPoint("LEFT", load2255, "RIGHT", 8, 0)
    pName:SetAutoFocus(false)
    pName:SetMaxLetters(24)
    pName:SetText("My MS")
    local pSave = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    pSave:SetSize(50, 20)
    pSave:SetPoint("LEFT", pName, "RIGHT", 4, 0)
    pSave:SetText("Save")
    pSave:SetScript("OnClick", function()
        if AscensionLFM.Presets then AscensionLFM.Presets.Save(pName:GetText()) end
        SyncWidgetsFromDB()
    end)
    presetLabelFS = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    presetLabelFS:SetPoint("TOPLEFT", 4, presetSecY - 46)
    presetLabelFS:SetPoint("RIGHT", -4, 0)
    presetLabelFS:SetJustifyH("LEFT")
    SetInk(presetLabelFS, MUTED)

    local slotsY = presetSecY - 70
    CreateSectionLabel(hosting, "Slots", slotsY)
    local slotRow = CreateFrame("Frame", nil, hosting)
    slotRow:SetPoint("TOPLEFT", 0, slotsY - 18)
    slotRow:SetPoint("TOPRIGHT", 0, slotsY - 18)
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
    slotsFS:SetPoint("TOPLEFT", 4, slotsY - 46)
    slotsFS:SetPoint("RIGHT", -4, 0)
    slotsFS:SetJustifyH("LEFT")
    SetInk(slotsFS, MUTED)

    local rcY = slotsY - 72
    CreateSectionLabel(hosting, "Role Check", rcY)
    widgets.autoMoveAura = CreateToggleRow(hosting, rcY - 18,
        "Auto-move Auras (1 per raid group)",
        "Keep at most one Aura player in each raid group (1–8). Extra Auras are moved to empty groups. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoMoveAura = on and true or false
            if on and AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.Balance then
                AscensionLFM.AuraBalance.Balance()
            end
        end)
    widgets.roleCheckAutoResync = CreateToggleRow(hosting, rcY - 18 - TOGGLE_STEP,
        "Auto-resync after listening window",
        "When the window ends: remove leavers, apply whispered roles, refresh filled counts. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().roleCheckAutoResync = on and true or false
        end)

    local rcFieldsY = rcY - 18 - TOGGLE_STEP - TOGGLE_ROW_H - 12
    local rcMsgLbl = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rcMsgLbl:SetPoint("TOPLEFT", 4, rcFieldsY)
    rcMsgLbl:SetText("RW message")
    SetInk(rcMsgLbl, INK)
    local rcMsg = CreateFrame("EditBox", "AscensionLFMRoleCheckMsg", hosting, "InputBoxTemplate")
    rcMsg:SetSize(340, 18)
    rcMsg:SetPoint("LEFT", rcMsgLbl, "RIGHT", 6, 0)
    rcMsg:SetAutoFocus(false)
    rcMsg:SetMaxLetters(200)
    rcMsg:SetScript("OnEnterPressed", function(self)
        AscensionLFM.Database.Get().roleCheckMessage = self:GetText() or ""
        self:ClearFocus()
    end)
    rcMsg:SetScript("OnEditFocusLost", function(self)
        AscensionLFM.Database.Get().roleCheckMessage = self:GetText() or ""
    end)
    widgets.roleCheckMsg = rcMsg

    local rcWinLbl = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rcWinLbl:SetPoint("TOPLEFT", 4, rcFieldsY - 26)
    rcWinLbl:SetText("Window (sec)")
    SetInk(rcWinLbl, INK)
    local rcWin = CreateFrame("EditBox", "AscensionLFMRoleCheckWindow", hosting, "InputBoxTemplate")
    rcWin:SetSize(40, 18)
    rcWin:SetPoint("LEFT", rcWinLbl, "RIGHT", 6, 0)
    rcWin:SetAutoFocus(false)
    rcWin:SetMaxLetters(3)
    rcWin:SetNumeric(true)
    local function commitWindow(self)
        local n = tonumber(self:GetText()) or 60
        if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ClampWindow then
            n = AscensionLFM.RoleCheck.ClampWindow(n)
        end
        local db = AscensionLFM.Database.Get()
        db.roleCheckWindow = n
        db.roleCheckDuration = n
        self:SetText(tostring(n))
    end
    rcWin:SetScript("OnEnterPressed", function(self)
        commitWindow(self)
        self:ClearFocus()
    end)
    rcWin:SetScript("OnEditFocusLost", commitWindow)
    widgets.roleCheckWindow = rcWin

    local rcBtnRow = CreateFrame("Frame", nil, hosting)
    rcBtnRow:SetPoint("TOPLEFT", 0, rcFieldsY - 52)
    rcBtnRow:SetPoint("TOPRIGHT", 0, rcFieldsY - 52)
    rcBtnRow:SetHeight(24)

    local rwBtn = CreateFrame("Button", nil, rcBtnRow, "UIPanelButtonTemplate")
    rwBtn:SetSize(120, 22)
    rwBtn:SetPoint("LEFT", 0, 0)
    rwBtn:SetText("RW Role Check")
    rwBtn:SetScript("OnClick", function()
        -- Same path as Mini HUD RW (announce fallback when not hosting / no privilege)
        if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.ActionRoleCheck then
            AscensionLFM.MiniHUD.ActionRoleCheck()
        elseif AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.StartCheck then
            local ok, reason = AscensionLFM.RoleCheck.StartCheck()
            if not ok and AscensionLFM.Print then
                AscensionLFM.Print("Role Check: " .. tostring(reason))
            end
        end
        MainWindow.RefreshRoleCheck()
    end)

    local resyncBtn = CreateFrame("Button", nil, rcBtnRow, "UIPanelButtonTemplate")
    resyncBtn:SetSize(130, 22)
    resyncBtn:SetPoint("LEFT", rwBtn, "RIGHT", 6, 0)
    resyncBtn:SetText("Resync roles now")
    resyncBtn:SetScript("OnClick", function()
        if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ResyncNow then
            AscensionLFM.RoleCheck.ResyncNow()
        elseif AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
            AscensionLFM.Slots.ScanRaid()
        end
        MainWindow.RefreshRoleCheck()
        MainWindow.RefreshSlots()
        MainWindow.RefreshPost()
    end)

    widgets.roleCheckStatus = hosting:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    widgets.roleCheckStatus:SetPoint("TOPLEFT", 4, rcFieldsY - 82)
    widgets.roleCheckStatus:SetPoint("RIGHT", -4, 0)
    widgets.roleCheckStatus:SetJustifyH("LEFT")
    SetInk(widgets.roleCheckStatus, MUTED)
    widgets.roleCheckStatus:SetText("Role check idle")
    roleCheckStatusFS = widgets.roleCheckStatus

    --------------------------------------------------------------------
    -- Post (LFM compose / scan / repost)
    --------------------------------------------------------------------
    local post = BuildCategoryPage(pageHost, CAT_POST, 560)
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
        local unassigned = 0
        if AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
            local _, _, u = AscensionLFM.Slots.ScanRaid()
            unassigned = tonumber(u) or 0
        end
        if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
            AscensionLFM.Poster.RefreshMessage()
        end
        MainWindow.RefreshSlots()
        MainWindow.RefreshPost()
        if AscensionLFM.Print then
            AscensionLFM.Print("scanned raid/party fills")
            if unassigned > 0 then
                AscensionLFM.Print(string.format(
                    "%d in group without role — Mini HUD RW, reply T/H/A/D", unassigned))
            end
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

    local rcPostRow = CreateFrame("Frame", nil, post)
    rcPostRow:SetPoint("TOPLEFT", 0, -196)
    rcPostRow:SetPoint("TOPRIGHT", 0, -196)
    rcPostRow:SetHeight(26)

    local postRwBtn = CreateFrame("Button", nil, rcPostRow, "UIPanelButtonTemplate")
    postRwBtn:SetSize(120, 22)
    postRwBtn:SetPoint("LEFT", 0, 0)
    postRwBtn:SetText("RW Role Check")
    postRwBtn:SetScript("OnClick", function()
        if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.ActionRoleCheck then
            AscensionLFM.MiniHUD.ActionRoleCheck()
        elseif AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.StartCheck then
            local ok, reason = AscensionLFM.RoleCheck.StartCheck()
            if not ok and AscensionLFM.Print then
                AscensionLFM.Print("Role Check: " .. tostring(reason))
            end
        end
        MainWindow.RefreshRoleCheck()
    end)

    local postResyncBtn = CreateFrame("Button", nil, rcPostRow, "UIPanelButtonTemplate")
    postResyncBtn:SetSize(130, 22)
    postResyncBtn:SetPoint("LEFT", postRwBtn, "RIGHT", 6, 0)
    postResyncBtn:SetText("Resync roles now")
    postResyncBtn:SetScript("OnClick", function()
        if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ResyncNow then
            AscensionLFM.RoleCheck.ResyncNow()
        elseif AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
            AscensionLFM.Slots.ScanRaid()
        end
        MainWindow.RefreshRoleCheck()
        MainWindow.RefreshSlots()
        MainWindow.RefreshPost()
    end)

    postRoleCheckStatusFS = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postRoleCheckStatusFS:SetPoint("TOPLEFT", 4, -226)
    postRoleCheckStatusFS:SetPoint("RIGHT", -4, 0)
    postRoleCheckStatusFS:SetJustifyH("LEFT")
    SetInk(postRoleCheckStatusFS, MUTED)
    postRoleCheckStatusFS:SetText("Role check idle")

    CreateSectionLabel(post, "Auto-repost", -250)
    widgets.autoRepost = CreateToggleRow(post, -268,
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
    widgets.announceFull = CreateToggleRow(post, -268 - TOGGLE_STEP,
        "Announce FULL when stopping",
        "Optional one public FULL line when auto-repost stops. Default OFF.",
        false,
        function(on)
            AscensionLFM.Database.Get().announceFull = on and true or false
        end)

    local intLbl = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intLbl:SetPoint("TOPLEFT", 4, -406)
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
    postStatusFS:SetPoint("TOPLEFT", 4, -434)
    postStatusFS:SetPoint("RIGHT", -4, 0)
    postStatusFS:SetJustifyH("LEFT")
    SetInk(postStatusFS, MUTED)

    local postHint = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postHint:SetPoint("TOPLEFT", 4, -456)
    postHint:SetPoint("RIGHT", -4, 0)
    postHint:SetJustifyH("LEFT")
    postHint:SetText("Example: LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS — filled from Hosting slots + Scan.")
    SetInk(postHint, MUTED)

    --------------------------------------------------------------------
    -- Queue (applicants)
    --------------------------------------------------------------------
    local queue = BuildCategoryPage(pageHost, CAT_QUEUE)
    CreateSectionLabel(queue, "Recent applicant whispers", -4)
    local qHint = queue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qHint:SetPoint("TOPLEFT", 4, -20)
    qHint:SetPoint("RIGHT", -4, 0)
    qHint:SetJustifyH("LEFT")
    qHint:SetText("Hosting whispers land here. Invite uses InviteUnit; Reject sends re-whisper once.")
    SetInk(qHint, MUTED)

    local qy = -44
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, queue)
        row:SetPoint("TOPLEFT", 0, qy)
        row:SetPoint("TOPRIGHT", 0, qy)
        row:SetHeight(48)
        ApplyInset(row)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 8, -6)
        lbl:SetPoint("RIGHT", row, "RIGHT", -150, 0)
        lbl:SetJustifyH("LEFT")
        SetInk(lbl, INK)
        row.label = lbl
        local inv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        inv:SetSize(64, 20)
        inv:SetPoint("TOPRIGHT", -8, -6)
        inv:SetText("Invite")
        inv:SetScript("OnClick", function()
            if row.name and AscensionLFM.Queue then
                AscensionLFM.Queue.Invite(row.name)
                MainWindow.RefreshQueue()
            end
        end)
        row.inviteBtn = inv
        local rej = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        rej:SetSize(110, 20)
        rej:SetPoint("TOPRIGHT", -8, -28)
        rej:SetText("Reject+whisp")
        rej:SetScript("OnClick", function()
            if row.name and AscensionLFM.Queue then
                AscensionLFM.Queue.Reject(row.name)
                MainWindow.RefreshQueue()
            end
        end)
        row.rejectBtn = rej
        row:Hide()
        queueRows[i] = row
        qy = qy - 54
    end

    --------------------------------------------------------------------
    -- Kick
    --------------------------------------------------------------------
    local kick = BuildCategoryPage(pageHost, CAT_KICK)
    CreateSectionLabel(kick, "Level-59 auto-kick", -4)
    widgets.autoKick = CreateToggleRow(kick, -22,
        "Enable kick at level 59 + raid warning every 10s",
        "Hosting/Full Auto · lead/assist · ignores self · RW then kick (deferred). /alfm status shows why. Default OFF.",
        true,
        function(on)
            AscensionLFM.Database.Get().autoKickLevel59 = on and true or false
            RefreshStatus()
        end)

    CreateSectionLabel(kick, "Recent kicks", -92)
    local kickBox = CreateFrame("Frame", nil, kick)
    kickBox:SetPoint("TOPLEFT", 0, -110)
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
    CreateSectionLabel(log, "Recent matches", -4)
    local matchBox = CreateFrame("Frame", nil, log)
    matchBox:SetPoint("TOPLEFT", 0, -20)
    matchBox:SetPoint("TOPRIGHT", 0, -20)
    matchBox:SetHeight(200)
    ApplyInset(matchBox)
    local my = -8
    for i = 1, 5 do
        local fs = matchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", matchBox, "TOPLEFT", 8, my)
        fs:SetPoint("TOPRIGHT", matchBox, "TOPRIGHT", -8, my)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        matchFS[i] = fs
        my = my - 36
    end

    CreateSectionLabel(log, "Activity (posts / invites / rejects / matches)", -230)
    local actBox = CreateFrame("Frame", nil, log)
    actBox:SetPoint("TOPLEFT", 0, -248)
    actBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ApplyInset(actBox)
    local ay = -8
    for i = 1, 6 do
        local fs = actBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", actBox, "TOPLEFT", 8, ay)
        fs:SetPoint("TOPRIGHT", actBox, "TOPRIGHT", -8, ay)
        fs:SetJustifyH("LEFT")
        SetInk(fs, INK)
        activityFS[i] = fs
        ay = ay - 18
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
    if not frame then
        error("AscensionLFMFrame failed to create")
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
    if not frame then
        error("AscensionLFMFrame failed to create")
    end
    frame:Show()
end

function MainWindow.GetFrame()
    return frame
end
