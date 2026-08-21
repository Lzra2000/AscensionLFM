-- AscensionLFM parser unit tests (pure Lua 5.1, no WoW APIs).
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

-- Minimal sandbox: Parser.lua expects optional _G.AscensionLFM
dofile("core/Parser.lua")

local Parser = assert(_G.AscensionLFM.Parser)
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

-- Classic example
local p = Parser.Parse("LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS")
check("classic is MS LFM", p and p.isManastormLFM == true)
check("classic tank 0/2", p and p.roles.tank and p.roles.tank.filled == 0 and p.roles.tank.total == 2)
check("classic healer 0/3", p and p.roles.healer and p.roles.healer.filled == 0 and p.roles.healer.total == 3)
check("classic aura 0/3", p and p.roles.aura and p.roles.aura.filled == 0 and p.roles.aura.total == 3)
check("classic dps 0/7", p and p.roles.dps and p.roles.dps.filled == 0 and p.roles.dps.total == 7)
check("classic tank open", p and p.roles.tank.open == true)

-- Case / keyword variants
p = Parser.Parse("lfm ms need tank and heals")
check("lower lfm ms", p and p.isManastormLFM)
check("need tank mentioned", p and p.roles.tank and p.roles.tank.open)

p = Parser.Parse("LFM Manastorm 1/2 Tank 2/3 H 0/7 DPS")
check("Manastorm word", p and p.isManastormLFM)
check("partial fills tank", p and p.roles.tank.filled == 1 and p.roles.tank.total == 2)
check("H alias healer", p and p.roles.healer and p.roles.healer.filled == 2 and p.roles.healer.total == 3)

-- Missing aura
p = Parser.Parse("LFM MS 0/2 Tanks 1/3 Healers 3/7 DPS")
check("no aura ok", p and p.isManastormLFM and p.roles.aura == nil)
check("healer open", p and p.roles.healer.open == true)

-- Role order shuffled + Heals alias
p = Parser.Parse("LFM MS 0/7 DPS 0/3 Heals 0/2 Tanks")
check("shuffled dps first", p and p.roles.dps and p.roles.dps.total == 7)
check("heals alias", p and p.roles.healer and p.roles.healer.total == 3)

-- LFG listings
p = Parser.Parse("LFG MS tank")
check("LFG MS is listing", p and p.isManastormLFG == true and p.isManastormListing == true)
check("LFG not LFM", p and p.isManastormLFM == false)
check("LFG tank open", p and p.roles.tank and p.roles.tank.open)

p = Parser.Parse("lfg manastorm need heals")
check("lfg manastorm", p and p.isManastormLFG and p.roles.healer and p.roles.healer.open)

p = Parser.Parse("LFG MS 0/2 Tanks 0/3 Healers")
check("LFG with slots", p and p.isManastormLFG and p.roles.tank.total == 2)

-- Softened Manastorm spelling / spacing variants
p = Parser.Parse("LFM mana storm 0/2 Tanks 0/7 DPS")
check("mana storm spaced", p and p.isManastormLFM and p.roles.tank and p.roles.tank.total == 2)

p = Parser.Parse("LFM Mana-Storm need tank")
check("mana-storm hyphen", p and p.isManastormLFM and p.roles.tank and p.roles.tank.open)

p = Parser.Parse("lfg ms")
check("bare lfg ms", p and p.isManastormLFG == true)

p = Parser.Parse("LFM Manastorm")
check("bare LFM Manastorm", p and p.isManastormLFM == true)

-- Non-match
check("trade spam nil", Parser.Parse("WTS epic mount cheap") == nil)
check("lfm without ms nil", Parser.Parse("LFM ICC 25 need tank") == nil)
check("lfg without ms nil", Parser.Parse("LFG ICC need tank") == nil)
check("ms without lfm soft", Parser.Parse("ms tank inv") ~= nil) -- role request path

-- NeedsAnyRole
p = Parser.Parse("LFM MS 2/2 Tanks 0/3 Healers 0/7 DPS")
check("needs healer", Parser.NeedsAnyRole(p, { tank = true, healer = true }) == true)
check("tank full skip", Parser.NeedsAnyRole(p, { tank = true, healer = false, dps = false, aura = false }) == false)

-- Role request / hosting whisper
p = Parser.Parse("inv ms tank")
check("inv ms tank is role req", p and p.isRoleRequest)
check("requested tank", Parser.RequestedRole(p) == "tank")

p = Parser.Parse("heal")
check("bare heal", p and Parser.RequestedRole(p) == "healer")

p = Parser.Parse("dps please")
check("dps please", p and Parser.RequestedRole(p) == "dps")

p = Parser.Parse("OT")
check("OT is tank", p and Parser.RequestedRole(p) == "tank")

p = Parser.Parse("MT ready")
check("MT is tank", p and Parser.RequestedRole(p) == "tank")

p = Parser.Parse("HPS")
check("HPS is healer", p and Parser.RequestedRole(p) == "healer")

-- Since v0.4.131 aura is an orthogonal TAG, not a 4th seat: an aura-only
-- signup seats as DPS and keeps the tag, rather than occupying an "aura
-- slot" that no longer exists.
local function roleAndAura(text)
    local parsedText = Parser.Parse(text)
    if not parsedText then
        return nil, false
    end
    return Parser.RequestedRole(parsedText)
end

local r, a = roleAndAura("Aura of Exp")
check("Aura of Exp seats as dps", r == "dps", tostring(r))
check("Aura of Exp keeps the aura tag", a == true, tostring(a))

r, a = roleAndAura("exp aura inv")
check("exp aura seats as dps", r == "dps", tostring(r))
check("exp aura keeps the aura tag", a == true, tostring(a))

r, a = roleAndAura("AoE aura")
check("AoE aura seats as dps", r == "dps", tostring(r))
check("AoE aura keeps the aura tag", a == true, tostring(a))

-- The headline case the whole model change exists for: a DPS who brings an
-- aura must resolve to BOTH, not collapse to one.
r, a = roleAndAura("dps with aura")
check("dps with aura -> dps seat", r == "dps", tostring(r))
check("dps with aura -> aura tag", a == true, tostring(a))

r, a = roleAndAura("tank aura")
check("tank aura -> tank seat", r == "tank", tostring(r))
check("tank aura -> aura tag", a == true, tostring(a))

r, a = roleAndAura("heal no aura")
check("heal no aura -> healer seat", r == "healer", tostring(r))
check("heal no aura -> no tag (negation respected)", a == false, tostring(a))

r, a = roleAndAura("dps")
check("plain dps -> dps seat", r == "dps", tostring(r))
check("plain dps -> no aura tag", a == false, tostring(a))

p = Parser.Parse("DD")
check("DD is dps", p and Parser.RequestedRole(p) == "dps")

-- Letter + DE + punctuation fallbacks
p = Parser.Parse("H")
check("letter H is healer", p and Parser.RequestedRole(p) == "healer")
p = Parser.Parse("T")
check("letter T is tank", p and Parser.RequestedRole(p) == "tank")
r, a = roleAndAura("A")
check("letter A seats as dps", r == "dps", tostring(r))
check("letter A keeps the aura tag", a == true, tostring(a))
p = Parser.Parse("D")
check("letter D is dps", p and Parser.RequestedRole(p) == "dps")
p = Parser.Parse("healers!")
check("healers! punct", p and Parser.RequestedRole(p) == "healer")
p = Parser.Parse("heiler")
check("DE heiler", p and Parser.RequestedRole(p) == "healer")
check("GuessRole healers", Parser.GuessRole("healers") == "healer")
check("GuessRole H", Parser.GuessRole("H") == "healer")
check("GuessRole dmg", Parser.GuessRole("dmg") == "dps")
check("GuessRole heiler pls", Parser.GuessRole("heiler pls") == "healer")

-- Full slots not open
p = Parser.Parse("LFM MS 2/2 Tanks 3/3 Healers 7/7 DPS")
check("all full tank closed", p and p.roles.tank.open == false)
check("all full needs none", Parser.NeedsAnyRole(p, { tank = true, healer = true, dps = true }) == false)

-- Slot totals helper
p = Parser.Parse("LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS")
local totals = Parser.SlotTotals(p)
check("slot totals tank", totals and totals.tank == 2)
check("slot totals aura", totals and totals.aura == 3)

-- Glued MS15 / Heal lfg MS15
p = Parser.Parse("Heal lfg MS15")
check("heal lfg MS15 parses", p ~= nil, tostring(p))
check("heal lfg MS15 is LFG", p and p.isManastormLFG == true)
check("heal lfg MS15 healer", p and p.roles and p.roles.healer and p.roles.healer.open == true)
p = Parser.Parse("LFG MS15 DPS")
check("LFG MS15 DPS", p and p.isManastormLFG and p.roles.dps)

--------------------------------------------------------------------
-- NegatedRoles: explicit "I don't want/have this role/attribute"
-- detection, English and German phrasing.
--------------------------------------------------------------------
check("english 'no aura'", Parser.NegatedRoles("dps no aura").aura == true)
check("english 'without aura'", Parser.NegatedRoles("dps without aura").aura == true)
check("english 'not a healer'", Parser.NegatedRoles("dps not a healer").healer == true)
check("english 'w/o aura'", Parser.NegatedRoles("dps w/o aura").aura == true)
check("english 'no-aura'", Parser.NegatedRoles("dps no-aura").aura == true)

check("german 'ohne aura'", Parser.NegatedRoles("dps ohne aura").aura == true)
check("german 'keine aura'", Parser.NegatedRoles("dps keine aura").aura == true)
check("german 'kein tank'", Parser.NegatedRoles("dps kein tank").tank == true)
check("german 'keinen heiler'", Parser.NegatedRoles("dps keinen heiler").healer == true)

-- 'keinerlei' must NOT match (the comment's own claim: the optional
-- kein[e]? ending shouldn't bleed into unrelated longer words).
local negKeinerlei = Parser.NegatedRoles("dps keinerlei aura interesse")
check("german 'keinerlei' does not false-match", negKeinerlei.aura == nil, tostring(negKeinerlei.aura))

-- Multiple negated roles in one message.
local negMulti = Parser.NegatedRoles("dps ohne aura, kein tank")
check("multiple negated roles: aura", negMulti.aura == true)
check("multiple negated roles: tank", negMulti.tank == true)

-- No negation phrasing present: empty set, not nil.
local negNone = Parser.NegatedRoles("dps full loom lfg ms")
check("no negation returns empty table", type(negNone) == "table" and next(negNone) == nil)

--------------------------------------------------------------------
-- German LFM/LFG phrasing. Role keyword aliases already had partial
-- German support ("heiler" for healer) but the LFM/LFG signal words
-- themselves never did - a host/seeker typing in German would never
-- have been detected at all before this.
--------------------------------------------------------------------
p = Parser.Parse("suche noch ms tank")
check("German LFM: 'suche noch' detected as recruiting", p and p.isManastormLFM == true, p and p.isManastormLFM)

p = Parser.Parse("sucht noch ms heiler")
check("German LFM: 'sucht noch' detected as recruiting", p and p.isManastormLFM == true)
check("German LFM: 'heiler' still maps to healer role", p and p.roles.healer and p.roles.healer.open)

p = Parser.Parse("brauche noch ms tank")
check("German LFM: 'brauche noch' detected as recruiting", p and p.isManastormLFM == true)

p = Parser.Parse("brauchen noch ms dps")
check("German LFM: 'brauchen noch' detected as recruiting", p and p.isManastormLFM == true)

p = Parser.Parse("suche gruppe ms tank")
check("German LFG: 'suche gruppe' detected as seeking", p and p.isManastormLFG == true
    and p.isManastormLFM == false)

p = Parser.Parse("suche grp ms")
check("German LFG: 'suche grp' detected as seeking", p and p.isManastormLFG == true)

p = Parser.Parse("suche mitspieler fuer ms")
check("German LFG: 'suche mitspieler' detected as seeking", p and p.isManastormLFG == true)

-- Still gated on an actual Manastorm mention - an ordinary German
-- sentence with "suche noch"/"suche gruppe" but no MS/manastorm word
-- must NOT be treated as a listing (same rule as the English phrases).
p = Parser.Parse("suche noch meine schluessel")
check("German phrase without Manastorm mention is not a listing",
    p == nil or (p.isManastormLFM ~= true and p.isManastormLFG ~= true))

io.write(string.format("parser tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
