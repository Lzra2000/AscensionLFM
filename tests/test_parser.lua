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

-- Missing aura
p = Parser.Parse("LFM MS 0/2 Tanks 1/3 Healers 3/7 DPS")
check("no aura ok", p and p.isManastormLFM and p.roles.aura == nil)
check("healer open", p and p.roles.healer.open == true)

-- Role order shuffled + Heals alias
p = Parser.Parse("LFM MS 0/7 DPS 0/3 Heals 0/2 Tanks")
check("shuffled dps first", p and p.roles.dps and p.roles.dps.total == 7)
check("heals alias", p and p.roles.healer and p.roles.healer.total == 3)

-- Non-match
check("trade spam nil", Parser.Parse("WTS epic mount cheap") == nil)
check("lfm without ms nil", Parser.Parse("LFM ICC 25 need tank") == nil)
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

-- Full slots not open
p = Parser.Parse("LFM MS 2/2 Tanks 3/3 Healers 7/7 DPS")
check("all full tank closed", p and p.roles.tank.open == false)
check("all full needs none", Parser.NeedsAnyRole(p, { tank = true, healer = true, dps = true }) == false)

io.write(string.format("parser tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
