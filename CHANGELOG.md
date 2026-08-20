# Changelog

## 0.4.109

- **AuraBalance race fix.** `Balance()` (aura-only, fired on nearly every
  roster event via Scanner/Slots) and `BalanceAll()` (tank->healer->aura,
  fired once per Role Check resync) shared one `waitingFor` settle-wait
  variable. Since `Balance()` runs far more often, a still-unsettled
  `BalanceAll()` move used to block `Balance()`'s own unrelated aura work
  too, and once settled either side could clear/overwrite the other's
  state - net effect, only the tank pass reliably applied per Role Check;
  the queued healer/aura passes had nothing to ever retry them. Split
  into separate `waitingForAura`/`waitingForAll` variables, and gave
  `BalanceAll()` an actual owner (`AuraBalance.Start()`, a 0.5s ticker
  that re-drives it while a move is pending) instead of relying on
  another Role Check to advance its queue. Regression test added and
  verified to fail against the old shared-state code before the fix.
- **RaidMarks.ClearAllMarks() no longer wipes unrelated markers.**
  Previously cleared all 8 raid-target icons unconditionally before every
  re-mark, including ones a raid leader placed by hand for an unrelated
  encounter mechanic (interrupt/kill-priority Star/Circle/Diamond etc).
  Now only clears icons from this addon's own tank/healer set
  (Skull/Cross/Square/Moon/Triangle), checked via `GetRaidTargetIndex`
  before clearing. New `tests/test_raid_marks.lua` - this module had zero
  test coverage before.
- Found via a targeted review of the four files that hadn't had a
  dedicated pass yet (`RaidMarks.lua`, `ManastormTracker.lua`,
  `Reject.lua`, a second look at `AuraBalance.lua`); `Reject.lua` had no
  real issues.

## 0.4.108

- **New: keystone-level filter.** Optional (off by default, "Min level to
  show" field in the LFG/LFM -> M+ pane, range 0-30). Once set, public
  Manastorm LFM/LFG posts that carry an explicit `[Dungeon +N]` tag
  (`Parser.ExtractKeystoneLevel`, same format `Poster.MPlusPrefix`
  produces) below the threshold are skipped entirely - no notify, no Log
  entry, no auto-whisper/auto-invite for them. Untagged posts (the vast
  majority of plain Manastorm runs) are never affected by this filter,
  since most hosts don't use the M+ tag at all and filtering those out
  too would gut the addon's core function.

## 0.4.107

- **Roster tab fixes** (found via targeted review):
  - Drag-and-drop between subgroups: releasing the mouse outside every
    card (the gutter between cards, the summary/Ready-button strip, or
    off the addon window) used to leave the drag ghost stuck following
    the cursor across the whole screen until the next roster membership
    change. A real global catch-all (`WorldFrame` `OnMouseUp` hook) now
    ends the drag on any release, matching what a stale comment already
    claimed existed.
  - Role picker and Group 1-8 picker now actually close on an outside
    click (`WorldFrame` `OnMouseDown` + `MouseIsOver`) instead of only on
    their own row-click or the next Refresh - previously they could sit
    stuck open on screen, even after switching tabs, until a roster event
    happened to fire.
  - The ⇄ subgroup-move button no longer shows on every roster row in a
    plain 5-man party, where moving between subgroups can never work (no
    subgroups exist outside a raid) - matches the gating the drag path
    already had.
  - Failed subgroup move message now also mentions missing raid rights as
    a possible cause, not just "target group may be full".

## 0.4.106

- **New: minimap icon.** Draggable button next to the minimap (ON by
  default) - left-click opens settings (same as `/alfm`), right-click
  toggles the Mini Quick HUD, hover shows current mode + session activity
  summary (`Activity.GetSessionSummary`/`FormatSessionSummary`) + a count
  of applicants still `pending` in the Queue. Small red badge shows the
  pending count at a glance without hovering. Position saved across
  sessions (`db.minimapAngle`). Toggle via Settings -> General -> Minimap
  or `/alfmminimap [on|off]`.

## 0.4.105

- **New: chat declutter filter.** Optional (off by default) - once a public
  chat line is confirmed as a genuine Manastorm LFM/LFG listing (same
  `Parser.Parse`/`isManastormListing` check the Log tab already uses), it
  can be hidden from Trade/General/Say/Yell/Guild instead of adding to the
  noise, since it's already captured in the Log tab either way. Toggle via
  Settings -> General -> Chat, or `/alfmchatfilter [on|off]`. Uses
  `ChatFrame_AddMessageEventFilter`, pcall-wrapped so a Parser error can
  never break chat entirely. Party/raid/whisper chat is untouched.
- Numerous UI/logic bugfixes from a full code review: dead `Chrome.
  SkinActionButton`/`IdentifyPiece` calls now actually implemented (every
  button was silently unstyled), Roster tab's "Ready" button no longer
  crashes on click, Roster tab's "Clear" button no longer wipes the Log
  tab's match history, LFG/LFM tab now reopens on the correct saved
  content type, migration logic no longer skipped for very old saves,
  MiniHUD collapse state no longer lost on toggle, chrome edge textures no
  longer warped, Appearance tab's Reset button now updates its own
  fields, duplicate-invite/kick-fallback/role-check-banter edge cases
  fixed. See commit history for the full list.

## 0.4.104

- **DragonUI-only chrome.** Removed WHITE8X8 gold edges from main frame,
  panels, nav buttons, and title strip when DragonUI is present. Outer
  frame uses bag-style metal nineslice (75/32) only.
- **New Appearance tab.** Full chrome configurability saved in
  `db.uiChrome`: metal on/off, topSize, bottomSize, topY, bottomY,
  leftOffset, rightOffset + reset button. Apply with `/reload`.
- Content shell inset increased so metal border stays visible.
- `/alfmchrome` suite unchanged for measuring.

## 0.4.103

- **Unified LFG/LFM into one "LFG/LFM" tab**, replacing the separate Raid
  and M+ tabs from 0.4.102. One MS/Raid/M+ toggle at the top switches
  between the three - each keeps its own settings independently (picking
  MS doesn't clear your saved M+ dungeon/level or Raid preset, it just
  stops showing/tagging with them).
  - **MS** (default): plain LFM post, no tag.
  - **Raid**: same 10/25/40-man slot-cap presets as before, now always
    tags the post `[RAID]`.
  - **M+**: same dungeon/level fields as before, tags `[Dungeon +Level]`
    when both are set.
  - New `db.contentType` ("ms"/"raid"/"mplus") is the single source of
    truth; `Poster.ContentPrefix()` resolves it to the right tag (or
    none). `Poster.BuildMessage()` takes it as an optional 5th argument -
    omitting it keeps the exact 0.4.102 behavior (plain M+ prefix logic),
    so nothing else calling it needed to change.
  - Fixed a real gap in `test_ui_smoke.lua`'s FontString mock (missing
    `SetAllPoints`/`SetWordWrap`) surfaced by this page's layout.

## 0.4.102

- **New: Raid + M+ tabs.** Two new categories in the settings sidebar:
  - **Raid** — one-click slot-cap presets for 10/25/40-man (Tank/Healer/
    Aura/DPS splits), applies via the existing `Slots.SetMax` so they're
    editable individually afterward on the Hosting tab like any other cap.
  - **M+** — dungeon name + keystone level fields. When both are set,
    automatically prepends `[Dungeon +Level]` to the LFM post (e.g.
    `[Deadmines +14] LFM MS ...`) via a new `Poster.MPlusPrefix()`, wired
    into every `Poster.BuildMessage` call site. Silent (no prefix) unless
    both fields are set - never posts `[Deadmines +0]` or `[ +14]`.

## 0.4.101

- **Regroup re-invites now retry.** Each person on the confirmed re-invite
  list gets `InviteUnit` fired 10 times back-to-back (still all inside the
  same confirmed click - no delay between attempts, since spreading them
  out over time would need a timer/OnUpdate and re-trigger the secure-call
  block from 0.4.99b). Covers the occasional invite that just doesn't land
  (brief connectivity hiccup) without needing a second manual click.

## 0.4.100

- **Regroup now requires confirmation before it disbands anything.** A
  single click on Regrp previously kicked the entire group instantly on a
  misclick. First click now only previews what would happen ("will
  disband the group and re-invite N - click again within 6s to confirm")
  and arms a 6-second window; only the second click actually warns,
  disbands, and re-invites. Someone with raid-warn but not assign/invite
  rights can still send the warning on a single click (nothing destructive
  to gate for them).
- Regrp button now has a tooltip explaining exactly what it does and how
  many people are currently on the watch list.
- `MakeBtn` (MiniHUD's button helper) gained optional tooltip support,
  reusable for future buttons.

## 0.4.99c

- **New: private "hall of shame" blocklist**, built on the existing
  reject-ignore infrastructure (which already auto-blocks future invites
  via `Invite.CanInvite`/`Scanner`) — now with a reason + date attached
  instead of a bare name. Never posted or broadcast anywhere; visible only
  to you, in your own chat/SavedVariables.
  - `/alfm block <name> [reason]`, `/alfm unblock <name>`, `/alfm shame`
    (lists everyone, most recent first, with reason and days-ago)
  - Roster: Shift+Click the kick (X) button to kick **and** block in one
    step instead of typing the name into a slash command.
- Ran the full test suite for the first time this session (it wasn't part
  of the uploaded working copy) and fixed everything it caught:
  - 26 unguarded `AscensionLFM.Chrome.X()` calls across MainWindow/MiniHUD/
    RosterPanel would crash if Chrome.lua somehow isn't loaded - all now
    guarded (`if AscensionLFM.Chrome and ...`).
  - Version was out of sync across the 3 required places (`AscensionLFM.toc`,
    `core/Bootstrap.lua`'s `VERSION`, `tests/test_toc_paths.lua`) - synced.
  - `tests/test_mini_hud.lua`, `test_ui_smoke.lua`, `test_roster_panel.lua`
    predate `ui/Chrome.lua`'s existence and didn't load it; added the
    `dofile` and the missing mock methods it needs (`SetAllPoints`,
    `SetFrameLevel`/`GetFrameLevel`, `SetBackdrop*`, `HookScript`,
    `IsAddOnLoaded` for the DragonUI-detection path).
  - `ActionRegroup`'s reinvite loop now explicitly excludes the player's
    own name (defensive - `RememberPresent` never adds it, but a test
    seeding `regroupRoster` directly, or old SavedVariables data, could).
  - New regression test: after a full disband, re-inviting past 4 people
    must call `ConvertToRaid()` first or the 5th+ invite silently never
    joins (plain party caps at 5) - verified this test actually fails
    without the fix before restoring it, per this repo's own testing
    workflow in `AGENTS.md`.

## 0.4.99b (hotfix)

- **Fixed "prevented the call of the secure function 'UNKNOWN()'"**, thrown
  by both the new Roster drag-and-drop and the paced Regroup re-invite
  queue. Root cause: WoW's secure-execution model only allows
  protected/protected-adjacent API calls (`SetRaidSubgroup`, `InviteUnit`,
  `UninviteUnit`) synchronously inside the call stack of a real hardware
  event (a click) — not from `OnUpdate`, timers, or anything deferred.
  - Drag-and-drop: dropped detection used to poll `IsMouseButtonDown` every
    `OnUpdate` tick and call `SetRaidSubgroup` from there. Rebuilt on real
    `OnMouseUp` handlers (each group card, each row, and each row's small
    buttons so a release anywhere in the drop zone is caught) — `OnUpdate`
    is now purely cosmetic (ghost position, border highlight), it never
    calls `TryMoveGroup` itself.
  - Regroup: the previous fix's paced re-invite queue (one invite per
    MiniHUD tick) hit the same wall. Reverted to firing all re-invites
    synchronously within the button click, and moved the `ConvertToRaid()`
    call (still needed after a full disband, see 0.4.99) into that same
    synchronous block instead of relying on `Invite.InvitePlayer`'s
    internal conversion — which also removes the cooldown-throttling that
    made pacing look necessary in the first place.

## 0.4.99

- **New: auto-mark tanks and healers with raid target icons.** New
  `core/RaidMarks.lua` — Skull/Cross go to the first two assigned tanks,
  Square/Moon/Triangle to the first three healers (order = whoever was
  assigned longest ago this session), matching the near-universal
  "skull = MT" raid convention instead of leaving markers unset or manual.
  New "Mark" button in the MiniHUD row and `/alfm mark`. Clears all 8
  existing markers first so a reassigned member doesn't keep a stale icon.
  Raid-only (SetRaidTarget has no equivalent group-wide meaning in a plain
  party); requires raid lead/assist like every other privileged action.

- **Window chrome nineslice edges fixed for real:** two-point anchor stretch
  (SetPoint on both ends of a texture, expecting the un-set axis to auto-size)
  turned out not to work reliably for Texture regions on this client — the
  unset axis silently fell back to the engine's 32px default regardless of
  the actual anchor gap. Edge widths/heights are now computed explicitly
  from frame size + corner offsets and hard-set via SetWidth/SetHeight.
  Fixes the gold SetBackdrop safety line showing through on both MainWindow
  and MiniHUD (compact profile was worse-hit: 48px needed, only 32px shown).
- New `ui/Chrome.lua` helpers: `HasDragonUI()`, `BackgroundPath()`,
  `ApplyClassicChrome()` — full native-Blizzard fallback (background + border
  + close button left alone) when DragonUI isn't installed, instead of the
  window rendering with only a bare 2px gold outline and nothing else.
- All 25 `UIPanelButtonTemplate` buttons across MainWindow/MiniHUD/RosterPanel
  reskinned to the addon's gold/dark chrome theme via `Chrome.SkinActionButton`
  (native grey Blizzard button look was the last visual inconsistency).
- **Roster: move members between raid subgroups.** New ⇄ button opens a
  Group 1-8 picker (`SetRaidSubgroup`); rows are also drag-and-droppable onto
  another group's card directly (manual cursor-poll drag simulation — WoW
  frames have no native HTML-style drag). Both paths share the same
  "don't trust a no-error call" verification pattern already used for kicks.
- **Regroup rewritten twice this cycle, both real bugs:**
  1. Now fully disbands the group (`UninviteUnit` on everyone but self) before
     re-inviting from a fresh snapshot, instead of only inviting people who
     were missing.
  2. That disband+reinvite bypassed `Invite.InvitePlayer` (raw `InviteUnit`
     calls), which skipped `EnsureRaidIfNeeded()` — after a full disband
     (which drops you to solo) the group never re-converted past a 5-person
     party, so anyone past the 4th re-invite silently failed. Also skipped
     `InvitePlayer`'s cooldown, so firing 15 invites in one synchronous loop
     would've had ~14 rejected by the global 3s cooldown once routed
     correctly. Fixed by queuing re-invites and draining one per MiniHUD tick
     through `Invite.InvitePlayer`, same conversion/cooldown/ignore-list
     handling as every other invite path in the addon.
  3. Watch list now ages out entries unseen for 6h (`regroupSeenAt` per
     name) instead of an unbounded FIFO that could carry names from an
     unrelated earlier raid for days.
  4. Watch list is also fully wiped on an observed solo→grouped transition
     during the session ("new group started"), not just time-based pruning —
     skipped on a reload while already mid-raid (state starts `nil`/unknown,
     not `false`, so that case isn't mistaken for a fresh group).

## 0.4.98

- **Chrome measurement toolkit for pixel-perfect nineslice tuning:**
  - `/alfmchrome` — dump MainWindow chrome pieces (size, points, texcoords, shown)
  - `/alfmchrome hud` — same for MiniHUD
  - `/alfmchromeref` — dump DragonUI metal/rock textures on ContainerFrame1 (bag reference)
  - `/alfmchromeside` — bag left + main window right for visual compare
  - `/alfmchromeprofile [full|compact]` — print current profile numbers for copy-paste

## 0.4.97

- **MainWindow no longer uses UIPanelDialogTemplate.** The template's
  baked regions and clipping kept fighting the DragonUI metal nineslice
  (border still invisible on 0.4.96 screenshots). Plain `Frame` only;
  rock + metal come entirely from `Chrome.ApplyMetalChrome`.
- **Visible gold outer edge fallback** (2px) so the window always has a
  clear border even if metal `.blp` files fail to resolve.
- Metal full profile tuned (56×56 corners, slight inset).
- Title uses `GameFontNormalLarge` + brighter gold so "AscensionLFM"
  reads clearly in the title strip.

## 0.4.96

- **Nineslice offsets moved inside the frame.** Full-profile metal corners
  used bag-style negative offsets (`leftOffset=-8`, `topY=16`) which
  sit outside the dialog bounds. On `UIPanelDialogTemplate` those pieces
  were clipped/invisible — screenshots still showed only a thin gold
  line. New full profile: 48×48 / 24 corners at offset 0 (fully inside),
  still using the real DragonUI metal atlases. Title bar FrameLevel
  raised above the chrome host so the title stays readable.

## 0.4.95

- **DragonUI nineslice drawn on elevated chrome host.** Metal border
  pieces (corners + stretched edges from `uiframemetal2x` /
  horizontal / vertical) are now created on a child host frame at
  FrameLevel+20 so they always render above content panels. Parent
  OVERLAY textures were being covered by sidebar/shell children, which
  is why the metal border looked missing on 0.4.9x screenshots. Same
  atlas/texcoords/offsets as DragonUI `RealChrome.Apply` / bags_skin
  LayoutChrome. Close button FrameLevel raised to +25. Rock BACKGROUND
  still on the main frame under content.

## 0.4.94

- **Text readability pass (light-on-dark).** Body/description colours were
  still the old parchment dark-ink values (or too dim), so labels looked
  muddy on rock panels. Raised contrast across the board:
  - `INK` → near-white cream for primary text
  - `MUTED` → brighter secondary descriptions
  - `SECTION` / `TITLE_INK` → clearer gold headers
  - `DANGER` → brighter coral for warnings
  - Nav labels stay light in both selected and idle states
  - MiniHUD status/chip and roster level text slightly brightened
- Includes the 18×18 DragonUI close button from 0.4.93 (hide template X).

## 0.4.93

- **Close (X) button resized to fit the DragonUI metal corner 1:1.**
  The UIPanelDialogTemplate close control was oversized and sat outside
  the chrome. It is now hidden; a dedicated 18×18 button uses
  DragonUI `redbutton2x` (same atlas/texcoords as bags/bank close) and
  is anchored `TOPRIGHT` (-6, -6) inside the metal corner piece.

## 0.4.92

- **Fix: DragonUI rock texture was invisible — panels looked flat brown.**
  `ApplyRockPanel` (and titleBg / roster cards) layered full-size
  WHITE8X8 textures with high-alpha vertex colours over the rock fill.
  Those overlays painted solid brown/gold on top of `ui-background-rock`,
  so the actual DragonUI texture never showed. Removed the covering
  overlays; panels now show the real rock texture with only a 1px gold
  `SetBackdrop` edge. Confirmed against live screenshot of v0.4.91.

## 0.4.91

- **Aligned with DragonUI's own `RealChrome` (from the user's DragonUI
  source package).** Added `Chrome.SkinCloseButton` using the exact
  `redbutton2x` path and texcoords from DragonUI `bags_skin.lua` /
  `chrome_shared.lua`. MainWindow skins the dialog-template close
  button after applying metal chrome. Confirmed texture set present
  under `Interface\AddOns\DragonUI\Textures\UI\` (rock, metal
  nineslice, redbutton2x). Outer frame chrome was already matching
  RealChrome.Apply profiles; this completes the close-button piece.

## 0.4.90

- **Full DragonUI skin for MainWindow content — no more parchment.**
  User request: only DragonUI elements. All previous cream/tooltip
  backdrops (`ApplyParchment`, `ApplyInset`, `ApplyToggleRow`,
  `ApplyNavButton`, sidebar) now go through a shared `ApplyRockPanel`
  helper that uses `ui-background-rock` + gold edge + dark inset —
  same language as the outer chrome / title bar / roster cards.
- **Text palette flipped to light-on-dark** (`INK` / `MUTED` / `SECTION`
  / `TITLE_INK` / `DANGER`) so labels stay readable on rock panels.
  Nav buttons use rock fill with a brighter gold edge when selected.
  Standard `UIPanelButtonTemplate` left as-is (matches DragonUI's own
  practice — no custom button atlas). Full suite green.

## 0.4.89

- **Fix: MainWindow title text was nearly invisible after the v0.4.87
  titleBg restyle.** Title/subtitle still used the parchment ink colours
  (`INK` / `MUTED` — dark brown) against the new dark rock background.
  Switched to light gold (`1.00, 0.82, 0.24` / `0.78, 0.68, 0.42`),
  matching the MiniHUD title and sidebar category labels.
- **Sidebar restyled to DragonUI rock.** `ApplySidebar` now uses the
  same rock fill + gold edge + dark inset as the outer chrome / title
  bar instead of the old dark tooltip backdrop. Category label colours
  were already light gold — no text changes needed there. Content-area
  parchment insets (`ApplyInset` / toggle rows) intentionally left
  alone: they still use dark ink on light fill for readability.
  Full suite green.

## 0.4.88

- **Roster cards + RolePicker restyled to match DragonUI chrome.** Group
  cards on the Roster tab and the role-picker popup previously used
  flat WHITE8X8 fills (cards only had a 2px gold top edge). Both now
  use the same `ui-background-rock` fill + full gold outer edge + dark
  inset language as the MainWindow title bar (v0.4.87), falling back to
  the Chrome module path when available. No behaviour change — pure
  visual consistency pass. Full suite green.

## 0.4.87

- **MainWindow title bar restyled to match DragonUI chrome.** The
  titleBg strip still used a light tooltip-style ApplyBackdrop (cream
  fill + gold edge) from before the v0.4.81 reskin, so it sat as a
  bright rectangle on top of the dark metal/rock chrome. Replaced with
  the same `ui-background-rock` texture the main frame uses, plus a
  thin gold outer edge and a dark inset — same colour language as the
  RolePicker / Roster cards, no new DragonUI atlas pieces required.
  Text colours (title ink / muted sub) unchanged. Full suite green.

## 0.4.86

- **Refactor: extract shared DragonUI chrome helper (`ui/Chrome.lua`).**
  MiniHUD and MainWindow both carried identical texture paths, atlas
  coordinate tables, `ConfigureTexture`, and `IdentifyPiece` logic
  (only the size/offset profile differed). Moved the common pieces into
  one module with named profiles (`compact` for MiniHUD, `full` for
  MainWindow). Both windows and both `/alfmhuddebug` / `/alfmmaindebug`
  diagnostics now call into `AscensionLFM.Chrome`. Behaviour and
  visual sizing are unchanged — this only removes the duplication so
  future chrome tweaks only need one edit.
  New pure unit tests in `tests/test_chrome.lua` (IdentifyPiece match/
  miss, both profiles, nil-safe ApplyMetalChrome). toc load order:
  Chrome before MiniHUD/MainWindow. Full suite green.

## 0.4.85

- **Collapsed MiniHUD now shows a leader-icon instead of "ALFM" text.**
  Aesthetic request: an icon reads cleaner than an abbreviated text
  label at the collapsed 56x28 size. Uses
  `Interface\GroupFrame\UI-Group-LeaderIcon` - the standard raid-leader
  crown icon, thematically fitting next to the "HOST" status this addon
  already shows. `SetExpanded()` now hides the title/chip text and
  shows the icon when collapsing, and the reverse when expanding
  (previously it just swapped the title text between "AscensionLFM"
  and "ALFM" - the chip text ("HOST") was left showing at the same time
  in both states, which is now also hidden while collapsed to keep the
  tiny collapsed view uncluttered).
  New regression tests (7 checks) verifying the icon/text visibility
  correctly flips both directions - confirmed the tests genuinely catch
  a reverted fix (temporarily disabled, watched it fail, restored).
  Test mock fixes: CreateFontString's Show/Hide/IsShown now track real
  state (previously no-ops with no IsShown at all - would have made
  this exact test impossible to write correctly).
  Full suite green (76 checks in test_mini_hud.lua, up from 69).

## 0.4.84

- **Fixed: status line ("T x/x H x/x A x/x D x/x") overlapped the
  DragonUI bottom chrome corners on MiniHUD.** Confirmed via a live
  screenshot. `statusFS` was anchored 8px in from each bottom corner;
  the v0.4.79 bottom-corner chrome pieces (16x16, offset slightly
  outside the frame edge) occupy roughly the first ~10px near each
  bottom corner both horizontally and vertically, so 8px wasn't enough
  clearance. Pushed the anchor to 18px in on both sides.
  Also checked the top corners (30x30, larger than the bottom ones) for
  the same category of issue against the title/HOST chip text - the
  screenshot didn't show a problem there, and since the corner's actual
  visible art is likely smaller than its full bounding box, this wasn't
  touched without concrete evidence it's actually broken (matching this
  session's "measure, don't guess" rule for DragonUI chrome work).
  Full suite green.

## 0.4.83

- **New: `/alfm debugall`** - consolidated diagnostic that opens every
  DragonUI-reskinned window it reasonably can and runs each one's atlas
  debug command in sequence, instead of running four separate commands
  by hand (`/duitsdebug`, `/duisbdebug`, `/alfmhuddebug`,
  `/alfmmaindebug`). Opens SpellBookFrame via the standard
  `ToggleSpellBook(BOOKTYPE_SPELL)` API and this addon's own MiniHUD/
  MainWindow directly, then calls each window's registered debug
  command. Works across the DragonUI/AscensionLFM addon boundary
  because `SlashCmdList` is a single global table shared by every
  addon regardless of which one registered a given command - no
  Lua-level dependency beyond that table existing.
  TradeSkillFrame is deliberately NOT force-opened: it only exists once
  the player is genuinely at a trainer or profession station, a real
  game-state precondition that can't be faked - prints a note to open
  one and run `/duitsdebug` manually instead of pretending to handle it.
  Full suite green.

## 0.4.82

- **Fixed: collapsed MiniHUD had oversized DragonUI border pieces.**
  Confirmed via a live `/alfmhuddebug` report this session: the
  collapsed MiniHUD actually resizes the frame to 56x28 (not just
  hides child content) - the v0.4.79 DragonUI chrome border pieces
  (30x30 corners etc.) are fixed-size textures that don't auto-shrink
  with the frame, so left visible at 56x28 they'd be wider than the
  entire collapsed HUD. `SetExpanded()` now hides all 8 chrome border
  pieces when collapsing and shows them again when expanding. The
  background texture didn't need the same fix - it's anchored via
  `SetAllPoints`, so it already correctly auto-adjusts to whatever size
  the frame becomes.
  New test hooks `MiniHUD._SetExpanded` / `MiniHUD._GetFrame`, and a
  regression test in test_mini_hud.lua (4 new checks) verifying the
  chrome pieces actually hide on collapse and show on expand -
  confirmed the test genuinely catches the regression by temporarily
  reverting the fix and watching it fail, then restoring. Test mock
  fix: CreateTexture's Show/Hide/IsShown now track real state instead
  of IsShown always reporting true regardless of calls (would have
  made this exact regression test a false-positive pass).
  Full suite green (69 checks in test_mini_hud.lua, up from 65).

## 0.4.81

- **Main window reskinned with real DragonUI assets** (same approach as
  v0.4.79's MiniHUD). `CreateMainFrame()`'s vanilla texture regions
  (from `UIPanelDialogTemplate`, or the manual `UI-DialogBox-Background`/
  `-Border` SetBackdrop fallback if that template failed to create) are
  neutered - same Show->Hide override technique as DragonUI's own
  characterpanel/chrome.lua - then DragonUI's real metal nineslice
  border + `ui-background-rock` background are layered on top, full-size
  profile (75/75/32, same as DragonUI's own bag/bank windows and this
  session's TradeSkillFrame/SpellBookFrame reskins - 760x600 is well
  within the size range that was confirmed for). Full-path texture
  references again (`Interface\AddOns\DragonUI\Textures\...`), no
  Lua-level dependency on DragonUI.
  Scope, honestly: only the main frame's own background/border. The
  titleBg sub-frame (already has its own non-vanilla custom styling,
  untouched), individual buttons across all 8 category pages (General/
  Seeking/Hosting/Post/Queue/Roster/Kick/Log - left on
  UIPanelButtonTemplate, matching DragonUI's own practice per v0.4.79's
  reasoning), and the separate Roster sub-panel window weren't converted
  in this pass - reskinning every individual element across a 2200+ line
  file in one shot without live verification at each step isn't
  something to attempt responsibly.
  New `/alfmmaindebug` diagnostic, same texcoord + atlas-piece-
  identification approach as `/alfmhuddebug` (v0.4.80).
  test_ui_smoke.lua's CreateTexture mock gained SetAlpha/GetObjectType/
  GetWidth/GetHeight/GetPoint/IsShown (needed by the new chrome code).
  Full suite green.

## 0.4.80

- **`/alfmhuddebug` upgraded: reports texcoords and auto-identifies
  known DragonUI atlas pieces.** Same generalized diagnostic approach
  built into DragonUI's own `RealChrome.Debug` this session (a shared
  function DragonUI's tradeskill_skin.lua/spellbook_skin.lua now both
  call instead of each keeping a separate duplicated debug command) -
  duplicated here rather than shared, since AscensionLFM is a separate
  addon with no Lua-level access to DragonUI's module table. Each
  texture region's `GetTexCoord()` is read (handling both the 4-value
  and 8-value quad return forms WoW's API can give back) and matched
  against every DragonUI atlas piece confirmed this session
  (uiframemetal2x's 4 corners, uiframemetalhorizontal2x/vertical2x's
  edges) - so the output can say e.g. "-> topLeft (uiframemetal2x)"
  next to a region instead of just raw numbers to cross-reference by
  hand. Honest framing, matching this session's DragonUI work: this is
  a measurement tool, not a guarantee - still needs a screenshot
  alongside it and a follow-up pass to actually confirm a fix landed
  right.
  Both the texcoord-parsing (4-value vs 8-value quad form) and the
  piece-identification matching were unit-tested in isolation before
  being wired in. Full suite green (mock gap for GetTexCoord not
  needed - the code's own defensive `if region.GetTexCoord then` check
  already handles a mock without it correctly, confirmed by the
  existing test passing unmodified).

## 0.4.79

- **MiniHUD reskinned to use real DragonUI assets.** Replaced the
  generic Blizzard `UI-DialogBox-Background`/`UI-DialogBox-Background-
  Dark` textures with DragonUI's own real metal nineslice border +
  `ui-background-rock` background - the exact same texture paths and
  atlas coordinates confirmed this session for DragonUI's own bag/bank
  windows (`bags_skin.lua`) and the DragonUI addon's TradeSkillFrame/
  SpellBookFrame reskins. Since AscensionLFM is a separate addon from
  DragonUI, these are referenced by their full
  `Interface\AddOns\DragonUI\Textures\...` path rather than through any
  DragonUI Lua call - only needs the texture files to exist on disk (DragonUI installed), not any
  timing/load-order dependency on DragonUI's own code having run yet.
  Scaled down further than even DragonUI's own "compact" nineslice
  profile (30/30/16 vs DragonUI's compact 52/52/24) since the MiniHUD
  is only 86px tall - DragonUI's compact sizing was tuned for taller
  windows and would have had the top/bottom corner pieces overlapping
  at this frame's actual height.
  Action buttons (LFM/RW/Sync/Wipe/Mobs/FULL/Regrp/T/H/A/D/Rost/RC) are
  left on `UIPanelButtonTemplate` - DragonUI has no universal custom
  button texture of its own (confirmed: DragonUI's own editor_mode.lua
  uses this same template for some of its own buttons), so this matches
  what DragonUI itself does rather than inventing a mismatched style.
  New `/alfmhuddebug` diagnostic (same pattern as DragonUI's own
  `/duitsdebug`/`/duisbdebug` from this session) dumps the live frame's
  actual texture region sizes/positions/shown-state, since the sizing
  above is a proportional estimate, not measured against a real render.
  Test mock gaps fixed in test_mini_hud.lua: CreateTexture's mock gained
  SetAlpha/SetSize/SetTexCoord/GetWidth/GetHeight/GetPoint/
  GetObjectType/GetTexture (needed by the new chrome code), and the
  frame mock gained GetRegions. Full suite green.

## 0.4.78

- **Removed: automated Aura of Experience buff scanning (AuraScan.lua,
  introduced during external reconciliation, v0.4.44-v0.4.68 batch).**
  Deliberate decision, not a bug fix: despite genuine effort across this
  whole session (checking Ascension's own nameplate buff-display code,
  CompactRaidFrames, and even AscensionLogsCompanion's full combat-log/
  inspect pipeline for a better technique), there is no reliable way to
  read another player's buffs at range on this client - the underlying
  `UnitAura` limitation AuraScan.lua's warn-then-verify-via-roster
  workaround existed for in the first place couldn't be improved on
  further. Rather than keep a feature that only partially works and
  needs a fragile workaround, it's removed entirely:
  - Deleted `core/AuraScan.lua` and `tests/test_aura_scan.lua`.
  - Removed its two toggles, "Scan now" button, and reliability-note
    label from the Kick tab; "Recent kicks" now sits directly under
    the level-59 auto-kick toggle. Kick tab content height reduced
    520 -> 300 to match (no more empty space where the removed section
    used to be).
  - Removed `/alfm aurascan`, its `diag` module-list entry, its
    `/alfm status` line, and its `Start()` call from Bootstrap.lua.
  - Removed the now-unused `auraScanEnabled` / `auraScanAutoKick` /
    `auraScanInterval` / `auraScanWarnInterval` DEFAULTS entries from
    Database.lua. The historical `rev < 6` migration step that zeroed
    the first two is left untouched (harmless no-op now, but migration
    chains shouldn't be edited retroactively).
  **What's unchanged, on purpose:** "aura" remains a fully first-class
  role everywhere else - whisper-based self-report still auto-invites
  aura-role applicants exactly as before (Parser.lua/Invite.lua/
  RoleCheck.lua untouched), and RosterPanel's role picker already lets
  a host manually assign/reassign anyone to the aura seat by clicking
  their role icon (`roles = { "tank", "healer", "aura", "dps", "" }`,
  pre-existing, not new) - manual aura-seat management was already
  fully supported before this change, nothing new needed there.
  Full suite green (test_aura_scan.lua's 20-some checks removed with
  the module; everything else passes unmodified).

## 0.4.77

- **New: Manastorm level clears/failures now feed into the Session
  Summary (v0.4.73).** New module `core/ManastormTracker.lua` listens
  for `MANASTORM_LEVEL_COMPLETED` and `MANASTORM_FAILED` - both
  confirmed real events, verified directly against Ascension's own
  AscensionLogsCompanion addon source (`Capture/ManastormScan.lua`,
  provided this session), which documents `MANASTORM_LEVEL_COMPLETED`
  firing once per level cleared (a1 = level number) and
  `MANASTORM_FAILED` on a wipe/ejection. The Log tab's session summary
  line now reads e.g. "Session (1h12m): 8 invited, 2 rejected, 1
  kicked, 6 matches, 3 posts, 4 levels cleared, 1 failed" - only
  appending the level-stats clause when there's something to show, so
  it stays quiet on non-CoA server variants (Bronzebeard/Epoch) where
  these events never fire (per that same source: "C_Manastorm is
  absent on Bronzebeard/Epoch" - confirmed CoA-only).
  Considered but did NOT build: switching Invite.lua/Poster.lua's
  pause-during-instance check from polling to reacting to
  `ACTIVE_MANASTORM_UPDATED` for instant resume the moment a host
  leaves - both already tick every 0.5s, so an event-driven switch
  would save at most 0.5s of latency, not worth the added complexity.
  Regression tests in new tests/test_manastorm_tracker.lua (15 checks):
  pure formatters, Activity.Push wiring, stacking across multiple
  clears, graceful no-op with a broken/missing Activity module, and
  FormatSessionSummary's zero-vs-non-zero append behavior. Full suite
  green.

## 0.4.76

- **Improved: "pause hosting while in instance" (v0.4.71) now uses the
  precise Manastorm-specific signal instead of a generic instance check.**
  Verified against Ascension's own client source (FrameXML/SharedXML,
  provided directly): `C_Manastorm.IsInManastorm()` is a real API, used
  throughout Ascension's own code for exactly this kind of state check
  (`ManastormUtil.lua`, `Minimap.lua`, `UIParent.lua`, `StaticPopup.lua`).
  Both `Invite.lua`'s `IsHostInsideInstance()` and `Poster.lua`'s
  equivalent check now prefer it over the generic `IsInInstance()` -
  which used to pause hosting for *any* instance the host stepped into,
  not just Manastorm itself. A host briefly ducking into an unrelated
  dungeon between hosting sessions no longer has auto-invite/auto-repost
  needlessly paused; falls back to `IsInInstance()` if `C_Manastorm`
  isn't available for any reason (defensive, matching this addon's
  established pattern of never assuming an API exists without checking).
  Also cross-checked `IsInInstance()`'s own usage pattern (`local
  inInstance, instanceType = IsInInstance()`) against Ascension's actual
  `PVPQueueButtonMixin:UpdateDisableReason` and `Atr_ContainerFrameItemButton_OnClick`'s
  hooked Blizzard functions (`ContainerFrameItemButton_OnClick`/
  `_OnModifiedClick`) from the Auctionator work - both confirmed to
  match exactly what was already assumed, no further changes needed
  there.
  Regression tests added to test_invite.lua and test_poster.lua:
  `C_Manastorm.IsInManastorm() == false` while `IsInInstance()` is true
  correctly does NOT pause (unrelated instance); `IsInManastorm() ==
  true` correctly does pause, taking priority over the generic check.
  Full suite green.

## 0.4.75

- **Fix: Roster tab's manual kick button trusted a successful
  `UninviteUnit` call as proof the removal actually happened.** Found
  while auditing `ui/RosterPanel.lua`'s interactive functions (built
  during the v0.4.66-v0.4.69 reconciliation, not yet reviewed at this
  level of detail). Same "no Lua error != it worked" trap already fixed
  for Kick59 (v0.4.28) and built correctly into AuraScan.lua's warn/kick
  cycle from the start — `UninviteUnit` is fire-and-forget and can
  silently no-op (privilege edge case, target in combat, etc.) without
  ever throwing, so `pcall(UninviteUnit, name)` succeeding is not proof
  of anything. The Roster panel's kick button printed "Roster: removing
  X" unconditionally right after the call, with no verification at all.
  Fixed with a lightweight deferred check (no full retry/give-up cycle
  needed — this is a manual one-off click, not an automated cycle; a
  human can just click again): `TryKick()` now schedules a check
  ~1.5s later via the panel's existing periodic ticker (moved out from
  under its 2s display-refresh throttle so the kick check itself isn't
  needlessly delayed), re-scans the live roster, and only then reports
  either a clean "removed" confirmation or an honest "still in group -
  try again (may lack privilege, or they're in combat)" — never a false
  positive.
  Regression tests added to test_roster_panel.lua: the immediate call
  doesn't confirm anything, checking before the delay elapses stays
  pending, a target still present at the delay gets the honest
  "still in group" message (not silently confirmed), and a target that
  genuinely left gets a clean "removed" confirmation with the exact
  message content verified both ways. Full suite green.

## 0.4.74

- **Global readability pass: every text color re-checked for contrast,
  several backdrops made fully opaque.** Reported live: all UI text hard
  to read / slightly overlapping. Root cause wasn't positioning this
  time - it was contrast. Two separate issues:
  1. The main window uses Blizzard's native `UIPanelDialogTemplate` for
     its outer chrome (title/subtitle sit directly on it, no backdrop of
     our own). This addon's user is running DragonUI (a UI-replacement
     addon, confirmed present in an earlier session log) - if it reskins
     native dialog templates with a different color scheme than
     Blizzard's stock light-tan header, our text colors (chosen assuming
     the stock look) can end up low-contrast against whatever DragonUI
     actually renders there, and there's no way to predict or control
     that from inside this addon. Fixed by no longer trusting the native
     template's coloring at all: added our own opaque cream backdrop
     plate specifically behind the title + subtitle, guaranteeing
     consistent contrast regardless of what any other addon has reskinned.
  2. `ApplyInset`/`ApplyToggleRow` - the backdrop used by nearly every
     content box and toggle row across every tab - were only 55% opaque,
     meaning their effective color blends with whatever's rendered behind
     the window in the game world at that moment. Bumped both to 92%
     opacity for a reliable, predictable light-cream background
     everywhere text is meant to sit.
  With a now-guaranteed light backdrop, re-checked every text color's
  actual contrast against it (rough luminance-based estimate, targeting
  WCAG AA's ~4.5:1 minimum) and darkened the ones that were still
  borderline-to-poor even against a solid light background:
  - `MUTED` (used for nearly all toggle descriptions, status lines, and
    hints across the whole UI - the single most impactful color in this
    pass): 0.35/0.28/0.18 (~2.8:1) -> 0.20/0.15/0.08 (~5:1).
  - `SECTION` (every category/section header, e.g. "AUTO-REPOST"):
    0.42/0.30/0.10 (~2.6:1) -> 0.24/0.15/0.04 (~4.4:1).
  - `DANGER` (red warning-style toggle titles): 0.55/0.18/0.08 (~2.9:1)
    -> 0.42/0.10/0.04 (~4:1).
  - Toggle row titles (every "Enable X" / "Auto-invite Y" label) used
    their own hardcoded inline color independent of the shared
    constants - replaced with `INK` (already the darkest/most legible
    color) instead of duplicating a separate, undermaintained value.
  - `categoryHeadSub` (the one-line description under each tab's own
    header) was borderline (~3.4:1) - now uses `MUTED`.
  - Found a genuine light-on-light bug along the way: the Kick tab's
    Aura-reliability status text (`auraRelFS`) used a *light* tan color
    (0.85/0.75/0.45) while sitting on the same light page background as
    everything else - likely near-invisible in practice, not just
    "hard to read". Changed to a dark, readable color.
  Left the sidebar category-nav buttons alone - already correctly
  swapping between dark text on a light selected-button background and
  light text on a dark unselected-button background, verified both
  ways have good contrast.
  `GOLD` is no longer referenced (previously only used for the title,
  which now uses `INK` against its own guaranteed-light backdrop) - left
  defined in case a future dark-backdrop element wants a bright accent
  color, rather than removing a working, harmless unused constant.
  Fixed two real gaps in the UI smoke-test mock along the way
  (`CreateFontString`'s mock was missing `ClearAllPoints`/`SetParent`/
  `SetDrawLayer` - real WoW FontStrings have all three). Full suite
  green; this class of change (color/contrast) isn't independently
  verifiable by the Lua unit test harness beyond "doesn't crash," so no
  new behavioral tests were added - only fixed what broke from the mock
  additions.

## 0.4.73

- **New: session summary in the Log tab.** `activityLog` (the rolling
  recent-activity list) is deliberately capped at 40 entries — fine for
  a scrollback view, but useless for "how did this session go" given the
  applicant volumes seen in busy hosting logs this whole session (dozens
  per minute easily blow past 40 within a couple minutes). Added
  separate, uncapped session counters in `core/Activity.lua`:
  `Activity.Push()` (the single choke-point every meaningful event
  already passes through) now also increments a per-kind counter in
  `db.sessionStats`, alongside the existing bounded log — no new call
  sites needed anywhere else. New `Activity.GetSessionSummary()`,
  `Activity.FormatSessionSummary()` (kept pure/testable, separate from
  the DB/clock-reading getter), and `Activity.ResetSession()` (clears
  counters + restarts the elapsed-time clock, leaves the rolling log
  untouched).
  Log tab gained a "Session summary" section between Recent matches and
  Activity, e.g. "Session (47m): 23 invited, 4 rejected, 2 kicked, 15
  matches, 3 posts", plus a "Reset session" button.
  Found and fixed a real gap while wiring this up: `core/AuraScan.lua`'s
  kick confirmation only ever logged to its own `kickHistory` table
  (used by the Kick tab's recent-kicks list) and never called
  `Activity.Push` at all — meaning Aura-of-Experience-liar kicks had
  zero activity trail and would never have counted toward "kicked" in
  the new summary. Now pushes `kind="kick"` like Kick59's kicks already
  did.
  Regression tests added: new `test_activity.lua` (20 checks - rolling
  log stays capped, session counters stay accurate well past 40 events,
  `FormatSessionSummary`'s hour/minute formatting and ASCII-only output,
  `ResetSession` clearing counters without touching the rolling log, and
  counting correctly resuming afterward). `test_aura_scan.lua` gained a
  check confirming the confirmed-kick path now reaches Activity. Full
  suite green.

## 0.4.72

- **Fix: v0.4.70's Post tab overlap fix was itself wrong.** Reported live
  via screenshot - still overlapping after the "fix". Root cause: my own
  pixel-math error, not anything in the external code. I verified every
  Hosting/Post tab layout change this session against `TOGGLE_ROW_H = 58`
  and `TOGGLE_STEP = 68` - but the actual constants in this codebase are
  `TOGGLE_ROW_H = 66` and `TOGGLE_STEP = 74`. v0.4.70's hardcoded fix
  (`intLbl` at literal `-474` etc.) was computed externally with the
  wrong numbers, leaving only a 4px gap in reality instead of the
  intended 12px - visually indistinguishable from no gap at all.
  Fixed properly this time: replaced the hardcoded literals with a real
  relative calculation (`postToggleBottom = -268 - TOGGLE_STEP*2 -
  TOGGLE_ROW_H`, then `intY = postToggleBottom - 12`, with
  `postStatusFS`/`postHint` positioned relative to `intY`) using the
  actual Lua constants directly rather than numbers computed by hand
  outside the file - this eliminates the whole bug class for this
  section permanently, since it can never drift out of sync with
  `TOGGLE_ROW_H`/`TOGGLE_STEP` again even if those change later.
  Audited the rest of this session's toggle-stacking work (v0.4.22/24/
  35/37/43/71's Hosting tab insertions) for the same mistake: all of it
  already referenced `TOGGLE_ROW_H`/`TOGGLE_STEP` symbolically rather
  than hardcoding computed numbers, so it was correct at runtime the
  whole time despite my verification scripts having used the wrong
  constants - only the Post tab used literal hardcoded numbers, and
  that's now fixed the same permanent way.
  `contentHeight` re-verified against the real constants (needs >=614,
  already at 620 - no change needed). Full suite green (no test changes
  needed - this class of bug isn't visible to the Lua unit test harness,
  which doesn't render layout; caught only by an actual screenshot).

## 0.4.71

- **New: pause the complete hosting automation while inside the
  instance** (not just the LFG-chat scan, as v0.4.27 did). A fresh
  invite can't meaningfully join a Manastorm run already underway, and
  re-advertising an LFM you're already deep into doesn't help anyone —
  so both `Invite.TryHostInvite` (direct whisper applications) and
  `Poster.Tick` (LFM auto-repost) now pause while `IsInInstance()`
  reports true. This broadens v0.4.27's original decision, which
  deliberately left whisper invites unaffected — reconsidered because a
  whisper invite mid-run has limited practical value anyway.
  Two new toggles (both default ON, in the Hosting tab's "Invite +
  reject" section): "Pause auto-invite while inside the instance" and
  "Pause LFM auto-repost while inside the instance" — a host who
  genuinely wants either to keep working mid-run can opt back in.
  Paused applicants are still queued (reason "host in instance") so the
  host can see and manually invite them via the Queue tab once back in
  town. Kick59, AuraScan, and RoleCheck are deliberately unaffected —
  those manage the existing raid regardless of whether new applicants
  can join.
  Layout note: inserted using this section's existing running-offset
  (`hy = hy - TOGGLE_STEP`) pattern rather than hardcoded Y positions,
  so everything below cascaded correctly without a manual per-element
  recalculation — verified anyway by hand-tracing the full chain down to
  the deepest element (needs >=1428px, set to 1510 for real headroom),
  given the exact class of bug just fixed in v0.4.70.
  Regression tests added to test_invite.lua (whisper invite paused in
  instance, toggle-off override, normal operation outside) and
  test_poster.lua (repost paused in instance, toggle-off override,
  normal operation outside).

## 0.4.70

- **Fix: real overlap bug in the Post tab, found via screenshot.** The
  v0.4.66/69 reconciliation brought in a new "LFM shows filled roles too"
  toggle (`postShowAllRoles`) in `ui/MainWindow.lua`, inserted as a third
  toggle row in the Auto-repost section — but everything below it
  (Interval field, role-check status line, the example hint text) was
  still hardcoded at its old Y position, landing squarely inside the new
  toggle's row. This is exactly the class of bug this session has hit
  and fixed several times before (v0.4.22/24/35/37/43 in the Hosting
  tab) — but this time it slipped through because the large 478-line
  `MainWindow.lua` diff from the v0.4.66 upload was accepted based on
  the UI otherwise looking coherent, without the same per-row pixel-math
  verification given to every toggle insertion done directly in this
  session. Recomputed the full Post-tab layout below the toggle section
  (same method as every prior overlap fix — precise top/bottom pixel
  accounting, verified zero negative gaps) and shifted the Interval
  field, `postStatusFS`, and the example hint down by one toggle row
  height; bumped the tab's `contentHeight` 560 -> 620 for real scroll
  headroom.
  Also verified `postShowAllRoles`'s actual behavior while looking at
  this: correctly implemented as an opt-in `BuildMessage(snapshot,
  showAll)` second argument, defaulting falsy so the v0.4.29 "only show
  open roles" behavior is unchanged unless a host explicitly turns it
  on — no functional regression, just the missing test coverage and the
  layout bug. Regression tests added to test_poster.lua (default/
  showAll=false/showAll=true, and disabled roles staying hidden even
  with showAll=true).

## 0.4.69

- **Reconciliation pass 2: merged a smaller external "stability-ui"
  update (v0.4.68) that continued from the *original* v0.4.66 baseline
  (not the v0.4.67 reconciliation above), so several of that pass's
  fixes needed re-applying on top. Diffed every file against v0.4.67
  first — most were byte-identical, confirming the earlier reconciliation
  was accurate.
  - **New: German applicant phrasing recognized as role negation**
    (`core/Parser.lua`'s `NegatedRoles`) — "DPS ohne Aura" ("without
    Aura"), "keine Aura"/"kein Tank" ("no Aura"/"no Tank"). Found and
    fixed a real gap while adding test coverage: the shipped pattern's
    own comment claimed it covered "kein/keine/keinen", but the actual
    regex only matched an optional single extra letter, missing "keinen"
    entirely — the correct German accusative for masculine nouns like
    "Heiler"/"Tank" (i.e. "keinen Heiler" is how a German speaker would
    naturally phrase "no healer" as a direct object). Replaced with three
    explicit endings (kein/keine/keinen); "keinerlei" still correctly
    does not false-match.
  - **Improved: `core/Invite.lua`'s cooldown-retry queue** (from this
    project's own v0.4.38) gained a `MAX_RETRY_ATTEMPTS` cap (3, then
    gives up loudly instead of retrying a blocked applicant forever) and
    de-duplication (a `CHAT_MSG` event firing twice for the same sender
    before the first retry executes no longer double-queues them) — two
    real gaps in the original design.
  - **Improved: `core/AuraScan.lua`'s combat-log argument-layout
    detection** refined from further live testing against Ascension's
    exact `COMBAT_LOG_EVENT_UNFILTERED` argument ordering (narrowed a
    `boolean or number` type check to `boolean` only, and corrected the
    resulting index shift), and `core/Scanner.lua`'s Seeking-mode
    follow-up auto-reply gained a 3s per-host cooldown so a chatty/looping
    host bot asking several questions in immediate succession can't cause
    reply spam.
  - **UI: `ui/MiniHUD.lua`** Quick HUD buttons and frame sizing increased
    slightly (each button +2-8px, frame 380x72→440x86 and
    420x78→440x86) — addresses real visual cramping, self-contained
    widget with its own frame, no interaction with the carefully
    pixel-verified MainWindow tab layouts.
  - Re-applied from the v0.4.67 pass (this branch continued from before
    it): the em-dash stock-message migration fix (this time for *both*
    affected migration steps, rev<4 and rev<5 — the rev<4 one was missed
    in the first pass), the `AuraScan.Start()` indentation cleanup, and
    `SpecRole._MatchRole`'s test-only export.
  - Test coverage added: `test_parser.lua` gained a full `NegatedRoles`
    section (18 checks: English + German phrasing, the "keinerlei"
    false-match guard, multiple negations in one message). `test_invite.lua`
    gained retry-cap and duplicate-queue regression checks.
    `test_v040_auto.lua`'s existing follow-up-reply tests needed a
    time-advance between steps to clear the new 3s cooldown, plus a
    dedicated regression test for the cooldown itself. Full suite green.

## 0.4.67

- **Reconciliation pass: merged a large batch of external work (v0.4.44-
  v0.4.66) developed outside this session's git history back into the
  tracked codebase, with full regression testing.** A v0.4.66 build was
  provided as a zip with no corresponding git commits and no test suite
  included. Rather than trust or discard it wholesale, every changed file
  was diffed against our last tracked state (v0.4.43), our full test
  suite was run against the new code, and every difference was
  individually verified as either a genuine improvement, a real bug, or
  a test that needed updating for legitimately new behavior:
  - **New: Aura of Experience verification (`core/AuraScan.lua`).**
    Detects who is genuinely wearing the Aura of Experience buff
    (spell 818059, confirmed via the real 3.3.5a `UnitAura` API) versus
    who merely claimed the "aura" role. Critically, this does **not**
    naively trust `UnitAura` on other players — live testing found
    Ascension often doesn't expose other players' buffs to `UnitAura`
    at all, which would make every "no buff visible" read a false
    positive. Detection only activates once the buff has actually been
    *proven* visible on at least one other party/raid member this
    session (via `UnitAura` and/or a `COMBAT_LOG_EVENT_UNFILTERED`
    mirror for spell 818059, handling multiple observed Ascension CLEU
    argument layouts) — otherwise it stays silently idle rather than
    accusing anyone. When it does act: warn first, defer, then verify
    the target actually left the roster before logging a kick (the same
    "don't trust a successful API call as proof" lesson from Kick59's
    v0.4.28 fix) — plus an `IsInCombat()` check deferring kicks during
    combat, where `UninviteUnit` is unreliable on Ascension. Defaults
    fully OFF (`auraScanEnabled`/`auraScanAutoKick`), matching Kick59's
    safety model. New `defaultsRev` 5→6 migration sets both to `false`
    for upgrading users.
  - **New: spec-based role guess (`core/SpecRole.lua`).** Best-effort
    role suggestion from the host's own active Ascension specialization
    or (classic 3.3.5a fallback) highest-invested talent tab, as a
    supplementary signal alongside the existing whisper self-report
    system. Fails soft (returns nil) if neither API is available —
    never blocks or overrides the whisper-based flow.
  - **New: Roster panel (`ui/RosterPanel.lua`).** Card-style raid-group
    overview (per-subgroup role icons/colors, T/H/A/D + online/total/
    unknown summary line), a new tab in the main window.
  - **Improved: "prefer support seat" near-full-raid logic** (originally
    v0.4.19) now only holds a DPS applicant back when a support-role
    applicant is *actually waiting in the queue* — previously it held
    every near-full DPS request regardless, which could leave a seat
    empty forever if nobody ever applied for the open support role.
  - **Robustness: ASCII-only user-facing strings.** Em-dashes (—) and
    middle-dots (·) throughout the codebase (chat messages, status text,
    comments) were normalized to plain hyphens/asterisks, avoiding any
    encoding-related risk in the WoW chat/Lua environment across
    different editors/OSes.
  - **`core/Kick.lua`:** added a Combat check (`IsInCombat` via
    `InCombatLockdown`/`UnitAffectingCombat`) before attempting a kick —
    live testing found `UninviteUnit` often silently no-ops while either
    party is in combat inside Manastorm — and a `sessionIgnore` set
    blocking re-invite of someone just kicked this session.
  - Window resized 720x560 → 760x600 for the new Roster tab.
  - `INSTALL.txt` gained a dedicated "Loaded: Incompatible" troubleshooting
    section (diagnosed via the new `/alfm diag` command, which lists every
    module as OK/MISSING) — merged with the existing bilingual EN/DE
    quick-start rather than replacing it.

  **Bugs found and fixed during reconciliation:**
  - The rev<5 stock-RW-message migration's `oldMsgs` lookup only matched
    the new hyphen variant of old stock messages, not the em-dash variant
    real upgrading users' SavedVariables still contain from before the
    ASCII-normalization above — meaning genuine upgraders would never get
    migrated. Added the em-dash variants back to the lookup table.
  - A stray indentation-only formatting slip in `AuraScan.Start()`'s
    `RegisterEvent` calls (cosmetic, no functional effect, cleaned up).
  - `SpecRole.lua`'s local `MatchRole` helper exposed as `SpecRole._MatchRole`
    for direct unit testing, matching this codebase's established
    pure-function-testability convention.

  **Test coverage added/updated** (full suite green, 17 files): new
  `test_aura_scan.lua` (33 checks: pure `SelectLiars`/`BuildWarnMessage`,
  the "never accuse until proven visible" safety gate across multiple
  ticks, combat-log parsing across argument layouts, and the complete
  warn→verify→kicked cycle including a still-present false-attempt and a
  genuine-departure success case), new `test_spec_role.lua` (26 checks),
  new `test_roster_panel.lua` (28 checks: `BuildData`'s raid/party paths,
  subgroup role-sorting and count aggregation, out-of-range subgroup
  clamping, `FormatSummary`'s formatting). Updated `test_defaults_notify.lua`
  (defaultsRev 5→6 + new em-dash-migration regression test),
  `test_poster.lua`/`test_rolecheck.lua` (ASCII-normalized text
  assertions), `test_ui_smoke.lua` (new frame size), `test_lfg_invite.lua`
  (both branches of the refined prefer-support-seat logic, plus missing
  `IsRaidLeader`/`IsRaidOfficer` mocks the new privilege path needed).

## 0.4.43

- **UI: Queue tab now shows a role icon per applicant** (step 1 of an
  incremental "all tabs" layout pass inspired by a competing addon's
  public "Waiting players" table — concept/layout only, our own parchment
  styling and implementation kept, no code viewed or copied). Each queue
  row now shows a 28x28 role icon (tank/healer/aura/dps, with a question
  mark for an unparsed/unknown role) next to the applicant name instead
  of plain `[dps]` text, giving a quicker visual scan. Row height/spacing
  adjusted slightly to fit the icon comfortably.
  Fixed a test-mock gap along the way: the UI smoke test's `CreateTexture`
  mock was missing `SetSize` (real WoW Texture objects have it) — added,
  plus `SetTexture`/`GetTexture` capture so icon assignment can actually
  be exercised by tests, not just silently no-op'd.
  Regression test added to test_ui_smoke.lua covering all five role
  states (tank/healer/aura/dps/unknown) rendering without error.
  Deliberately scoped to one tab per pass rather than a single large
  "redesign everything" change — each tab needs its own careful layout
  verification (as every prior Hosting-tab overlap fix this session
  showed), and there's no way to visually preview WoW FrameXML changes
  before they're actually loaded in-game.

## 0.4.42

- **New: per-message delivery routing (Message Studio-style).** Inspired
  by a competing addon's public release notes (concept only — no code
  viewed or copied; own independent implementation) offering per-message
  Raid/Raid Warning/local/disabled delivery. AscensionLFM already matched
  two of its other highlighted features (strict combined MS+LF/LFG chat
  scanning, and auto-recruitment fully independent of posting) — this
  adds the one genuinely new capability: `db.messageRouting[kind]` now
  lets you override how each broadcast-style message is delivered,
  independent of the existing smart-cascade default:
  - `"auto"` (default/unset) — unchanged: RAID_WARNING if privileged in a
    raid, else raid/party chat, else yell.
  - `"raidwarning"` — force RW only; fails outright (no fallback) if not
    privileged, rather than silently landing somewhere else.
  - `"raid"` — force raid/party chat, skipping RW even when privileged.
  - `"local"` — don't broadcast at all, just note it in your own chat.
  - `"disabled"` — send nothing for that message kind.
  Covers the Role Check RW trigger (`"rw"`), Wipe, Shield, Regroup, Full,
  and Need announcements — all the group-wide broadcasts that funnel
  through `MiniHUD`'s shared `SendGroupAnnounce`, now `SendGroupAnnounce
  (msg, kind)`.
  UI for picking routes per message kind not built yet (this pass adds
  the backend + full test coverage) — usable today by setting
  `db.messageRouting.wipe = "raid"` etc. directly; a follow-up will add
  the in-game picker.
  Regression tests added to test_mini_hud.lua covering all four override
  modes plus confirming an override on one kind doesn't affect others.

## 0.4.41

- **CRITICAL FIX: a freshly-invited applicant's role could be wiped
  before they even finished joining.** Reported live via a detailed log:
  right after "invited Bebi as dps" → "Bebi has joined the raid group",
  the "in group without role" count went UP instead of staying the same
  or going down — despite Bebi having just been explicitly invited *as
  dps*. Traced and reproduced exactly: `Slots.Assign()` records a role
  the instant `InviteUnit` succeeds, but `InviteUnit` is fire-and-forget —
  there's a real gap before the player actually appears in the live
  roster ("X has joined the raid group" lags behind). If a resync (from
  `RoleCheck.Resync()` *or* the independent roster-change-triggered
  `Slots.SyncFromRoster()`/`ScanRaid()` path) landed in that gap, it saw
  "assigned but not currently present" and wrongly pruned the brand-new
  assignment as if it were a stale leaver's — so by the time the player
  actually joined a moment later, their role was already gone.
  Fixed with a time-based grace period: new `Slots.RecentlyAssigned(name,
  graceSeconds=20)` tracks when each assignment happened; both pruning
  paths (`RoleCheck.ResyncAssigned` and `Slots.ReconcileAssigned`) now
  accept an optional `protectedNames` set built from it, so a just-invited
  name is protected from removal for ~20s — long enough to actually join —
  while a genuinely stale assignment (declined/expired invite, real
  leaver) still gets correctly cleaned up once the grace period elapses.
  Regression tests added to test_slots.lua (unit-level: `RecentlyAssigned`
  timing, `ReconcileAssigned` with/without protection) and
  test_rolecheck.lua (integration: a fresh assignment survives an
  immediate resync, then correctly gets pruned once 20s+ have passed with
  no join). Full suite green.

## 0.4.40

- **New: auto-convert party to raid when growing past 5 members.**
  Found while exploring the API docs (`RaidDocumentation.lua`): WoW caps
  a plain party at 5 members — inviting a 6th person while still a party
  (not yet converted to raid) fails client-side. AscensionLFM's own
  slotMax defaults total up to 15 (2 tank + 3 heal + 3 aura + 7 dps), so
  a host who started from a small party could hit an invisible 5-person
  wall well before their configured slots were full. `Invite.InvitePlayer`
  now calls `ConvertToRaid()` automatically right when the party is full
  (4 others + you) and about to grow past it — a no-op once already a
  raid. Covers both the whisper (`TryHostInvite`) and LFG-chat-scan
  (`TryLfgInvite`) paths, since both funnel through the same
  `InvitePlayer`.
  Regression tests added to test_invite.lua: inviting a 6th person from a
  full 5-person party triggers exactly one `ConvertToRaid()` call and the
  invite still succeeds; already being in a raid never calls it again.

## 0.4.39

- **API validation pass using the real 3.3.5a (build 30300)
  Blizzard_APIDocumentation dump.** Cross-referenced every WoW API call in
  the addon (SetRaidSubgroup, SwapRaidSubgroup, UninviteUnit, InviteUnit,
  IsInInstance, GetChannelName, GetChannelList, IsIgnored, UnitName,
  UnitLevel, GetNumPartyMembers, GetNumRaidMembers, IsPartyLeader/
  IsRaidLeader/IsRaidOfficer, UnitAffectingCombat, GetRaidRosterInfo, and
  more) against the documented signatures for this exact client build.
  All confirmed correct — no API misuse bugs found. Caught and correctly
  avoided two false positives along the way (`IsIgnored` and `UnitName`'s
  documented-but-effectively-optional trailing parameter) by cross-checking
  against real-world community usage before "fixing" something that
  wasn't actually broken.
- **`/alfm status` now shows the new toggles.** The roleCheck status line
  was missing `autoMoveTank`/`autoMoveHealer`/`passiveRoleDetect`
  (all added in v0.4.35/37) — now shown as `autoMove T/H/A=.../../...`
  and `passiveDetect=...`. Added a new `invite: cooldown=... · pending
  retries=N` line so the v0.4.38 auto-retry queue is visible for future
  diagnostics, matching the pattern Kick59's `gaveUp=N` already
  established.

## 0.4.38

- **CRITICAL FIX: legitimate tank/healer invites silently swallowed by
  the invite cooldown during busy hosting sessions.** Reported live via
  a long whisper log: DPS/Aura applicants always got some visible
  response (invited, "Sorry, X is full", or "prefer support seat"), but
  Tank/Healer applicants with genuinely open slots ("Jimsalabim whispers:
  tank", "Trogosr whispers: heal") got absolutely nothing — no invite, no
  reject message — and had to notice and re-whisper themselves.
  Root cause: `CanInvite()`'s per-name/global invite cooldown (default 3s,
  meant to avoid flooding `InviteUnit` calls) was blocking these, but
  "global cooldown"/"per-name cooldown" are deliberately NOT in
  `Reject.REJECTABLE` (correctly — replying to a transient internal
  throttle would be misleading), so the applicant got zero feedback of
  any kind. Reproduced exactly: DPS/Aura requests mostly get caught by
  "prefer support seat" or "slot full" checks that run *before* the
  cooldown check, masking the issue for those roles, while Tank/Healer
  requests routinely reach the cooldown check itself during a busy
  session with many simultaneous applicants.
  Fixed with an auto-retry queue instead of a silent drop: when
  `InvitePlayer` fails specifically due to a cooldown, the exact same
  application is automatically re-attempted once the cooldown window has
  passed (staggered if multiple are queued, so a retry burst can't
  re-trigger the same global cooldown on itself). New `Invite.Tick()` +
  `Invite.Start()` (own lightweight ticker, wired into Bootstrap
  alongside Scanner/Kick/Poster), covers both the whisper path
  (`TryHostInvite`) and the LFG-chat-scan path (`TryLfgInvite`).
  Regression test added to test_invite.lua reproducing the exact
  scenario: a cooldown-blocked applicant gets nothing immediately, stays
  queued if ticked too early, then gets auto-invited once the cooldown
  has genuinely elapsed. Full suite green.

## 0.4.37

- **New: catch role words in raid/party chat anytime, not just during an
  active Role Check.** Reported live: a player ("Thapuckyman") replied
  "heal" in raid chat well outside any formal Role Check window — people
  often just type their role whenever it occurs to them rather than
  whispering or waiting for the RW prompt. Added
  `RoleCheck.HandlePassiveGroupChat()`, wired into Scanner's group-chat
  dispatch as a fallback after the existing active-Role-Check handling.
  Deliberately uses a new strict exact-word-only matcher
  (`RoleCheck.ParseBareRoleWord`) instead of the broader Parser/substring
  matching `ParseWhisperRole` uses — since this now runs continuously
  while hosting, a substring match would risk assigning a role off an
  unrelated sentence that merely mentions a role word ("that fight needs
  more heal players" correctly does NOT match). New toggle in the Hosting
  tab (default ON): "Catch role words in raid/party chat anytime".
  Regression tests added to test_rolecheck.lua and test_whisper_hosting.lua
  covering the exact reported message, unrelated-sentence false-positive
  prevention, non-group-member rejection, and the toggle-off case.

## 0.4.36

- **CRITICAL FIX: LFM posting was completely broken since v0.4.29.**
  Reported live: `[AscensionLFM] LFM failed: SendChatMessage(): Invalid
  escape code in chat message` on every single post attempt (both regular
  posting and the Mini HUD LFM button). Root cause: v0.4.29's readability
  change introduced `" | "` as the separator between roles in the posted
  LFM text — but WoW reserves `|` as the start of a chat escape/color/link
  code (`|cAARRGGBB`, `|H...|h`, `|T...|t`), so an unescaped `|` not
  followed by a recognized code throws this exact error and the entire
  `SendChatMessage` call fails outright.
  Fixed by escaping `|` → `||` (the standard WoW convention for a literal
  pipe, which renders identically to a single `|` for readers) right
  before the actual `SendChatMessage` call in both `Poster.PostOnce()`
  and the "announce FULL" message — `BuildMessage()`'s output, the Post
  tab's preview box, and `Parser.Parse()` (reading other hosts' posts)
  are untouched and still show/expect a clean single pipe.
  Regression test added to test_poster.lua reproducing the exact
  failure: builds a `|`-separated message, posts it, and asserts the
  actual `SendChatMessage` call receives escaped `||` while the
  internal/UI-facing message and `/alfm status` still show a clean
  single `|`. Full suite green.

## 0.4.35

- **New: Auto-move Tanks and Healers to one-per-raid-group (extends the
  existing Aura balancing).** Requested: tanks should end up in groups 1
  and 2, healers spread one per group, automatically — same rule Aura
  already followed. Generalized `AuraBalance.PlanMoves` into
  `PlanRoleMoves(members, roleKey, opts)`, reusable for any role:
  - **Tank** fills the lowest-numbered empty group first (2 tanks land in
    groups 1 and 2, matching how a raid frame reads).
  - **Healer** (and Aura, unchanged) fills the emptiest group first, same
    rule as before.
  - Healer/Aura balancing never displaces an already-placed Tank via swap
    unless a completely full group leaves no other choice.
  New `AuraBalance.BalanceAll()` runs Tank → Healer → Aura in that
  priority order, one move per call (same careful roster-settle-wait
  design as the original `Balance()`), wired into `RoleCheck.Resync` so
  it runs automatically on every role-check resync, matching Aura's
  existing trigger. Two new toggles in the Hosting tab (default ON):
  "Auto-move Tanks" and "Auto-move Healers".
  Extensive regression tests added to test_aura_rolecheck.lua: tank
  fills lowest empty group, already-balanced tanks aren't moved
  needlessly, healer swap never picks a tank as victim (verified with a
  full 8-group raid), and the full BalanceAll priority order across
  sequential calls.

## 0.4.34

- **Fix: posting to a channel index you haven't joined silently reached
  nobody.** Follow-up to v0.4.33, prompted by a screenshot of the actual
  channel config: on this server channel 1 is "Ascension" (not
  General/Trade — Trade is 4), and "3.Zone" was shown unchecked
  (not joined). Even with a channel id that resolves successfully,
  `SendChatMessage` to a channel you haven't joined doesn't throw a Lua
  error — it silently fails client-side, the same "no error != it
  worked" trap already fixed for Kick59's `UninviteUnit` (v0.4.28).
  `Poster.PostOnce()` now checks `GetChannelList()` (the player's actual
  joined channels) before sending, and fails loudly with a clear message
  if the resolved channel isn't one of them — same "fail loud, don't
  silently do the wrong thing" philosophy as v0.4.33. Defaults to
  allowing the post if the check itself can't be verified, so this can
  never become a new reason a previously-working setup stops posting.
  Regression tests added to test_poster.lua using the exact channel
  layout from the report (1=Ascension, 2=Newcomers, 3=Zone unjoined,
  4=Trade, 5=LookingForGroup): posting to unjoined channel 3 fails
  loudly, posting to joined channel 4 works normally.

## 0.4.33

- **Fix: unresolved channel name silently posted to YELL instead.**
  Reported live: "buggy, findet die channels nicht" — a channel post
  configured with a name/number the addon couldn't resolve (e.g. "1."
  copy-pasted from the chat tab label "1. General") would silently
  switch to YELL and post there instead, with only an easy-to-miss chat
  print explaining why. YELL has a tiny radius compared to a real
  channel, so the LFM looked like it posted fine while actually reaching
  almost nobody. `Poster.PostOnce()` no longer falls back to YELL on a
  channel resolution failure — it fails loudly instead (clear Print
  message + `lastStatus` now shows "post failed: bad channel" so the
  Post tab's own status line reflects it, not just a chat message that
  can scroll past).
  Also: `GetChannelName()` is now called through `pcall` — an
  unrecognized name should mean "not found", not risk an uncaught error
  silently breaking the whole resolution. And a copy-pasted "N." prefix
  like "1." (from how channels are labeled in the chat tab) now resolves
  via the numeric fallback even when the string-name lookup can't match
  it.
  Regression tests added to test_poster.lua: "1." resolves correctly,
  a genuinely bad channel name fails without any YELL fallback and with
  status reflecting it, and a `GetChannelName` that errors outright gets
  caught instead of propagating.

## 0.4.32

- **Fix: manually-picked "My host role" (v0.4.22) ignored being disabled
  later.** If you picked e.g. Healer as your own host role via the
  Hosting tab picker, then later turned off Healer under Accept Roles,
  `Slots.EnsureHostAssigned()` still blindly trusted the stale
  `db.hostRole` and kept assigning you to a role you'd explicitly said
  you no longer accept — bypassing the auto-pick fallback entirely. Same
  "don't trust a stale/disabled role selection" pattern already fixed for
  the dps-fallback (v0.4.17), Log-tab notify (v0.4.21), and posted LFM
  text (v0.4.26). Now falls through to auto-pick (first accepted role
  with room) whenever the picked host role is no longer accepted.
  Regression test added to test_slots.lua.

## 0.4.31

- **Fix: v0.4.30's follow-up auto-reply fired on the bot's own
  confirmation message, not just its questions.** Caught by testing
  against the exact Suriana example from the original report: "Registered
  as DPS - Aura: Yes. Waiting for invite." contains "Aura" as a whole
  word too, so the new feature would have fired ANOTHER unsolicited
  "aura yes" reply right back at the bot that had just confirmed us —
  the same shape of bug already fixed once on the hosting side (v0.4.20).
  `DetectFollowUpKind` now requires the message to actually look like a
  question (contains "?" or "please") before matching level/role/aura
  keywords at all. Regression test added: the confirmation message from
  the original screenshot now correctly gets no reply.

## 0.4.30

- **New: Seeking mode auto-replies to a host's own follow-up questions.**
  Reported live (screenshot): applying to another host's group (Suriana),
  their own registration bot asked "Please whisper your role and aura as:
  Tank/Heal/DPS + Aura yes/no." then "What level are you?" — Seeking mode
  had no way to handle this, so Hasan had to type "dps + aura" and "21"
  manually. Now, for 5 minutes after auto-whispering an LFM leader
  (`autoWhisper` toggle), a follow-up whisper from that same host
  containing "level" gets an automatic numeric reply (`UnitLevel`); one
  containing "role" and/or "aura" gets a best-effort reply in the
  "{role} + aura yes/no" convention. Never replies to hosts we didn't
  recently whisper — same anti-spam principle as the v0.4.20 fix on the
  hosting side. Role/aura phrasing varies a lot between different hosts'
  bots, so this is explicitly best-effort, not a universal parser — risk
  accepted knowingly rather than staying silent.
  Regression tests added to test_v040_auto.lua covering the full Suriana
  flow (apply → role+aura question → level question) plus confirming no
  reply goes to an unrelated stranger.

## 0.4.29

- **Improved LFM message readability: only shows open roles, with clear
  separators.** Was: `LFM MS 2/2 Tanks 2/3 Healers 1/3 Aura 7/7 DPS` — hard
  to scan, and full roles (2/2, 7/7) added noise without information. Now:
  `LFM MS | 2/3 Healers | 1/3 Aura` — full or disabled roles are omitted
  entirely, remaining roles separated with `|` for quick scanning. If
  every role is full, posts `LFM MS — full` instead of an empty tail.
  Updated the Post tab's example hint text and test_poster.lua/
  test_v040_auto.lua's format assertions to match. `Parser.Parse()` (which
  reads *other* players' LFM posts) is unaffected — it still needs to
  handle whatever format other hosts use, old or new.

## 0.4.28

- **Fix: Kick59 warns but nobody actually gets removed, with zero error
  message.** Reported live: the raid warning fires, the target stays in
  the group, and nothing else prints at all — not even a failure message.
  Root cause: `DoKick()` treated `pcall(UninviteUnit, name)` succeeding
  with no Lua error as proof the kick worked. `UninviteUnit` doesn't
  reliably error even when the server silently ignores the request (e.g.
  a privilege edge case), so a no-op request was being logged as a
  successful kick and no retry ever happened — the addon believed the job
  was done while the player was still sitting in the raid.
  `Kick.lua` now verifies: after a `UninviteUnit` call that didn't error,
  it waits ~1.5s (for `RAID_ROSTER_UPDATE` to settle) and checks the live
  roster. Only confirmed-gone counts as kicked; still-present now counts
  as a failed attempt and feeds into the existing retry/give-up-after-3
  logic (v0.4.18), so a silently-ignored kick now gets retried and
  eventually surfaces a clear "giving up — remove manually" message
  instead of silently doing nothing forever.
  Regression test added to test_kick.lua simulating exactly this:
  `UninviteUnit` "succeeds" but the roster never actually changes — now
  correctly caught as a failure instead of falsely logged as kicked.

## 0.4.27

- **Fix: LFG-chat auto-invite/reply DMing strangers who never applied.**
  Reported live (Lazynorm: "brother, I hadn't even sent my message yet").
  `TryLfgInvite` (the public LFG-chat scan) reacts to *any* "LFG MS" line
  in General/Trade — including posts from completely unrelated players
  advertising their own, different search while you're already inside
  your own Manastorm instance (General/Trade still relays their messages
  across zones). The addon whispered them an invite/reject as if they'd
  personally applied to your group, which they never did — confusing and
  unsolicited from their side. Auto-invite/reply from the LFG scan now
  pauses entirely while you're inside any instance (`IsInInstance()`).
  Direct whispers to you (`TryHostInvite`) are unaffected — those are
  always a genuine, intentional application regardless of where you are.

## 0.4.26

- **Fix: posted LFM could advertise a role you turned off.** `db.roles[role]
  = false` (Accept roles toggle) and `db.slotMax[role]` (the numeric cap)
  are independent settings — turning off e.g. Healer doesn't reset its
  leftover slotMax. The posted LFM text and `/alfm status` built straight
  from `Slots.Snapshot()`, which only reflects slotMax, not acceptance — so
  a disabled role with old slotMax still leftover showed as e.g.
  "0/3 Healers" (looks actively sought), while any healer who whispered in
  response got rejected with "Not looking for healer right now" (role
  filtered) — a contradictory experience. Now zeroed to "0/0" in the
  posted message and status when the role is off, without touching
  `Slots.Snapshot()` itself (UI slot editors and invite logic still need
  the raw configured numbers).

## 0.4.25

- **Fix: "prefer support seat" (v0.4.19) applicants got zero feedback.**
  Reported live: several dps whispers in a near-full raid showed as
  "blocked" in the Queue tab but never got an auto-reply, while other
  applicants did. Root cause: `Reject.REJECTABLE` never included
  `"prefer support seat"` (added in v0.4.19) — a real, understood block
  reason (dps recognized, but deliberately held back to save the last
  1-2 seats for tank/heal/aura), unlike an actual failure. Added it to
  `REJECTABLE` with its own template: "Saving the last couple seats for
  tank/heal/aura — try again if one opens up!".
- Confirmed `"global cooldown"`/`"per-name cooldown"` (Invite.lua's own
  invite-attempt throttle, separate from Reject's cooldown) are correctly
  and intentionally excluded from auto-reply — an existing test already
  asserts this. If several applicants whisper within the same ~3s window
  (`db.inviteCooldown`), only one gets processed that tick; the others
  need to be reached on a later pass rather than getting a reply that
  would misleadingly look like a real rejection.

## 0.4.24

- **Fix real UI overlap in Post tab:** the "Interval (sec, min 30)" label +
  edit box was positioned at y=-368, landing squarely inside the "Announce
  FULL when stopping" toggle row's frame (y=-336 to -394, which has its own
  visible bordered backdrop) — the interval field rendered on top of that
  toggle's description text. Pre-existing since this tab was built; found by
  systematically recomputing every tab's layout math after the Hosting tab
  changes in v0.4.22/23. Moved the interval row (and postStatusFS/postHint
  below it) down past the toggle.
- **Fix near-zero-gap section header in Kick tab:** "Recent kicks" section
  label sat at y=-80, exactly flush against the "Enable kick at level 59…"
  toggle row's bottom edge (0px gap, vs. 8-20px everywhere else in the UI).
  Added normal spacing.
- Re-verified the Hosting tab's new "My host role" section (v0.4.22) against
  the deepest element (~y=-1048) with only ~12px of scroll-range headroom
  under `contentHeight=1060` — bumped to 1120 for real margin, since this is
  a scrollable page and too little headroom means the scroll range can't
  reach the bottom-most content, not just a visual issue.
- Systematically re-simulated exact pixel math for every tab (General,
  Seeking, Hosting, Post) confirming no other overlaps.

## 0.4.23

- **Fix: unbounded SavedVariables growth in the regroup watch list.**
  `db.regroupRoster` (Mini HUD "Regrp" watch list) is correctly capped at
  `REGROUP_MAX` (40) with FIFO eviction, but the paired `db.regroupDisplay`
  lookup table (keeps original name casing for `InviteUnit`) was never
  pruned to match — every name ever seen present in your group stayed in
  SavedVariables forever, growing unbounded over months of play. Now
  pruned to match the roster on every update.
- **Cleanup:** `Scanner.lua`'s `IsGroupChatEvent()` checked for
  `CHAT_MSG_RAID_WARNING`, which was never registered in `CHAT_EVENTS` and
  is a one-way leader/assist broadcast players can't reply through anyway
  — removed the unreachable check.

## 0.4.22

- **New: "My host role" picker (Hosting tab).** `Slots.EnsureHostAssigned()`
  already supported a `db.hostRole` override to let you pick your own role
  instead of auto-guessing, but nothing ever set that field — no default,
  no UI. Added a Tank/Healer/Aura/DPS picker under Accept roles: picking one
  sets your own slot immediately (not just a preference for the next
  auto-assign) and remembers it; "Auto" clears it and lets the host
  auto-pick an open accepted role again, matching prior behavior.

## 0.4.21

- **Fix: Log tab notified about LFG posts for disabled roles while
  Hosting.** `Scanner.lua`'s hosting-mode notify check had two branches: a
  specific-role branch (when the LFG line names a role) only checked
  `Slots.HasOpenSlot(role)`, while the generic/ambiguous branch right below
  it correctly also checked `db.roles[role]` (whether that role is even
  accepted). Since `HasOpenSlot` only looks at the slot cap, not
  acceptance, a host who explicitly turned off e.g. Healer still got Log
  entries for "LFG MS heal" posts as long as the healer slot cap
  technically had room. Both branches now check acceptance consistently.

## 0.4.20

- **Fix: unrelated whispers triggered a confusing auto-reply.** Reported
  live: a player whispered the host about something completely unrelated
  ("i didnt whisper you so dont whisper me XD"), and got an automated
  "Please whisper a role: tank / heal / aura / dps." reply back — because
  every whisper received while hosting is parsed as a potential
  application, and Reject Re-whisper auto-replies whenever no role is
  found. Now: for the "no role"/"no parse" case specifically, the
  auto-reply only fires if the message itself has some minimal ms/invite
  signal (mentions ms/manastorm/inv — e.g. "inv ms please", which is
  clearly a forgotten-role application and still gets the clarifying
  reply). A message with zero MS/invite signal stays silent instead of
  auto-whispering a stranger out of nowhere. Genuine detected-but-full/
  filtered requests are unaffected — those still always get the automatic
  reply since a role was actually recognized. Manual Reject+whisper from
  the Queue tab still works regardless of reason.

## 0.4.19

- **Fix inconsistent "last seats prefer support" policy:** the v0.4.16
  "don't burn the last 1-2 raid seats on DPS while tank/heal/aura are still
  open" rule only applied to the LFG-chat-scan auto-invite path
  (`TryLfgInvite`) — a private whisper applicant asking for dps in the exact
  same situation got auto-invited immediately, defeating the policy for the
  more common whisper-hosting flow. Extracted the shared check
  (`ShouldPreferSupportOverDps`) and applied it to `TryHostInvite` too, so
  both paths behave the same.

## 0.4.18

- **Fix Kick59 infinite re-warn spam:** if `UninviteUnit` kept failing for a
  target (e.g. privilege edge case on some cores), the addon warned the raid
  and silently retried forever — same identical raid warning every
  `kickWarnInterval`, with the failure reason only ever printed to the host's
  own chat, never visible to the raid. Now gives up after 3 failed attempts
  per target, prints a clear "giving up — remove manually" message + logs it
  to Activity, and stops re-warning about that target (until they leave and
  rejoin, which resets the retry budget). Warn message now shows
  `retry N/3` on repeat attempts so it's visibly different from the first try.
  `/alfm status` kick line now shows `gaveUp=N`.
- **Fix Activity log kind validation:** `aura`/`wipe`/`shield`/`regroup`/
  `rolecheck` activity entries were silently relabeled `[match]` in the Log
  tab because `Activity.lua`'s kind whitelist never included them.

## 0.4.17

- **Bugfix batch (code review):** `Parser.lua` bare-role whisper match used a
  Lua pattern with `|` as separator — Lua patterns have no alternation
  operator, so that branch could never match and was dead code; replaced with
  a table lookup. `Invite.lua` hosting-invite "ms-related" gate always
  evaluated true (dead reject branch) since `role` is already non-nil by that
  point — removed instead of enforced, since enforcing it would reject plain
  role whispers ("tank") that don't mention ms/manastorm/inv. `Slots.lua`
  `EnsureHostAssigned` no longer hard-falls-back to `"dps"` when no accepted
  role has room — that silently force-counted the host into a disabled/full
  role and skewed slot counts + the posted LFM message; host now stays
  unassigned in that case instead. Regression tests added to `test_slots.lua`.

## 0.4.16

- **Bugfix batch:** parse glued `MS15` (Heal lfg MS15 works); hosting LFG
  notify only when that role still has an open slot; auto-repost pauses at
  14/15 when people are unassigned (need RW); host self-assigns a role on
  Hosting/Full Auto/Scan; last 1–2 seats prefer tank/heal/aura over DPS;
  LFG GuessRole fallback; Mini HUD clicks are pcall-wrapped (no silent Lua errors).

## 0.4.15

- **Status diagnosis:** `/alfm status` always reports RoleCheck (or MODULE MISSING),
  and shows `unassigned=N` plus names when group members have no T/H/A/D role yet —
  explains stuck LFM lines like `Aura 0/3` with a nearly full raid. Sync / Scan
  print the same hint so you know to click **RW**.

## 0.4.14

- **Debug / harden Mini HUD:** every button prints on fail (no silent clicks);
  raid non-lead uses `RAID` before yell; rate-limit stamps only after a successful
  send; Regrp skips invites without lead/assist (solo still invites); bad Post
  channel falls back to YELL; Settings RW uses the same announce fallback as the
  Mini HUD; `/alfm status` shows a miniHUD debug line.

## 0.4.13

- **Fix Mini HUD RW:** button no longer no-ops outside Hosting / without lead —
  always sends the role-check line (party/yell fallback like Wipe). Full listen
  window still opens when Hosting/Full Auto. Solo hosts yell the RW. Rate-limited
  re-click re-warns without blocking.

## 0.4.12

- **Fix Mini HUD / Regrp bugs:** remember group names *before* roster sync drops
  leavers; store display-name casing for `InviteUnit`; snapshot on login; per-action
  rate limits (Wipe no longer blocks Mobs/Regrp); clearer empty-watch-list message.

## 0.4.11

- **Mini HUD — Regrp:** announces `REGROUP — accept invite` and re-invites missing
  players from the regroup watch list (filled from party/raid + assigned roles as
  people join). Cap 15 invites per click.

## 0.4.10

- **Mini HUD — Mobs:** new **Mobs** button raid-warns
  `KILL MOBS — boss shield still up!` (party/yell fallback). Reminds the group to
  clear adds so the boss shield drops. Custom text via `shieldAnnounceMessage`.

## 0.4.9

- **Mini Quick HUD:** floating click bar (default ON) — LFM / RW / Sync / Wipe / FULL /
  Need T·H·A·D without typing `/alfm`. Drag to move; × collapses to an `ALFM` chip;
  chip click expands; title click opens full settings. Toggle under General.
- Wipe uses raid warning (party/yell fallback). Need lines post on your Post channel.

## 0.4.8

- **Fix RW Role Check:** accept `UnitIsPartyLeader("player")` (same Ascension privilege
  gap as Kick59). Roster membership uses `UnitName` when `GetRaidRosterInfo` name is
  empty so member role replies are not dropped.
- During the listen window, **party/raid chat** role replies count (not only whispers) —
  common after a raid warning.
- Stock RW text mentions party replies; `/alfm status` prints canWarn / lastStart /
  reply count.

## 0.4.7

- **Fix Kick59:** roster level `0` no longer blocks kicks — prefer `UnitLevel` when
  `GetRaidRosterInfo` reports 0/unknown; also try `UnitName` when roster name is empty.
- Privilege: `UnitIsPartyLeader("player")` accepted (party + raid lead on Ascension).
- Uninvite is deferred ~0.6s after the raid warning and staggered per target (same-frame
  chat+uninvite was unreliable); bare name retry for `Name-Realm`.
- `/alfm status` prints kick last-reason / canKick / pending. Kick ticker also starts from
  login directly (not only via Scanner).

## 0.4.6

- **Fix Aura auto-group:** respect 5-player raid subgroup cap (swap when full), apply
  one move at a time and wait for roster settle (raid indices reshuffle after each
  `SetRaidSubgroup` / `SwapRaidSubgroup`), skip moves while in combat.

## 0.4.5

- **UI overlap fix:** category pages are scrollable; toggle rows taller (58px) with 10px gaps.
- Shorter Hosting helper text; Reject tmpl moved below Sound; Post Role Check status on its own line.
- Dialog height 560 (fits 768+ screens); Hosting/Seeking/Post scroll with mouse wheel.

## 0.4.4

- **Broader role-whisper fallbacks:** `healers` / `heiler` / `H` / `T` / `A` / `D` /
  `dmg` / trailing punctuation (`healers!`) map to Tank/Healer/Aura/DPS for auto-invite
  and RW Role Check. New `Parser.GuessRole` used when the strict parse misses.
- **One-time migration:** saved **Full Auto Hosting** installs that still had Healer/Aura
  accept off (pre-0.4.3) get all four accept roles enabled on first login to 0.4.4.

## 0.4.3

- **Fix Full Auto whisper invites:** turning **Full Auto Hosting** ON now enables Accept
  roles Tank/Healer/Aura/DPS. Previously defaults often left Healer/Aura off, so those
  whispers failed as `role filtered` and felt like Full Auto whisper was broken.
- Role Check still consumes only **group-member** whispers during the window; outside
  applicants still go through auto-invite / Queue.

## 0.4.2

- **Copy polish:** clearer Hosting Role Check / Aura helper text (no raw API jargon).
- Shorter default raid-warning: `ROLE CHECK — whisper tank / heal / aura / dps`.
- Friendlier chat status lines for Role Check start/end/errors and Aura moves.
- README EN + new DE how-to for RW Role Check and Aura auto-move.

## 0.4.1

- **RW Role Check:** Hosting / Post buttons send a raid warning (lead/assist; party/yell
  fallback like Kick59) asking members to whisper `tank` / `heal` / `aura` / `dps`.
- **Listening window** (default 60s, configurable): group whispers update `Slots.Assign`
  / `assignedRoles` live; status shows `Role check active — Xs left · N responses`.
- **Resync roles now:** prune leavers, re-apply role-check responses, `Slots.ScanRaid`,
  refresh LFM preview + filled counts — works without a prior RW.
- Optional **auto-resync** when the window ends (default ON). RW rate-limited (min 30s).
  Hosting / Full Auto only.
- **Aura 1 per raid group + auto-move:** at most one Aura-assigned player per raid
  subgroup (1–8); extras are moved with `SetRaidSubgroup`. Toggle default **ON**.
  Runs after assign / ScanRaid / roster sync / role resync.

## 0.4.0

- **LFG auto-invite (Hosting):** when someone posts `LFG MS …` with a role you accept
  and that slot is open → `InviteUnit`. Toggle **Auto-invite LFG seekers** (default ON
  while Hosting; Full Auto enables it). No-role LFG lines are denied unless
  `lfgInviteWithoutRole` is on.
- **Full Auto Hosting** master (default OFF): whisper invite + LFG invite + roster scan +
  auto-repost + reject-rewhisper.
- Reject re-whisper on slot/group full / no role; Applicant **Queue**; presets; activity log;
  seeking whisper variants + leader blacklist; opt-in sounds.
- TOC backslash paths (from 0.3.1) kept so `/alfm` loads on Ascension.

## 0.3.1

- **Fix `/alfm` not working on Ascension:** TOC file paths use Windows backslashes
  (`core\Bootstrap.lua`) like AscensionSuite — forward slashes often prevent Lua from
  loading on 3.3.5a/Ascension, so slash commands never register.
- Slash re-registered on `ADDON_LOADED` / `PLAYER_LOGIN`; aliases `/mslfm`, `/alfmshow`.
- UI `Init`/`Toggle` wrapped with `pcall` + dialog-template fallback; errors print to chat
  instead of silently failing. `/alfm help` and clearer status hints.

## 0.3.0

- **LFM Post composer** (new **Post** sidebar category): preview/edit box builds
  `LFM MS {t}/{tmax} Tanks {h}/{hmax} Healers {a}/{amax} Aura {d}/{dmax} DPS`
  from Hosting slot filled/max; channel YELL / SAY / GUILD / CHANNEL (+ optional name);
  **Post once** via `SendChatMessage`.
- **Scan raid/party** recounts filled from roster + `assignedRoles`; auto-refresh on
  `PARTY_MEMBERS_CHANGED` / `RAID_ROSTER_UPDATE` while Hosting or auto-repost is on.
- **Auto-repost** (default OFF): interval seconds (default 60, min 30); Hosting only;
  rebuilds the LFM string each tick; stops when all role caps are filled or group hits
  Max size; status shows next-repost countdown and last post time.
- Kick59 and invite behavior unchanged (kick still opt-in default OFF).
- TOC load order: Database → Parser → Slots → Invite → Kick → **Poster** → Scanner →
  MainWindow → **Bootstrap last**.
- Tests for message builder, stop-when-full, interval clamp; mockup updated.

## 0.2.2

- **Fix empty Match Log / “addon does nothing”:** default mode is now **Notify** (Listening ON). Public LFM/LFG MS lines go to chat + Log without setup; kick and auto-invite stay off. One-time upgrade flips leftover `Off` installs to Notify.
- **TOC load order:** Database → Parser → Slots → Invite → Kick → Scanner → MainWindow → **Bootstrap last**; forward-slash paths; Interface 30300.
- Parser accepts `mana storm` / `mana-storm` and bare `lfg ms` / `LFM Manastorm` variants.
- Login chat: prints mode, `/alfm`, and Hosting hint. **`/alfm test`** injects a fake Log entry.
- **Install:** `INSTALL.txt` in the release zip; README EN+DE — use Releases zip only (not GitHub “Source code” / `AscensionLFM-main`). Folder must be `AscensionLFM/AscensionLFM.toc`.
- UI status shows **Listening ON/OFF** explicitly.

## 0.2.1

- Settings UI rebuilt as AscensionSuite-style **Categories** sidebar: General · Seeking · Hosting · Kick · Log.
- Right parchment page switches per category (no single-column control pile-up); content clipped inside DialogFrame.
- Mockup updated (`docs/sketch/ascension-lfm-mockup.html`); light UI smoke test for frame + category helpers.
- All v0.2.0 scanner / slots / invite / kick behavior unchanged (kick still default OFF).

## 0.2.0

- Scan **LFG** Manastorm lines as well as LFM (notify / seeking; toggle **Scan LFG MS**).
- Hosting whisper roles expanded: OT/MT, HPS, DD/Damage, **Aura of Exp** / exp aura / AoE aura (case-insensitive).
- Per-role **slot caps** (default 2/3/3/7) with filled tracking; no invite when that role is full; UI max editors + filled row.
- Default-deny invites when whisper has **no role**; overall max size default 15 for MS level runs.
- Roster sync on `PARTY_MEMBERS_CHANGED` / `RAID_ROSTER_UPDATE` keeps whisper-assigned roles for present members.
- **Opt-in** level-59 auto-kick: raid warning every 10s naming targets, then `UninviteUnit`; kick log in UI (default off; hosting + lead/assist only).
- Settings UI expanded for LFG scan, slots, kick enable, recent kicks; mockup updated.

## 0.1.0

- Initial release: Manastorm Level Run LFM scanner for Ascension WotLK 3.3.5a.
- Parses public chat + whispers for LFM/MS listings with flexible role slot patterns.
- Modes: Off (default), Notify only, Seeking (optional auto-whisper), Hosting (optional auto-invite).
- Settings UI (`/alfm`, `/mslfm`) with role filters, whisper message, max party size, recent matches.
- Deduplication, ignore-list respect, invite/whisper rate limits, party-full guard.
