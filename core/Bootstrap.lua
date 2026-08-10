-- AscensionLFM: core/Bootstrap.lua
-- Namespace + slash commands + ADDON_LOADED / PLAYER_LOGIN wiring.
-- Loaded LAST in AscensionLFM.toc so Database/Parser/Scanner/UI exist.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

AscensionLFM.VERSION = "0.3.1"
AscensionLFM.ADDON_NAME = "AscensionLFM"

local function Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc8a03c[AscensionLFM]|r " .. tostring(msg))
    end
end
AscensionLFM.Print = Print

local function ModeLabel(mode)
    if mode == "notify" then
        return "Notify (Listening ON)"
    elseif mode == "seeking" then
        return "Seeking (Listening ON)"
    elseif mode == "hosting" then
        return "Hosting (Listening ON)"
    end
    return "Off (Listening OFF)"
end

local function InjectTestMatch()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        Print("Database not ready — is the addon enabled and /reload done?")
        return
    end
    local sample = "LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS"
    local parsed = AscensionLFM.Parser and AscensionLFM.Parser.Parse and AscensionLFM.Parser.Parse(sample)
    AscensionLFM.Database.PushMatch({
        leader = "TestLeader",
        text = sample,
        summary = (parsed and parsed.summary) or "MS test",
        source = "test",
        kind = "lfm",
        t = time and time() or 0,
    })
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshMatches then
        pcall(AscensionLFM.MainWindow.RefreshMatches)
    end
    Print("injected test match into Log — /alfm → Log")
end

local function SafeStart(name, fn)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn)
    if not ok then
        Print(name .. " failed: " .. tostring(err))
    end
end

local function RegisterSlash()
    -- Re-register so Ascension / other addons cannot silently steal /alfm after load.
    SLASH_ASCENSIONLFM1 = "/alfm"
    SLASH_ASCENSIONLFM2 = "/mslfm"
    SLASH_ASCENSIONLFM3 = "/ascensionlfm"
    SLASH_ASCENSIONLFM4 = "/alfmshow"
    SlashCmdList["ASCENSIONLFM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "status" then
            local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
            local mode = (db and db.mode) or "notify"
            Print("mode=" .. ModeLabel(mode) .. " version=" .. AscensionLFM.VERSION)
            Print("slash OK — try /alfm to toggle UI, /alfm test for Log")
            return
        end
        if msg == "test" then
            InjectTestMatch()
            return
        end
        if msg == "help" then
            Print("/alfm | /mslfm — toggle UI")
            Print("/alfm status | test | help")
            return
        end
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
            local ok, err = pcall(AscensionLFM.MainWindow.Toggle)
            if not ok then
                Print("UI error: " .. tostring(err))
                Print("Slash still works — /alfm status · /alfm test")
            end
        else
            Print("UI module missing — check AddOns list (AscensionLFM enabled?) then /reload")
        end
    end
end

RegisterSlash()

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AscensionLFM.ADDON_NAME then
        SafeStart("Database.Init", AscensionLFM.Database and AscensionLFM.Database.Init)
        RegisterSlash()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Late-join /reload: ADDON_LOADED may have already fired before this file loaded.
        if AscensionLFM.Database and AscensionLFM.Database.Init then
            SafeStart("Database.Init", AscensionLFM.Database.Init)
        end
        RegisterSlash()
        SafeStart("Scanner.Start", AscensionLFM.Scanner and AscensionLFM.Scanner.Start)
        SafeStart("Poster.Start", AscensionLFM.Poster and AscensionLFM.Poster.Start)
        SafeStart("MainWindow.Init", AscensionLFM.MainWindow and AscensionLFM.MainWindow.Init)
        local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
        local mode = (db and db.mode) or "notify"
        Print("v" .. AscensionLFM.VERSION .. " — mode=" .. ModeLabel(mode))
        Print("/alfm · /mslfm · /alfm status · /alfm test")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
