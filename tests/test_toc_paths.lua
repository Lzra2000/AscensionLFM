-- AscensionLFM: tests/test_toc_paths.lua
-- Guard: TOC must use backslash paths (Ascension/Windows 3.3.5a load).

local function Fail(msg)
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    os.exit(1)
end

local function Ok(msg)
    print("OK: " .. tostring(msg))
end

local f = io.open("AscensionLFM.toc", "r")
if not f then
    Fail("cannot open AscensionLFM.toc")
end
local toc = f:read("*a")
f:close()

if not toc:find("## Version: 0.4.22", 1, true) then
    Fail("toc version should be 0.4.22")
end
Ok("version 0.4.22")

-- Forward-slash lua paths break Ascension load for many clients.
if toc:find("core/Database.lua", 1, true)
    or toc:find("core/Bootstrap.lua", 1, true)
    or toc:find("ui/MainWindow.lua", 1, true)
    or toc:find("ui/MiniHUD.lua", 1, true) then
    Fail("toc still has forward-slash lua paths — Ascension may not load /alfm")
end
Ok("no forward-slash lua paths")

local files = {}
for line in toc:gmatch("[^\r\n]+") do
    local path = line:match("^(%S+%.lua)%s*$")
    if path then
        table.insert(files, path)
    end
end
if #files < 12 then
    Fail("expected >= 12 lua files in toc, got " .. tostring(#files))
end
Ok(#files .. " lua files in toc")

-- MiniHUD must load before MainWindow (settings toggle references it)
local miniIdx, mainIdx
for i, path in ipairs(files) do
    if path:find("MiniHUD", 1, true) then miniIdx = i end
    if path:find("MainWindow", 1, true) then mainIdx = i end
end
if not miniIdx then
    Fail("ui\\MiniHUD.lua missing from toc")
end
if miniIdx and mainIdx and miniIdx > mainIdx then
    Fail("MiniHUD must load before MainWindow")
end
Ok("MiniHUD before MainWindow")

local boot = files[#files]
-- Accept either escaping style when reading the file as a Lua string
if boot ~= "core\\Bootstrap.lua" and boot ~= [[core\Bootstrap.lua]] then
    -- On some readers a single backslash is one char
    local okBoot = boot:match("Bootstrap%.lua$") and boot:find("core", 1, true) == 1 and not boot:find("/", 1, true)
    if not okBoot then
        Fail("Bootstrap.lua must be last in toc, got [" .. tostring(boot) .. "]")
    end
end
Ok("Bootstrap last")

print("toc path tests passed")
