-- AscensionLFM: ui/Chrome.lua
-- Shared DragonUI metal nineslice + rock background.
-- Technique matches DragonUI modules/chrome_shared.lua RealChrome.Apply
-- and bags_skin.lua EnsureChrome/LayoutChrome:
--   * 4 fixed-size corner slices from uiframemetal2x
--   * 4 edge slices stretched BETWEEN corners (SetPoint both ends)
--   * rock BACKGROUND inset under the border
--   * textures tagged _duiOwned so region-sweeps skip them
-- No Lua dependency on DragonUI — only needs its texture files on disk.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

local Chrome = {}
AscensionLFM.Chrome = Chrome

Chrome.DUI_METAL   = "Interface\\AddOns\\DragonUI\\Textures\\UI\\uiframemetal2x"
Chrome.DUI_METAL_H = "Interface\\AddOns\\DragonUI\\Textures\\UI\\uiframemetalhorizontal2x"
Chrome.DUI_METAL_V = "Interface\\AddOns\\DragonUI\\Textures\\UI\\uiframemetalvertical2x"
Chrome.DUI_BG      = "Interface\\AddOns\\DragonUI\\Textures\\UI\\ui-background-rock"
Chrome.DUI_CLOSE   = "Interface\\AddOns\\DragonUI\\Textures\\UI\\redbutton2x"

-- Classic Blizzard fallback (100% built-in, no addon dependency). Used
-- whenever DragonUI is not installed/enabled, so the window never ends
-- up with only the thin gold SetBackdrop edge and nothing else.
Chrome.CLASSIC_BG   = "Interface\\DialogFrame\\UI-DialogBox-Background"
Chrome.CLASSIC_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"

--- Detects whether DragonUI is actually present this session. Cached
-- after the first real check (result can't change mid-session — an
-- addon's load state is fixed at login), pcall-wrapped since
-- IsAddOnLoaded's availability/signature is not guaranteed on every
-- client build.
local hasDragonUICache = nil
function Chrome.HasDragonUI()
    if hasDragonUICache ~= nil then
        return hasDragonUICache
    end
    local result = false
    if type(IsAddOnLoaded) == "function" then
        local ok, loaded = pcall(IsAddOnLoaded, "DragonUI")
        if ok and loaded then
            result = true
        end
    end
    hasDragonUICache = result
    return result
end

--- Single source of truth for "which rock/background texture to use".
-- Every UI file should call this instead of hardcoding the DragonUI
-- path with an `or` fallback (which still pointed at DragonUI even
-- when it wasn't installed).
function Chrome.BackgroundPath()
    if Chrome.HasDragonUI() then
        return Chrome.DUI_BG
    end
    return Chrome.CLASSIC_BG
end

Chrome.KNOWN_PIECES = {
    [Chrome.DUI_METAL] = {
        { "topLeft", 0.00195312, 0.294922, 0.00195312, 0.294922 },
        { "topRight", 0.298828, 0.591797, 0.00195312, 0.294922 },
        { "bottomLeft", 0.298828, 0.423828, 0.298828, 0.423828 },
        { "bottomRight", 0.427734, 0.552734, 0.298828, 0.423828 },
    },
    [Chrome.DUI_METAL_H] = {
        { "top edge", 0, 1, 0.00390625, 0.589844 },
        { "bottom edge", 0, 0.5, 0.597656, 0.847656 },
    },
    [Chrome.DUI_METAL_V] = {
        { "left edge", 0.00195312, 0.294922, 0, 1 },
        { "right edge", 0.298828, 0.591797, 0, 1 },
    },
}

-- compact = MiniHUD; full = MainWindow (bag/bank-sized corners)
Chrome.PROFILES = {
    compact = {
        topSize = 30, topHeight = 30, bottomSize = 16,
        topY = 7, bottomY = -1,
        leftOffset = -6, rightOffset = 2,
        bgInsets = nil,
    },
    full = {
        -- Inset nineslice (pieces inside the frame). Bag-style negative
        -- offsets were clipped on UIPanelDialogTemplate frames, so the
        -- metal border looked completely missing on screenshots.
        topSize = 56, topHeight = 56, bottomSize = 28,
        topY = 2, bottomY = 2,
        leftOffset = 2, rightOffset = -2,
        bgInsets = { left = 8, top = -12, right = -8, bottom = 8 },
    },
}

function Chrome.ConfigureTexture(texture, path, width, height, left, right, top, bottom, lockAxis)
    texture:SetTexture(path)
    lockAxis = lockAxis or "both"
    -- "both": fixed-size corner piece, no stretch anchors expected.
    -- "height": horizontal edge - only pin height, width comes from the
    --   two opposing LEFT/RIGHT point anchors (SetSize here would lock
    --   width too and defeat that stretch - this was the actual bug:
    --   top/bottom edges stayed at their tiny initial width instead of
    --   spanning the gap between corners, leaving the gold SetBackdrop
    --   line exposed underneath).
    -- "width": vertical edge - only pin width, height stretches from the
    --   two opposing TOP/BOTTOM point anchors, same reasoning.
    if lockAxis == "both" and width and height and texture.SetSize then
        texture:SetSize(width, height)
    elseif lockAxis == "height" and height and texture.SetHeight then
        texture:SetHeight(height)
    elseif lockAxis == "width" and width and texture.SetWidth then
        texture:SetWidth(width)
    end
    if texture.SetTexCoord then
        texture:SetTexCoord(left, right, top, bottom)
    end
    if texture.SetDrawLayer then
        texture:SetDrawLayer("OVERLAY", 7)
    end
end

function Chrome.IdentifyPiece(tex, left, right, top, bottom)
    local candidates = tex and Chrome.KNOWN_PIECES[tex]
    if not candidates or not left then
        return nil
    end
    local EPS = 0.001
    for _, piece in ipairs(candidates) do
        if math.abs(left - piece[2]) < EPS and math.abs(right - piece[3]) < EPS
            and math.abs(top - piece[4]) < EPS and math.abs(bottom - piece[5]) < EPS then
            return piece[1]
        end
    end
    return nil
end

--- Apply DragonUI metal nineslice + rock background to `frame`.
-- `profileNameOrOpts`: "compact" | "full" | opts table (same keys as PROFILES).
-- Chrome textures live on a child host frame with elevated FrameLevel so
-- the metal border always draws ABOVE content panels (parent OVERLAY
-- textures were being covered by child frames on 0.4.9x screenshots).
--- Classic Blizzard-only chrome: native dialog background + native
-- dialog border via SetBackdrop, no DragonUI textures referenced at
-- all. This is what renders when Chrome.HasDragonUI() is false, so a
-- player without DragonUI installed gets a complete, correct-looking
-- window instead of the thin gold outline that was the only fallback
-- before.
function Chrome.ApplyClassicChrome(frame)
    if type(frame) ~= "table" or type(frame.SetBackdrop) ~= "function" then
        return nil, nil
    end
    frame:SetBackdrop({
        bgFile = Chrome.CLASSIC_BG,
        edgeFile = Chrome.CLASSIC_EDGE,
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    if frame.SetBackdropColor then
        frame:SetBackdropColor(1, 1, 1, 1)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    end
    frame._alfmChromePieces = nil
    frame._alfmChromeBg = nil
    frame._alfmChromeClassic = true
    return nil, nil
end

function Chrome.ApplyMetalChrome(frame, profileNameOrOpts)
    if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then
        return nil, nil
    end

    if not Chrome.HasDragonUI() then
        return Chrome.ApplyClassicChrome(frame)
    end

    local opts
    if type(profileNameOrOpts) == "string" then
        opts = Chrome.PROFILES[profileNameOrOpts] or Chrome.PROFILES.full
    elseif type(profileNameOrOpts) == "table" then
        opts = profileNameOrOpts
    else
        opts = Chrome.PROFILES.full
    end

    local topSize = opts.topSize or 75
    local topHeight = opts.topHeight or topSize
    local bottomSize = opts.bottomSize or 32
    local leftOffset = opts.leftOffset or -8
    local rightOffset = opts.rightOffset or 4
    local topY = opts.topY or 16
    local bottomY = opts.bottomY or -3
    local bgInsets = opts.bgInsets

    local DUI_METAL = Chrome.DUI_METAL
    local DUI_METAL_H = Chrome.DUI_METAL_H
    local DUI_METAL_V = Chrome.DUI_METAL_V
    local DUI_BG = Chrome.DUI_BG

    -- Rock background stays on the target frame (under content).
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(DUI_BG)
    bg:SetAlpha(0.97)
    bg._duiOwned = true
    if bgInsets and type(bgInsets) == "table" then
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgInsets.left or 2, bgInsets.top or -20)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bgInsets.right or -2, bgInsets.bottom or 3)
    else
        bg:SetAllPoints(frame)
    end

    -- Always-visible thin gold edge (works even if .blp metal fails to load).
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        if frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(0.85, 0.70, 0.25, 0.95)
        end
        if frame.SetBackdropColor then
            frame:SetBackdropColor(0, 0, 0, 0)
        end
    end

    -- Dedicated chrome host: elevated level so metal is never buried.
    local host = frame
    if type(CreateFrame) == "function" then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        if host.SetFrameLevel and frame.GetFrameLevel then
            host:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
        end
        host:EnableMouse(false)
        frame._alfmChromeHost = host
    end

    local function piece(layer)
        local t = host:CreateTexture(nil, layer or "OVERLAY")
        t._duiOwned = true
        if t.SetDrawLayer then
            t:SetDrawLayer("OVERLAY", 7)
        end
        if t.Show then
            t:Show()
        end
        return t
    end

    local cTopLeft = piece()
    Chrome.ConfigureTexture(cTopLeft, DUI_METAL, topSize, topHeight, 0.00195312, 0.294922, 0.00195312, 0.294922)
    cTopLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", leftOffset, topY)

    local cTopRight = piece()
    Chrome.ConfigureTexture(cTopRight, DUI_METAL, topSize, topHeight, 0.298828, 0.591797, 0.00195312, 0.294922)
    cTopRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", rightOffset, topY)

    local cBottomLeft = piece()
    Chrome.ConfigureTexture(cBottomLeft, DUI_METAL, bottomSize, bottomSize, 0.298828, 0.423828, 0.298828, 0.423828)
    cBottomLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", leftOffset, bottomY)

    local cBottomRight = piece()
    Chrome.ConfigureTexture(cBottomRight, DUI_METAL, bottomSize, bottomSize, 0.427734, 0.552734, 0.298828, 0.423828)
    cBottomRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rightOffset, bottomY)

    -- Edges stretch between corners. The two-anchor "auto stretch" that
    -- normally works for Frames turned out NOT to reliably resize plain
    -- Texture regions on this client - confirmed via /alfmchrome: a
    -- texture anchored on both ends still reported the engine's default
    -- 32px on the un-set axis instead of the actual anchor-implied span.
    -- So the size is computed explicitly here and hard-set, with the
    -- point anchors kept only for correct positioning.
    local frameW = frame.GetWidth and frame:GetWidth() or 0
    local frameH = frame.GetHeight and frame:GetHeight() or 0
    local topEdgeW = math.max(0, (frameW + rightOffset - topSize) - (leftOffset + topSize))
    local bottomEdgeW = math.max(0, (frameW + rightOffset - bottomSize) - (leftOffset + bottomSize))
    local vertEdgeH = math.max(0, (frameH - bottomY - bottomSize) - (topHeight - topY))

    local cTop = piece()
    Chrome.ConfigureTexture(cTop, DUI_METAL_H, 32, topHeight, 0, 1, 0.00390625, 0.589844, "height")
    cTop:SetPoint("TOPLEFT", cTopLeft, "TOPRIGHT")
    cTop:SetPoint("TOPRIGHT", cTopRight, "TOPLEFT")
    cTop:SetWidth(topEdgeW)

    local cBottom = piece()
    Chrome.ConfigureTexture(cBottom, DUI_METAL_H, 16, bottomSize, 0, 0.5, 0.597656, 0.847656, "height")
    cBottom:SetPoint("TOPLEFT", cBottomLeft, "TOPRIGHT")
    cBottom:SetPoint("TOPRIGHT", cBottomRight, "TOPLEFT")
    cBottom:SetWidth(bottomEdgeW)

    local cLeft = piece()
    Chrome.ConfigureTexture(cLeft, DUI_METAL_V, topSize, 16, 0.00195312, 0.294922, 0, 1, "width")
    cLeft:SetPoint("TOPLEFT", cTopLeft, "BOTTOMLEFT")
    cLeft:SetPoint("BOTTOMLEFT", cBottomLeft, "TOPLEFT")
    cLeft:SetHeight(vertEdgeH)

    local cRight = piece()
    Chrome.ConfigureTexture(cRight, DUI_METAL_V, topSize, 16, 0.298828, 0.591797, 0, 1, "width")
    cRight:SetPoint("TOPRIGHT", cTopRight, "BOTTOMRIGHT")
    cRight:SetPoint("BOTTOMRIGHT", cBottomRight, "TOPRIGHT")
    cRight:SetHeight(vertEdgeH)

    local borderPieces = {
        cTopLeft, cTopRight, cBottomLeft, cBottomRight,
        cTop, cBottom, cLeft, cRight,
    }
    frame._alfmChromePieces = borderPieces
    frame._alfmChromeBg = bg
    return borderPieces, bg
end

--- Reskins a UIPanelButtonTemplate-based button to match the addon's
-- gold/dark chrome theme, used consistently for cards and pickers. Uses a
-- SetBackdrop treatment (no external texture file) rather than pointing at
-- a guessed DragonUI button atlas path - unlike DUI_CLOSE (a verified
-- round-close-button texture DragonUI ships), there's no confirmed generic
-- rectangular action-button texture in this codebase, and guessing one
-- would repeat the exact "path to a file that may not exist" mistake this
-- addon already had to fix once for the window chrome.
-- If a real DragonUI button atlas path becomes known, this is the single
-- place to switch it in - every caller just calls Chrome.SkinActionButton.
function Chrome.SkinActionButton(button)
    if type(button) ~= "table" or type(button.SetBackdrop) ~= "function" then
        return
    end
    -- Hide the native grey button textures so the backdrop is all that shows.
    if button.SetNormalTexture then button:SetNormalTexture("") end
    if button.SetPushedTexture then button:SetPushedTexture("") end
    if button.SetDisabledTexture then button:SetDisabledTexture("") end
    if button.GetHighlightTexture and button:GetHighlightTexture() then
        local hi = button:GetHighlightTexture()
        hi:SetTexture("Interface\\Buttons\\WHITE8X8")
        hi:SetVertexColor(1, 1, 1, 0.12)
    end

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    button:SetBackdropColor(0.08, 0.07, 0.05, 0.92)
    button:SetBackdropBorderColor(0.85, 0.68, 0.22, 0.55)

    local fontString = button.GetFontString and button:GetFontString()
    if fontString then
        fontString:SetTextColor(0.92, 0.84, 0.58)
    end

    button:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.95, 0.80, 0.35, 0.95)
    end)
    button:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.85, 0.68, 0.22, 0.55)
    end)
    button:HookScript("OnMouseDown", function(self)
        self:SetBackdropColor(0.04, 0.035, 0.025, 0.95)
    end)
    button:HookScript("OnMouseUp", function(self)
        self:SetBackdropColor(0.08, 0.07, 0.05, 0.92)
    end)
    button._alfmSkinned = true
end

function Chrome.SkinCloseButton(button)
    if not button then
        return
    end
    if not Chrome.HasDragonUI() then
        -- No DragonUI textures to point at - leave the button's default
        -- (native Blizzard or caller-provided) look untouched.
        return
    end
    local path = Chrome.DUI_CLOSE
    local function set(tex, l, r, t, b)
        if not tex then return end
        tex:SetTexture(path)
        tex:SetTexCoord(l, r, t, b)
    end
    if button.GetNormalTexture then
        set(button:GetNormalTexture(), 0.152344, 0.292969, 0.0078125, 0.304688)
    end
    if button.GetDisabledTexture then
        set(button:GetDisabledTexture(), 0.152344, 0.292969, 0.320312, 0.617188)
    end
    if button.GetPushedTexture then
        set(button:GetPushedTexture(), 0.152344, 0.292969, 0.632812, 0.929688)
    end
    if button.GetHighlightTexture then
        set(button:GetHighlightTexture(), 0.449219, 0.589844, 0.0078125, 0.304688)
    end
end

-- ============================================================================
-- Debug / measurement tools (pixel-perfect nineslice tuning)
-- /alfmchrome [main|hud]  - dump chrome pieces on MainWindow or MiniHUD
-- /alfmchromeref          - dump metal/rock textures on ContainerFrame1 (DragonUI bag)
-- /alfmchromeside         - place bag left + main window right for visual compare
-- ============================================================================

local function chat(msg)
    if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffAscensionLFM|r " .. tostring(msg))
    elseif type(print) == "function" then
        print("AscensionLFM " .. tostring(msg))
    end
end

local function shortPath(path)
    if type(path) ~= "string" then
        return tostring(path)
    end
    return path:match("([^\\/]+)$") or path
end

local function dumpTexture(label, tex)
    if not tex then
        chat(label .. ": <nil>")
        return
    end
    local path = tex.GetTexture and tex:GetTexture()
    local w = tex.GetWidth and tex:GetWidth() or 0
    local h = tex.GetHeight and tex:GetHeight() or 0
    local shown = tex.IsShown and tex:IsShown()
    local l, r, top, b = 0, 0, 0, 0
    if tex.GetTexCoord then
        l, r, top, b = tex:GetTexCoord()
    end
    local p1, _, _, x1, y1 = nil, nil, nil, 0, 0
    if tex.GetPoint then
        p1, _, _, x1, y1 = tex:GetPoint(1)
    end
    local p2, _, _, x2, y2 = nil, nil, nil, 0, 0
    if tex.GetNumPoints and tex:GetNumPoints() >= 2 then
        p2, _, _, x2, y2 = tex:GetPoint(2)
    end
    chat(string.format(
        "%s shown=%s size=%.1fx%.1f tex=%s",
        label, tostring(shown), w, h, shortPath(path)))
    chat(string.format(
        "  coords=%.5f,%.5f,%.5f,%.5f",
        l or 0, r or 0, top or 0, b or 0))
    chat(string.format(
        "  point1=%s (%.2f, %.2f)%s",
        tostring(p1), x1 or 0, y1 or 0,
        p2 and string.format("  point2=%s (%.2f, %.2f)", tostring(p2), x2 or 0, y2 or 0) or ""))
end

function Chrome.DumpFrameChrome(frame, title)
    title = title or "frame"
    if type(frame) ~= "table" then
        chat(title .. ": no frame")
        return
    end
    local fw = frame.GetWidth and frame:GetWidth() or 0
    local fh = frame.GetHeight and frame:GetHeight() or 0
    local fl = frame.GetFrameLevel and frame:GetFrameLevel() or -1
    chat(string.format("=== %s  size=%.0fx%.0f level=%s ===", title, fw, fh, tostring(fl)))
    if frame._alfmChromeHost and frame._alfmChromeHost.GetFrameLevel then
        chat("chromeHost level=" .. tostring(frame._alfmChromeHost:GetFrameLevel()))
    end
    dumpTexture("bg", frame._alfmChromeBg)
    local pieces = frame._alfmChromePieces
    if type(pieces) ~= "table" or #pieces == 0 then
        chat("no _alfmChromePieces (ApplyMetalChrome not run or failed)")
        return
    end
    local names = { "TL", "TR", "BL", "BR", "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for i, tex in ipairs(pieces) do
        dumpTexture(names[i] or ("#" .. i), tex)
    end
    -- Profile hint for copy-paste tuning
    if pieces[1] and pieces[1].GetWidth then
        chat(string.format(
            "hint profile: topSize~%.0f bottomSize~%.0f",
            pieces[1]:GetWidth() or 0,
            (pieces[3] and pieces[3].GetWidth and pieces[3]:GetWidth()) or 0))
    end
end

function Chrome.DumpBagReference()
    local f = _G.ContainerFrame1
    if type(f) ~= "table" then
        chat("ContainerFrame1 missing - open a bag first")
        return
    end
    chat(string.format("=== ContainerFrame1 (DragonUI bag ref) size=%.0fx%.0f ===",
        f:GetWidth() or 0, f:GetHeight() or 0))
    local n = 0
    if f.GetRegions then
        for _, region in ipairs({ f:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                local path = region.GetTexture and region:GetTexture()
                if type(path) == "string" and (
                    path:find("uiframe", 1, true) or
                    path:find("ui%-background", 1, true) or
                    path:find("redbutton", 1, true)
                ) then
                    n = n + 1
                    dumpTexture("bag#" .. n, region)
                end
            end
        end
    end
    if n == 0 then
        chat("no DragonUI metal/rock textures on ContainerFrame1 - is DragonUI bags skin active?")
    else
        chat("bag chrome regions: " .. n)
    end
end

function Chrome.SideBySide()
    local bag = _G.ContainerFrame1
    local main = _G.AscensionLFMFrame
    if type(bag) ~= "table" then
        chat("open a bag first (ContainerFrame1)")
        return
    end
    if type(main) ~= "table" then
        chat("open main UI first (/alfm)")
        return
    end
    if bag.ClearAllPoints then bag:ClearAllPoints() end
    if bag.SetPoint then bag:SetPoint("RIGHT", UIParent, "CENTER", -20, 0) end
    if bag.Show then bag:Show() end
    if main.ClearAllPoints then main:ClearAllPoints() end
    if main.SetPoint then main:SetPoint("LEFT", UIParent, "CENTER", 20, 0) end
    if main.Show then main:Show() end
    chat("side-by-side: bag LEFT of center, AscensionLFM RIGHT of center")
end

function Chrome.PrintProfile(name)
    name = name or "full"
    local opts = Chrome.PROFILES[name]
    if not opts then
        chat("unknown profile: " .. tostring(name))
        return
    end
    chat("profile '" .. name .. "':")
    chat(string.format(
        "  topSize=%s topHeight=%s bottomSize=%s",
        tostring(opts.topSize), tostring(opts.topHeight), tostring(opts.bottomSize)))
    chat(string.format(
        "  topY=%s bottomY=%s leftOffset=%s rightOffset=%s",
        tostring(opts.topY), tostring(opts.bottomY),
        tostring(opts.leftOffset), tostring(opts.rightOffset)))
end

-- Slash commands
SLASH_ALFMCHROME1 = "/alfmchrome"
SLASH_ALFMCHROMEREF1 = "/alfmchromeref"
SLASH_ALFMCHROMESIDE1 = "/alfmchromeside"
SLASH_ALFMCHROMEPROFILE1 = "/alfmchromeprofile"

if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMCHROME"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "hud" or msg == "minihud" then
            local hud
            if AscensionLFM and AscensionLFM.MiniHUD and type(AscensionLFM.MiniHUD.GetFrame) == "function" then
                hud = AscensionLFM.MiniHUD.GetFrame()
            end
            if type(hud) ~= "table" then
                hud = _G.AscensionLFMMiniHUD
            end
            if type(hud) ~= "table" then
                chat("MiniHUD not built yet - enable it or /reload")
                return
            end
            Chrome.DumpFrameChrome(hud, "MiniHUD")
            Chrome.PrintProfile("compact")
        else
            local f = _G.AscensionLFMFrame
            if type(f) ~= "table" and AscensionLFM and AscensionLFM.MainWindow
                and type(AscensionLFM.MainWindow.GetFrame) == "function" then
                f = AscensionLFM.MainWindow.GetFrame()
            end
            if type(f) ~= "table" then
                chat("open main UI first: /alfm")
                return
            end
            Chrome.DumpFrameChrome(f, "MainWindow")
            Chrome.PrintProfile("full")
        end
    end

    SlashCmdList["ALFMCHROMEREF"] = function()
        Chrome.DumpBagReference()
    end

    SlashCmdList["ALFMCHROMESIDE"] = function()
        Chrome.SideBySide()
    end

    SlashCmdList["ALFMCHROMEPROFILE"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "" then
            Chrome.PrintProfile("full")
            Chrome.PrintProfile("compact")
        else
            Chrome.PrintProfile(msg)
        end
    end
end


return Chrome
