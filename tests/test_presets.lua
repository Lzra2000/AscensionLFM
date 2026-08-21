-- AscensionLFM: tests/test_presets.lua
-- Presets.lua: full-fidelity capture/apply round-trip, Save/Load/Delete,
-- IsBuiltin/Get. tests/test_v040_auto.lua already covers a basic List/
-- Load/Save round trip for slotMax/maxPartySize only - this file closes
-- the rest of the gap (Delete, IsBuiltin, Get, and the other captured
-- fields: postChannel, postChannelName, repostInterval, roles,
-- announceFull, rejectRewhisper).

package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

local failed = 0
local passed = 0

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. name .. (detail and (" - " .. detail) or "") .. "\n")
    end
end

_G.AscensionLFM = nil
_G.AscensionLFMDB = nil
dofile("core/Database.lua")
dofile("core/Presets.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
local Presets = assert(AscensionLFM.Presets)

--------------------------------------------------------------------
-- IsBuiltin
--------------------------------------------------------------------
check("builtin MS 2/3/3/10 is builtin", Presets.IsBuiltin("MS 2/3/3/10") == true)
check("builtin MS 2/2/2/7 is builtin", Presets.IsBuiltin("MS 2/2/2/7") == true)
check("builtin MS tanks+heals is builtin", Presets.IsBuiltin("MS tanks+heals") == true)
check("unknown name is not builtin", Presets.IsBuiltin("TotallyMadeUp") == false)
check("empty name is not builtin", Presets.IsBuiltin("") == false)
check("nil name is not builtin", Presets.IsBuiltin(nil) == false)

--------------------------------------------------------------------
-- Get
--------------------------------------------------------------------
local got, isBuiltin = Presets.Get("MS 2/3/3/10")
check("Get returns the builtin preset", got and got.slotMax and got.slotMax.tank == 2)
check("Get flags it as builtin", isBuiltin == true)

-- Get's builtin result is a copy, not a live reference - mutating it
-- must not corrupt the real builtin table for later lookups.
got.slotMax.tank = 999
local got2 = Presets.Get("MS 2/3/3/10")
check("Get returns an isolated copy (builtin)", got2.slotMax.tank == 2, tostring(got2.slotMax.tank))

local missing, missingIsBuiltin = Presets.Get("NoSuchPreset")
check("Get returns nil for an unknown preset", missing == nil)
check("Get's second return is false for an unknown preset", missingIsBuiltin == false)

--------------------------------------------------------------------
-- Save / Get / Delete for a user preset, full round trip of every
-- captured field (not just slotMax/maxPartySize).
--------------------------------------------------------------------
db.slotMax = { tank = 3, healer = 4, aura = 1, dps = 9 }
db.maxPartySize = 20
db.postChannel = "CHANNEL"
db.postChannelName = "2.Trade"
db.repostInterval = 90
db.roles = { tank = true, healer = false, aura = true, dps = false }
db.announceFull = true
db.rejectRewhisper = true

local ok, why = Presets.Save("FullRoundTrip")
check("save a user preset", ok == true, tostring(why))

local userGot, userIsBuiltin = Presets.Get("FullRoundTrip")
check("Get finds the saved user preset", userGot ~= nil)
check("Get flags a user preset as not builtin", userIsBuiltin == false)
check("captured slotMax round-trips", userGot.slotMax.tank == 3 and userGot.slotMax.healer == 4
    and userGot.slotMax.aura == 1 and userGot.slotMax.dps == 9)
check("captured maxPartySize round-trips", userGot.maxPartySize == 20)
check("captured postChannel round-trips", userGot.postChannel == "CHANNEL")
check("captured postChannelName round-trips", userGot.postChannelName == "2.Trade")
check("captured repostInterval round-trips", userGot.repostInterval == 90)
check("captured roles round-trips", userGot.roles.tank == true and userGot.roles.healer == false
    and userGot.roles.aura == true and userGot.roles.dps == false)
check("captured announceFull round-trips", userGot.announceFull == true)
check("captured rejectRewhisper round-trips", userGot.rejectRewhisper == true)

-- Now mutate db away from those values and confirm Load restores them all.
db.slotMax = { tank = 1, healer = 1, aura = 1, dps = 1 }
db.maxPartySize = 5
db.postChannel = "YELL"
db.postChannelName = ""
db.repostInterval = 30
db.roles = { tank = false, healer = false, aura = false, dps = false }
db.announceFull = false
db.rejectRewhisper = false

ok = Presets.Load("FullRoundTrip")
check("load the user preset", ok == true)
check("loaded slotMax applied", db.slotMax.tank == 3 and db.slotMax.dps == 9)
check("loaded maxPartySize applied", db.maxPartySize == 20)
check("loaded postChannel applied", db.postChannel == "CHANNEL")
check("loaded postChannelName applied", db.postChannelName == "2.Trade")
check("loaded repostInterval applied", db.repostInterval == 90)
check("loaded roles applied", db.roles.tank == true and db.roles.aura == true
    and db.roles.healer == false and db.roles.dps == false)
check("loaded announceFull applied", db.announceFull == true)
check("loaded rejectRewhisper applied", db.rejectRewhisper == true)

--------------------------------------------------------------------
-- Delete
--------------------------------------------------------------------
local delOk, delWhy = Presets.Delete("MS 2/3/3/10")
check("cannot delete a builtin preset", delOk == false and delWhy == "builtin", tostring(delWhy))
check("builtin preset still exists after failed delete", Presets.Get("MS 2/3/3/10") ~= nil)

delOk, delWhy = Presets.Delete("NoSuchPreset")
check("deleting an unknown preset fails", delOk == false and delWhy == "not found", tostring(delWhy))

delOk = Presets.Delete("FullRoundTrip")
check("delete a real user preset", delOk == true)
check("deleted preset no longer found", Presets.Get("FullRoundTrip") == nil)

local names = Presets.List()
local stillListed = false
for _, n in ipairs(names) do
    if n == "FullRoundTrip" then stillListed = true end
end
check("deleted preset no longer in List()", stillListed == false)

--------------------------------------------------------------------
-- Save name edge cases
--------------------------------------------------------------------
ok, why = Presets.Save("")
check("cannot save with an empty name", ok == false and why == "empty name", tostring(why))
ok, why = Presets.Save("   ")
check("cannot save with a whitespace-only name", ok == false and why == "empty name", tostring(why))
ok, why = Presets.Save("MS 2/2/2/7")
check("cannot save over a builtin name", ok == false and why == "builtin name", tostring(why))

io.write(string.format("test_presets: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
