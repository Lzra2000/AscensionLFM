-- AscensionLFM: ui/MinimapButton.lua
-- Draggable minimap icon: left-click opens settings, right-click toggles
-- the Mini Quick HUD. Tooltip shows mode + session activity + pending
-- applicants. On (shown) by default; toggle via Settings -> General ->
-- Minimap, or /alfmminimap [on|off].

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local MinimapButton = {}
AscensionLFM.MinimapButton = MinimapButton

local RADIUS = 80
local DEFAULT_ANGLE = 220
local button

local function DB()
    return AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
end

local function SetAngle(angleDeg)
    local db = DB()
    if db then
        db.minimapAngle = angleDeg
    end
    if not button or type(Minimap) ~= "table" then
        return
    end
    local rad = math.rad(angleDeg)
    local x = math.cos(rad) * RADIUS
    local y = math.sin(rad) * RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local MODE_LABEL = {
    off = "Off",
    notify = "Notify",
    seeking = "Seeking",
    hosting = "Hosting",
}

local function PendingCount()
    if not (AscensionLFM.Queue and AscensionLFM.Queue.Recent) then
        return 0
    end
    local ok, entries = pcall(AscensionLFM.Queue.Recent)
    if not ok or type(entries) ~= "table" then
        return 0
    end
    local n = 0
    for _, e in ipairs(entries) do
        if e.status == "pending" then
            n = n + 1
        end
    end
    return n
end

local function UpdateBadge()
    if not button or not button.badge then
        return
    end
    local n = PendingCount()
    if n > 0 then
        button.badge:SetText(n > 9 and "9+" or tostring(n))
        button.badge:Show()
    else
        button.badge:Hide()
    end
end
MinimapButton.UpdateBadge = UpdateBadge

local function BuildTooltip(self)
    if type(GameTooltip) ~= "table" then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("AscensionLFM", 1, 0.82, 0.24)
    local db = DB()
    local mode = (db and MODE_LABEL[db.mode]) or "Notify"
    GameTooltip:AddLine("Mode: " .. mode, 0.9, 0.9, 0.9)
    if AscensionLFM.Activity and AscensionLFM.Activity.GetSessionSummary and AscensionLFM.Activity.FormatSessionSummary then
        local ok, summary = pcall(AscensionLFM.Activity.GetSessionSummary)
        if ok and summary then
            local ok2, line = pcall(AscensionLFM.Activity.FormatSessionSummary, summary)
            if ok2 and line then
                GameTooltip:AddLine(line, 0.7, 0.7, 0.7, true)
            end
        end
    end
    local pending = PendingCount()
    if pending > 0 then
        GameTooltip:AddLine(pending .. " applicant(s) waiting in Queue", 1, 0.6, 0.3)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: open settings", 0.6, 0.8, 1)
    GameTooltip:AddLine("Right-click: toggle Mini HUD", 0.6, 0.8, 1)
    GameTooltip:AddLine("Drag: move", 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function BuildButton()
    if button or type(CreateFrame) ~= "function" or type(Minimap) ~= "table" then
        return button
    end
    local b = CreateFrame("Button", "AscensionLFMMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)

    if b.SetHighlightTexture then
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end

    local badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("BOTTOMRIGHT", 2, 0)
    badge:SetTextColor(1, 0.3, 0.3)
    badge:Hide()
    b.badge = badge

    b:SetScript("OnEnter", BuildTooltip)
    b:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" then
            GameTooltip:Hide()
        end
    end)

    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.SetShown and AscensionLFM.MiniHUD.IsShown then
                AscensionLFM.MiniHUD.SetShown(not AscensionLFM.MiniHUD.IsShown())
            end
        else
            if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
                pcall(AscensionLFM.MainWindow.Toggle)
            end
        end
    end)

    b:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    b:SetScript("OnUpdate", function(self, elapsed)
        if self.dragging then
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            SetAngle(angle)
        end
        self.badgeAcc = (self.badgeAcc or 0) + (elapsed or 0)
        if self.badgeAcc >= 2 then
            self.badgeAcc = 0
            UpdateBadge()
        end
    end)

    button = b
    return b
end

function MinimapButton.SetShown(on)
    local db = DB()
    if db then
        db.minimapIconShown = on and true or false
    end
    if not button then
        if on then
            BuildButton()
            local db2 = DB()
            SetAngle((db2 and tonumber(db2.minimapAngle)) or DEFAULT_ANGLE)
            UpdateBadge()
        end
        return
    end
    if on then
        button:Show()
    else
        button:Hide()
    end
end

function MinimapButton.IsShown()
    return button and button:IsShown() and true or false
end

function MinimapButton.Start()
    local db = DB()
    if db and db.minimapIconShown == false then
        return
    end
    BuildButton()
    local db2 = DB()
    SetAngle((db2 and tonumber(db2.minimapAngle)) or DEFAULT_ANGLE)
    UpdateBadge()
end

SLASH_ALFMMINIMAP1 = "/alfmminimap"
if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMMINIMAP"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "on" then
            MinimapButton.SetShown(true)
        elseif msg == "off" then
            MinimapButton.SetShown(false)
        else
            MinimapButton.SetShown(not MinimapButton.IsShown())
        end
        if AscensionLFM.Print then
            AscensionLFM.Print("Minimap icon: " .. (MinimapButton.IsShown() and "ON" or "OFF"))
        end
    end
end

return MinimapButton
