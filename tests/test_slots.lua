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

-- Regression: Slots.Assign()/ScanRaid() must NOT auto-trigger AuraBalance
-- anymore. Both are called from event/timer contexts (whisper
-- auto-invite, roster-update handlers) where WoW's secure-execution
-- model blocks SetRaidSubgroup/SwapRaidSubgroup ("prevented the call of
-- the secure function") - confirmed live. Group sorting is now the
-- host-triggered "Sort Groups" button (AuraBalance.SortGroupsNow())
-- instead of an automatic side effect of assigning a role.
local balanceCalls = 0
AscensionLFM.AuraBalance = {
    Balance = function() balanceCalls = balanceCalls + 1; return 0 end,
    BalanceAll = function() balanceCalls = balanceCalls + 1; return 0 end,
}
Slots.Assign("Aurabot", "aura")
check("Assign(aura) does not auto-trigger AuraBalance", balanceCalls == 0, tostring(balanceCalls))

_G.GetNumRaidMembers = function() return 1 end
_G.GetRaidRosterInfo = function(i) if i == 1 then return "Aurabot" end end
Slots.ScanRaid()
check("ScanRaid() does not auto-trigger AuraBalance", balanceCalls == 0, tostring(balanceCalls))
AscensionLFM.AuraBalance = nil

--------------------------------------------------------------------
-- v0.4.131: aura as an orthogonal tag + the DPS-seat reservation.
--------------------------------------------------------------------

-- No roster APIs here, so CountFilled/CountAura count every tracked entry
-- (the groupSize==0 "tests / loading" path).
_G.GetNumRaidMembers = function() return 0 end
_G.GetNumPartyMembers = function() return 0 end
_G.GetRaidRosterInfo = function() return nil end
_G.UnitName = function() return nil end

local sdb = AscensionLFM.Database.Get()
Slots.ClearAll()
sdb.roles = { tank = true, healer = true, aura = true, dps = true }
Slots.SetMax("tank", 2); Slots.SetMax("healer", 3); Slots.SetMax("aura", 3); Slots.SetMax("dps", 7)

-- The tag is orthogonal: setting it must not disturb the combat seat.
Slots.Assign("Auradin", "tank", nil, true)
check("aura tag does not change the combat role", Slots.GetAssigned("Auradin") == "tank",
    tostring(Slots.GetAssigned("Auradin")))
check("aura tag is readable", Slots.HasAura("Auradin") == true)
check("tagged tank still counts as a tank", Slots.CountFilled("tank") == 1,
    tostring(Slots.CountFilled("tank")))
check("tagged tank counts toward aura coverage", Slots.CountAura() == 1,
    tostring(Slots.CountAura()))
check("CountFilled('aura') is coverage, not a seat count", Slots.CountFilled("aura") == 1,
    tostring(Slots.CountFilled("aura")))

Slots.SetAura("Auradin", false)
check("aura tag can be removed without losing the seat",
    Slots.HasAura("Auradin") == false and Slots.GetAssigned("Auradin") == "tank")
Slots.SetAura("Auradin", true)

-- Reservation: aura target 3, one carrier so far -> 2 still needed, so the
-- last 2 of the 7 DPS seats are held for aura carriers.
check("aura shortfall reflects the target", Slots.AuraShortfall() == 2, tostring(Slots.AuraShortfall()))
for i = 1, 5 do Slots.Assign("Plain" .. i, "dps") end
check("5 plain dps seated", Slots.CountFilled("dps") == 5, tostring(Slots.CountFilled("dps")))
check("dps seat still open in raw terms", Slots.HasOpenSlot("dps") == true)
check("non-aura dps is turned away while aura is short",
    Slots.HasOpenSlotFor("dps", false) == false)
check("aura-carrying dps is still accepted", Slots.HasOpenSlotFor("dps", true) == true)
check("tank is never blocked for aura", Slots.HasOpenSlotFor("tank", false) == true)
check("healer is never blocked for aura", Slots.HasOpenSlotFor("healer", false) == true)

-- Turning the reservation off fills DPS with whoever shows up.
sdb.roles.aura = false
check("reservation off lets plain dps in", Slots.HasOpenSlotFor("dps", false) == true)
sdb.roles.aura = true

-- Meeting the target releases the held seats. Coverage is filled here by
-- two aura-carrying HEALERS, which is exactly the case the old exclusive
-- model could not express - and it proves the reservation frees DPS seats
-- without those seats having to be spent on the aura carriers themselves.
Slots.Assign("AuraHeal1", "healer", nil, true)
Slots.Assign("AuraHeal2", "healer", nil, true)
check("aura target met from non-dps seats", Slots.AuraShortfall() == 0,
    tostring(Slots.AuraShortfall()))
check("held dps seats released once coverage is met",
    Slots.HasOpenSlotFor("dps", false) == true)

-- Clearing a member drops both their seat and their tag.
Slots.ClearName("AuraHeal1")
check("ClearName drops the aura tag too", Slots.HasAura("AuraHeal1") == false)
check("ClearName drops the seat too", Slots.GetAssigned("AuraHeal1") == nil)
check("coverage drops back when a carrier leaves", Slots.AuraShortfall() == 1,
    tostring(Slots.AuraShortfall()))

-- SnapshotAuraFlags is what lets RoleCheck.Resync survive its ClearAll().
local snap = Slots.SnapshotAuraFlags()
check("snapshot captures live tags", snap.auradin == true, tostring(snap.auradin))
Slots.ClearAll()
check("ClearAll wipes tags", Slots.CountAura() == 0, tostring(Slots.CountAura()))
Slots.Assign("Auradin", "tank", nil, snap.auradin)
check("tags can be restored from a snapshot", Slots.HasAura("Auradin") == true)

io.write(string.format("slots tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
