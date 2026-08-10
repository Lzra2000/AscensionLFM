-- AscensionLFM: core/Bootstrap.lua
-- Namespace + slash commands + ADDON_LOADED / PLAYER_LOGIN wiring.
-- Loaded LAST in AscensionLFM.toc so Database/Parser/Scanner/UI exist.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

AscensionLFM.VERSION = "0.3.0"
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
        Print("Database not ready.")
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
        AscensionLFM.MainWindow.RefreshMatches()
    end
    Print("injected test match into Log — /alfm → Log")
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AscensionLFM.ADDON_NAME then
        if AscensionLFM.Database and AscensionLFM.Database.Init then
            AscensionLFM.Database.Init()
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if AscensionLFM.Scanner and AscensionLFM.Scanner.Start then
            AscensionLFM.Scanner.Start()
        end
        if AscensionLFM.Poster and AscensionLFM.Poster.Start then
            AscensionLFM.Poster.Start()
        end
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Init then
            AscensionLFM.MainWindow.Init()
        end
        local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
        local mode = (db and db.mode) or "notify"
        Print("v" .. AscensionLFM.VERSION .. " — mode=" .. ModeLabel(mode))
        Print("/alfm to open settings · /alfm test for a fake Log entry")
        Print("Hosting → invite; Post → LFM compose/scan/repost (kick stays opt-in OFF)")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

SLASH_ASCENSIONLFM1 = "/alfm"
SLASH_ASCENSIONLFM2 = "/mslfm"
SLASH_ASCENSIONLFM3 = "/ascensionlfm"
SlashCmdList["ASCENSIONLFM"] = function(msg)
    msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "status" then
        local db = AscensionLFM.Database and AscensionLFM.Database.Get()
        local mode = (db and db.mode) or "notify"
        Print("mode=" .. ModeLabel(mode) .. " version=" .. AscensionLFM.VERSION)
        return
    end
    if msg == "test" then
        InjectTestMatch()
        return
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
        AscensionLFM.MainWindow.Toggle()
    else
        Print("UI not ready yet.")
    end
end
