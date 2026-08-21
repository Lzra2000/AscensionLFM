-- AscensionLFM: core/Bootstrap.lua
-- Namespace + slash commands + ADDON_LOADED / PLAYER_LOGIN wiring.
-- Loaded LAST in AscensionLFM.toc so Database/Parser/Scanner/UI exist.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

AscensionLFM.VERSION = "0.4.134"
AscensionLFM.ADDON_NAME = "AscensionLFM"

local function Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffc8a03c[AscensionLFM]|r " .. tostring(msg))
    end
end
AscensionLFM.Print = Print

local function ModeLabel(mode)
    if mode == "notify" then
        return "Notify (Listening ON)"
    elseif mode == "seeking" then
        return "Seeking (Listening ON)"
    elseif mode == "hosting" then
        return "Hosting (Listening ON)"
    end
    return "Off (Listening OFF)"
end

local function OnOff(v)
    return v and "ON" or "off"
end

local function PrintStatus()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        Print("Database not ready - is the addon enabled and /reload done?")
        return
    end
    local mode = db.mode or "notify"
    Print("v" .. AscensionLFM.VERSION .. " * mode=" .. ModeLabel(mode))
    Print(string.format("Full Auto Hosting=%s * autoInvite=%s * autoRepost=%s * rejectRewhisper=%s",
        OnOff(db.fullAutoHosting), OnOff(db.autoInvite), OnOff(db.autoRepost), OnOff(db.rejectRewhisper)))
    Print(string.format("autoWhisper=%s * variants=%s * Kick59=%s * announceFull=%s",
        OnOff(db.autoWhisper), OnOff(db.useWhisperVariants ~= false),
        OnOff(db.autoKickLevel59), OnOff(db.announceFull)))
    if AscensionLFM.Invite and AscensionLFM.Invite._GetPendingRetries then
        local pr = AscensionLFM.Invite._GetPendingRetries()
        Print(string.format("invite: cooldown=%ss * pending retries=%d",
            tostring(db.inviteCooldown or 3), pr and #pr or 0))
    end
    if AscensionLFM.Kick and AscensionLFM.Kick.GetStatus then
        local ks = AscensionLFM.Kick.GetStatus()
        if ks then
            Print(string.format("kick: last=%s * can=%s * group=%s * pending=%s * hosting=%s * gaveUp=%d * ignore=%d * combat=%s",
                tostring(ks.last or "?"),
                OnOff(ks.canKick),
                tostring(ks.group or "?"),
                tostring(ks.pending or 0),
                OnOff(ks.hosting),
                tonumber(ks.gaveUp) or 0,
                tonumber(ks.sessionIgnore) or 0,
                OnOff(ks.inCombat)))
        end
    end
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.GetStatus then
        local okRc, rc = pcall(AscensionLFM.RoleCheck.GetStatus)
        if okRc and rc then
            Print(string.format("roleCheck: %s * window=%ss * autoResync=%s * autoMove T/H/A=%s/%s/%s * passiveDetect=%s",
                tostring(rc.status or "idle"),
                tostring(db.roleCheckWindow or db.roleCheckDuration or 60),
                OnOff(db.roleCheckAutoResync ~= false),
                OnOff(db.autoMoveTank ~= false),
                OnOff(db.autoMoveHealer ~= false),
                OnOff(db.autoMoveAura ~= false),
                OnOff(db.passiveRoleDetect ~= false)))
            Print(string.format("roleCheck: canWarn=%s * group=%s * hosting=%s * lastStart=%s * replies=%s",
                OnOff(rc.canWarn),
                tostring(rc.group or "?"),
                OnOff(rc.hosting),
                tostring(rc.lastStart or "?"),
                tostring(rc.responses or 0)))
        else
            Print("roleCheck: GetStatus failed - " .. tostring(rc))
        end
    else
        Print("roleCheck: MODULE MISSING - reinstall AscensionLFM.zip (RoleCheck.lua)")
    end
    Print(string.format("sounds: match=%s applicant=%s * channel=%s interval=%ss",
        OnOff(db.soundOnMatch), OnOff(db.soundOnApplicant),
        tostring(db.postChannel or "YELL"),
        tostring(db.repostInterval or 60)))
    local snap = AscensionLFM.Slots and AscensionLFM.Slots.Snapshot and AscensionLFM.Slots.Snapshot()
    if snap then
        local bits = {}
        for _, role in ipairs({ "tank", "healer", "aura", "dps" }) do
            local s = snap[role]
            if s then
                table.insert(bits, string.format("%s %d/%d", role:sub(1, 1):upper(), s.filled, s.max))
            end
        end
        local gsz = AscensionLFM.Invite and AscensionLFM.Invite.GetGroupSize and AscensionLFM.Invite.GetGroupSize() or "?"
        local unNames, unN = {}, 0
        if AscensionLFM.Slots.UnassignedMembers then
            unNames, unN = AscensionLFM.Slots.UnassignedMembers()
        end
        Print("slots: " .. table.concat(bits, " * ") .. " * group " .. tostring(gsz) .. "/" .. tostring(db.maxPartySize or 15)
            .. " * unassigned=" .. tostring(unN or 0))
        if unN and unN > 0 then
            local show = {}
            for i = 1, math.min(5, #unNames) do
                table.insert(show, unNames[i])
            end
            Print("unassigned: " .. table.concat(show, ", ")
                .. (unN > 5 and (" +" .. tostring(unN - 5) .. " more") or "")
                .. " - click Mini HUD RW, have them reply T/H/A/D")
        end
    end
    local q = (type(db.applicantQueue) == "table" and #db.applicantQueue) or 0
    local act = (type(db.activityLog) == "table" and #db.activityLog) or 0
    local matches = (type(db.matchHistory) == "table" and #db.matchHistory) or 0
    Print(string.format("queue=%d * activity=%d * matches=%d", q, act, matches))
    if AscensionLFM.Poster and AscensionLFM.Poster.GetStatus then
        local st = AscensionLFM.Poster.GetStatus()
        if st then
            Print(string.format("repost: %s * status=%s * full=%s * countdown=%ss",
                OnOff(st.enabled), tostring(st.status or "?"),
                tostring(st.isFull), tostring(st.countdown or 0)))
        end
    end
    if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.GetDebugStatus then
        local mh = AscensionLFM.MiniHUD.GetDebugStatus()
        if mh then
            Print(string.format(
                "miniHUD: show=%s * expand=%s * mode=%s * host=%s * canWarn=%s * group=%s * canInvite=%s * watch=%d * post=%s",
                OnOff(mh.shown), OnOff(mh.expanded), tostring(mh.mode),
                OnOff(mh.hosting), OnOff(mh.canWarn), tostring(mh.group),
                OnOff(mh.canInvite), tonumber(mh.watch) or 0, tostring(mh.postChannel)
            ))
        end
    end
    Print("slash OK - /alfm UI * /alfm test")
end

local function InjectTestMatch()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        Print("Database not ready - is the addon enabled and /reload done?")
        return
    end
    local sample = "LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS"
    local parsed = AscensionLFM.Parser and AscensionLFM.Parser.Parse and AscensionLFM.Parser.Parse(sample)
    AscensionLFM.Database.PushMatch({
        leader = "TestLeader",
        text = sample,
        summary = (parsed and parsed.summary) or "MS test",
        source = "test",
        kind = "lfm",
        t = time and time() or 0,
    })
    if AscensionLFM.Activity and AscensionLFM.Activity.Push then
        AscensionLFM.Activity.Push("match", "TestLeader - MS test (test)")
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshMatches then
        pcall(AscensionLFM.MainWindow.RefreshMatches)
    end
    Print("injected test match into Log - /alfm -> Log")
end

local function SafeStart(name, fn)
    if type(fn) ~= "function" then
        return
    end
    local ok, err = pcall(fn)
    if not ok then
        Print(name .. " failed: " .. tostring(err))
    end
end

local function RegisterSlash()
    -- Re-register so Ascension / other addons cannot silently steal /alfm after load.
    SLASH_ASCENSIONLFM1 = "/alfm"
    SLASH_ASCENSIONLFM2 = "/mslfm"
    SLASH_ASCENSIONLFM3 = "/ascensionlfm"
    SLASH_ASCENSIONLFM4 = "/alfmshow"
    SlashCmdList = SlashCmdList or {}
    SlashCmdList["ASCENSIONLFM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "status" then
            PrintStatus()
            return
        end
        if msg == "diag" or msg == "debug" then
            Print("diag v" .. tostring(AscensionLFM.VERSION))
            local mods = {
                "Database", "Parser", "Slots", "SpecRole", "Queue", "Reject",
                "Invite", "Kick", "RoleCheck", "Poster", "Scanner",
                "MainWindow", "MiniHUD", "RosterPanel",
            }
            for _, m in ipairs(mods) do
                Print("  " .. m .. " = " .. (AscensionLFM[m] and "OK" or "MISSING"))
            end
            local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
            Print("  db = " .. (db and "OK" or "nil"))
            return
        end
        if msg == "test" then
            InjectTestMatch()
            return
        end
        if msg == "applyspec" or msg == "specrole" then
            if AscensionLFM.SpecRole and AscensionLFM.SpecRole.ApplyToSelf then
                AscensionLFM.SpecRole.ApplyToSelf()
            else
                Print("SpecRole module missing")
            end
            return
        end
        if msg == "mark" then
            if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.ActionAutoMark then
                AscensionLFM.MiniHUD.ActionAutoMark()
            else
                Print("MiniHUD module missing")
            end
            return
        end
        local blockName, blockReason = msg:match("^block%s+(%S+)%s*(.-)$")
        if blockName then
            if not AscensionLFM.Reject or not AscensionLFM.Reject.AddIgnore then
                Print("Reject module missing")
                return
            end
            AscensionLFM.Reject.AddIgnore(blockName, blockReason ~= "" and blockReason or nil)
            Print("Blocked " .. blockName .. (blockReason ~= "" and (" (" .. blockReason .. ")") or "")
                .. " - no future invites, private to you")
            return
        end
        local unblockName = msg:match("^unblock%s+(%S+)")
        if unblockName then
            if not AscensionLFM.Reject or not AscensionLFM.Reject.RemoveIgnore then
                Print("Reject module missing")
                return
            end
            AscensionLFM.Reject.RemoveIgnore(unblockName)
            Print("Unblocked " .. unblockName)
            return
        end
        if msg == "shame" then
            if not AscensionLFM.Reject or not AscensionLFM.Reject.GetHallOfShame then
                Print("Reject module missing")
                return
            end
            local list = AscensionLFM.Reject.GetHallOfShame()
            if #list == 0 then
                Print("Hall of shame is empty")
                return
            end
            Print("Hall of shame (" .. #list .. ", private to you):")
            for _, entry in ipairs(list) do
                local age = ""
                if entry.addedAt and type(GetTime) == "function" then
                    local days = math.floor((GetTime() - entry.addedAt) / 86400)
                    age = days > 0 and (" - " .. days .. "d ago") or " - today"
                end
                Print("  " .. tostring(entry.name) .. (entry.reason and (": " .. entry.reason) or "") .. age)
            end
            return
        end
        if msg == "debugall" then
            -- Consolidated diagnostic: opens every DragonUI-reskinned
            -- window it can (SpellBookFrame via the standard
            -- ToggleSpellBook API; AscensionLFM's own MiniHUD/
            -- MainWindow directly) and runs each one's atlas debug
            -- command. SlashCmdList is a single global table shared
            -- across ALL addons regardless of which one registered a
            -- given command - DUITSDEBUG/DUISBDEBUG (DragonUI) are
            -- reachable from here the same way ALFMHUDDEBUG/
            -- ALFMMAINDEBUG (this addon) are, no cross-addon Lua
            -- dependency needed beyond that shared table existing.
            --
            -- TradeSkillFrame is deliberately NOT force-opened: it only
            -- exists once the player is actually at a trainer or
            -- profession station, a real game-state precondition this
            -- can't fake - run /duitsdebug yourself once it's open.
            Print("Running all UI diagnostics...")

            if type(ToggleSpellBook) == "function" then
                local okOpen = pcall(ToggleSpellBook, BOOKTYPE_SPELL)
                if okOpen and type(SlashCmdList) == "table" and type(SlashCmdList["DUISBDEBUG"]) == "function" then
                    pcall(SlashCmdList["DUISBDEBUG"])
                else
                    Print("  (SpellBookFrame: couldn't open or /duisbdebug not registered - is DragonUI installed?)")
                end
            end

            if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.SetShown then
                pcall(AscensionLFM.MiniHUD.SetShown, true)
            end
            if type(SlashCmdList) == "table" and type(SlashCmdList["ALFMHUDDEBUG"]) == "function" then
                pcall(SlashCmdList["ALFMHUDDEBUG"])
            end

            if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Show then
                pcall(AscensionLFM.MainWindow.Show)
            end
            if type(SlashCmdList) == "table" and type(SlashCmdList["ALFMMAINDEBUG"]) == "function" then
                pcall(SlashCmdList["ALFMMAINDEBUG"])
            end

            if type(SlashCmdList) == "table" and type(SlashCmdList["DUITSDEBUG"]) == "function" then
                Print("  (TradeSkillFrame: not opened automatically - needs an actual trainer/profession station. Open one, then run /duitsdebug yourself.)")
            end

            Print("Done. Copy the output above (or screenshots) back for a precise pass.")
            return
        end
        if msg == "help" then
            Print("/alfm | /mslfm - toggle UI")
            Print("/alfm status | diag | test | applyspec | debugall | help")
            Print("Full Auto Hosting: /alfm -> Hosting -> master toggle (default OFF)")
            return
        end
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
            local ok, err = pcall(AscensionLFM.MainWindow.Toggle)
            if not ok then
                Print("UI error: " .. tostring(err))
                Print("Try /alfm diag * /alfm status")
            end
        else
            Print("UI module missing - folder must be Interface/AddOns/AscensionLFM/")
            Print("Then /reload. Use /alfm diag")
        end
    end
end


RegisterSlash()


local bootDone = false

local function StartModules()
    if bootDone then
        return
    end
    bootDone = true
    RegisterSlash()
    SafeStart("Database.Init", AscensionLFM.Database and AscensionLFM.Database.Init)
    SafeStart("ChatFilter.Install", AscensionLFM.ChatFilter and AscensionLFM.ChatFilter.Install)
    SafeStart("Scanner.Start", AscensionLFM.Scanner and AscensionLFM.Scanner.Start)
    SafeStart("Invite.Start", AscensionLFM.Invite and AscensionLFM.Invite.Start)
    SafeStart("Kick.Start", AscensionLFM.Kick and AscensionLFM.Kick.Start)
    SafeStart("AuraBalance.Start", AscensionLFM.AuraBalance and AscensionLFM.AuraBalance.Start)
    SafeStart("Poster.Start", AscensionLFM.Poster and AscensionLFM.Poster.Start)
    SafeStart("RoleCheck.EnsureTicker", AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.EnsureTicker)
    SafeStart("MainWindow.Init", AscensionLFM.MainWindow and AscensionLFM.MainWindow.Init)
    SafeStart("MiniHUD.Start", AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.Start)
    SafeStart("MinimapButton.Start", AscensionLFM.MinimapButton and AscensionLFM.MinimapButton.Start)
    SafeStart("LfmChatTab.Start", AscensionLFM.LfmChatTab and AscensionLFM.LfmChatTab.Start)
    SafeStart("RosterPanel.Start", AscensionLFM.RosterPanel and AscensionLFM.RosterPanel.Start)
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    local mode = (db and db.mode) or "notify"
    Print("v" .. tostring(AscensionLFM.VERSION) .. " - mode=" .. ModeLabel(mode))
    Print("/alfm * /mslfm * /alfm status * /alfm diag")
    Print("Mini HUD ON by default * Full Auto OFF * Kick59 opt-in OFF")
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AscensionLFM.ADDON_NAME then
        SafeStart("Database.Init", AscensionLFM.Database and AscensionLFM.Database.Init)
        RegisterSlash()
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        StartModules()
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
        end
        -- keep PEW once more for late /reload edge cases then drop
        if event == "PLAYER_ENTERING_WORLD" and bootDone then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
end)

-- If this file loads after login (rare), still boot.
if type(IsLoggedIn) == "function" then
    local ok, logged = pcall(IsLoggedIn)
    if ok and logged then
        StartModules()
    end
end
