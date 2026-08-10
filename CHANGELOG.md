# Changelog

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
