-- AscensionLFM: core/Bootstrap.lua
-- Namespace + slash commands + ADDON_LOADED / PLAYER_LOGIN wiring.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

AscensionLFM.VERSION = "0.2.0"
AscensionLFM.ADDON_NAME = "AscensionLFM"

local function Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc8a03c[AscensionLFM]|r " .. tostring(msg))
    end
end
AscensionLFM.Print = Print

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
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Init then
            AscensionLFM.MainWindow.Init()
        end
        Print("loaded v" .. AscensionLFM.VERSION .. " — /alfm")
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
        local mode = (db and db.mode) or "off"
        Print("mode=" .. tostring(mode) .. " version=" .. AscensionLFM.VERSION)
        return
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
        AscensionLFM.MainWindow.Toggle()
    else
        Print("UI not ready yet.")
    end
end
