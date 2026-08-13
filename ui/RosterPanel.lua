-- AscensionLFM: ui/RosterPanel.lua
-- Group overview: raid subgroups with assigned roles (Manastorm-style cards).

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local RosterPanel = {}
AscensionLFM.RosterPanel = RosterPanel

local function Now()
    return (type(GetTime) == "function" and GetTime()) or os.clock()
end

-- { name=, checkAt= } - set after a TryKick() UninviteUnit call that
-- didn't error, verified on the next tick before trusting it. Same
-- "no error != it worked" lesson as Kick.lua's v0.4.28 fix (and the
-- warn/kick cycle the removed AuraScan.lua used to have) -
-- UninviteUnit is fire-and-forget and can silently no-op (e.g. lacking
-- privilege in an edge case, or the target being in combat) without
-- ever throwing a Lua error.
local KICK_VERIFY_DELAY = 1.5
local pendingKickVerify = nil

local ROLE_ORDER = { "tank", "healer", "aura", "dps", "" }
local ROLE_SHORT = { tank = "T", healer = "H", aura = "A", dps = "D", [""] = "?" }
local ROLE_LABELS = {
    tank = "Tank",
    healer = "Healer",
    aura = "Aura",
    dps = "DPS",
    [""] = "None",
}
local ROLE_ICONS = {
    tank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    healer = "Interface\\Icons\\Spell_Holy_HolyBolt",
    aura = "Interface\\Icons\\Spell_Nature_LightningShield",
    dps = "Interface\\Icons\\INV_Sword_27",
    [""] = "Interface\\Icons\\INV_Misc_QuestionMark",
}
local ROLE_COLORS = {
    tank = { 0.4, 0.6, 1.0 },
    healer = { 0.3, 0.9, 0.4 },
    aura = { 0.9, 0.7, 0.2 },
    dps = { 0.95, 0.45, 0.35 },
    [""] = { 0.55, 0.55, 0.55 },
}

local CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 },
    PRIEST = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0.00, 0.44, 0.87 },
    MAGE = { 0.41, 0.80, 0.94 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID = { 1.00, 0.49, 0.04 },
}

local groupCards = {} -- [subgroup] = { title, auraFS, rows = { {frame, roleBtn, nameFS, lvlFS, kickBtn} } }
local summaryFS
local hostFrame
local lastBuildAt = 0

local function LowerName(name)
    return tostring(name or ""):lower():gsub("%-.*$", "")
end

local function GetAssigned(name)
    if AscensionLFM.Slots and AscensionLFM.Slots.GetAssigned then
        return AscensionLFM.Slots.GetAssigned(name)
    end
    return nil
end

local function AssignRole(name, role)
    if type(name) ~= "string" or name == "" then
        return
    end
    role = role or ""
    if AscensionLFM.Slots then
        if role == "" and AscensionLFM.Slots.ClearName then
            AscensionLFM.Slots.ClearName(name)
        elseif role ~= "" and AscensionLFM.Slots.Assign then
            AscensionLFM.Slots.Assign(name, role)
        end
    end
    if AscensionLFM.Print then
        AscensionLFM.Print(string.format("Roster: %s -> %s", name, role ~= "" and role or "unassigned"))
    end
    RosterPanel.Refresh()
end

local rolePicker
local rolePickerTarget

local function HideRolePicker()
    if rolePicker then
        rolePicker:Hide()
    end
    rolePickerTarget = nil
end

local function EnsureRolePicker()
    if rolePicker then
        return rolePicker
    end
    local f = CreateFrame("Frame", "AscensionLFMRolePicker", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(200)
    f:SetWidth(148)
    f:SetHeight(5 * 28 + 12)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.08, 0.07, 0.05, 0.96)
    local border = f:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")
    border:SetVertexColor(0.85, 0.68, 0.22, 0.55)
    -- inset bg
    local inset = f:CreateTexture(nil, "BACKGROUND")
    inset:SetPoint("TOPLEFT", 1, -1)
    inset:SetPoint("BOTTOMRIGHT", -1, 1)
    inset:SetTexture("Interface\\Buttons\\WHITE8X8")
    inset:SetVertexColor(0.10, 0.09, 0.07, 0.98)

    f.rows = {}
    local roles = { "tank", "healer", "aura", "dps", "" }
    for i, role in ipairs(roles) do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 28)
        row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 28)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexture(ROLE_ICONS[role] or ROLE_ICONS[""])
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        fs:SetText(ROLE_LABELS[role] or role)
        local col = ROLE_COLORS[role] or ROLE_COLORS[""]
        fs:SetTextColor(col[1], col[2], col[3], 1)
        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetTexture("Interface\\Buttons\\WHITE8X8")
        hi:SetVertexColor(1, 1, 1, 0.12)
        row.role = role
        row:SetScript("OnClick", function(self)
            if rolePickerTarget then
                AssignRole(rolePickerTarget, self.role)
            end
            HideRolePicker()
        end)
        f.rows[i] = row
    end

    f:SetScript("OnHide", function()
        rolePickerTarget = nil
    end)
    -- click outside: close when parent mouse down - simple escape via update
    f:Hide()
    rolePicker = f
    return f
end

local function ShowRolePicker(anchor, memberName)
    if type(memberName) ~= "string" or memberName == "" then
        return
    end
    local f = EnsureRolePicker()
    rolePickerTarget = memberName
    f:ClearAllPoints()
    if anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 4)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    f:Show()
    f:Raise()
end

local function TryKick(name)
    if type(UninviteUnit) ~= "function" or type(name) ~= "string" then
        return
    end
    local can = false
    if type(IsRaidLeader) == "function" and IsRaidLeader() then
        can = true
    end
    if type(IsRaidOfficer) == "function" and IsRaidOfficer() then
        can = true
    end
    if type(IsPartyLeader) == "function" and IsPartyLeader() then
        can = true
    end
    if not can then
        if AscensionLFM.Print then
            AscensionLFM.Print("Roster: need lead/assist to remove " .. name)
        end
        return
    end
    local ok = pcall(UninviteUnit, name)
    if not ok then
        if AscensionLFM.Print then
            AscensionLFM.Print("Roster: failed to remove " .. name)
        end
        return
    end
    -- Don't trust this yet - verify on the next tick before confirming.
    pendingKickVerify = { name = name, checkAt = Now() + KICK_VERIFY_DELAY }
    if AscensionLFM.Print then
        AscensionLFM.Print("Roster: removing " .. name .. " ...")
    end
end

--- Check a pending TryKick() removal against the live roster. Called from
-- the panel's own periodic ticker (RosterPanel.Start()) - no separate
-- Start/Tick pair needed since this is a single manual action, not an
-- automated cycle with retries.
local function CheckPendingKick()
    if not pendingKickVerify then
        return
    end
    if Now() < pendingKickVerify.checkAt then
        return
    end
    local name = pendingKickVerify.name
    pendingKickVerify = nil
    local stillPresent = false
    local groups = RosterPanel.BuildData()
    for g = 1, 8 do
        for _, m in ipairs(groups[g] or {}) do
            if LowerName(m.name) == LowerName(name) then
                stillPresent = true
                break
            end
        end
        if stillPresent then
            break
        end
    end
    if AscensionLFM.Print then
        if stillPresent then
            AscensionLFM.Print("Roster: " .. name .. " still in group - try again "
                .. "(may lack privilege, or they're in combat)")
        else
            AscensionLFM.Print("Roster: " .. name .. " removed")
        end
    end
end

--- Pure roster snapshot for UI / tests.
-- @return groups { [1..8] = { {name, level, class, online, role, subgroup}, ... } }, counts
function RosterPanel.BuildData()
    local groups = {}
    for g = 1, 8 do
        groups[g] = {}
    end
    local counts = { tank = 0, healer = 0, aura = 0, dps = 0, unknown = 0, total = 0, online = 0 }

    local raid = (type(GetNumRaidMembers) == "function" and GetNumRaidMembers()) or 0
    if raid and raid > 0 then
        for i = 1, raid do
            local name, _, subgroup, level, class, classFile, _, online = nil, nil, 1, 0, nil, nil, nil, 1
            if type(GetRaidRosterInfo) == "function" then
                name, _, subgroup, level, class, classFile, _, online = GetRaidRosterInfo(i)
            end
            if type(name) ~= "string" or name == "" then
                if type(UnitName) == "function" then
                    name = UnitName("raid" .. i)
                end
            end
            if type(name) == "string" and name ~= "" then
                subgroup = tonumber(subgroup) or 1
                if subgroup < 1 then subgroup = 1 end
                if subgroup > 8 then subgroup = 8 end
                local role = GetAssigned(name) or ""
                local entry = {
                    name = name,
                    level = tonumber(level) or 0,
                    class = classFile or class or "",
                    online = online ~= 0 and online ~= false,
                    role = role,
                    subgroup = subgroup,
                    unit = "raid" .. i,
                }
                table.insert(groups[subgroup], entry)
                counts.total = counts.total + 1
                if entry.online then
                    counts.online = counts.online + 1
                end
                if role == "tank" then counts.tank = counts.tank + 1
                elseif role == "healer" then counts.healer = counts.healer + 1
                elseif role == "aura" then counts.aura = counts.aura + 1
                elseif role == "dps" then counts.dps = counts.dps + 1
                else counts.unknown = counts.unknown + 1
                end
            end
        end
    else
        -- Party / solo
        local function add(unit, subgroup)
            local name = type(UnitName) == "function" and UnitName(unit) or nil
            if type(name) ~= "string" or name == "" then
                return
            end
            local level = (type(UnitLevel) == "function" and UnitLevel(unit)) or 0
            local classFile
            if type(UnitClass) == "function" then
                local _, cf = UnitClass(unit)
                classFile = cf
            end
            local role = GetAssigned(name) or ""
            local entry = {
                name = name,
                level = tonumber(level) or 0,
                class = classFile or "",
                online = true,
                role = role,
                subgroup = subgroup,
                unit = unit,
            }
            table.insert(groups[subgroup], entry)
            counts.total = counts.total + 1
            counts.online = counts.online + 1
            if role == "tank" then counts.tank = counts.tank + 1
            elseif role == "healer" then counts.healer = counts.healer + 1
            elseif role == "aura" then counts.aura = counts.aura + 1
            elseif role == "dps" then counts.dps = counts.dps + 1
            else counts.unknown = counts.unknown + 1
            end
        end
        add("player", 1)
        local party = (type(GetNumPartyMembers) == "function" and GetNumPartyMembers()) or 0
        for i = 1, party do
            add("party" .. i, 1)
        end
    end
    local roleRank = { tank = 1, healer = 2, aura = 3, dps = 4, [""] = 5 }
    for g = 1, 8 do
        table.sort(groups[g], function(a, b)
            local ra = roleRank[a.role or ""] or 5
            local rb = roleRank[b.role or ""] or 5
            if ra ~= rb then return ra < rb end
            return tostring(a.name) < tostring(b.name)
        end)
    end
    return groups, counts
end

function RosterPanel.FormatSummary(counts, slotMax)
    counts = counts or {}
    slotMax = slotMax or {}
    local function pair(role, short)
        local filled = tonumber(counts[role]) or 0
        local max = tonumber(slotMax[role]) or 0
        if max > 0 then
            return string.format("%s %d/%d", short, filled, max)
        end
        return string.format("%s %d", short, filled)
    end
    return string.format("%s   %s   %s   %s   |  %d online / %d total   unk %d",
        pair("tank", "T"), pair("healer", "H"), pair("aura", "A"), pair("dps", "D"),
        tonumber(counts.online) or 0, tonumber(counts.total) or 0, tonumber(counts.unknown) or 0)
end

local function SetRoleButton(btn, role)
    role = role or ""
    local col = ROLE_COLORS[role] or ROLE_COLORS[""]
    if btn.icon then
        btn.icon:SetTexture(ROLE_ICONS[role] or ROLE_ICONS[""])
        if btn.icon.SetTexCoord then
            btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    if btn.bg then
        btn.bg:SetTexture("Interface\Buttons\WHITE8X8")
        btn.bg:SetVertexColor(col[1] * 0.2, col[2] * 0.2, col[3] * 0.2, 0.95)
    end
    if btn.border then
        btn.border:SetTexture("Interface\Buttons\WHITE8X8")
        btn.border:SetVertexColor(col[1], col[2], col[3], 0.9)
    end
    if btn.letter then
        btn.letter:SetText(ROLE_SHORT[role] or "?")
        btn.letter:SetTextColor(1, 1, 1, 0.9)
    end
end

local function EnsureCards(parent)
    if groupCards[1] then
        return
    end
    local colW = 248
    local cardH = 156
    for g = 1, 8 do
        local col = ((g - 1) % 2)
        local row = math.floor((g - 1) / 2)
        local card = CreateFrame("Frame", nil, parent)
        card:SetSize(colW, cardH)
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 4 + col * (colW + 10), -36 - row * (cardH + 10))

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.10, 0.09, 0.07, 0.92)

        local edge = card:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", 0, 0)
        edge:SetPoint("TOPRIGHT", 0, 0)
        edge:SetHeight(2)
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        edge:SetVertexColor(0.85, 0.68, 0.22, 0.7)

        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 8, -6)
        title:SetText("Group " .. g)
        title:SetTextColor(1, 0.82, 0.28)
        card.titleFS = title

        local aura = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        aura:SetPoint("TOPRIGHT", -8, -8)
        aura:SetJustifyH("RIGHT")
        aura:SetTextColor(0.9, 0.72, 0.25)
        card.auraFS = aura

        card.rows = {}
        for i = 1, 5 do
            local rowF = CreateFrame("Frame", nil, card)
            rowF:SetSize(colW - 12, 24)
            rowF:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 25)

            local roleBtn = CreateFrame("Button", nil, rowF)
            roleBtn:SetSize(22, 22)
            roleBtn:SetPoint("LEFT", 0, 0)
            local bg = roleBtn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            roleBtn.bg = bg
            local border = roleBtn:CreateTexture(nil, "BORDER")
            border:SetPoint("TOPLEFT", -1, 1)
            border:SetPoint("BOTTOMRIGHT", 1, -1)
            border:SetTexture("Interface\\Buttons\\WHITE8X8")
            roleBtn.border = border
            local icon = roleBtn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", -2, 2)
            icon:SetTexture(ROLE_ICONS[""])
            roleBtn.icon = icon
            local letter = roleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            letter:SetPoint("BOTTOMRIGHT", 1, -1)
            letter:SetText("?")
            roleBtn.letter = letter
            roleBtn:SetScript("OnClick", function(self)
                if self.memberName then
                    ShowRolePicker(self, self.memberName)
                end
            end)
            roleBtn:SetScript("OnEnter", function(self)
                if not self.memberName then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.memberName)
                GameTooltip:AddLine("Click to open role menu", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            roleBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            local kickBtn = CreateFrame("Button", nil, rowF, "UIPanelButtonTemplate")
            kickBtn:SetSize(26, 18)
            kickBtn:SetPoint("RIGHT", -2, 0)
            kickBtn:SetText("X")
            kickBtn:SetScript("OnClick", function(self)
                if self.memberName then
                    TryKick(self.memberName)
                end
            end)

            local lvlFS = rowF:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            lvlFS:SetPoint("RIGHT", kickBtn, "LEFT", -6, 0)
            lvlFS:SetWidth(26)
            lvlFS:SetJustifyH("RIGHT")
            lvlFS:SetTextColor(0.7, 0.65, 0.5)

            local nameFS = rowF:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameFS:SetPoint("LEFT", roleBtn, "RIGHT", 6, 0)
            nameFS:SetPoint("RIGHT", lvlFS, "LEFT", -4, 0)
            nameFS:SetJustifyH("LEFT")
            if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end

            rowF.roleBtn = roleBtn
            rowF.nameFS = nameFS
            rowF.lvlFS = lvlFS
            rowF.kickBtn = kickBtn
            card.rows[i] = rowF
        end
        groupCards[g] = card
    end
end

function RosterPanel.Attach(parent)
    if not parent or type(CreateFrame) ~= "function" then
        return
    end
    hostFrame = parent
    summaryFS = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryFS:SetPoint("TOPLEFT", 6, -6)
    summaryFS:SetPoint("TOPRIGHT", -90, -6)
    summaryFS:SetJustifyH("LEFT")
    summaryFS:SetTextColor(0.95, 0.88, 0.55)
    summaryFS:SetText("Roster empty")
    if summaryFS.SetWordWrap then summaryFS:SetWordWrap(false) end

    local rcBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    rcBtn:SetSize(70, 22)
    rcBtn:SetPoint("TOPRIGHT", -4, -4)
    rcBtn:SetText("Ready")
    rcBtn:SetScript("OnClick", function()
        RosterPanel.DoReadyCheck()
    end)
    hostFrame.readyBtn = rcBtn

    EnsureCards(parent)
    RosterPanel.Refresh()
end

function RosterPanel.Refresh()
    HideRolePicker()
    if not hostFrame then
        return
    end
    EnsureCards(hostFrame)
    local groups, counts = RosterPanel.BuildData()
    local slotMax = {}
    if AscensionLFM.Slots and AscensionLFM.Slots.GetMax then
        for _, r in ipairs({ "tank", "healer", "aura", "dps" }) do
            slotMax[r] = AscensionLFM.Slots.GetMax(r)
        end
    end
    if summaryFS then
        local sum = RosterPanel.FormatSummary(counts, slotMax)
        if #sum > 72 then sum = sum:sub(1, 71) .. "..." end
        summaryFS:SetText(sum)
    end

    for g = 1, 8 do
        local card = groupCards[g]
        if card then
            local list = groups[g] or {}
            local auraN = 0
            for _, m in ipairs(list) do
                if m.role == "aura" then
                    auraN = auraN + 1
                end
            end
            if card.auraFS then
                if auraN > 0 then
                    card.auraFS:SetText("Aura x" .. auraN)
                    card.auraFS:SetTextColor(0.9, 0.75, 0.2)
                else
                    card.auraFS:SetText(#list > 0 and "no aura" or "")
                    card.auraFS:SetTextColor(0.6, 0.4, 0.35)
                end
            end
            for i = 1, 5 do
                local row = card.rows[i]
                local m = list[i]
                if m then
                    row:Show()
                    row.roleBtn.memberName = m.name
                    row.kickBtn.memberName = m.name
                    SetRoleButton(row.roleBtn, m.role)
                    local cc = CLASS_COLORS[string.upper(tostring(m.class or ""))] or { 0.85, 0.8, 0.7 }
                    if not m.online then
                        cc = { 0.45, 0.45, 0.45 }
                    end
                    row.nameFS:SetText(m.name)
                    row.nameFS:SetTextColor(cc[1], cc[2], cc[3])
                    row.lvlFS:SetText(m.level > 0 and tostring(m.level) or "")
                    row.kickBtn:Show()
                else
                    row.roleBtn.memberName = nil
                    row.kickBtn.memberName = nil
                    row.nameFS:SetText("")
                    row.lvlFS:SetText("")
                    row.kickBtn:Hide()
                    SetRoleButton(row.roleBtn, "")
                    if i == 1 and #list == 0 then
                        row:Show()
                        row.nameFS:SetText("|cff5a4a30Empty|r")
                    else
                        row:Hide()
                    end
                end
            end
        end
    end
    lastBuildAt = (type(GetTime) == "function" and GetTime()) or 0
end

function RosterPanel.Start()
    if RosterPanel._frame then
        return
    end
    if type(CreateFrame) ~= "function" then
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PARTY_MEMBERS_CHANGED")
    f:RegisterEvent("RAID_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        RosterPanel.Refresh()
    end)
    f:SetScript("OnUpdate", function(self, elapsed)
        if pendingKickVerify then
            CheckPendingKick()
        end
        self._t = (self._t or 0) + (elapsed or 0)
        if self._t < 2 then
            return
        end
        self._t = 0
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.GetActiveCategory
            and AscensionLFM.MainWindow.GetActiveCategory() == "roster" then
            RosterPanel.Refresh()
        end
    end)
    RosterPanel._frame = f
end

RosterPanel.ROLE_ICONS = ROLE_ICONS
RosterPanel.ROLE_ORDER = ROLE_ORDER
RosterPanel._TryKick = TryKick
RosterPanel._CheckPendingKick = CheckPendingKick
RosterPanel._GetPendingKickVerify = function() return pendingKickVerify end
RosterPanel._ResetForTests = function() pendingKickVerify = nil end
