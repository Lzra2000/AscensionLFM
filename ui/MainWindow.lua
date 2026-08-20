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
local FRAME_WIDTH = 760
-- Dialog height fits common 768+ screens; tall category pages scroll.
local FRAME_HEIGHT = 600
local SIDEBAR_WIDTH = 158
-- Toggle rows: title + 2-line desc must fit without spilling into the next control.
local TOGGLE_ROW_H = 66
local TOGGLE_STEP = 74 -- row height + gap (no overlap)

local CAT_GENERAL = "general"
local CAT_SEEKING = "seeking"
local CAT_HOSTING = "hosting"
local CAT_POST = "post"
local CAT_QUEUE = "queue"
local CAT_ROSTER = "roster"
local CAT_CONTENT = "content"
local CAT_KICK = "kick"
local CAT_APPEARANCE = "appearance"
local CAT_LOG = "log"

local CATEGORIES = {
    { id = CAT_GENERAL, label = "General",
      title = "General",
      sub = "Mode, Mini HUD, message delivery routing. Default Notify = Listening ON." },
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
      sub = "Recent applicant whispers - Invite or Reject+rewhisper." },
    { id = CAT_ROSTER, label = "Roster",
      title = "Roster",
      sub = "Groups 1-8: click role icon for popup, Ready check, Spec, X to remove." },
    { id = CAT_CONTENT, label = "LFG/LFM",
      title = "LFG/LFM",
      sub = "Pick MS, Raid, or M+ - each keeps its own settings and tags the LFM post." },
    { id = CAT_KICK, label = "Kick",
      title = "Kick",
      sub = "Level-59 kick + Aura buff scan (idle if buff hidden on others). Default OFF." },
    { id = CAT_APPEARANCE, label = "Appearance",
      title = "Appearance",
      sub = "DragonUI chrome only: metal nineslice size/offsets. Requires /reload after changes." },
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

-- High-contrast light-on-dark (readable on DragonUI rock panels).
local INK = { 0.96, 0.92, 0.82, 1 }       -- primary body text
local GOLD = { 1.00, 0.86, 0.28, 1 }      -- accents / highlights
local MUTED = { 0.82, 0.76, 0.60, 1 }     -- secondary / descriptions
local TITLE_INK = { 1.00, 0.88, 0.35, 1 } -- page titles
local SECTION = { 1.00, 0.84, 0.40, 1 }   -- section headers
local DANGER = { 1.00, 0.42, 0.32, 1 }    -- warnings / errors

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
local sessionSummaryFS = nil
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

local function RockPath()
    if AscensionLFM.Chrome and AscensionLFM.Chrome.BackgroundPath then
        return AscensionLFM.Chrome.BackgroundPath()
    end
    -- Chrome module missing entirely (shouldn't happen given TOC load
    -- order) - fall back to the classic Blizzard texture, never DragonUI.
    return "Interface\\DialogFrame\\UI-DialogBox-Background"
end

--- Pure DragonUI rock fill. No WHITE8X8 overlays that paint over the
-- texture (that was hiding the rock and producing flat brown panels).
-- Optional 1px gold edge via SetBackdrop only — does not cover the fill.
local function ApplyRockPanel(f, edgeA, _insetA, bgA)
    -- Pure DragonUI rock fill. No WHITE8X8 / gold edges (outer metal nineslice only).
    if type(f) ~= "table" then
        return
    end
    if f._alfmRockApplied == true then
        return
    end
    f._alfmRockApplied = true
    local path = RockPath()
    if type(f.CreateTexture) == "function" then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        bg:SetTexture(path)
        bg:SetAlpha(type(bgA) == "number" and bgA or 0.97)
        bg._duiOwned = true
        f._alfmRockBg = bg
    end
    -- Clear any prior backdrop so no non-DragonUI edge remains.
    if f.SetBackdrop then
        f:SetBackdrop(nil)
    end
end

local function ApplyParchment(f)
    ApplyRockPanel(f, 0.45, nil, 0.97)
end

local function ApplySidebar(f)
    ApplyRockPanel(f, 0.40, nil, 0.97)
end

local function ApplyInset(f)
    ApplyRockPanel(f, 0.50, nil, 0.95)
end

local function ApplyToggleRow(f)
    ApplyRockPanel(f, 0.40, nil, 0.94)
end

local function ApplyNavButton(f, selected)
    if type(f) ~= "table" then
        return
    end
    if type(f.CreateTexture) == "function" and type(f._alfmNavBg) ~= "table" then
        f._alfmNavBg = f:CreateTexture(nil, "BACKGROUND")
        f._alfmNavBg:SetPoint("TOPLEFT", 1, -1)
        f._alfmNavBg:SetPoint("BOTTOMRIGHT", -1, 1)
        f._alfmNavBg:SetTexture(RockPath())
        f._alfmNavBg._duiOwned = true
    end
    if type(f._alfmNavBg) == "table" and f._alfmNavBg.SetAlpha then
        f._alfmNavBg:SetAlpha(0.97)
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = nil,
            -- edgeFile WHITE8X8 removed (DragonUI only)
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        if selected then
            if f.SetBackdropBorderColor then
                f:SetBackdropBorderColor(0.95, 0.82, 0.30, 0.95)
            end
        else
            if f.SetBackdropBorderColor then
                f:SetBackdropBorderColor(0.55, 0.42, 0.18, 0.45)
            end
        end
        if f.SetBackdropColor then
            f:SetBackdropColor(0, 0, 0, 0)
        end
    end
end

local function SetInk(fs, rgba)
    if fs and fs.SetTextColor then
        fs:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4] or 1)
    end
end

local function TruncateText(text, maxLen)
    text = tostring(text or "")
    maxLen = tonumber(maxLen) or 72
    -- strip color codes for length estimate
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
    if #plain <= maxLen then
        return text
    end
    return plain:sub(1, maxLen - 1) .. "..."
end

--- Fit a FontString into a region so long lines wrap instead of overlapping.
local function FitText(fs, maxWidth, maxHeight)
    if type(fs) ~= "table" then
        return
    end
    if maxWidth and fs.SetWidth then
        fs:SetWidth(maxWidth)
    end
    if maxHeight and fs.SetHeight then
        fs:SetHeight(maxHeight)
    end
    if fs.SetWordWrap then
        fs:SetWordWrap(true)
    end
    if fs.SetNonSpaceWrap then
        fs:SetNonSpaceWrap(true)
    end
    if fs.SetJustifyV then
        fs:SetJustifyV("TOP")
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
        last = "  |  Last: " .. TruncateText(
            tostring(m.leader or "") .. " - " .. tostring(m.summary or m.text or ""), 40)
    end
    local kickBit = db.autoKickLevel59 and " * |cffff6060Kick59 ON|r" or ""
    local fullBit = db.fullAutoHosting and " * |cff2a7a3aFull Auto ON|r" or ""
    statusFS:SetText(TruncateText(string.format("Status: %s  *  Mode: |cffc8a03c%s|r%s%s%s",
        listening, ModeLabel(db.mode), fullBit, kickBit, last), 110))

    if footerStatus then
        local kick = db.autoKickLevel59 and "Kick59 ON" or "Kick59 off"
        if activeCategory == CAT_KICK then
            footerStatus:SetText("Kick log * Clear removes kick history")
        elseif activeCategory == CAT_LOG then
            footerStatus:SetText("Match + activity * Clear removes both")
        elseif activeCategory == CAT_QUEUE then
            footerStatus:SetText("Applicant queue * Clear empties queue")
        else
            local fa = db.fullAutoHosting and "FullAuto ON" or "FullAuto off"
            footerStatus:SetText(TruncateText(string.format("%s * Mode %s * %s * %s",
                listeningOn and "Listening ON" or "Listening OFF",
                ModeLabel(db.mode), fa, kick), 72))
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
    slotsFS:SetText(TruncateText("Filled: " .. table.concat(bits, "  *  "), 90))
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
        postStatusFS:SetText(table.concat(bits, "  *  "))
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
                local reason = k.reason
                if reason and reason ~= "" then
                    fs:SetText(string.format("|cff4a3010%s|r - |cff802020%s|r",
                        tostring(k.name or "?"), tostring(reason)))
                else
                    fs:SetText(string.format("|cff4a3010%s|r at level |cff802020%s|r",
                        tostring(k.name or "?"), tostring(k.level or "?")))
                end
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
                local text = tostring(a.text or "")
                if #text > 72 then text = text:sub(1, 69) .. "..." end
                fs:SetText(string.format("|cff6a4a10[%s]|r %s",
                    tostring(a.kind or "?"), text))
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
    if sessionSummaryFS and AscensionLFM.Activity and AscensionLFM.Activity.GetSessionSummary
        and AscensionLFM.Activity.FormatSessionSummary then
        local summary = AscensionLFM.Activity.GetSessionSummary()
        sessionSummaryFS:SetText(AscensionLFM.Activity.FormatSessionSummary(summary))
    end
end

function MainWindow.RefreshQueue()
    local list = AscensionLFM.Queue and AscensionLFM.Queue.Recent and AscensionLFM.Queue.Recent(5) or {}
    for i = 1, 5 do
        local row = queueRows[i]
        if row then
            local q = list[i]
            if q then
                local role = q.role and tostring(q.role) or nil
                local st = tostring(q.status or "pending")
                row.label:SetText(string.format("|cff4a3010%s|r  |cff5a4a30[%s]|r  %s\n%s",
                    tostring(q.name or "?"), role or "?", st, tostring(q.message or ""):sub(1, 60)))
                if row.icon then
                    local path = role and row.ROLE_ICONS and row.ROLE_ICONS[role]
                    row.icon:SetTexture(path or row.ROLE_ICON_UNKNOWN)
                end
                row.name = q.name
                row:Show()
                if row.inviteBtn then row.inviteBtn:Show() end
                if row.rejectBtn then row.rejectBtn:Show() end
            else
                row.name = nil
                row.label:SetText(i == 1 and "|cff5a4a30No applicants yet.|r" or "")
                if row.icon then
                    row.icon:SetTexture(i == 1 and row.ROLE_ICON_UNKNOWN or nil)
                end
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
    if widgets.routeButtons then
        local routing = type(db.messageRouting) == "table" and db.messageRouting or {}
        local labels = {
            auto = "Auto",
            raidwarning = "RW only",
            raid = "Raid/Party",
            ["local"] = "Local",
            disabled = "Off",
        }
        for kind, btn in pairs(widgets.routeButtons) do
            if btn and btn.SetText then
                local r = routing[kind]
                if r == nil or r == "" then r = "auto" end
                btn:SetText(labels[tostring(r)] or tostring(r))
            end
        end
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
    if widgets.autoMoveTank and widgets.autoMoveTank.SetChecked then
        widgets.autoMoveTank:SetChecked(db.autoMoveTank ~= false)
    end
    if widgets.autoMoveHealer and widgets.autoMoveHealer.SetChecked then
        widgets.autoMoveHealer:SetChecked(db.autoMoveHealer ~= false)
    end
    if widgets.autoMoveAura and widgets.autoMoveAura.SetChecked then
        widgets.autoMoveAura:SetChecked(db.autoMoveAura ~= false)
    end
    if widgets.passiveRoleDetect and widgets.passiveRoleDetect.SetChecked then
        widgets.passiveRoleDetect:SetChecked(db.passiveRoleDetect ~= false)
    end
    if widgets.fullAuto and widgets.fullAuto.SetChecked then
        widgets.fullAuto:SetChecked(db.fullAutoHosting and true or false)
    end
    if widgets.rejectRewhisper and widgets.rejectRewhisper.SetChecked then
        widgets.rejectRewhisper:SetChecked(db.rejectRewhisper and true or false)
    end
    if widgets.pauseInviteInInstance and widgets.pauseInviteInInstance.SetChecked then
        widgets.pauseInviteInInstance:SetChecked(db.pauseInviteInInstance ~= false)
    end
    if widgets.pauseRepostInInstance and widgets.pauseRepostInInstance.SetChecked then
        widgets.pauseRepostInInstance:SetChecked(db.pauseRepostInInstance ~= false)
    end
    if widgets.announceFull and widgets.announceFull.SetChecked then
        widgets.announceFull:SetChecked(db.announceFull and true or false)
    end
    if widgets.postShowAllRoles and widgets.postShowAllRoles.SetChecked then
        widgets.postShowAllRoles:SetChecked(db.postShowAllRoles and true or false)
    end
    if widgets.miniHud and widgets.miniHud.SetChecked then
        widgets.miniHud:SetChecked(db.miniHudShow ~= false)
    end
    if widgets.chatFilter and widgets.chatFilter.SetChecked then
        widgets.chatFilter:SetChecked(db.chatFilterEnabled == true)
    end
    if widgets.minimapIcon and widgets.minimapIcon.SetChecked then
        widgets.minimapIcon:SetChecked(db.minimapIconShown ~= false)
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
    titleFs:SetPoint("TOPLEFT", check, "TOPRIGHT", 6, -4)
    titleFs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    titleFs:SetJustifyH("LEFT")
    titleFs:SetText(TruncateText(title, 64))
    if danger then
        SetInk(titleFs, DANGER)
    else
        SetInk(titleFs, INK)
    end

    local descFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
    descFs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
    descFs:SetJustifyH("LEFT")
    FitText(descFs, nil, 36)
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
                    button._label:SetTextColor(1.00, 0.92, 0.55, 1)
                else
                    button._label:SetTextColor(0.90, 0.84, 0.68, 1)
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
        if id == CAT_ROSTER and AscensionLFM.RosterPanel and AscensionLFM.RosterPanel.Refresh then
            AscensionLFM.RosterPanel.Refresh()
        end
        if id == CAT_LOG or id == CAT_KICK or id == CAT_QUEUE then
            clearBtn:Show()
        else
            clearBtn:Hide()
        end
    end

    RefreshStatus()
end

local function CreateMainFrame()
    -- Plain frame only — UIPanelDialogTemplate fights DragonUI chrome
    -- (baked regions + clipping). Rock + metal nineslice come from Chrome.lua.
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    return f
end


-- Appearance category (module-level to stay under Lua 5.1 60-upvalue limit in Init).
local function BuildAppearanceCategory(pageHost)
    local appearance = BuildCategoryPage(pageHost, CAT_APPEARANCE, 420)
    local y = -8
    local function uiChrome()
        local db = DB()
        if type(db.uiChrome) ~= "table" then db.uiChrome = {} end
        return db.uiChrome
    end
    local function note(parent, text, yy)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 8, yy)
        fs:SetPoint("RIGHT", parent, "RIGHT", -12, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        SetInk(fs, MUTED)
        return fs
    end
    note(appearance, "Only DragonUI textures (rock + metal nineslice). Changes to sizes need /reload.", y)
    y = y - 28

    local metalRow = CreateFrame("Frame", nil, appearance)
    metalRow:SetPoint("TOPLEFT", 4, y)
    metalRow:SetPoint("RIGHT", appearance, "RIGHT", -4, 0)
    metalRow:SetHeight(TOGGLE_ROW_H)
    ApplyToggleRow(metalRow)
    local metalCb = CreateFrame("CheckButton", nil, metalRow, "UICheckButtonTemplate")
    metalCb:SetPoint("TOPLEFT", 6, -8)
    metalCb:SetChecked(uiChrome().metalEnabled ~= false)
    metalCb:SetScript("OnClick", function(self)
        uiChrome().metalEnabled = self:GetChecked() and true or false
        if AscensionLFM.Print then AscensionLFM.Print("Metal chrome: " .. (uiChrome().metalEnabled and "ON" or "OFF") .. " — /reload to apply") end
    end)
    local metalLbl = metalRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    metalLbl:SetPoint("LEFT", metalCb, "RIGHT", 4, 0)
    metalLbl:SetText("Metal nineslice (outer frame)")
    SetInk(metalLbl, INK)
    local metalDesc = metalRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metalDesc:SetPoint("TOPLEFT", metalCb, "BOTTOMLEFT", 0, -2)
    metalDesc:SetPoint("RIGHT", metalRow, "RIGHT", -8, 0)
    metalDesc:SetJustifyH("LEFT")
    metalDesc:SetText("Requires DragonUI. Off = rock background only. /reload after toggle.")
    SetInk(metalDesc, MUTED)
    y = y - TOGGLE_STEP

    local chromeEdits = {}
    local function numRow(label, key, default, lo, hi)
        local row = CreateFrame("Frame", nil, appearance)
        row:SetPoint("TOPLEFT", 4, y)
        row:SetPoint("RIGHT", appearance, "RIGHT", -4, 0)
        row:SetHeight(36)
        ApplyInset(row)
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", 10, 0)
        fs:SetText(label)
        SetInk(fs, INK)
        local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        edit:SetSize(64, 20)
        edit:SetPoint("RIGHT", -12, 0)
        edit:SetAutoFocus(false)
        local cur = tonumber(uiChrome()[key]) or default
        edit:SetText(tostring(cur))
        edit:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText())
            if not n then self:SetText(tostring(uiChrome()[key] or default)); self:ClearFocus(); return end
            if n < lo then n = lo end
            if n > hi then n = hi end
            uiChrome()[key] = n
            self:SetText(tostring(n))
            self:ClearFocus()
            if AscensionLFM.Print then AscensionLFM.Print(label .. " = " .. n .. " — /reload to apply") end
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(uiChrome()[key] or default))
            self:ClearFocus()
        end)
        chromeEdits[key] = edit
        y = y - 42
    end

    numRow("Corner size (topSize)", "topSize", 75, 24, 96)
    numRow("Bottom corner size", "bottomSize", 32, 12, 64)
    numRow("Top offset (topY)", "topY", 16, -20, 40)
    numRow("Bottom offset (bottomY)", "bottomY", -3, -20, 20)
    numRow("Left offset", "leftOffset", -8, -24, 24)
    numRow("Right offset", "rightOffset", 4, -24, 24)

    note(appearance, "Tips: /alfmchrome • /alfmchromeref • /alfmchromeside. Enter value then /reload.", y - 4)

    local resetBtn = CreateFrame("Button", nil, appearance, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(resetBtn) end
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("BOTTOMLEFT", 8, 12)
    resetBtn:SetText("Reset chrome defaults")
    resetBtn:SetScript("OnClick", function()
        local u = uiChrome()
        u.metalEnabled = true
        u.topSize = 75
        u.bottomSize = 32
        u.topY = 16
        u.bottomY = -3
        u.leftOffset = -8
        u.rightOffset = 4
        metalCb:SetChecked(true)
        for key, edit in pairs(chromeEdits) do
            edit:SetText(tostring(u[key]))
        end
        if AscensionLFM.Print then AscensionLFM.Print("Chrome defaults restored — /reload") end
    end)
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

    -- Real DragonUI chrome (background + metal nineslice border), same
    -- approach and same confirmed texture paths/atlas coordinates as
    -- DragonUI's own bag/bank windows and this session's
    -- TradeSkillFrame/SpellBookFrame reskins. AscensionLFM is a
    -- separate addon from DragonUI, so these are full-path texture
    -- references (no Lua-level dependency on DragonUI's code having
    -- run - only needs the texture files present).
    --
    -- CreateMainFrame() falls back between UIPanelDialogTemplate (has
    -- its own baked-in border/background texture regions) and a manual
    -- SetBackdrop version - "neuter" (Show->Hide override, same
    -- technique as DragonUI's own characterpanel/chrome.lua) whichever
    -- vanilla texture regions exist directly on `frame` so DragonUI's
    -- own code can't bring them back, then layer the real chrome on
    -- top. This only sweeps frame:GetRegions() (direct texture
    -- children) - titleBg below is a separate child FRAME (restyled in
    -- v0.4.87 to rock + gold edge so it matches the DragonUI chrome).
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and not region._duiOwned then
            region._duiShow = region.Show
            region.Show = region.Hide
            region:Hide()
        end
    end
    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    -- DragonUI chrome via shared helper (ui/Chrome.lua). Full-size profile
    -- (75/75/32) matches bag/bank/TradeSkillFrame sizing used previously.
    if AscensionLFM.Chrome and AscensionLFM.Chrome.ApplyMetalChrome then
        if AscensionLFM.Chrome and AscensionLFM.Chrome.ApplyMetalChrome then AscensionLFM.Chrome.ApplyMetalChrome(frame, "full") end
    end

    -- Hide the oversized UIPanelDialogTemplate close button, then place a
    -- DragonUI-sized (18x18) X in the top-right metal corner so it sits
    -- 1:1 inside the chrome piece (same redbutton2x atlas as bags/bank).
    -- Skipped entirely without DragonUI: the native close button (already
    -- correctly sized for the classic SetBackdrop chrome applied above)
    -- stays exactly as-is instead of being replaced with a texture that
    -- doesn't exist on disk.
    if AscensionLFM.Chrome and AscensionLFM.Chrome.HasDragonUI and AscensionLFM.Chrome.HasDragonUI() then
        local function hideClose(btn)
            if not btn then return end
            btn:Hide()
            if btn.EnableMouse then btn:EnableMouse(false) end
            if btn.SetScript then
                btn:SetScript("OnClick", nil)
            end
        end
        hideClose(_G[FRAME_NAME .. "Close"])
        hideClose(_G[FRAME_NAME .. "CloseButton"])
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                local n = child.GetName and child:GetName()
                if n and (n:find("Close") or n:find("close")) then
                    hideClose(child)
                end
            end
        end

        local closeBtn = CreateFrame("Button", FRAME_NAME .. "DUIClose", frame)
        closeBtn:SetSize(18, 18)
        -- Sit inside the top-right metal corner (full profile rightOffset=4, topY=16).
        closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
        if closeBtn.SetFrameLevel and frame.GetFrameLevel then
            closeBtn:SetFrameLevel((frame:GetFrameLevel() or 0) + 25)
        end
        closeBtn:EnableMouse(true)
        closeBtn:RegisterForClicks("AnyUp")

        local path = (AscensionLFM.Chrome and AscensionLFM.Chrome.DUI_CLOSE)
            or "Interface\\AddOns\\DragonUI\\Textures\\UI\\redbutton2x"
        local function tex(parent, layer)
            local t = parent:CreateTexture(nil, layer or "ARTWORK")
            t:SetAllPoints(parent)
            t:SetTexture(path)
            return t
        end
        local normal = tex(closeBtn, "ARTWORK")
        normal:SetTexCoord(0.152344, 0.292969, 0.0078125, 0.304688)
        closeBtn:SetNormalTexture(normal)
        local pushed = tex(closeBtn, "ARTWORK")
        pushed:SetTexCoord(0.152344, 0.292969, 0.632812, 0.929688)
        closeBtn:SetPushedTexture(pushed)
        local highlight = tex(closeBtn, "HIGHLIGHT")
        highlight:SetTexCoord(0.449219, 0.589844, 0.0078125, 0.304688)
        if highlight.SetBlendMode then
            highlight:SetBlendMode("ADD")
        end
        closeBtn:SetHighlightTexture(highlight)
        local disabled = tex(closeBtn, "ARTWORK")
        disabled:SetTexCoord(0.152344, 0.292969, 0.320312, 0.617188)
        closeBtn:SetDisabledTexture(disabled)

        closeBtn:SetScript("OnClick", function()
            frame:Hide()
        end)
        frame._alfmCloseBtn = closeBtn
    end

    local titleBg = CreateFrame("Frame", nil, frame)
    titleBg:SetPoint("TOP", frame, "TOP", 0, -2)
    titleBg:SetSize(260, 34)
    if titleBg.SetFrameLevel and frame.GetFrameLevel then
        -- Above chrome host (+20) so title text is not covered by metal.
        titleBg:SetFrameLevel((frame:GetFrameLevel() or 0) + 22)
    end
    -- Rock title strip only under DragonUI, where it's sized/tuned to sit
    -- inside the metal nineslice chrome. Without DragonUI there's no metal
    -- border to blend into, and stretching the same full-dialog background
    -- texture across this small 260x34 box just warps it into a distorted
    -- gold/tan capsule that clashes with the frame's own classic dialog
    -- background - so leave titleBg transparent there and let the title
    -- text sit directly on frame's own background instead.
    if AscensionLFM.Chrome and AscensionLFM.Chrome.HasDragonUI and AscensionLFM.Chrome.HasDragonUI() then
        local tbg = titleBg:CreateTexture(nil, "BACKGROUND")
        tbg:SetTexture(RockPath())
        tbg:SetAllPoints(titleBg)
        tbg:SetAlpha(0.97)
        tbg._duiOwned = true
    end
    if titleBg.SetBackdrop then
        titleBg:SetBackdrop(nil)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:ClearAllPoints()
    title:SetParent(titleBg)
    title:SetDrawLayer("OVERLAY")
    title:SetPoint("TOP", titleBg, "TOP", 0, -6)
    title:SetText("AscensionLFM")
    -- Light gold on dark rock titleBg (INK/MUTED are dark parchment colours
    -- and would be nearly invisible after the v0.4.87 titleBg restyle).
    SetInk(title, { 1.00, 0.90, 0.35, 1 })

    local sub = titleBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -2)
    sub:SetText("Manastorm Level Run LFM/LFG * v" .. tostring(AscensionLFM.VERSION or "0.4.16"))
    SetInk(sub, { 0.88, 0.80, 0.55, 1 })

    local shell = CreateFrame("Frame", FRAME_NAME .. "Shell", frame)
    shell:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -52)
    shell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)

    local sidebar = CreateFrame("Frame", FRAME_NAME .. "Sidebar", shell)
    sidebar:SetPoint("TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    ApplySidebar(sidebar)

    local sideLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideLabel:SetPoint("TOPLEFT", 10, -10)
    sideLabel:SetText("CATEGORIES")
    SetInk(sideLabel, { 1.00, 0.84, 0.35, 1 })

    local y = -26
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        local btn = CreateFrame("Button", FRAME_NAME .. "Nav_" .. cat.id, sidebar)
        btn:SetHeight(26)
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
    SetInk(categoryHeadSub, MUTED)

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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(closeBtn) end
    closeBtn:SetSize(72, 22)
    closeBtn:SetPoint("RIGHT", 0, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    clearBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(clearBtn) end
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
    local general = BuildCategoryPage(pageHost, CAT_GENERAL, 700)

    local statusBox = CreateFrame("Frame", nil, general)
    statusBox:SetPoint("TOPLEFT", 0, 0)
    statusBox:SetPoint("TOPRIGHT", 0, 0)
    statusBox:SetHeight(48)
    ApplyInset(statusBox)
    statusFS = statusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusFS:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 8, -8)
    statusFS:SetPoint("BOTTOMRIGHT", statusBox, "BOTTOMRIGHT", -8, 8)
    statusFS:SetJustifyH("LEFT")
    FitText(statusFS, nil, 36)
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
    modeHint:SetText("|cff5a4010Off|r - Listening OFF (no chat scan).\n"
        .. "|cff5a4010Notify|r - Listening ON: print MS LFM/LFG to chat + Log (default).\n"
        .. "|cff5a4010Seeking|r - match open roles; optional auto-whisper LFM leaders.\n"
        .. "|cff5a4010Hosting|r - role whispers -> invite only if accepted role + open slot.\n"
        .. "|cff5a4010Full Auto|r - Hosting category master (default OFF): invite + scan + repost + reject.")
    SetInk(modeHint, MUTED)

    CreateSectionLabel(general, "Mini Quick HUD", -210)
    widgets.miniHud = CreateToggleRow(general, -228,
        "Show floating quick bar",
        "LFM / RW / Sync / Wipe / Mobs / FULL / Regrp / Need - no /alfm. Drag to move. Default ON.",
        false,
        function(on)
            if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.SetShown then
                AscensionLFM.MiniHUD.SetShown(on)
            else
                AscensionLFM.Database.Get().miniHudShow = on and true or false
            end
        end)

    -- Message delivery routing (backend since 0.4.42; UI picker now)
    CreateSectionLabel(general, "Message delivery (Mini HUD)", -300)
    local routeHint = general:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    routeHint:SetPoint("TOPLEFT", 4, -318)
    routeHint:SetPoint("RIGHT", -4, 0)
    routeHint:SetJustifyH("LEFT")
    routeHint:SetText("Per-message route for group announces. Click a button to cycle. "
        .. "|cff5a4010Auto|r smart cascade * |cff5a4010RW only|r * |cff5a4010Raid/Party|r * |cff5a4010Local|r * |cff5a4010Off|r")
    SetInk(routeHint, MUTED)

    local ROUTE_CYCLE = { "auto", "raidwarning", "raid", "local", "disabled" }
    local ROUTE_LABEL = {
        auto = "Auto",
        raidwarning = "RW only",
        raid = "Raid/Party",
        ["local"] = "Local",
        disabled = "Off",
    }
    local ROUTE_KINDS = {
        { "rw", "Role Check" },
        { "wipe", "Wipe" },
        { "shield", "Mobs/Shield" },
        { "regroup", "Regroup" },
        { "full", "FULL" },
        { "need", "Need T/H/A/D" },
    }
    widgets.routeButtons = {}
    local function CurrentRoute(kind)
        local db = AscensionLFM.Database.Get()
        if type(db.messageRouting) ~= "table" then
            db.messageRouting = {}
        end
        local r = db.messageRouting[kind]
        if r == nil or r == "" then
            return "auto"
        end
        return tostring(r)
    end
    local function CycleRoute(kind)
        local cur = CurrentRoute(kind)
        local idx = 1
        for i, v in ipairs(ROUTE_CYCLE) do
            if v == cur then
                idx = i
                break
            end
        end
        local nxt = ROUTE_CYCLE[(idx % #ROUTE_CYCLE) + 1]
        local db = AscensionLFM.Database.Get()
        if type(db.messageRouting) ~= "table" then
            db.messageRouting = {}
        end
        if nxt == "auto" then
            db.messageRouting[kind] = nil
        else
            db.messageRouting[kind] = nxt
        end
        return nxt
    end
    local ry = -360
    for _, entry in ipairs(ROUTE_KINDS) do
        local kind, label = entry[1], entry[2]
        local row = CreateFrame("Frame", nil, general)
        row:SetPoint("TOPLEFT", 4, ry)
        row:SetPoint("TOPRIGHT", -4, ry)
        row:SetHeight(22)
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(label)
        SetInk(lbl, INK)
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(btn) end
        btn:SetSize(90, 20)
        btn:SetPoint("RIGHT", 0, 0)
        btn:SetText(ROUTE_LABEL[CurrentRoute(kind)] or "Auto")
        btn:SetScript("OnClick", function(self)
            local nxt = CycleRoute(kind)
            self:SetText(ROUTE_LABEL[nxt] or nxt)
        end)
        widgets.routeButtons[kind] = btn
        ry = ry - 26
    end

    CreateSectionLabel(general, "Chat", ry - 6)
    widgets.chatFilter = CreateToggleRow(general, ry - 24,
        "Hide MS LFM/LFG spam from chat",
        "Removes public Manastorm LFM/LFG listings from Trade/General/Say/Yell/Guild once matched - they're still logged in the Log tab. Off by default.",
        false,
        function(on)
            if AscensionLFM.ChatFilter and AscensionLFM.ChatFilter.SetEnabled then
                AscensionLFM.ChatFilter.SetEnabled(on)
            else
                AscensionLFM.Database.Get().chatFilterEnabled = on and true or false
            end
        end)

    CreateSectionLabel(general, "Minimap", ry - 100)
    widgets.minimapIcon = CreateToggleRow(general, ry - 118,
        "Show minimap icon",
        "Draggable icon near the minimap. Left-click: open settings. Right-click: toggle Mini HUD. Hover: mode + session activity + pending applicants. Default ON.",
        false,
        function(on)
            if AscensionLFM.MinimapButton and AscensionLFM.MinimapButton.SetShown then
                AscensionLFM.MinimapButton.SetShown(on)
            else
                AscensionLFM.Database.Get().minimapIconShown = on and true or false
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
        "Rate-limited whisper when needed, plus best-effort replies to their level/role/aura follow-ups. Off by default.",
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
        "Cycles 2-3 templates below. {role} becomes tank/healer/aura/dps. Default ON.",
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(blAdd) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(blRem) end
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
    local hosting = BuildCategoryPage(pageHost, CAT_HOSTING, 1510)
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
    -- when set, instead of guessing). Applies to your own slot immediately -
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(hostRoleAutoBtn) end
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
        "When someone posts LFG MS with a role you need + open slot -> InviteUnit. Default ON while Hosting.",
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
    hy = hy - TOGGLE_STEP
    widgets.pauseInviteInInstance = CreateToggleRow(hosting, hy,
        "Pause auto-invite while inside the instance",
        "A fresh invite can't join a run already underway. Covers whisper + LFG-chat invites. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().pauseInviteInInstance = on and true or false
        end)
    hy = hy - TOGGLE_STEP
    widgets.pauseRepostInInstance = CreateToggleRow(hosting, hy,
        "Pause LFM auto-repost while inside the instance",
        "No point re-advertising a run you're already deep into. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().pauseRepostInInstance = on and true or false
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(load2337) end
    load2337:SetSize(100, 20)
    load2337:SetPoint("LEFT", 0, 0)
    load2337:SetText("MS 2/3/3/7")
    load2337:SetScript("OnClick", function()
        if AscensionLFM.Presets then AscensionLFM.Presets.Load("MS 2/3/3/7") end
        SyncWidgetsFromDB()
    end)
    local load2255 = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(load2255) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(pSave) end
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
    FitText(slotsFS, nil, 18)
    SetInk(slotsFS, MUTED)

    local rcY = slotsY - 72
    CreateSectionLabel(hosting, "Role Check", rcY)
    widgets.autoMoveTank = CreateToggleRow(hosting, rcY - 18,
        "Auto-move Tanks (1 per raid group, fills g1/g2 first)",
        "Keep at most one Tank in each raid group (1-8), filling the lowest-numbered empty group first. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoMoveTank = on and true or false
            if on and AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.BalanceAll then
                AscensionLFM.AuraBalance.BalanceAll()
            end
        end)
    widgets.autoMoveHealer = CreateToggleRow(hosting, rcY - 18 - TOGGLE_STEP,
        "Auto-move Healers (1 per raid group)",
        "Keep at most one Healer in each raid group. Won't displace a placed Tank unless a full group leaves no other choice. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoMoveHealer = on and true or false
            if on and AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.BalanceAll then
                AscensionLFM.AuraBalance.BalanceAll()
            end
        end)
    widgets.autoMoveAura = CreateToggleRow(hosting, rcY - 18 - TOGGLE_STEP * 2,
        "Auto-move Auras (1 per raid group)",
        "Keep at most one Aura player in each raid group (1-8). Extra Auras are moved to empty groups. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().autoMoveAura = on and true or false
            if on and AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.BalanceAll then
                AscensionLFM.AuraBalance.BalanceAll()
            end
        end)
    widgets.roleCheckAutoResync = CreateToggleRow(hosting, rcY - 18 - TOGGLE_STEP * 3,
        "Auto-resync after listening window",
        "When the window ends: remove leavers, apply whispered roles, refresh filled counts. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().roleCheckAutoResync = on and true or false
        end)
    widgets.passiveRoleDetect = CreateToggleRow(hosting, rcY - 18 - TOGGLE_STEP * 4,
        "Catch role words in raid/party chat anytime",
        "Assign a role the moment someone types exactly 'heal'/'tank'/'dps'/'aura' in group chat - no active Role Check needed. Default ON.",
        false,
        function(on)
            AscensionLFM.Database.Get().passiveRoleDetect = on and true or false
        end)

    local rcFieldsY = rcY - 18 - TOGGLE_STEP * 4 - TOGGLE_ROW_H - 12
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(rwBtn) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(resyncBtn) end
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
    local post = BuildCategoryPage(pageHost, CAT_POST, 620)
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(rebuildBtn) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(scanBtn) end
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
                    "%d in group without role - Mini HUD RW, reply T/H/A/D", unassigned))
            end
        end
    end)

    local postBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(postBtn) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(postRwBtn) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(postResyncBtn) end
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
    widgets.postShowAllRoles = CreateToggleRow(post, -268 - TOGGLE_STEP * 2,
        "LFM shows filled roles too",
        "Post e.g. 2/2 Tanks | 1/3 Healers instead of only open slots. Default OFF.",
        false,
        function(on)
            local db = AscensionLFM.Database.Get()
            db.postShowAllRoles = on and true or false
            if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
                AscensionLFM.Poster.RefreshMessage()
            end
            MainWindow.RefreshPost()
        end)

    local postToggleBottom = -268 - TOGGLE_STEP * 2 - TOGGLE_ROW_H -- bottom of postShowAllRoles row
    local intY = postToggleBottom - 12

    local intLbl = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intLbl:SetPoint("TOPLEFT", 4, intY)
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
    postStatusFS:SetPoint("TOPLEFT", 4, intY - 28)
    postStatusFS:SetPoint("RIGHT", -4, 0)
    postStatusFS:SetJustifyH("LEFT")
    SetInk(postStatusFS, MUTED)

    local postHint = post:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    postHint:SetPoint("TOPLEFT", 4, intY - 50)
    postHint:SetPoint("RIGHT", -4, 0)
    postHint:SetJustifyH("LEFT")
    postHint:SetText("Example: LFM MS | 2/3 Healers | 1/3 Aura - full roles omitted, filled from Hosting slots + Scan.")
    SetInk(postHint, MUTED)

    --------------------------------------------------------------------
    -- Queue (applicants)
    --------------------------------------------------------------------
    local queue = BuildCategoryPage(pageHost, CAT_QUEUE, 420)
    CreateSectionLabel(queue, "Recent applicant whispers", -4)
    local qHint = queue:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qHint:SetPoint("TOPLEFT", 4, -20)
    qHint:SetPoint("RIGHT", -4, 0)
    qHint:SetJustifyH("LEFT")
    qHint:SetText("Hosting whispers land here. Invite uses InviteUnit; Reject sends re-whisper once.")
    SetInk(qHint, MUTED)

    local qy = -44
    local ROLE_ICONS = {
        tank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
        healer = "Interface\\Icons\\Spell_Holy_Heal",
        aura = "Interface\\Icons\\Spell_Holy_AuraOfLight",
        dps = "Interface\\Icons\\Ability_DualWield",
    }
    local ROLE_ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, queue)
        row:SetPoint("TOPLEFT", 0, qy)
        row:SetPoint("TOPRIGHT", 0, qy)
        row:SetHeight(52)
        ApplyInset(row)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("TOPLEFT", 8, -10)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the default icon border
        row.icon = icon
        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 4)
        lbl:SetPoint("RIGHT", row, "RIGHT", -150, 0)
        lbl:SetJustifyH("LEFT")
        SetInk(lbl, INK)
        row.label = lbl
        row.ROLE_ICONS = ROLE_ICONS
        row.ROLE_ICON_UNKNOWN = ROLE_ICON_UNKNOWN
        local inv = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(inv) end
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
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(rej) end
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
        qy = qy - 58
    end

    --------------------------------------------------------------------
    -- Kick
    --------------------------------------------------------------------
    local roster = BuildCategoryPage(pageHost, CAT_ROSTER, 720)
    local rosterBar = CreateFrame("Frame", nil, roster)
    rosterBar:SetPoint("TOPLEFT", 0, -2)
    rosterBar:SetPoint("TOPRIGHT", 0, -2)
    rosterBar:SetHeight(44)
    ApplyInset(rosterBar)

    local rosterHint = rosterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterHint:SetPoint("TOPLEFT", 8, -6)
    rosterHint:SetPoint("RIGHT", -160, 0)
    rosterHint:SetJustifyH("LEFT")
    if rosterHint.SetWordWrap then rosterHint:SetWordWrap(true) end
    if rosterHint.SetHeight then rosterHint:SetHeight(32) end
    rosterHint:SetText("Click role icon -> choose Tank/Heal/Aura/DPS  |  X remove  |  gold = aura")
    SetInk(rosterHint, MUTED)

    local specBtn = CreateFrame("Button", nil, rosterBar, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(specBtn) end
    specBtn:SetSize(88, 22)
    specBtn:SetPoint("TOPRIGHT", -8, -10)
    specBtn:SetText("My Spec")
    specBtn:SetScript("OnClick", function()
        if AscensionLFM.SpecRole and AscensionLFM.SpecRole.ApplyToSelf then
            AscensionLFM.SpecRole.ApplyToSelf()
        elseif AscensionLFM.Print then
            AscensionLFM.Print("SpecRole module missing")
        end
    end)

    if AscensionLFM.RosterPanel and AscensionLFM.RosterPanel.Attach then
        local host = CreateFrame("Frame", nil, roster)
        host:SetPoint("TOPLEFT", 0, -50)
        host:SetPoint("BOTTOMRIGHT", 0, 0)
        AscensionLFM.RosterPanel.Attach(host)
    end

--------------------------------------------------------------------
    -- LFG/LFM (unified content-type selector: MS / Raid / M+)
    --------------------------------------------------------------------
    local content = BuildCategoryPage(pageHost, CAT_CONTENT, 300)
    CreateSectionLabel(content, "Content type", -4)
    do
        local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", 0, -22)
        note:SetPoint("TOPRIGHT", 0, -22)
        note:SetJustifyH("LEFT")
        SetInk(note, MUTED)
        note:SetText("Switching type doesn't clear the other type's settings - your Raid preset and M+ dungeon/level are both remembered, only one is shown/tagged at a time.")
        if note.SetWordWrap then note:SetWordWrap(true) end

        local typeBtns = {}
        local raidPane = CreateFrame("Frame", nil, content)
        local mplusPane = CreateFrame("Frame", nil, content)
        local msPane = CreateFrame("Frame", nil, content)

        local function ShowPaneFor(t)
            msPane:Hide()
            raidPane:Hide()
            mplusPane:Hide()
            if t == "raid" then
                raidPane:Show()
            elseif t == "mplus" then
                mplusPane:Show()
            else
                msPane:Show()
            end
            for id, btn in pairs(typeBtns) do
                if btn.SetBackdropBorderColor then
                    btn:SetBackdropBorderColor(id == t and 0.95 or 0.85,
                        id == t and 0.80 or 0.68, id == t and 0.35 or 0.22, id == t and 0.95 or 0.50)
                end
            end
        end

        local function SetContentType(t)
            local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
            if db then
                db.contentType = t
            end
            ShowPaneFor(t)
            if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
                AscensionLFM.Poster.RefreshMessage()
            end
        end

        local xPos = 0
        for _, def in ipairs({ { id = "ms", label = "MS" }, { id = "raid", label = "Raid" }, { id = "mplus", label = "M+" } }) do
            local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then
                AscensionLFM.Chrome.SkinActionButton(btn)
            end
            btn:SetSize(80, 24)
            btn:SetPoint("TOPLEFT", xPos, -60)
            btn:SetText(def.label)
            btn:SetScript("OnClick", function() SetContentType(def.id) end)
            typeBtns[def.id] = btn
            xPos = xPos + 86
        end

        -- MS pane: nothing special to configure - just says so.
        msPane:SetPoint("TOPLEFT", 0, -96)
        msPane:SetPoint("TOPRIGHT", 0, -96)
        msPane:SetHeight(40)
        local msNote = msPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        msNote:SetAllPoints()
        msNote:SetJustifyH("LEFT")
        SetInk(msNote, INK)
        msNote:SetText("MS (default): standard LFM post, no content tag added. Slot caps are set on the Hosting tab.")
        if msNote.SetWordWrap then msNote:SetWordWrap(true) end

        -- Raid pane: the three size presets.
        raidPane:SetPoint("TOPLEFT", 0, -96)
        raidPane:SetPoint("TOPRIGHT", 0, -96)
        raidPane:SetHeight(140)
        do
            local rNote = raidPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rNote:SetPoint("TOPLEFT", 0, 0)
            rNote:SetPoint("TOPRIGHT", 0, 0)
            rNote:SetJustifyH("LEFT")
            SetInk(rNote, INK)
            rNote:SetText("Tags the LFM post [RAID]. Pick a size to set Tank/Healer/Aura/DPS caps (editable individually afterward on Hosting):")
            if rNote.SetWordWrap then rNote:SetWordWrap(true) end

            local presets = {
                { label = "10-man", tank = 2, healer = 2, aura = 1, dps = 5 },
                { label = "25-man", tank = 3, healer = 5, aura = 2, dps = 15 },
                { label = "40-man", tank = 4, healer = 8, aura = 3, dps = 25 },
            }
            local btnY = -34
            for _, p in ipairs(presets) do
                local pbtn = CreateFrame("Button", nil, raidPane, "UIPanelButtonTemplate")
                if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then
                    AscensionLFM.Chrome.SkinActionButton(pbtn)
                end
                pbtn:SetSize(180, 24)
                pbtn:SetPoint("TOPLEFT", 0, btnY)
                pbtn:SetText(string.format("%s (T%d/H%d/A%d/D%d)", p.label, p.tank, p.healer, p.aura, p.dps))
                pbtn:SetScript("OnClick", function()
                    if not AscensionLFM.Slots then
                        return
                    end
                    AscensionLFM.Slots.SetMax("tank", p.tank)
                    AscensionLFM.Slots.SetMax("healer", p.healer)
                    AscensionLFM.Slots.SetMax("aura", p.aura)
                    AscensionLFM.Slots.SetMax("dps", p.dps)
                    MainWindow.RefreshSlots()
                    if AscensionLFM.Print then
                        AscensionLFM.Print("Raid: applied " .. p.label .. " slot preset")
                    end
                end)
                btnY = btnY - 30
            end
        end

        -- M+ pane: dungeon + level fields, live preview.
        mplusPane:SetPoint("TOPLEFT", 0, -96)
        mplusPane:SetPoint("TOPRIGHT", 0, -96)
        mplusPane:SetHeight(175)
        do
            local dLabel = mplusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dLabel:SetPoint("TOPLEFT", 0, 0)
            dLabel:SetText("Dungeon")
            SetInk(dLabel, MUTED)

            local dEdit = CreateFrame("EditBox", "AscensionLFMMPlusDungeon", mplusPane, "InputBoxTemplate")
            dEdit:SetSize(220, 20)
            dEdit:SetPoint("TOPLEFT", 60, 2)
            dEdit:SetAutoFocus(false)
            dEdit:SetMaxLetters(40)
            local db0 = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
            dEdit:SetText((db0 and db0.mplusDungeon) or "")

            local lLabel = mplusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lLabel:SetPoint("TOPLEFT", 0, -30)
            lLabel:SetText("Level")
            SetInk(lLabel, MUTED)

            local lEdit = CreateFrame("EditBox", "AscensionLFMMPlusLevel", mplusPane, "InputBoxTemplate")
            lEdit:SetSize(40, 20)
            lEdit:SetPoint("TOPLEFT", 60, -28)
            lEdit:SetAutoFocus(false)
            lEdit:SetMaxLetters(2)
            lEdit:SetNumeric(true)
            lEdit:SetText(tostring((db0 and db0.mplusLevel) or 0))

            local preview = mplusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            preview:SetPoint("TOPLEFT", 0, -66)
            preview:SetPoint("TOPRIGHT", 0, -66)
            preview:SetJustifyH("LEFT")
            SetInk(preview, GOLD)
            if preview.SetWordWrap then preview:SetWordWrap(true) end

            local minLabel = mplusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            minLabel:SetPoint("TOPLEFT", 0, -96)
            minLabel:SetText("Min level to show")
            SetInk(minLabel, MUTED)

            local minEdit = CreateFrame("EditBox", "AscensionLFMMPlusMinLevel", mplusPane, "InputBoxTemplate")
            minEdit:SetSize(40, 20)
            minEdit:SetPoint("TOPLEFT", 120, -94)
            minEdit:SetAutoFocus(false)
            minEdit:SetMaxLetters(2)
            minEdit:SetNumeric(true)
            minEdit:SetText(tostring((db0 and db0.minKeystoneLevel) or 0))

            local minHint = mplusPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            minHint:SetPoint("TOPLEFT", 170, -94)
            minHint:SetPoint("RIGHT", 0, 0)
            minHint:SetJustifyH("LEFT")
            minHint:SetText("0 = off. Hides only \"[Dungeon +N]\"-tagged posts below this.")
            SetInk(minHint, MUTED)
            if minHint.SetWordWrap then minHint:SetWordWrap(true) end

            local function ApplyMinLevel(self)
                local n = tonumber(self:GetText())
                local dbNow = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
                if not n or n < 0 then n = 0 end
                if n > 30 then n = 30 end
                if dbNow then
                    dbNow.minKeystoneLevel = n
                end
                self:SetText(tostring(n))
                self:ClearFocus()
            end
            minEdit:SetScript("OnEnterPressed", ApplyMinLevel)
            minEdit:SetScript("OnEditFocusLost", ApplyMinLevel)

            local function ApplyAndPreview()
                local dbNow = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
                if not dbNow then
                    return
                end
                dbNow.mplusDungeon = dEdit:GetText() or ""
                dbNow.mplusLevel = tonumber(lEdit:GetText()) or 0
                local prefix = ""
                if AscensionLFM.Poster and AscensionLFM.Poster.MPlusPrefix then
                    prefix = AscensionLFM.Poster.MPlusPrefix(dbNow.mplusDungeon, dbNow.mplusLevel)
                end
                preview:SetText(prefix ~= "" and ("Preview: " .. prefix .. "LFM MS ...") or "Preview: (set both fields to tag the post)")
                if AscensionLFM.Poster and AscensionLFM.Poster.RefreshMessage then
                    AscensionLFM.Poster.RefreshMessage()
                end
            end

            dEdit:SetScript("OnEnterPressed", function(self) ApplyAndPreview(); self:ClearFocus() end)
            dEdit:SetScript("OnEditFocusLost", ApplyAndPreview)
            lEdit:SetScript("OnEnterPressed", function(self) ApplyAndPreview(); self:ClearFocus() end)
            lEdit:SetScript("OnEditFocusLost", ApplyAndPreview)

            local clearBtn2 = CreateFrame("Button", nil, mplusPane, "UIPanelButtonTemplate")
            if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then
                AscensionLFM.Chrome.SkinActionButton(clearBtn2)
            end
            clearBtn2:SetSize(70, 22)
            clearBtn2:SetPoint("TOPLEFT", 110, -28)
            clearBtn2:SetText("Clear")
            clearBtn2:SetScript("OnClick", function()
                dEdit:SetText("")
                lEdit:SetText("0")
                ApplyAndPreview()
            end)

            ApplyAndPreview()
        end

        local startDb = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
        local startType = (startDb and startDb.contentType) or "ms"
        ShowPaneFor(startType)
    end

    local kick = BuildCategoryPage(pageHost, CAT_KICK, 300)
    CreateSectionLabel(kick, "Level-59 auto-kick", -4)
    widgets.autoKick = CreateToggleRow(kick, -22,
        "Enable kick at level 59 + raid warning every 10s",
        "Hosting/Full Auto * lead/assist * ignores self * RW then kick (deferred). /alfm status shows why. Default OFF.",
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
        if fs.SetHeight then fs:SetHeight(14) end
        FitText(fs, nil, 14)
        kickFS[i] = fs
        ky = ky - 18
    end

    --------------------------------------------------------------------
    -- Log
    --------------------------------------------------------------------

    BuildAppearanceCategory(pageHost)

    local log = BuildCategoryPage(pageHost, CAT_LOG, 480)
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
        if fs.SetHeight then fs:SetHeight(32) end
        FitText(fs, nil, 32)
        matchFS[i] = fs
        my = my - 38
    end

    CreateSectionLabel(log, "Session summary", -232)
    sessionSummaryFS = log:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionSummaryFS:SetPoint("TOPLEFT", 4, -250)
    sessionSummaryFS:SetPoint("RIGHT", -110, 0)
    sessionSummaryFS:SetJustifyH("LEFT")
    SetInk(sessionSummaryFS, INK)
    sessionSummaryFS:SetText("Session (0m): 0 invited, 0 rejected, 0 kicked, 0 matches, 0 posts")

    local sessionResetBtn = CreateFrame("Button", nil, log, "UIPanelButtonTemplate")
    if AscensionLFM.Chrome and AscensionLFM.Chrome.SkinActionButton then AscensionLFM.Chrome.SkinActionButton(sessionResetBtn) end
    sessionResetBtn:SetSize(96, 20)
    sessionResetBtn:SetPoint("TOPRIGHT", -4, -248)
    sessionResetBtn:SetText("Reset session")
    sessionResetBtn:SetScript("OnClick", function()
        if AscensionLFM.Activity and AscensionLFM.Activity.ResetSession then
            AscensionLFM.Activity.ResetSession()
        end
        MainWindow.RefreshActivity()
    end)

    CreateSectionLabel(log, "Activity (posts / invites / rejects / matches)", -282)
    local actBox = CreateFrame("Frame", nil, log)
    actBox:SetPoint("TOPLEFT", 0, -300)
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

-- ============================================================================
-- ============================================================================
-- Diagnostic: /alfmmaindebug
-- ============================================================================
-- Atlas identification lives in ui/Chrome.lua (shared with MiniHUD).
local function MainWinIdentifyPiece(tex, left, right, top, bottom)
    if AscensionLFM.Chrome and AscensionLFM.Chrome.IdentifyPiece then
        return AscensionLFM.Chrome.IdentifyPiece(tex, left, right, top, bottom)
    end
    return nil
end

SLASH_ALFMMAINDEBUG1 = "/alfmmaindebug"
if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMMAINDEBUG"] = function()
        if type(frame) ~= "table" or not frame.GetRegions then
            print("AscensionLFM: main window isn't built yet - open it first (/alfm).")
            return
        end

        print("AscensionLFM MainWindow debug:")
        print(string.format("  Frame size: %.0f x %.0f", frame:GetWidth(), frame:GetHeight()))

        local i = 0
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                i = i + 1
                local tex = region.GetTexture and region:GetTexture()
                local w, h = region:GetWidth(), region:GetHeight()
                local okPoint, rPoint, rRel, rRelPoint, rX, rY = pcall(region.GetPoint, region, 1)
                local shown = (region.IsShown and region:IsShown()) and " shown" or " hidden"
                local owned = region._duiOwned and " [DragonUI-added]" or ""

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
                        local name = MainWinIdentifyPiece(tex, l, r, t, b)
                        if name then identified = "  -> " .. name end
                    end
                end

                if okPoint then
                    print(string.format("  [%d] %.0fx%.0f%s  point=%s rel=%s,%s off=%.0f,%.0f  tex=%s%s%s%s",
                        i, w or 0, h or 0, shown,
                        rPoint or "?", rRel and (rRel.GetName and rRel:GetName() or "?") or "?", rRelPoint or "?",
                        rX or 0, rY or 0, tostring(tex), owned, coordLine, identified))
                else
                    print(string.format("  [%d] %.0fx%.0f%s  (no point)  tex=%s%s%s%s", i, w or 0, h or 0, shown, tostring(tex), owned, coordLine, identified))
                end
            end
        end
        print(string.format("  Total texture regions: %d", i))
        print("Copy this output (or a screenshot of the window) back for a more precise pass.")
    end
end

