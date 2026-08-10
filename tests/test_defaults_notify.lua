-- AscensionLFM: default mode + scanner → matchHistory path tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" — " .. detail) or "") .. "\n")
    end
end

-- Fresh SavedVariables
_G.AscensionLFMDB = nil
_G.AscensionLFM = nil

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Scanner.lua")

local Database = assert(_G.AscensionLFM.Database)
local Parser = assert(_G.AscensionLFM.Parser)
local Scanner = assert(_G.AscensionLFM.Scanner)

Database.Init()
local db = Database.Get()

check("default mode is notify", db.mode == "notify")
check("defaultsRev is 5", tonumber(db.defaultsRev) == 5)
check("autoKick still off", db.autoKickLevel59 == false)
check("autoWhisper still off", db.autoWhisper == false)
check("autoRepost still off", db.autoRepost == false)
check("fullAutoHosting still off", db.fullAutoHosting == false)
check("rejectRewhisper still off", db.rejectRewhisper == false)
check("repostInterval default 60", tonumber(db.repostInterval) == 60)
check("postChannel default YELL", db.postChannel == "YELL")
check("roleCheckMessage mentions T/H/A/D",
    tostring(db.roleCheckMessage):find("T/H/A/D", 1, true) ~= nil)

-- Fresh defaults table
local defs = Database.Defaults()
check("Defaults().mode notify", defs.mode == "notify")

-- Upgrade path: leftover Off → notify once
_G.AscensionLFMDB = {
    mode = "off",
    defaultsRev = 1,
    matchHistory = {},
}
Database.Init()
check("migrate off→notify", Database.Get().mode == "notify")
check("migrate sets defaultsRev 5", tonumber(Database.Get().defaultsRev) == 5)

-- Do not re-flip after user sets Off post-migration
Database.SetMode("off")
Database.Init()
check("user Off stays after rev>=2", Database.Get().mode == "off")

-- v0.4.2: stock old RW message → shorter default; custom text kept
_G.AscensionLFMDB = {
    mode = "notify",
    defaultsRev = 2,
    roleCheckMessage = "ROLE CHECK — whisper me tank / heal / aura / dps to sync MS slots",
}
Database.Init()
check("migrate shortens stock RW msg",
    tostring(Database.Get().roleCheckMessage):find("T/H/A/D", 1, true) ~= nil)
check("migrate mentions party replies",
    tostring(Database.Get().roleCheckMessage):find("party", 1, true) ~= nil)
_G.AscensionLFMDB = {
    mode = "notify",
    defaultsRev = 2,
    roleCheckMessage = "Custom ROLE CHECK please whisper me",
}
Database.Init()
check("custom RW msg kept",
    Database.Get().roleCheckMessage == "Custom ROLE CHECK please whisper me")

-- v0.4.4: saved Full Auto with healer/aura off → enable all accept roles once
_G.AscensionLFMDB = {
    mode = "hosting",
    defaultsRev = 3,
    fullAutoHosting = true,
    autoInvite = true,
    roles = { tank = true, healer = false, aura = false, dps = true },
}
Database.Init()
local migrated = Database.Get()
check("full auto migrate rev 5", tonumber(migrated.defaultsRev) == 5)
check("full auto migrate healer on", migrated.roles.healer == true)
check("full auto migrate aura on", migrated.roles.aura == true)

-- Restore notify for scanner path tests
Database.SetMode("notify")
Database.ClearMatches()

local samples = {
    "LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS",
    "lfg ms tank",
    "LFM Manastorm need heals",
    "LFM mana storm 0/2 Tanks 0/7 DPS",
}

for i, line in ipairs(samples) do
    local parsed = Parser.Parse(line)
    check("sample " .. i .. " parses listing", parsed and parsed.isManastormListing == true)
end

-- Scanner public path pushes history when mode=notify
local before = #(Database.Get().matchHistory or {})
Scanner._HandlePublicListing("HostOne", samples[1], "CHAT_MSG_CHANNEL")
local hist = Database.Get().matchHistory
check("notify pushes match history", hist and #hist == before + 1)
check("history leader", hist[1] and hist[1].leader == "HostOne")
check("history has text", hist[1] and tostring(hist[1].text or ""):find("LFM MS", 1, true) ~= nil)

-- LFG sample
Scanner._HandlePublicListing("SeekerTwo", samples[2], "CHAT_MSG_YELL")
hist = Database.Get().matchHistory
check("lfg pushes history", hist[1] and hist[1].leader == "SeekerTwo")
check("lfg kind", hist[1] and hist[1].kind == "lfg")

-- mana storm variant
Scanner._HandlePublicListing("HostThree", samples[4], "CHAT_MSG_SAY")
hist = Database.Get().matchHistory
check("mana storm pushes history", hist[1] and hist[1].leader == "HostThree")

-- Off mode ignores public chat
Database.SetMode("off")
local countBefore = #hist
Scanner._HandlePublicListing("Ignored", samples[1], "CHAT_MSG_CHANNEL")
check("off ignores public listing", #Database.Get().matchHistory == countBefore)

io.write(string.format("test_defaults_notify: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
