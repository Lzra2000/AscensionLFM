-- AscensionLFM: ui/Chrome.lua
-- Shared DragonUI metal nineslice + rock background.
-- ONLY DragonUI textures when DragonUI is loaded. No WHITE8X8 gold edges.
-- Technique matches DragonUI bags_skin LayoutChrome / RealChrome.Apply.

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

Chrome.CLASSIC_BG   = "Interface\\DialogFrame\\UI-DialogBox-Background"
Chrome.CLASSIC_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"

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

-- bag-style defaults (visible metal). Appearance tab can override via db.uiChrome.
Chrome.PROFILES = {
    compact = {
        topSize = 30, topHeight = 30, bottomSize = 16,
        topY = 7, bottomY = -1,
        leftOffset = -6, rightOffset = 2,
        bgInsets = nil,
    },
    full = {
        -- Match DragonUI bag/bank chrome so metal is clearly visible.
        topSize = 75, topHeight = 75, bottomSize = 32,
        topY = 16, bottomY = -3,
        leftOffset = -8, rightOffset = 4,
        bgInsets = { left = 4, top = -24, right = -4, bottom = 4 },
    },
}

function Chrome.GetUiChromeDB()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if type(db) ~= "table" then
        return nil
    end
    if type(db.uiChrome) ~= "table" then
        db.uiChrome = {}
    end
    return db.uiChrome
end

--- Merge profile with optional db.uiChrome overrides (Appearance tab).
function Chrome.ResolveOpts(profileNameOrOpts)
    local opts
    if type(profileNameOrOpts) == "string" then
        opts = Chrome.PROFILES[profileNameOrOpts] or Chrome.PROFILES.full
    elseif type(profileNameOrOpts) == "table" then
        opts = profileNameOrOpts
    else
        opts = Chrome.PROFILES.full
    end
    -- copy so we never mutate PROFILES
    local out = {}
    for k, v in pairs(opts) do
        out[k] = v
    end
    local ui = Chrome.GetUiChromeDB()
    if ui and (profileNameOrOpts == "full" or profileNameOrOpts == nil) then
        if ui.metalEnabled == false then
            out.metalEnabled = false
        else
            out.metalEnabled = true
        end
        if tonumber(ui.topSize) then out.topSize = tonumber(ui.topSize); out.topHeight = tonumber(ui.topSize) end
        if tonumber(ui.bottomSize) then out.bottomSize = tonumber(ui.bottomSize) end
        if tonumber(ui.topY) then out.topY = tonumber(ui.topY) end
        if tonumber(ui.bottomY) then out.bottomY = tonumber(ui.bottomY) end
        if tonumber(ui.leftOffset) then out.leftOffset = tonumber(ui.leftOffset) end
        if tonumber(ui.rightOffset) then out.rightOffset = tonumber(ui.rightOffset) end
    else
        out.metalEnabled = true
    end
    return out
end

function Chrome.ConfigureTexture(texture, path, width, height, left, right, top, bottom)
    texture:SetTexture(path)
    if width and height and texture.SetSize then
        texture:SetSize(width, height)
    end
    if texture.SetTexCoord then
        texture:SetTexCoord(left, right, top, bottom)
    end
    if texture.SetDrawLayer then
        texture:SetDrawLayer("OVERLAY", 7)
    end
    if texture.Show then
        texture:Show()
    end
end

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
    if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 1) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 1, 1, 1) end
    return nil, nil
end

function Chrome.ApplyMetalChrome(frame, profileNameOrOpts)
    if type(frame) ~= "table" or type(frame.CreateTexture) ~= "function" then
        return nil, nil
    end

    if not Chrome.HasDragonUI() then
        return Chrome.ApplyClassicChrome(frame)
    end

    local opts = Chrome.ResolveOpts(profileNameOrOpts)
    if opts.metalEnabled == false then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(Chrome.DUI_BG)
        bg:SetAllPoints(frame)
        bg:SetAlpha(0.97)
        bg._duiOwned = true
        frame._alfmChromeBg = bg
        frame._alfmChromePieces = {}
        return {}, bg
    end

    local topSize = opts.topSize or 75
    local topHeight = opts.topHeight or topSize
    local bottomSize = opts.bottomSize or 32
    local leftOffset = opts.leftOffset or -8
    local rightOffset = opts.rightOffset or 4
    local topY = opts.topY or 16
    local bottomY = opts.bottomY or -3
    local bgInsets = opts.bgInsets

    -- NO WHITE8X8 gold edge — pure DragonUI only.

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(Chrome.DUI_BG)
    bg:SetAlpha(0.97)
    bg._duiOwned = true
    if bgInsets and type(bgInsets) == "table" then
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgInsets.left or 4, bgInsets.top or -24)
        bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bgInsets.right or -4, bgInsets.bottom or 4)
    else
        bg:SetAllPoints(frame)
    end

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

    local function piece()
        local t = host:CreateTexture(nil, "OVERLAY")
        t._duiOwned = true
        if t.SetDrawLayer then t:SetDrawLayer("OVERLAY", 7) end
        if t.Show then t:Show() end
        return t
    end

    local DUI_METAL, DUI_METAL_H, DUI_METAL_V = Chrome.DUI_METAL, Chrome.DUI_METAL_H, Chrome.DUI_METAL_V

    -- Two-point SetPoint anchoring doesn't reliably auto-stretch Texture
    -- regions on this client (the unset axis silently falls back to the
    -- size ConfigureTexture set instead of the real anchor gap), so the
    -- mid-edge pieces below get their stretched axis hard-set from frame
    -- size + corner offsets, same as the corner pieces are already sized.
    local frameW = (frame.GetWidth and frame:GetWidth()) or 0
    local frameH = (frame.GetHeight and frame:GetHeight()) or 0
    local topEdgeW = math.max(0, frameW - (2 * topSize) + rightOffset - leftOffset)
    local bottomEdgeW = math.max(0, frameW - (2 * bottomSize) + rightOffset - leftOffset)
    local sideEdgeH = math.max(0, frameH - topHeight - bottomSize + topY - bottomY)

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

    local cTop = piece()
    Chrome.ConfigureTexture(cTop, DUI_METAL_H, 32, topHeight, 0, 1, 0.00390625, 0.589844)
    cTop:SetPoint("TOPLEFT", cTopLeft, "TOPRIGHT")
    cTop:SetPoint("TOPRIGHT", cTopRight, "TOPLEFT")
    if cTop.SetWidth then cTop:SetWidth(topEdgeW) end

    local cBottom = piece()
    Chrome.ConfigureTexture(cBottom, DUI_METAL_H, 16, bottomSize, 0, 0.5, 0.597656, 0.847656)
    cBottom:SetPoint("TOPLEFT", cBottomLeft, "TOPRIGHT")
    cBottom:SetPoint("TOPRIGHT", cBottomRight, "TOPLEFT")
    if cBottom.SetWidth then cBottom:SetWidth(bottomEdgeW) end

    local cLeft = piece()
    Chrome.ConfigureTexture(cLeft, DUI_METAL_V, topSize, 16, 0.00195312, 0.294922, 0, 1)
    cLeft:SetPoint("TOPLEFT", cTopLeft, "BOTTOMLEFT")
    cLeft:SetPoint("BOTTOMLEFT", cBottomLeft, "TOPLEFT")
    if cLeft.SetHeight then cLeft:SetHeight(sideEdgeH) end

    local cRight = piece()
    Chrome.ConfigureTexture(cRight, DUI_METAL_V, topSize, 16, 0.298828, 0.591797, 0, 1)
    cRight:SetPoint("TOPRIGHT", cTopRight, "BOTTOMRIGHT")
    cRight:SetPoint("BOTTOMRIGHT", cBottomRight, "TOPRIGHT")
    if cRight.SetHeight then cRight:SetHeight(sideEdgeH) end

    local borderPieces = {
        cTopLeft, cTopRight, cBottomLeft, cBottomRight,
        cTop, cBottom, cLeft, cRight,
    }
    frame._alfmChromePieces = borderPieces
    frame._alfmChromeBg = bg
    return borderPieces, bg
end

--- Identify which named chrome piece a texture+texcoord rect corresponds to
--  (matches against KNOWN_PIECES). Returns a name string, or nil if unknown.
function Chrome.IdentifyPiece(tex, left, right, top, bottom)
    if type(tex) ~= "string" then return nil end
    local pieces = Chrome.KNOWN_PIECES[tex]
    if not pieces or not left or not right or not top or not bottom then return nil end
    local EPS = 0.01
    for _, entry in ipairs(pieces) do
        local name, l, r, t, b = entry[1], entry[2], entry[3], entry[4], entry[5]
        if math.abs(left - l) < EPS and math.abs(right - r) < EPS
            and math.abs(top - t) < EPS and math.abs(bottom - b) < EPS then
            return name
        end
    end
    return nil
end

--- Reskin a standard UIPanelButtonTemplate button to match the gold/dark
--  chrome theme. DragonUI has no universal custom button atlas of its own
--  (confirmed against its own editor_mode.lua, which still uses
--  UIPanelButtonTemplate for some buttons - see CHANGELOG 0.4.79/0.4.90),
--  so this tints the existing Blizzard button art/text instead of swapping
--  in texture coordinates that don't exist.
function Chrome.SkinActionButton(button)
    if type(button) ~= "table" then return end
    if button.GetFontString and button:GetFontString() then
        button:GetFontString():SetTextColor(1.00, 0.82, 0.24)
    end
    local function tint(tex)
        if tex and tex.SetVertexColor then
            tex:SetVertexColor(0.85, 0.72, 0.45)
        end
    end
    if button.GetNormalTexture then tint(button:GetNormalTexture()) end
    if button.GetPushedTexture then tint(button:GetPushedTexture()) end
    if button.GetDisabledTexture then tint(button:GetDisabledTexture()) end
end

function Chrome.SkinCloseButton(button)
    if not button then return end
    local path = Chrome.DUI_CLOSE
    local function set(tex, l, r, t, b)
        if not tex then return end
        tex:SetTexture(path)
        tex:SetTexCoord(l, r, t, b)
    end
    if button.GetNormalTexture then set(button:GetNormalTexture(), 0.152344, 0.292969, 0.0078125, 0.304688) end
    if button.GetDisabledTexture then set(button:GetDisabledTexture(), 0.152344, 0.292969, 0.320312, 0.617188) end
    if button.GetPushedTexture then set(button:GetPushedTexture(), 0.152344, 0.292969, 0.632812, 0.929688) end
    if button.GetHighlightTexture then set(button:GetHighlightTexture(), 0.449219, 0.589844, 0.0078125, 0.304688) end
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
    local a,b,c,d = 0,0,0,0
    if tex.GetTexCoord then a,b,c,d = tex:GetTexCoord() end
    local p1,_,_,x1,y1 = nil,nil,nil,0,0
    if tex.GetPoint then p1,_,_,x1,y1 = tex:GetPoint(1) end
    chat(string.format("%s shown=%s size=%.1fx%.1f tex=%s", label, tostring(shown), w, h, shortPath(path)))
    chat(string.format("  coords=%.5f,%.5f,%.5f,%.5f", a or 0, b or 0, c or 0, d or 0))
    chat(string.format("  point1=%s (%.2f, %.2f)", tostring(p1), x1 or 0, y1 or 0))
end

function Chrome.DumpFrameChrome(frame, title)
    title = title or "frame"
    if type(frame) ~= "table" then chat(title .. ": no frame"); return end
    chat(string.format("=== %s  size=%.0fx%.0f level=%s HasDragonUI=%s ===",
        title, frame:GetWidth() or 0, frame:GetHeight() or 0,
        tostring(frame.GetFrameLevel and frame:GetFrameLevel()),
        tostring(Chrome.HasDragonUI())))
    if frame._alfmChromeHost and frame._alfmChromeHost.GetFrameLevel then
        chat("chromeHost level=" .. tostring(frame._alfmChromeHost:GetFrameLevel()))
    end
    dumpTexture("bg", frame._alfmChromeBg)
    local pieces = frame._alfmChromePieces
    if type(pieces) ~= "table" or #pieces == 0 then
        chat("no _alfmChromePieces")
        return
    end
    local names = { "TL", "TR", "BL", "BR", "TOP", "BOTTOM", "LEFT", "RIGHT" }
    for i, tex in ipairs(pieces) do
        dumpTexture(names[i] or ("#" .. i), tex)
    end
end

function Chrome.DumpBagReference()
    local f = _G.ContainerFrame1
    if type(f) ~= "table" then chat("open a bag first"); return end
    chat(string.format("=== ContainerFrame1 size=%.0fx%.0f ===", f:GetWidth() or 0, f:GetHeight() or 0))
    local n = 0
    if f.GetRegions then
        for _, region in ipairs({ f:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                local path = region.GetTexture and region:GetTexture()
                if type(path) == "string" and (path:find("uiframe", 1, true) or path:find("ui%-background", 1, true) or path:find("redbutton", 1, true)) then
                    n = n + 1
                    dumpTexture("bag#" .. n, region)
                end
            end
        end
    end
    chat("bag chrome regions: " .. n)
end

function Chrome.SideBySide()
    local bag = _G.ContainerFrame1
    local main = _G.AscensionLFMFrame
    if type(bag) ~= "table" then chat("open a bag first"); return end
    if type(main) ~= "table" then chat("open main UI first: /alfm"); return end
    if bag.ClearAllPoints then bag:ClearAllPoints() end
    if bag.SetPoint then bag:SetPoint("RIGHT", UIParent, "CENTER", -20, 0) end
    if bag.Show then bag:Show() end
    if main.ClearAllPoints then main:ClearAllPoints() end
    if main.SetPoint then main:SetPoint("LEFT", UIParent, "CENTER", 20, 0) end
    if main.Show then main:Show() end
    chat("side-by-side: bag | AscensionLFM")
end

function Chrome.PrintProfile(name)
    name = name or "full"
    local opts = Chrome.ResolveOpts(name)
    chat("profile '" .. name .. "' (with db overrides):")
    chat(string.format("  topSize=%s bottomSize=%s metal=%s",
        tostring(opts.topSize), tostring(opts.bottomSize), tostring(opts.metalEnabled ~= false)))
    chat(string.format("  topY=%s bottomY=%s leftOffset=%s rightOffset=%s",
        tostring(opts.topY), tostring(opts.bottomY), tostring(opts.leftOffset), tostring(opts.rightOffset)))
end

SLASH_ALFMCHROME1 = "/alfmchrome"
SLASH_ALFMCHROMEREF1 = "/alfmchromeref"
SLASH_ALFMCHROMESIDE1 = "/alfmchromeside"
SLASH_ALFMCHROMEPROFILE1 = "/alfmchromeprofile"

if type(SlashCmdList) == "table" then
    SlashCmdList["ALFMCHROME"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "hud" or msg == "minihud" then
            local hud = AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.GetFrame and AscensionLFM.MiniHUD.GetFrame()
            Chrome.DumpFrameChrome(hud, "MiniHUD")
            Chrome.PrintProfile("compact")
        else
            local f = _G.AscensionLFMFrame
            if type(f) ~= "table" then chat("open main UI first: /alfm"); return end
            Chrome.DumpFrameChrome(f, "MainWindow")
            Chrome.PrintProfile("full")
        end
    end
    SlashCmdList["ALFMCHROMEREF"] = function() Chrome.DumpBagReference() end
    SlashCmdList["ALFMCHROMESIDE"] = function() Chrome.SideBySide() end
    SlashCmdList["ALFMCHROMEPROFILE"] = function(msg)
        msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
        if msg == "" then Chrome.PrintProfile("full"); Chrome.PrintProfile("compact")
        else Chrome.PrintProfile(msg) end
    end
end

return Chrome
