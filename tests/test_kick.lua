-- AscensionLFM kick scheduler pure-function tests.
package.path = "./?.lua;./core/?.lua;" .. (package.path or "")

dofile("core/Kick.lua")

local Kick = assert(_G.AscensionLFM.Kick)
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

local roster = {
    { name = "Alice", level = 58 },
    { name = "Bob", level = 59 },
    { name = "Carl", level = 60 },
    { name = "Host", level = 59 },
}

local targets = Kick.SelectTargets(roster, 59, "Host")
check("selects two", #targets == 2)
check("excludes self", targets[1].name ~= "Host" and targets[2].name ~= "Host")
check("includes Bob", targets[1].name == "Bob" or targets[2].name == "Bob")
check("includes Carl", targets[1].name == "Carl" or targets[2].name == "Carl")
check("skips 58", true)

targets = Kick.SelectTargets(roster, 59, nil)
check("with no self includes Host", #targets == 3)

targets = Kick.SelectTargets({ { name = "Low", level = 10 } }, 59, "Me")
check("empty when none", #targets == 0)

check("should warn first", Kick.ShouldWarn(100, 0, 10) == true)
check("rate limit", Kick.ShouldWarn(105, 100, 10) == false)
check("after interval", Kick.ShouldWarn(110, 100, 10) == true)

local msg = Kick.BuildWarnMessage({ { name = "Bob", level = 59 } }, 59)
check("warn message", type(msg) == "string" and msg:find("Bob", 1, true) ~= nil and msg:find("59", 1, true) ~= nil)
check("warn nil empty", Kick.BuildWarnMessage({}, 59) == nil)

io.write(string.format("kick tests: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
