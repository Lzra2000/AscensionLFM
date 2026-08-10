# Changelog

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
