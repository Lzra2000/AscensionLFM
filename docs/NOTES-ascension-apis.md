# NOTES — Ascension / Manastorm / LFG API map (AscensionLFM)

Generated 2026-08-22 from call-site mining. **No proprietary Lua in git.**

## Purpose

AscensionLFM is a **chat-based Manastorm LFM/LFG host helper**. It does not
drive Wildcard rolls or the official LFD queue. This note maps which
Ascension `C_*` surfaces exist, which this addon already uses, which Safe
read wrappers exist, and which must stay untouched.

## Sources (read-only)

| Tree | Path |
|---|---|
| Extract (canonical) | `C:\Users\x\Documents\AscensionLuaExtract\by-archive\patch-B.MPQ` |
| Interface extract | `C:\Users\x\Documents\AscensionInterfaceExtract\by-archive\patch-B.MPQ` |
| Live AddOns | `C:\Ascension\Launcher\resources\ascension-live\Interface\AddOns` |
| Cross-check | live `AscensionLogsCompanion\Capture\ManastormScan.lua` |
| Blizzard API docs addon | `APIDocumentation\Documentation\LookingForGroupDocumentation.lua` (stock LFG globals only) |

Hard rules: no shipping extract Lua; no inventing coefficients or APIs;
`pcall` success ≠ server acted on mutate calls.

## Kind legend

- `read` — returns data / player or run state
- `query` — Can*/Is* predicates
- `mutate` — Enter / Leave / SetLoadout / rolls — **do not call from AscensionLFM**
- `OWN` — already used at live call sites (or via `AscensionLFM.API`)

---

## Addon usage today (OWN)

| Call site | API | Why |
|---|---|---|
| `Invite.lua`, `Poster.lua`, `MiniHUD.lua` | `C_Manastorm.IsInManastorm` | Pause invite/repost/Regroup only for a real MS run (not any instance) |
| `ManastormTracker.lua` | `C_Manastorm.GetActiveLevel` | Level on `MANASTORM_FAILED` when payload empty (read at event time) |
| Events | `MANASTORM_LEVEL_COMPLETED`, `MANASTORM_FAILED` | Session Activity log |

All go through `AscensionLFM.Safe` / `AscensionLFM.API` as of 0.4.135.

**Intentionally not re-shipped:** LFM post `[+% Loot]` tag via
`GetRewardModifier` group bonus (added 0.4.125, **removed 0.4.126** — hosts
are mostly 10–59 speed-leveling; loot bonus callout not relevant). The
**read wrapper** `API.GetGroupRewardBonusPercent` remains for HUD/status
experiments without auto-tagging chat.

---

## `C_Manastorm` (CoA-only)

Absent on Bronzebeard/Epoch — presence of `IsInManastorm` is the gate
(ALC `isAvailable()`). While in-run, values zero on eject; read at event
time, never poll afterward (ALC + ManastormTracker).

| Method | Kind | OWN / Safe | Evidence |
|---|---|---|---|
| `IsInManastorm` | query | OWN + `API.IsInManastorm` | Manastorm.lua, Minimap, UIParent, ManastormUtil, Queue |
| `GetActiveLevel` | read | OWN + `API.GetActiveLevel` | Manastorm.lua, ManastormUtil |
| `GetActiveManastormID` | read | `API.GetActiveManastormID` | Manastorm.lua, ManastormUtil |
| `GetActiveManastormType` | read | `API.GetActiveManastormType` | Manastorm.lua, ManastormUtil → SOLO/DUO/TRIO/GROUP |
| `GetRewardModifier(id)` | read | `API.GetRewardModifier` | Manastorm.lua tracker (end/encounter/groupEnd/groupEncounter) |
| `GetStageBonusExperience` | read | `API.GetStageBonusExperience` | Manastorm.lua (in-run XP line) |
| `GetExperienceModifier(diff, level)` | read | `API.GetExperienceModifier` | ManastormQueue level list |
| `GetMaxCompletedLevels(unit)` | read | `API.GetMaxCompletedLevels` | Queue + PaperDoll; **needs unit** (`"player"`). No-arg fails validation (ALC Error.txt) |
| `GetEnterableLevels` | read | `API.GetEnterableLevels` | ManastormQueue |
| `CanEnter(level)` | query | `API.CanEnter` | ManastormQueue / UIParent |
| `CanLeave` | query | `API.CanLeave` | ManastormQueue / Minimap |
| `GetBoss` | read | `API.GetBoss` | Manastorm.lua tracker |
| `GetManastormCacheInfo` | read | `API.GetManastormCacheInfo` | Manastorm.lua bonus chest |
| `GetRewardVisibility(ctx, itemID)` | read | `API.GetRewardVisibility` | ManastormUtil |
| `GetRewardLimitProgress(ctx, itemID)` | read | `API.GetRewardLimitProgress` | ManastormUtil |
| `GetNumLoadoutSlots` | read | `API.GetNumLoadoutSlots` | ManastormLoadout / Util |
| `GetLoadoutSpellAtIndex(i)` | read | `API.GetLoadoutSpellAtIndex` | ManastormLoadout / Util |
| `GetAvailableLoadoutSpells` | read | `API.GetAvailableLoadoutSpells` | LoadoutFlyout / Util |
| `Enter(level)` | mutate | **forbidden** | ManastormQueue |
| `Leave` | mutate | **forbidden** | StaticPopup |
| `SetLoadoutSpellAtIndex` | mutate | **forbidden** | LoadoutFlyout |

### Events (FrameXML / Ascension_Manastorm / ALC)

| Event | Notes |
|---|---|
| `MANASTORM_LEVEL_COMPLETED` | a1 = cleared level (OWN) |
| `MANASTORM_FAILED` | wipe/eject; level may be missing (OWN + GetActiveLevel fallback) |
| `ACTIVE_MANASTORM_UPDATED` | tracker refresh; ALC: `(prev, new)`, `new==0` = out |
| `ENTER_MANASTORM_RESULT` / `LEAVE_MANASTORM_RESULT` | queue UI; OK codes hide panel |
| `MAX_COMPLETED_MANASTORM_*_LEVEL_UPDATED` | PaperDoll / queue highest levels |
| `MANASTORM_CHAOTIC_LINK_UPDATED` | tracker chaotic-link stacks |
| `MANASTORM_REWARD_VISIBILITY_UPDATED` | ManastormUtil constant |

---

## `C_LFG` (FrameXML/Util/C_LFG.lua)

Lua table + methods for Ascension’s LFG / Manastorm **tab eligibility**.
Not the same as chat LFM/LFG parsing this addon does.

| Method | Kind | Safe | Notes |
|---|---|---|---|
| `CanUseManastorm` | query | `API.CanUseManastorm` | CONFIG_MANASTORM_ENABLED + level ≥ 10 |
| `CanUseGroupFinder` | query | `API.CanUseGroupFinder` | Challenges + CONFIG_GROUP_FINDER_ENABLED |
| `CanUseLFD` | query | — | LFD level gate; low value for MS host helper |
| `CanUseRandomLFD` | query | — | Random dungeon ilvl/PvE-power/events |
| `IsRandomDungeonDisplayable` | query | — | Random dungeon list |
| `IsScalingDungeon` | query | — | Scaling dungeon id set |
| `GetLFGDungeonRewards` | read | — | wraps stock GetLFGDungeonRewards* |

Stock WotLK LFG globals (`GetLFGMode`, `GetLFGRoles`, …) are documented in
`LookingForGroupDocumentation.lua`. `UnitGroupRolesAssigned` only fills from
LFD role check — **not** manual whisper groups (see AGENTS.md).

---

## `C_Wildcard` — out of scope for AscensionLFM

Full roll / Rapid-Rolling / Desire surface lives in Ascension_WildCard +
WildCardUtil. Useful for **AscBuildschmiede** export, not for MS hosting.

| Examples | Kind | AscensionLFM |
|---|---|---|
| `CanRollAbilities`, `RollAbilities`, `StartRapidRolling`, … | query/mutate | **forbidden** (`scripts/check.sh`) |
| `GetRapidRollingState`, breakpoint getters, repurchase counts | read | Buildschmiede only |
| `GetStartingChoiceEntries` | read | Buildschmiede only |

`ManastormQueue:UpdateRewards` uses `C_GameMode:IsGameModeActive(Enum.GameMode.WildCard)`
to show/hide a 4th reward icon — wrapped as `API.IsGameModeActive(mode)` for
optional UI context only.

---

## `AscensionLFM.API` (shipped Safe surface)

Module: `core/AscensionAPI.lua` (loads early). Primitive: `AscensionLFM.Safe`.

| Wrapper | Backing API |
|---|---|
| `HasManastorm` / `IsInManastorm` / `IsHostInsideInstance` | `C_Manastorm.IsInManastorm` (+ `IsInInstance` fallback) |
| `GetActiveLevel` / `GetActiveManastormID` / `GetActiveManastormType` | matching getters |
| `ReadActiveManastorm` | ALC-shaped snapshot |
| `GetRewardModifier` / `GetGroupRewardBonusPercent` | reward modifiers (no auto LFM tag) |
| `GetStageBonusExperience` / `GetExperienceModifier` | XP modifiers |
| `GetMaxCompletedLevels` / `GetEnterableLevels` | progress / queue |
| `CanEnter` / `CanLeave` | query only |
| `GetBoss` / `GetManastormCacheInfo` | in-run tracker |
| `GetRewardVisibility` / `GetRewardLimitProgress` | reward UI |
| `GetNumLoadoutSlots` / `GetLoadoutSpellAtIndex` / `GetAvailableLoadoutSpells` | loadout reads |
| `CanUseManastorm` / `CanUseGroupFinder` | `C_LFG` |
| `IsGameModeActive` | `C_GameMode` |
| `GetAverageItemLevel(unit)` | `UnitAverageItemLevel(unit)` (+ player fallbacks `GetAverageItemLevel` / `C_Player:GetAverageItemLevel`) |

**Not wrapped (mutate):** `Enter`, `Leave`, `SetLoadoutSpellAtIndex`, any
`C_Wildcard.*` roll/repurchase.

---

## Item level (average)

| API | Kind | Notes |
|---|---|---|
| `UnitAverageItemLevel(unit)` | read | **Canonical.** PaperDoll `PaperDollFrame_SetItemLevel(statFrame, unit)` and AscensionUI CallBoard use this. Takes a unit token. |
| `GetAverageItemLevel()` | read | UnitUtil.lua → `UnitAverageItemLevel("player")` only |
| `C_Player:GetAverageItemLevel()` | read | Same player-only wrapper; used by `C_LFG` random-dungeon gate |

**Missing for AscensionLFM chat lists:** there is **no** API that returns average
ilvl for a remote LFM leader or whisper applicant by name. Without a unit
token (`player` / `partyN` / `raidN` / inspect target), the addon cannot show
or filter ilvl — and must not invent one. Display/filter therefore only apply
when the player is already group-visible (or still in the short ItemLevel
cache after leaving).

Shipped surface: `AscensionLFM.API.GetAverageItemLevel` + `core/ItemLevel.lua`
(roster column `59·142`, queue badge `i142`, `db.minIlvl` / `/alfm minilvl`).

---

## check.sh allowlist

`ALLOWED_C_API` may list only extract-verified namespaces this addon
references on purpose: `C_Manastorm`, `C_LFG`, `C_GameMode`. Adding a name
requires a row in this NOTES file first. `C_Player` is not on the allowlist —
ilvl uses the `UnitAverageItemLevel` global (string/`NS` lookup only for the
optional player fallback).
