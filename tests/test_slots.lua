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

-- Regression: host must NOT be force-assigned to a disabled/full role.
-- Only tank+healer accepted, both already full, dps explicitly off (but has
-- room) — EnsureHostAssigned used to hard-fall-back to "dps" regardless.
Slots.ClearAll()
db.mode = "hosting"
db.roles = { tank = true, healer = true, aura = false, dps = false }
db.slotMax = { tank = 1, healer = 1, aura = 3, dps = 7 }
Slots.Assign("SomeTank", "tank")
Slots.Assign("SomeHealer", "healer")
local noRole = Slots.EnsureHostAssigned()
check("no forced dps fallback when full/disabled", noRole == nil, tostring(noRole))
check("host stays unassigned", Slots.GetAssigned("HostPlayer") == nil, tostring(Slots.GetAssigned("HostPlayer")))
check("dps not silently filled", Slots.CountFilled("dps") == 0, tostring(Slots.CountFilled("dps")))

-- Regression: a manually-picked db.hostRole (v0.4.22) that's since been
-- disabled via Accept Roles must not still be trusted — should fall
-- through to auto-pick instead of assigning a no-longer-accepted role.
Slots.ClearAll()
db.mode = "hosting"
db.hostRole = "healer"
db.roles = { tank = true, healer = false, aura = true, dps = true }
db.slotMax = { tank = 2, healer = 3, aura = 3, dps = 7 }
local staleRole = Slots.EnsureHostAssigned()
check("stale hostRole falls through to auto-pick", staleRole == "tank", tostring(staleRole))
check("not assigned to disabled hostRole", Slots.GetAssigned("HostPlayer") ~= "healer",
    tostring(Slots.GetAssigned("HostPlayer")))
db.hostRole = nil

-- Regression: Slots.RecentlyAssigned / ReconcileAssigned protection
-- (the race-condition fix for a just-invited applicant getting pruned
-- before they've actually shown up in the roster).
_G.GetTime = function() return _G._slotsNow or 5000 end
_G._slotsNow = 5000
Slots.ClearAll()
Slots.Assign("Freshy", "dps")
check("recently assigned right after Assign", Slots.RecentlyAssigned("Freshy") == true)
check("recently assigned respects custom grace window",
    Slots.RecentlyAssigned("Freshy", 0) == false, "0s grace should already be expired")

_G._slotsNow = 5000 + 25
check("no longer recently assigned after grace period", Slots.RecentlyAssigned("Freshy") == false)
check("unknown name never recently assigned", Slots.RecentlyAssigned("NeverAssigned") == false)

-- ReconcileAssigned: protectedNames keeps an absent-but-protected name;
-- without protection (or once expired) it's correctly pruned as usual.
_G._slotsNow = 5000
local map = { freshy = "dps", stale = "tank" }
local present = {} -- nobody present
local protectedNames = { freshy = true } -- only Freshy is protected
local kept, removedCount = Slots.ReconcileAssigned(map, present, protectedNames)
check("protected name kept despite absence", kept.freshy == "dps", tostring(kept.freshy))
check("unprotected name still pruned", kept.stale == nil)
check("removed count reflects only the unprotected one", removedCount == 1, tostring(removedCount))

local keptNoProtect, removedNoProtect = Slots.ReconcileAssigned(map, present)
check("no protectedNames arg behaves as before (both pruned)",
    keptNoProtect.freshy == nil and keptNoProtect.stale == nil)
check("removed count both without protection", removedNoProtect == 2, tostring(removedNoProtect))

io.write(string.format("slots tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
