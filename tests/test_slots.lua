-- AscensionLFM slot cap unit tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Slots.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }

local Slots = AscensionLFM.Slots
local Parser = AscensionLFM.Parser
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

Slots.ClearAll()
check("default tank max 2", Slots.GetMax("tank") == 2)
check("open when empty", Slots.HasOpenSlot("tank") == true)

Slots.Assign("A", "tank")
Slots.Assign("B", "tank")
check("full after 2", Slots.HasOpenSlot("tank") == false)
check("healer still open", Slots.HasOpenSlot("healer") == true)

Slots.SetMax("tank", 3)
check("raised max opens", Slots.HasOpenSlot("tank") == true)

local p = Parser.Parse("LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS")
check("apply caps", Slots.ApplyParsedCaps(p) == true)
check("applied tank max", Slots.GetMax("tank") == 2)
check("applied dps max", Slots.GetMax("dps") == 7)

local snap = Slots.Snapshot()
check("snapshot filled", snap.tank.filled == 2)
check("snapshot max", snap.dps.max == 7)

local names, n = Slots.ListUnassigned({ a = true, b = true, c = true }, { a = "tank", b = "tank" })
check("list unassigned count", n == 1, tostring(n))
check("list unassigned name", names[1] == "c")
names, n = Slots.ListUnassigned({ a = true }, { a = "tank" })
check("list none unassigned", n == 0)

_G.UnitName = function() return "HostPlayer" end
Slots.ClearAll()
db.mode = "hosting"
db.roles = { tank = true, healer = true, aura = true, dps = true }
local hostRole = Slots.EnsureHostAssigned()
check("host assigned", hostRole == "tank", tostring(hostRole))
check("host remembered", Slots.GetAssigned("HostPlayer") == "tank")
check("host assign idempotent", Slots.EnsureHostAssigned() == nil)

io.write(string.format("slots tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
