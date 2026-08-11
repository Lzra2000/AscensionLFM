# Changelog

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
