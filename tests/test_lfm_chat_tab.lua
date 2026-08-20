-- AscensionLFM: tests/test_lfm_chat_tab.lua
-- LfmChatTab.lua: dedicated chat-tab find/create/post, all against a
-- mocked chat-window API (GetChatWindowInfo/NUM_CHAT_WINDOWS/
-- FCF_OpenNewWindow) - this addon can't verify the real client API this
-- session, so every path here proves the module degrades gracefully
-- (never errors) if that mock doesn't match reality either.

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
AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local db = AscensionLFM.Database.Get()

--------------------------------------------------------------------
-- Disabled by default: Ensure()/Post() are safe no-ops, no chat-window
-- API is touched at all.
--------------------------------------------------------------------
_G.NUM_CHAT_WINDOWS = 10
_G.GetChatWindowInfo = function() error("should not be called while disabled") end
_G.FCF_OpenNewWindow = function() error("should not be called while disabled") end
dofile("ui/LfmChatTab.lua")
local LfmChatTab = AscensionLFM.LfmChatTab

check("disabled by default", LfmChatTab.IsEnabled() == false)
local ok1 = pcall(LfmChatTab.Post, "hello")
check("Post() is a safe no-op while disabled", ok1 == true)
local ensured1 = LfmChatTab.Ensure()
check("Ensure() returns nil while disabled", ensured1 == nil)

--------------------------------------------------------------------
-- Enabled, no existing tab, FCF_OpenNewWindow available: creates one.
--------------------------------------------------------------------
db.lfmChatTabEnabled = false -- re-dofile below resets module state; keep DB clean first
local windows = {} -- [i] = name
_G.GetChatWindowInfo = function(i) return windows[i] end
local openCalls = {}
_G.FCF_OpenNewWindow = function(name)
    table.insert(openCalls, name)
    windows[2] = name -- simulate the new tab landing at ChatFrame2
    _G.ChatFrame2 = { AddMessage = function() end }
end
dofile("ui/LfmChatTab.lua") -- fresh module state (tabFrame upvalue reset)
LfmChatTab = AscensionLFM.LfmChatTab
LfmChatTab.SetEnabled(true)

check("enabling calls FCF_OpenNewWindow once", #openCalls == 1, tostring(#openCalls))
check("FCF_OpenNewWindow called with the addon's tab name", openCalls[1] == "AscensionLFM", tostring(openCalls[1]))
local ensured2 = LfmChatTab.Ensure()
check("Ensure() finds the newly created tab", ensured2 == _G.ChatFrame2)

local posted = {}
_G.ChatFrame2.AddMessage = function(self, text, r, g, b)
    table.insert(posted, { text = text, r = r, g = g, b = b })
end
LfmChatTab.Post("Someone - LFM MS need tank")
check("Post() forwards to the tab's AddMessage", #posted == 1 and posted[1].text == "Someone - LFM MS need tank",
    posted[1] and posted[1].text or "none")

-- A second Ensure()/Post() call must not create a second window, and
-- must not even re-scan for one - proves the module caches the frame
-- reference (the upvalue) rather than relying on re-finding it every
-- time, by making a re-scan itself fail loudly if it were attempted.
_G.GetChatWindowInfo = function() error("should not re-scan - tabFrame must be cached") end
local ok1b = pcall(LfmChatTab.Post, "Second line")
check("second Post doesn't re-scan for the tab (cached)", ok1b == true)
check("no duplicate window created on a second Post", #openCalls == 1, tostring(#openCalls))
check("both lines landed in the same tab", #posted == 2)

--------------------------------------------------------------------
-- Enabled, tab already exists from a previous session (persisted
-- Blizzard chat-window layout) - found without calling FCF_OpenNewWindow.
--------------------------------------------------------------------
windows = { [3] = "AscensionLFM" }
_G.GetChatWindowInfo = function(i) return windows[i] end
_G.ChatFrame3 = { AddMessage = function() end }
openCalls = {}
dofile("ui/LfmChatTab.lua")
LfmChatTab = AscensionLFM.LfmChatTab
db.lfmChatTabEnabled = true
local ensured3 = LfmChatTab.Ensure()
check("finds a pre-existing tab without creating a new one", ensured3 == _G.ChatFrame3
    and #openCalls == 0, tostring(#openCalls))

--------------------------------------------------------------------
-- Enabled, but this client has no FCF_OpenNewWindow at all (API
-- mismatch) - degrades to a safe no-op instead of erroring.
--------------------------------------------------------------------
windows = {}
_G.FCF_OpenNewWindow = nil
dofile("ui/LfmChatTab.lua")
LfmChatTab = AscensionLFM.LfmChatTab
db.lfmChatTabEnabled = true
local ensured4 = LfmChatTab.Ensure()
check("no FCF_OpenNewWindow -> Ensure() returns nil, no error", ensured4 == nil)
local ok2 = pcall(LfmChatTab.Post, "should not error")
check("Post() still safe with no usable tab", ok2 == true)

--------------------------------------------------------------------
-- No chat-window API globals present at all (very defensive baseline).
--------------------------------------------------------------------
_G.NUM_CHAT_WINDOWS = nil
_G.GetChatWindowInfo = nil
_G.FCF_OpenNewWindow = nil
dofile("ui/LfmChatTab.lua")
LfmChatTab = AscensionLFM.LfmChatTab
db.lfmChatTabEnabled = true
local ok3, ensured5 = pcall(LfmChatTab.Ensure)
check("no chat-window globals at all -> Ensure() doesn't error", ok3 == true and ensured5 == nil)

io.write(string.format("test_lfm_chat_tab: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
