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
local ANNOUNCE_GAP = 2

local frame
local expanded = true
local buttons = {}
local lastAnnounceAt = 0
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

local function CanRaidWarn()
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.CanRaidWarn then
        return AscensionLFM.RoleCheck.CanRaidWarn()
    end
    if AscensionLFM.Kick and AscensionLFM.Kick.CanKick then
        return AscensionLFM.Kick.CanKick()
    end
    return false, "none"
end

local function SendGroupAnnounce(msg)
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
    elseif groupKind == "party" then
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

local function RateOk()
    local now = Now()
    if (now - lastAnnounceAt) < ANNOUNCE_GAP then
        return false
    end
    lastAnnounceAt = now
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

function MiniHUD.ActionOpenSettings()
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
        pcall(AscensionLFM.MainWindow.Toggle)
        return true
    end
    Print("settings UI missing — /alfm")
    return false
end

function MiniHUD.ActionPostLfm()
    local db = DB()
    if not AscensionLFM.Poster or not AscensionLFM.Poster.PostOnce then
        return false, "no poster"
    end
    if AscensionLFM.Poster.RefreshMessage then
        AscensionLFM.Poster.RefreshMessage()
    end
    local msg = AscensionLFM.Poster.GetMessage and AscensionLFM.Poster.GetMessage() or nil
    return AscensionLFM.Poster.PostOnce(msg, db and db.postChannel, db and db.postChannelName)
end

function MiniHUD.ActionRoleCheck()
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.StartCheck then
        return AscensionLFM.RoleCheck.StartCheck()
    end
    return false, "no rolecheck"
end

function MiniHUD.ActionResync()
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.ResyncNow then
        return AscensionLFM.RoleCheck.ResyncNow()
    end
    if AscensionLFM.Slots and AscensionLFM.Slots.ScanRaid then
        AscensionLFM.Slots.ScanRaid()
        return true
    end
    return false, "no resync"
end

function MiniHUD.ActionWipe()
    if not RateOk() then
        return false, "rate limited"
    end
    local db = DB()
    local msg = MiniHUD.BuildWipeMessage(db and db.wipeAnnounceMessage)
    local ok, ch = SendGroupAnnounce(msg)
    if ok then
        Print("Wipe → " .. tostring(ch) .. ": " .. msg)
        if AscensionLFM.Activity and AscensionLFM.Activity.Push then
            AscensionLFM.Activity.Push("wipe", msg)
        end
    end
    return ok, ch
end

function MiniHUD.ActionFull()
    if not RateOk() then
        return false, "rate limited"
    end
    local db = DB()
    local msg = tostring((db and db.fullAnnounceMessage) or "LFM MS FULL — thanks!")
    local channel = (db and db.postChannel) or "YELL"
    if AscensionLFM.Poster and AscensionLFM.Poster.PostOnce then
        return AscensionLFM.Poster.PostOnce(msg, channel, db and db.postChannelName)
    end
    local ok, ch = SendGroupAnnounce(msg)
    return ok, ch
end

function MiniHUD.ActionNeed(role)
    if not RateOk() then
        return false, "rate limited"
    end
    local msg = MiniHUD.BuildNeedMessage(role)
    if not msg then
        return false, "bad role"
    end
    local db = DB()
    local channel = (db and db.postChannel) or "YELL"
    if AscensionLFM.Poster and AscensionLFM.Poster.PostOnce then
        local ok, err = AscensionLFM.Poster.PostOnce(msg, channel, db and db.postChannelName)
        return ok, err or channel
    end
    return SendGroupAnnounce(msg)
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
        frame:SetWidth(320)
        frame:SetHeight(58)
        if frame.titleFS then
            frame.titleFS:SetText("AscensionLFM")
        end
        for _, b in pairs(buttons) do
            if b and b.Show then
                b:Show()
            end
        end
        if frame.collapseBtn then
            frame.collapseBtn:SetText("×")
        end
        if statusFS then
            statusFS:Show()
        end
    else
        frame:SetWidth(56)
        frame:SetHeight(28)
        if frame.titleFS then
            frame.titleFS:SetText("ALFM")
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
    end
    MiniHUD.Refresh()
end

local function MakeBtn(parent, label, width, onClick, danger)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 40, 20)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
        local ok, err = onClick()
        if ok == false and err and AscensionLFM.Print then
            AscensionLFM.Print("MiniHUD: " .. tostring(err))
        end
        MiniHUD.Refresh()
    end)
    if danger and btn.GetFontString then
        local fs = btn:GetFontString()
        if fs and fs.SetTextColor then
            fs:SetTextColor(1, 0.55, 0.45)
        end
    end
    return btn
end

local function BuildFrame()
    if frame or type(CreateFrame) ~= "function" then
        return frame
    end
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetWidth(320)
    f:SetHeight(58)
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

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    bg:SetVertexColor(0.15, 0.12, 0.06, 0.92)

    local border = f:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    border:SetVertexColor(0.7, 0.55, 0.2, 0.55)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("AscensionLFM")
    title:SetTextColor(1, 0.82, 0.24)
    f.titleFS = title

    local chip = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chip:SetPoint("LEFT", title, "RIGHT", 8, 0)
    chip:SetText("HOST")
    chip:SetTextColor(0.85, 0.75, 0.4)
    f.chipFS = chip

    -- Click brand / collapsed chip → settings (expanded) or expand (collapsed)
    local hit = CreateFrame("Button", nil, f)
    hit:SetPoint("TOPLEFT", 4, -2)
    hit:SetSize(120, 18)
    hit:SetScript("OnClick", function()
        if not expanded then
            SetExpanded(true)
            return
        end
        MiniHUD.ActionOpenSettings()
    end)

    local collapse = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    collapse:SetSize(20, 18)
    collapse:SetPoint("TOPRIGHT", -4, -4)
    collapse:SetText("×")
    collapse:SetScript("OnClick", function()
        SetExpanded(false)
    end)
    f.collapseBtn = collapse

    local y = -28
    local x = 6
    local function place(btn)
        btn:SetPoint("TOPLEFT", x, y)
        x = x + (btn:GetWidth() or 40) + 3
    end

    buttons.lfm = MakeBtn(f, "LFM", 40, function()
        return MiniHUD.ActionPostLfm()
    end)
    place(buttons.lfm)

    buttons.rw = MakeBtn(f, "RW", 34, function()
        return MiniHUD.ActionRoleCheck()
    end)
    place(buttons.rw)

    buttons.sync = MakeBtn(f, "Sync", 40, function()
        return MiniHUD.ActionResync()
    end)
    place(buttons.sync)

    buttons.wipe = MakeBtn(f, "Wipe", 40, function()
        return MiniHUD.ActionWipe()
    end, true)
    place(buttons.wipe)

    buttons.full = MakeBtn(f, "FULL", 42, function()
        return MiniHUD.ActionFull()
    end)
    place(buttons.full)

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

    statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusFS:SetPoint("BOTTOMLEFT", 8, 4)
    statusFS:SetPoint("BOTTOMRIGHT", -8, 4)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetText("LFM · RW · Sync · Wipe · FULL · Need")
    statusFS:SetTextColor(0.65, 0.58, 0.4)

    frame = f
    ApplyPosition()
    local db = DB()
    local wantExpand = not (db and db.miniHudExpanded == false)
    SetExpanded(wantExpand)
    return frame
end

function MiniHUD.Refresh()
    if not frame then
        return
    end
    if frame.chipFS then
        frame.chipFS:SetText(HostingHint())
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
            SetExpanded(true)
        end
    elseif frame then
        frame:Hide()
    end
end

function MiniHUD.IsShown()
    return frame and frame:IsShown() and true or false
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
end

function MiniHUD._ResetForTests()
    lastAnnounceAt = 0
    expanded = true
end

MiniHUD.DEFAULT_WIPE = DEFAULT_WIPE
MiniHUD.ANNOUNCE_GAP = ANNOUNCE_GAP
