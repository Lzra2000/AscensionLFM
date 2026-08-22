-- AscensionLFM: ui/Chrome.lua
-- Visual bar: official AscensionUI / Interface Options discipline.
-- Outer window: DialogBox + optional header / UIPanelCloseButton.
-- Wells: InsetFrameTemplate (marble) + COMMON ShadowOverlay (CallBoard).
-- Category list: QuestTitleHighlight, GameFontNormal / GameFontHighlightSmall.
-- Buttons: stock UIPanelButtonTemplate at 22px — no gold vertex wash.
--
-- No DragonUI. NEVER PortraitFrameTemplate (EditBox parenting).
-- Engine texture paths only — no proprietary FrameXML copied into the repo.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Chrome = {}
AscensionLFM.Chrome = Chrome

Chrome.CLASSIC_BG     = "Interface\\DialogFrame\\UI-DialogBox-Background"
Chrome.CLASSIC_EDGE   = "Interface\\DialogFrame\\UI-DialogBox-Border"
Chrome.CLASSIC_HEADER = "Interface\\DialogFrame\\UI-DialogBox-Header"
Chrome.CLASSIC_CORNER = "Interface\\DialogFrame\\UI-DialogBox-Corner"
Chrome.MARBLE_BG      = "Interface\\FrameGeneral\\UI-Background-Marble"
Chrome.NAV_HIGHLIGHT  = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
Chrome.SHADOW_TOP     = "Interface\\COMMON\\ShadowOverlay-Top"
Chrome.SHADOW_BOTTOM  = "Interface\\COMMON\\ShadowOverlay-Bottom"
Chrome.SHADOW_LEFT    = "Interface\\COMMON\\ShadowOverlay-left"
Chrome.SHADOW_RIGHT   = "Interface\\COMMON\\ShadowOverlay-Right"

-- MagicButton / UIPanelButton height (AscensionUI ButtonTemplates).
Chrome.BUTTON_H = 22
Chrome.NAV_H    = 22
Chrome.NAV_GAP  = 2

-- GameFontNormal gold (WotLK / AscensionUI). Do not invent extra golds.
Chrome.FONT_NORMAL    = { 1.00, 0.82, 0.00, 1 }
Chrome.FONT_HIGHLIGHT = { 1.00, 1.00, 1.00, 1 }

-- Light ink for InputBoxTemplate on dark DialogBox / inset panels.
-- InputBoxTemplate defaults to near-black text — invisible on dark chrome.
-- Do NOT parent EditBoxes under PortraitFrameTemplate title/portrait
-- regions either — empty/clipped export text (Buildschmiede lesson).
Chrome.EDIT_INK = { 0.96, 0.92, 0.82, 1 }

Chrome.INSET_FALLBACK = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

--- Style an EditBox for dark chrome: AutoFocus off + readable ink.
function Chrome.StyleEditBox(edit)
    if type(edit) ~= "table" then
        return edit
    end
    if edit.SetAutoFocus then
        edit:SetAutoFocus(false)
    end
    if edit.SetTextColor then
        local ink = Chrome.EDIT_INK
        edit:SetTextColor(ink[1], ink[2], ink[3], ink[4] or 1)
    end
    return edit
end

--- Always DialogBox background — no external addon textures.
function Chrome.BackgroundPath()
    return Chrome.CLASSIC_BG
end

--- CallBoard-style inner shadow on an InsetFrame (client COMMON overlays).
function Chrome.ApplyInsetShadows(inset)
    if type(inset) ~= "table" or type(inset.CreateTexture) ~= "function" then
        return
    end
    if inset._alfmShadows then
        return
    end
    inset._alfmShadows = true
    local function edge(path, pointA, relA, pointB, relB)
        local tex = inset:CreateTexture(nil, "OVERLAY")
        if not tex then return end
        tex:SetTexture(path)
        if tex.SetAlpha then tex:SetAlpha(0.45) end
        if tex.SetPoint then
            tex:SetPoint(pointA, inset, relA or pointA, 0, 0)
            if pointB then
                tex:SetPoint(pointB, inset, relB or pointB, 0, 0)
            end
        end
        if path == Chrome.SHADOW_TOP or path == Chrome.SHADOW_BOTTOM then
            if tex.SetHeight then tex:SetHeight(20) end
        else
            if tex.SetWidth then tex:SetWidth(16) end
        end
    end
    edge(Chrome.SHADOW_TOP, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT")
    edge(Chrome.SHADOW_BOTTOM, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT")
    edge(Chrome.SHADOW_LEFT, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT")
    edge(Chrome.SHADOW_RIGHT, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT")
end

--- Interface Options category row: highlight + GameFont, no gold box.
function Chrome.ApplyCategoryButton(button, selected)
    if type(button) ~= "table" then
        return
    end
    if type(button.CreateTexture) == "function" and type(button._alfmNavHi) ~= "table" then
        local hi = button:CreateTexture(nil, "BACKGROUND")
        hi:SetTexture(Chrome.NAV_HIGHLIGHT)
        if hi.SetBlendMode then
            pcall(function() hi:SetBlendMode("ADD") end)
        end
        if hi.SetPoint then
            hi:SetPoint("TOPLEFT", 2, 0)
            hi:SetPoint("BOTTOMRIGHT", -2, 0)
        end
        if hi.SetAlpha then hi:SetAlpha(0.75) end
        button._alfmNavHi = hi
    end
    local hi = button._alfmNavHi
    if type(hi) == "table" then
        if selected then
            if hi.Show then hi:Show() end
            if hi.SetAlpha then hi:SetAlpha(0.80) end
        elseif hi.Hide then
            hi:Hide()
        end
    end
    if button.SetBackdrop then
        button:SetBackdrop(nil)
    end
    local lbl = button._label
    if type(lbl) == "table" then
        if selected then
            if lbl.SetFontObject then
                pcall(function() lbl:SetFontObject("GameFontNormal") end)
            end
            if lbl.SetTextColor then
                local c = Chrome.FONT_NORMAL
                lbl:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        else
            if lbl.SetFontObject then
                pcall(function() lbl:SetFontObject("GameFontHighlightSmall") end)
            end
            if lbl.SetTextColor then
                local c = Chrome.FONT_HIGHLIGHT
                lbl:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
end

--- Apply DialogBox chrome. opts.header / opts.closeButton optional.
function Chrome.ApplyClassicChrome(frame, opts)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then
        return nil, nil
    end
    opts = type(opts) == "table" and opts or {}
    frame:SetBackdrop({
        bgFile = Chrome.CLASSIC_BG,
        edgeFile = Chrome.CLASSIC_EDGE,
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 1) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 1, 1, 1) end

    -- Optional DialogBox header banner (RaidInfo / AscFastRoll family).
    -- Off by default — MiniHUD and other compact frames must not grow a
    -- 64px banner. MainWindow passes header=true explicitly.
    if opts.header == true and type(frame.CreateTexture) == "function" and not frame._alfmDialogHeader then
        local header = frame:CreateTexture(nil, "ARTWORK")
        header:SetTexture(Chrome.CLASSIC_HEADER)
        header:SetWidth(opts.headerWidth or 360)
        header:SetHeight(opts.headerHeight or 64)
        header:SetPoint("TOP", 0, opts.headerY or 12)
        frame._alfmDialogHeader = header
        if opts.corner ~= false then
            local corner = frame:CreateTexture(nil, "OVERLAY")
            corner:SetTexture(Chrome.CLASSIC_CORNER)
            corner:SetWidth(32)
            corner:SetHeight(32)
            corner:SetPoint("TOPRIGHT", -6, -7)
            frame._alfmDialogCorner = corner
        end
    end

    if opts.closeButton == true and not frame._alfmPanelClose then
        Chrome.CreatePanelCloseButton(frame, opts.onClose)
    end

    frame._alfmChromePieces = frame._alfmChromePieces or {}
    return frame._alfmChromePieces, frame._alfmChromeBg
end

--- Alias kept for older call sites; always native DialogBox (never DragonUI).
function Chrome.ApplyMetalChrome(frame, profileNameOrOpts)
    local opts = {}
    if type(profileNameOrOpts) == "table" then
        opts = profileNameOrOpts
    elseif profileNameOrOpts == "full" then
        opts = { header = false, closeButton = false }
    else
        -- compact / MiniHUD: backdrop only, no banner
        opts = { header = false, closeButton = false }
    end
    return Chrome.ApplyClassicChrome(frame, opts)
end

--- Proven content well: InsetFrameTemplate + marble when the engine has it,
--  else MacroFrame-style tooltip backdrop. Never PortraitFrame.
--  Parent EditBoxes / ScrollFrames to the returned frame (or a child of it),
--  never to a chrome host.
function Chrome.CreateInset(parent, name)
    if type(parent) ~= "table" or type(CreateFrame) ~= "function" then
        return nil
    end
    local inset
    local ok = pcall(function()
        inset = CreateFrame("Frame", name, parent, "InsetFrameTemplate")
    end)
    if ok and type(inset) == "table" then
        local bg = inset.Bg
        if type(bg) == "table" and type(bg.SetTexture) == "function" then
            pcall(function()
                bg:SetTexture(Chrome.MARBLE_BG, true, true)
                if type(bg.SetHorizTile) == "function" then
                    bg:SetHorizTile(true)
                    bg:SetVertTile(true)
                end
            end)
            inset._alfmInsetKind = "InsetFrameTemplate"
            Chrome.ApplyInsetShadows(inset)
            return inset
        end
        -- Template name accepted but no Bg region (sandbox / stub) — fall through.
    end

    inset = CreateFrame("Frame", name, parent)
    if inset.SetBackdrop then
        inset:SetBackdrop(Chrome.INSET_FALLBACK)
        local cr, cg, cb, ca = 0.09, 0.09, 0.11, 0.92
        local br, bgc, bb = 0.5, 0.5, 0.5
        if TOOLTIP_DEFAULT_BACKGROUND_COLOR then
            cr = TOOLTIP_DEFAULT_BACKGROUND_COLOR.r or cr
            cg = TOOLTIP_DEFAULT_BACKGROUND_COLOR.g or cg
            cb = TOOLTIP_DEFAULT_BACKGROUND_COLOR.b or cb
        end
        if TOOLTIP_DEFAULT_COLOR then
            br = TOOLTIP_DEFAULT_COLOR.r or br
            bgc = TOOLTIP_DEFAULT_COLOR.g or bgc
            bb = TOOLTIP_DEFAULT_COLOR.b or bb
        end
        if inset.SetBackdropColor then inset:SetBackdropColor(cr, cg, cb, ca) end
        if inset.SetBackdropBorderColor then inset:SetBackdropBorderColor(br, bgc, bb, 1) end
    end
    inset._alfmInsetKind = "tooltip-fallback"
    Chrome.ApplyInsetShadows(inset)
    return inset
end

--- Standard engine close control (UIPanelCloseButton).
function Chrome.CreatePanelCloseButton(parent, onClick)
    if type(parent) ~= "table" or type(CreateFrame) ~= "function" then
        return nil
    end
    local btn
    local ok = pcall(function()
        btn = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    end)
    if not ok or type(btn) ~= "table" then
        btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        if btn.SetSize then btn:SetSize(24, 24) end
        if btn.SetText then btn:SetText("X") end
        Chrome.SkinActionButton(btn)
    end
    if btn.SetPoint then
        btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    end
    if btn.SetScript then
        btn:SetScript("OnClick", function()
            if type(onClick) == "function" then
                onClick()
            elseif parent.Hide then
                parent:Hide()
            end
        end)
    end
    parent._alfmPanelClose = btn
    return btn
end

--- Stock UIPanelButton — AscensionUI / Interface Options do not gold-wash
-- the atlas. Hook kept so call sites stay stable; height is set at create.
function Chrome.SkinActionButton(button)
    return button
end

--- Floating popup / picker: tooltip inset (Interface Options menus), not
-- DialogBox gold or WHITE8X8 hairlines.
function Chrome.ApplyTooltipPopup(frame)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then
        return
    end
    if frame._alfmTooltipPopup then
        return
    end
    frame._alfmTooltipPopup = true
    frame:SetBackdrop(Chrome.INSET_FALLBACK)
    local cr, cg, cb, ca = 0.09, 0.09, 0.11, 0.92
    local br, bgc, bb = 0.5, 0.5, 0.5
    if TOOLTIP_DEFAULT_BACKGROUND_COLOR then
        cr = TOOLTIP_DEFAULT_BACKGROUND_COLOR.r or cr
        cg = TOOLTIP_DEFAULT_BACKGROUND_COLOR.g or cg
        cb = TOOLTIP_DEFAULT_BACKGROUND_COLOR.b or cb
    end
    if TOOLTIP_DEFAULT_COLOR then
        br = TOOLTIP_DEFAULT_COLOR.r or br
        bgc = TOOLTIP_DEFAULT_COLOR.g or bgc
        bb = TOOLTIP_DEFAULT_COLOR.b or bb
    end
    if frame.SetBackdropColor then frame:SetBackdropColor(cr, cg, cb, ca) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(br, bgc, bb, 1) end
end

--- Title + subtitle on the DialogBox header banner (RaidInfo / CallBoard).
function Chrome.AnchorDialogTitle(frame, titleFs, subFs)
    if type(frame) ~= "table" or type(titleFs) ~= "table" then
        return false
    end
    local header = frame._alfmDialogHeader
    if type(header) ~= "table" or type(titleFs.SetPoint) ~= "function" then
        return false
    end
    titleFs:ClearAllPoints()
    titleFs:SetPoint("TOP", header, "TOP", 0, -14)
    if type(subFs) == "table" and subFs.SetPoint then
        subFs:ClearAllPoints()
        subFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -2)
    end
    return true
end

-- ---- Debug tools ----
local function chat(msg)
    if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAscensionLFM|r " .. tostring(msg))
    elseif type(print) == "function" then
        print("AscensionLFM " .. tostring(msg))
    end
end

local function shortPath(path)
    if type(path) ~= "string" then return tostring(path) end
    return path:match("([^\\/]+)$") or path
end

local function dumpTexture(label, tex)
    if not tex then chat(label .. ": <nil>"); return end
    local path = tex.GetTexture and tex:GetTexture()
    local w = tex.GetWidth and tex:GetWidth() or 0
    local h = tex.GetHeight and tex:GetHeight() or 0
    local shown = tex.IsShown and tex:IsShown()
    chat(string.format("%s shown=%s size=%.1fx%.1f tex=%s",
        label, tostring(shown), w, h, shortPath(path)))
end

function Chrome.DumpFrameChrome(frame, title)
    title = title or "frame"
    if type(frame) ~= "table" then chat(title .. ": no frame"); return end
    chat(string.format("=== %s  size=%.0fx%.0f level=%s native=DialogBox ===",
        title, frame:GetWidth() or 0, frame:GetHeight() or 0,
        tostring(frame.GetFrameLevel and frame:GetFrameLevel())))
    dumpTexture("bg", frame._alfmChromeBg)
    local pieces = frame._alfmChromePieces
    if type(pieces) ~= "table" or #pieces == 0 then
        chat("no chrome border pieces (DialogBox backdrop only)")
        return
    end
    for i, tex in ipairs(pieces) do
        dumpTexture("#" .. i, tex)
    end
end

SLASH_ALFMCHROME1 = "/alfmchrome"

if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMCHROME"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "hud" or msg == "minihud" then
            local hud = AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.GetFrame and AscensionLFM.MiniHUD.GetFrame()
            Chrome.DumpFrameChrome(hud, "MiniHUD")
        else
            local f = _G.AscensionLFMFrame
            if type(f) ~= "table" then chat("open main UI first: /alfm"); return end
            Chrome.DumpFrameChrome(f, "MainWindow")
        end
    end
end

return Chrome
