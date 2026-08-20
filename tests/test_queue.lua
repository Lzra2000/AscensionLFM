-- AscensionLFM: tests/test_queue.lua
-- Queue.lua: applicant queue push/dedup, role-label resolution, status,
-- trimming, invite/reject dispatch. No test file existed for this module
-- before - added alongside the roleLabel-drift fix below.

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
_G._now = 1000
_G.time = function() return _G._now end

dofile("core/Database.lua")
dofile("core/Parser.lua")
dofile("core/Queue.lua")

local AscensionLFM = _G.AscensionLFM
AscensionLFM.Database.Init()
local Queue = assert(AscensionLFM.Queue)

--------------------------------------------------------------------
-- FormatRoleLabel: pure primary+offered role -> label string
--------------------------------------------------------------------
check("primary only", Queue.FormatRoleLabel("tank", nil) == "tank")
check("primary + offered secondary", Queue.FormatRoleLabel("dps", "dps also have aura") == "dps+aura",
    Queue.FormatRoleLabel("dps", "dps also have aura"))
check("offered only, no primary", Queue.FormatRoleLabel(nil, "also aura") == "aura",
    tostring(Queue.FormatRoleLabel(nil, "also aura")))
check("nothing at all -> nil", Queue.FormatRoleLabel(nil, nil) == nil)
check("primary not duplicated if also offered", Queue.FormatRoleLabel("aura", "aura please") == "aura")

--------------------------------------------------------------------
-- Push: fresh insert
--------------------------------------------------------------------
Queue.Clear()
Queue.Push("Applicant1", "tank", "inv ms tank", "pending")
local recent = Queue.Recent()
check("insert adds one entry", #recent == 1, tostring(#recent))
check("insert sets role", recent[1].role == "tank")
check("insert sets roleLabel", recent[1].roleLabel == "tank")
check("insert sets status", recent[1].status == "pending")

--------------------------------------------------------------------
-- Push: dedup-update moves the entry to front and merges fields
--------------------------------------------------------------------
Queue.Push("Applicant0", "healer", "inv ms heal", "pending")
check("two entries now", #Queue.Recent() == 2)
Queue.Push("Applicant1", "dps", "actually dps now", "pending")
recent = Queue.Recent()
check("dedup does not add a new entry", #recent == 2, tostring(#recent))
check("dedup moves updated entry to front", recent[1].name == "Applicant1", recent[1].name)
check("dedup updates role", recent[1].role == "dps", tostring(recent[1].role))
check("dedup updates roleLabel to match new role", recent[1].roleLabel == "dps", tostring(recent[1].roleLabel))

--------------------------------------------------------------------
-- Regression: a dedup-update whisper with NO primary role of its own but
-- a mentioned secondary one used to overwrite roleLabel with text that no
-- longer matched the resolved (preserved) role - the Queue UI would show
-- one role while Invite (which reads q[i].role, not roleLabel) used
-- another. roleLabel must now always be derived from the same resolved
-- role that ends up stored, never the raw incoming (possibly nil) param.
--------------------------------------------------------------------
Queue.Clear()
Queue.Push("Drifter", "tank", "inv ms tank", "pending")
Queue.Push("Drifter", nil, "also have aura", "pending") -- no primary role this time, just mentions aura
recent = Queue.Recent()
check("regression: role preserved when update has no primary role",
    recent[1].role == "tank", tostring(recent[1].role))
check("regression: roleLabel matches the preserved role, not the raw nil param",
    recent[1].roleLabel == "tank+aura", tostring(recent[1].roleLabel))

--------------------------------------------------------------------
-- MAX_ENTRIES trims oldest (tail), keeps newest MAX_ENTRIES
--------------------------------------------------------------------
Queue.Clear()
for i = 1, Queue.MAX_ENTRIES + 5 do
    Queue.Push("P" .. i, "dps", "inv ms dps", "pending")
end
recent = Queue.Recent()
check("trims to MAX_ENTRIES", #recent == Queue.MAX_ENTRIES, tostring(#recent))
check("newest entry kept at front", recent[1].name == "P" .. (Queue.MAX_ENTRIES + 5), recent[1].name)
check("oldest entries trimmed off", recent[#recent].name == "P6", recent[#recent].name)

--------------------------------------------------------------------
-- SetStatus
--------------------------------------------------------------------
Queue.Clear()
Queue.Push("Statused", "tank", "inv ms tank", "pending")
local ok = Queue.SetStatus("Statused", "blocked", "ignored")
check("SetStatus returns true for existing entry", ok == true)
check("SetStatus updates status/detail", Queue.Recent()[1].status == "blocked"
    and Queue.Recent()[1].detail == "ignored")
ok = Queue.SetStatus("NoSuchApplicant", "blocked")
check("SetStatus returns false for a name not in the queue", ok == false)

--------------------------------------------------------------------
-- Invite: reads the queued role, dispatches to Invite.InvitePlayer,
-- marks the entry invited on success.
--------------------------------------------------------------------
Queue.Clear()
Queue.Push("Recruit", "healer", "inv ms heal", "pending")
local invitedCalls = {}
AscensionLFM.Invite = {
    InvitePlayer = function(name, role)
        table.insert(invitedCalls, { name = name, role = role })
        return true
    end,
}
local invOk = Queue.Invite("Recruit")
check("Invite dispatches with the queued role", invOk == true
    and invitedCalls[1] and invitedCalls[1].role == "healer",
    invitedCalls[1] and invitedCalls[1].role or "none")
check("Invite marks the entry invited on success", Queue.Recent()[1].status == "invited")

--------------------------------------------------------------------
-- Reject: dispatches to Reject.TryRewhisper, marks the entry rejected
-- regardless of whether the rewhisper itself succeeded.
--------------------------------------------------------------------
Queue.Clear()
Queue.Push("Declined", "tank", "inv ms tank", "pending")
local rejectCalls = {}
AscensionLFM.Reject = {
    TryRewhisper = function(name, reason, role)
        table.insert(rejectCalls, { name = name, reason = reason, role = role })
        return true
    end,
    ClearCooldown = function() end,
    IsRejectableReason = function() return false end,
}
local rejOk = Queue.Reject("Declined", "slot full")
check("Reject dispatches with the queued role", rejOk == true
    and rejectCalls[1] and rejectCalls[1].role == "tank")
check("Reject marks the entry rejected", Queue.Recent()[1].status == "rejected")

io.write(string.format("test_queue: %d passed, %d failed\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
