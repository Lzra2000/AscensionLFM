-- AscensionLFM: core/Bootstrap.lua
-- Namespace + slash commands + ADDON_LOADED / PLAYER_LOGIN wiring.
-- Loaded LAST in AscensionLFM.toc so Database/Parser/Scanner/UI exist.

local AscensionLFM = _G.AscensionLFM
if type(AscensionLFM) ~= "table" then
    AscensionLFM = {}
    _G.AscensionLFM = AscensionLFM
end

AscensionLFM.VERSION = "0.4.18"
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
        Print("Database not ready — is the addon enabled and /reload done?")
        return
    end
    local mode = db.mode or "notify"
    Print("v" .. AscensionLFM.VERSION .. " · mode=" .. ModeLabel(mode))
    Print(string.format("Full Auto Hosting=%s · autoInvite=%s · autoRepost=%s · rejectRewhisper=%s",
        OnOff(db.fullAutoHosting), OnOff(db.autoInvite), OnOff(db.autoRepost), OnOff(db.rejectRewhisper)))
    Print(string.format("autoWhisper=%s · variants=%s · Kick59=%s · announceFull=%s",
        OnOff(db.autoWhisper), OnOff(db.useWhisperVariants ~= false),
        OnOff(db.autoKickLevel59), OnOff(db.announceFull)))
    if AscensionLFM.Kick and AscensionLFM.Kick.GetStatus then
        local ks = AscensionLFM.Kick.GetStatus()
        if ks then
            Print(string.format("kick: last=%s · can=%s · group=%s · pending=%s · hosting=%s · gaveUp=%d",
                tostring(ks.last or "?"),
                OnOff(ks.canKick),
                tostring(ks.group or "?"),
                tostring(ks.pending or 0),
                OnOff(ks.hosting),
                tonumber(ks.gaveUp) or 0))
        end
    end
    if AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.GetStatus then
        local okRc, rc = pcall(AscensionLFM.RoleCheck.GetStatus)
        if okRc and rc then
            Print(string.format("roleCheck: %s · window=%ss · autoResync=%s · autoMoveAura=%s",
                tostring(rc.status or "idle"),
                tostring(db.roleCheckWindow or db.roleCheckDuration or 60),
                OnOff(db.roleCheckAutoResync ~= false),
                OnOff(db.autoMoveAura ~= false)))
            Print(string.format("roleCheck: canWarn=%s · group=%s · hosting=%s · lastStart=%s · replies=%s",
                OnOff(rc.canWarn),
                tostring(rc.group or "?"),
                OnOff(rc.hosting),
                tostring(rc.lastStart or "?"),
                tostring(rc.responses or 0)))
        else
            Print("roleCheck: GetStatus failed — " .. tostring(rc))
        end
    else
        Print("roleCheck: MODULE MISSING — reinstall AscensionLFM.zip (RoleCheck.lua)")
    end
    Print(string.format("sounds: match=%s applicant=%s · channel=%s interval=%ss",
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
        Print("slots: " .. table.concat(bits, " · ") .. " · group " .. tostring(gsz) .. "/" .. tostring(db.maxPartySize or 15)
            .. " · unassigned=" .. tostring(unN or 0))
        if unN and unN > 0 then
            local show = {}
            for i = 1, math.min(5, #unNames) do
                table.insert(show, unNames[i])
            end
            Print("unassigned: " .. table.concat(show, ", ")
                .. (unN > 5 and (" +" .. tostring(unN - 5) .. " more") or "")
                .. " — click Mini HUD RW, have them reply T/H/A/D")
        end
    end
    local q = (type(db.applicantQueue) == "table" and #db.applicantQueue) or 0
    local act = (type(db.activityLog) == "table" and #db.activityLog) or 0
    local matches = (type(db.matchHistory) == "table" and #db.matchHistory) or 0
    Print(string.format("queue=%d · activity=%d · matches=%d", q, act, matches))
    if AscensionLFM.Poster and AscensionLFM.Poster.GetStatus then
        local st = AscensionLFM.Poster.GetStatus()
        if st then
            Print(string.format("repost: %s · status=%s · full=%s · countdown=%ss",
                OnOff(st.enabled), tostring(st.status or "?"),
                tostring(st.isFull), tostring(st.countdown or 0)))
        end
    end
    if AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.GetDebugStatus then
        local mh = AscensionLFM.MiniHUD.GetDebugStatus()
        if mh then
            Print(string.format(
                "miniHUD: show=%s · expand=%s · mode=%s · host=%s · canWarn=%s · group=%s · canInvite=%s · watch=%d · post=%s",
                OnOff(mh.shown), OnOff(mh.expanded), tostring(mh.mode),
                OnOff(mh.hosting), OnOff(mh.canWarn), tostring(mh.group),
                OnOff(mh.canInvite), tonumber(mh.watch) or 0, tostring(mh.postChannel)
            ))
        end
    end
    Print("slash OK — /alfm UI · /alfm test")
end

local function InjectTestMatch()
    local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
    if not db then
        Print("Database not ready — is the addon enabled and /reload done?")
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
        AscensionLFM.Activity.Push("match", "TestLeader — MS test (test)")
    end
    if AscensionLFM.MainWindow and AscensionLFM.MainWindow.RefreshMatches then
        pcall(AscensionLFM.MainWindow.RefreshMatches)
    end
    Print("injected test match into Log — /alfm → Log")
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
    SlashCmdList["ASCENSIONLFM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if msg == "status" then
            PrintStatus()
            return
        end
        if msg == "test" then
            InjectTestMatch()
            return
        end
        if msg == "help" then
            Print("/alfm | /mslfm — toggle UI")
            Print("/alfm status | test | help")
            Print("Full Auto Hosting: /alfm → Hosting → master toggle (default OFF)")
            return
        end
        if AscensionLFM.MainWindow and AscensionLFM.MainWindow.Toggle then
            local ok, err = pcall(AscensionLFM.MainWindow.Toggle)
            if not ok then
                Print("UI error: " .. tostring(err))
                Print("Slash still works — /alfm status · /alfm test")
            end
        else
            Print("UI module missing — check AddOns list (AscensionLFM enabled?) then /reload")
        end
    end
end

RegisterSlash()

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AscensionLFM.ADDON_NAME then
        SafeStart("Database.Init", AscensionLFM.Database and AscensionLFM.Database.Init)
        RegisterSlash()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Late-join /reload: ADDON_LOADED may have already fired before this file loaded.
        if AscensionLFM.Database and AscensionLFM.Database.Init then
            SafeStart("Database.Init", AscensionLFM.Database.Init)
        end
        RegisterSlash()
        SafeStart("Scanner.Start", AscensionLFM.Scanner and AscensionLFM.Scanner.Start)
        SafeStart("Kick.Start", AscensionLFM.Kick and AscensionLFM.Kick.Start)
        SafeStart("Poster.Start", AscensionLFM.Poster and AscensionLFM.Poster.Start)
        SafeStart("RoleCheck.EnsureTicker", AscensionLFM.RoleCheck and AscensionLFM.RoleCheck.EnsureTicker)
        SafeStart("MainWindow.Init", AscensionLFM.MainWindow and AscensionLFM.MainWindow.Init)
        SafeStart("MiniHUD.Start", AscensionLFM.MiniHUD and AscensionLFM.MiniHUD.Start)
        local db = AscensionLFM.Database and AscensionLFM.Database.Get and AscensionLFM.Database.Get()
        local mode = (db and db.mode) or "notify"
        Print("v" .. AscensionLFM.VERSION .. " — mode=" .. ModeLabel(mode))
        Print("/alfm · /mslfm · /alfm status · /alfm test")
        Print("Mini HUD ON by default · Full Auto OFF · Kick59 opt-in OFF")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
