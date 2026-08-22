# AGENTS.md — working notes for AI agents in this repo

This file is for AI coding assistants (Claude, Claude Code, or any other
agent) picking up work on AscensionLFM. It exists so each session doesn't
have to re-discover the same gotchas from scratch. Keep it current: when
you learn something the hard way, add it here before you forget.

## What this addon is

AscensionLFM is a WoW 3.3.5a addon for Ascension.gg (a WotLK private
server with a "classless" custom class system, Manastorm dungeon runs,
and other server-specific systems). It helps hosts recruit/manage a
Manastorm run: whisper parsing, auto-invite, slot tracking, kick
verification, an LFM poster, and a roster panel.

Repo: `Lzra2000/AscensionLFM`. Direct-pushes to `main`, no PR workflow.

## Before touching anything

1. Read `README.md` for the user-facing feature list.
2. Read the last ~5 entries of `CHANGELOG.md` for recent context - it's
   written in enough detail to double as a decision log, not just a
   user-facing changelog.
3. Run the full test suite before making ANY change, so you know your
   baseline is green:
   ```
   for f in tests/test_*.lua; do lua5.1 "$f" || echo "FAIL: $f"; done
   ```

## Mandatory workflow for every change

1. **Syntax-check every file you touch** with `luac5.1 -p <file>` before
   moving on. This catches typos immediately instead of at the end.
2. **Run the full test suite** (all `tests/test_*.lua`) before every
   commit. Never commit red. If a test's mock is missing a method your
   new code needs (common when adding new WoW API calls), fix the mock -
   don't skip the test.
3. **When you fix a real bug, add a regression test for it**, and
   verify the test actually catches the regression: temporarily revert
   your fix, confirm the test fails, then restore the fix and confirm
   it passes again. A test that was never seen to fail is not proven to
   catch anything.
4. **Bump the version** in three places, kept in sync:
   `AscensionLFM.toc` (`## Version:`), `core/Bootstrap.lua`
   (`AscensionLFM.VERSION`), and `tests/test_toc_paths.lua` (asserts the
   toc version string matches).
5. **Write a CHANGELOG.md entry** before committing - detailed enough
   that a future session (human or AI) can understand *why* a change
   was made, not just what changed. Cite what was verified against real
   source vs. what's still an approximation.
6. **Commit and push directly to `main`** with a descriptive message
   (the changelog entry is usually a good source for this).
7. **Build and present the release zip** after pushing: archive
   `README.md AscensionLFM.toc INSTALL.txt LICENSE CHANGELOG.md ui core`
   into `AscensionLFM-<version>.zip`, present it to the user - the repo
   isn't directly installable, only the zip is.

## UI chrome rules (Season 10 bar)

- **Never `PortraitFrameTemplate`** for windows that host EditBoxes /
  multiline text. Buildschmiede hit empty / clipped export text after
  PortraitFrame reparenting. Prefer DialogBox + `Chrome.CreateInset` +
  `UIPanelButtonTemplate`.
- Every `InputBoxTemplate` must go through `Chrome.StyleEditBox` (or
  `CreateStyledEditBox` in MainWindow) so ink stays readable on dark
  DialogBox / inset panels. Do not rely on the template default.
- User-facing German uses **du**, short sentences. No `string.upper` on
  labels that may contain Umlaute.
- Ascension APIs: prefer `AscensionLFM.Safe` / `pcall`; remember
  **pcall success ≠ server acted** (see Sort Groups / UninviteUnit).
- **No DragonUI.** Chrome is Ascension FrameXML DialogBox only
  (`ui/Chrome.lua`). Do not reintroduce `Interface\AddOns\DragonUI\…`
  texture paths, `HasDragonUI`, or metal nineslice.

## Module map

- `core/AscensionAPI.lua` — `AscensionLFM.Safe` + read-only Manastorm/LFG
  wrappers (`AscensionLFM.API`). Extract-verified only; see
  `docs/NOTES-ascension-apis.md`. No `Enter`/`Leave`/`C_Wildcard` rolls.
- `core/Database.lua` — SavedVariables schema + defaults +
  version-gated migrations (`defaultsRev`). **Never edit a historical
  migration step retroactively** - the migration chain is order-
  dependent; if a field it sets is now unused, that's a harmless no-op,
  leave it alone.
- `core/Parser.lua` — whisper message parsing (role detection, negation
  handling like German "kein/keine/keinen").
- `core/Slots.lua` — roster slot assignment, `assignedAt` grace-period
  tracking (protects freshly-invited players from being pruned as
  "not present" during join lag).
- `core/SpecRole.lua` — self spec/role detection. **Only supports the
  local player** - Ascension's own `UnitSpecAndIcon` (confirmed via
  their client source) explicitly comments "only supports player atm"
  for classless/CoA characters. Don't try to extend this to inspect
  other players' specs; it was tried and confirmed infeasible this
  session.
- `core/Invite.lua` / `core/Poster.lua` — both have their own
  `IsHostInsideInstance()` (duplicated, not shared - matches this
  codebase's existing convention). Prefers
  `AscensionLFM.API.IsHostInsideInstance()` (`C_Manastorm.IsInManastorm`
  when present) over the generic `IsInInstance()` — CoA-only API,
  always falls back if `C_Manastorm` isn't a table.
- `core/Kick.lua` / `ui/RosterPanel.lua` — both independently learned
  the "no Lua error ≠ it worked" lesson for `UninviteUnit`: it's
  fire-and-forget and can silently no-op (privilege, combat). Both
  verify via a delayed re-check rather than trusting the call.
- `core/Activity.lua` — bounded rolling log + uncapped session-total
  counters, feeds the Log tab's session summary.
- `core/ManastormTracker.lua` — feeds `MANASTORM_LEVEL_COMPLETED`/
  `MANASTORM_FAILED` into Activity; level fallback via
  `API.GetActiveLevel`. CoA-only events, same fallback posture as the
  instance check above.
- `ui/MainWindow.lua` — the big one (2300+ lines). Category-tab layout
  (`CreateSectionLabel`/`CreateToggleRow`/`BuildCategoryPage`) uses
  **symbolic constants** (`TOGGLE_STEP = 74`, `TOGGLE_ROW_H = 66`) for
  spacing, not hardcoded pixel math - if you see a hardcoded literal
  number in a position calculation instead of these constants, that's
  almost certainly a copy-paste bug waiting to overlap something (this
  happened twice in this repo's history: v0.4.70 and its own "fix" in
  v0.4.72 both got the constants wrong before landing on symbolic
  references). Always use `TOGGLE_STEP`/`TOGGLE_ROW_H` in new layout
  code, never a bare number.
- `ui/MiniHUD.lua` — the small floating HUD. Has a collapsed state that
  **actually resizes the frame** (56x28) rather than just hiding
  content - anything anchored with fixed sizing (not stretched via
  `SetAllPoints`) needs to be explicitly hidden/shown across that
  transition (see `chromeBorderPieces` for the pattern).
- `ui/RosterPanel.lua` — per-group roster cards, role picker (click a
  role icon → assign Tank/Healer/Aura/DPS/clear) already supports
  manual aura-seat assignment; don't rebuild this if asked for it.

## Chrome (Ascension-native only)

As of v0.4.138 there is **no DragonUI** in this addon:

- `ui/Chrome.lua` — DialogBox backdrop, optional header / UIPanelCloseButton,
  InsetFrame wells. `ApplyMetalChrome` is an alias that always calls
  `ApplyClassicChrome`.
- Do **not** reintroduce `Interface\AddOns\DragonUI\…` paths, `HasDragonUI`,
  metal nineslice, or Appearance offset knobs for foreign textures.
- Diagnostics: `/alfmchrome`, `/alfmhuddebug`, `/alfmmaindebug` measure
  native chrome regions — use them instead of guessing.

## Testing conventions

- Tests are plain Lua scripts run with `lua5.1`, no test framework -
  each file has its own `check(name, condition, detail)` helper and a
  `passed`/`failed` counter, exits non-zero on any failure.
- `tests/test_ui_smoke.lua` and `tests/test_mini_hud.lua` mock the WoW
  frame API (`CreateFrame`, `CreateTexture`, `CreateFontString`, etc.).
  When you add a new WoW API call in `ui/*.lua`, check whether the mock
  already has that method - if not, add it, and make it **track real
  state** (not just accept-and-ignore) if a test needs to observe the
  result, e.g. `Show`/`Hide`/`IsShown` need to actually flip a
  `self._shown` flag, not just be no-ops, or a test asserting
  visibility state would be a false-positive pass no matter what the
  real code does.
- `tests/test_toc_paths.lua` asserts the `.toc` file lists every real
  file, uses backslash path separators (WoW client requirement, not
  forward slash), and that the version string matches across files.

## Things that were tried and confirmed NOT to work

Documented so nobody re-investigates these from scratch:

- **Reading another player's buff/aura state reliably.** `UnitAura` on
  party/raid members at range is unreliable on this client - confirmed
  by checking Ascension's own nameplate buff code, CompactRaidFrames,
  and AscensionLogsCompanion's full combat-log/inspect pipeline, none
  of which have a better technique. This is why the automated
  "AuraScan" liar-detection feature was removed entirely in v0.4.78
  rather than kept as a half-working feature.
- **Inspecting another player's spec/build.** `UnitSpecAndIcon`
  (Ascension's own client source) explicitly only supports the local
  player for classless/CoA characters.
- **A native "who's assigned Tank/Healer/DPS" API for manually-formed
  groups.** `UnitGroupRolesAssigned` only gets populated by the LFD
  queue's own role-selection flow, not by manual whisper-invited
  groups - confirmed via Ascension's own `CompactRaidFrameManager.lua`
  usage. Also checked and ruled out: `GetRaidRosterInfo`'s 10th field
  is the old MAINTANK/MAINASSIST marking flag, not a combat role.
- **Average ilvl for remote chat LFM/LFG names.** Ascension exposes
  `UnitAverageItemLevel(unit)` (PaperDoll / CallBoard / `C_Player` and
  `GetAverageItemLevel` are player wrappers). That needs a unit token.
  Chat leaders and whisper applicants have none — do not invent. See
  `docs/NOTES-ascension-apis.md` → Item level; `core/ItemLevel.lua`
  shows/filters only when the API (or short cache) has a real value.
  Still true as of v0.4.138: Log/chat LFM rows stay without fake ilvl.

## Where the Ascension/DragonUI source research lives

Large parts of this session's work were verified against Ascension's
actual client source (FrameXML, SharedXML, and several `Ascension_*`
custom modules) and DragonUI's actual addon source, provided directly
by the user rather than assumed from general WoW knowledge. That source
isn't in this repo. If you're told it's available again in a future
session, it's worth re-consulting before assuming an API behaves the
"standard" WoW way - this server has a lot of custom systems
(Manastorm, classless specs, Mystic Enchants, Personal/Realm Bank
sharing the guild bank frame, etc.) that don't match vanilla/retail
assumptions.
