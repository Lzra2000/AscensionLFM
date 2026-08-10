# AscensionLFM

WotLK **3.3.5a** addon for Ascension that scans chat and whispers for **Manastorm Level Run** **LFM** and **LFG** messages, notifies you of matches, and optionally auto-whispers leaders or auto-invites applicants when you host — with per-role slot caps, Full Auto Hosting, **RW Role Check**, reject re-whisper, applicant queue, LFM post/repost, and an opt-in level-59 auto-kick.

## Install (EN)

1. Download **`AscensionLFM.zip`** from [Releases](https://github.com/Lzra2000/AscensionLFM/releases) — **not** GitHub “Source code” / Code → Download ZIP (that becomes `AscensionLFM-main` and **will not** appear in the AddOns list).
2. Extract so you have exactly `Interface/AddOns/AscensionLFM/AscensionLFM.toc` (folder name must match the `.toc` basename).
3. Enable the addon on the character select AddOns list, then login or `/reload`.
4. `/alfm` opens settings. Default mode is **Notify** (Listening ON). Use `/alfm test` to inject a fake Log entry.

See `INSTALL.txt` inside the zip for a short checklist.

## Installation (DE)

1. **`AscensionLFM.zip`** von [Releases](https://github.com/Lzra2000/AscensionLFM/releases) laden — **nicht** „Source code“ / Code → Download ZIP (`AscensionLFM-main` erscheint **nicht** in der AddOns-Liste).
2. Entpacken zu `Interface/AddOns/AscensionLFM/AscensionLFM.toc` (Ordnername = TOC-Basename).
3. Addon in der Charakter-AddOns-Liste aktivieren, einloggen oder `/reload`.
4. `/alfm` öffnet die Einstellungen. Standard: **Notify** (Listening ON). `/alfm test` legt einen Test-Eintrag ins Log.

## Slash commands

| Command | Action |
|---------|--------|
| `/alfm` / `/mslfm` | Open settings |
| `/alfmshow` | Same |
| `/alfm status` | Rich status (Full Auto, invites, repost, slots, queue) |
| `/alfm test` | Inject a fake match into the Log |
| `/alfm help` | List commands |

## Modes (default: **Notify** — Listening ON)

1. **Off** — Listening OFF (no chat scan).
2. **Notify only** (default) — print matching Manastorm LFM/LFG lines to chat and list them in the Log. No auto-whisper / auto-invite.
3. **Seeking** — notify when a listing still needs one of **your** roles; optional **auto-whisper** the LFM leader (rate-limited, respect ignore list). LFG lines are notified when **Scan LFG MS** is on (no auto-whisper to seekers).
4. **Hosting** — (a) whisper applicants with matching roles → **InviteUnit**; (b) **LFG auto-invite**: players who post `LFG MS …` with a role you need and an open slot are invited from public chat.

## Hosting: slots + invites

Default Manastorm level-run caps: **2 tank / 3 healer / 3 aura / 7 DPS** (editable in UI). The filled/max row updates as invites assign roles from whispers. Party/raid roster changes drop leavers from the assignment map; unknown roles for manually invited players stay uncounted until they whisper a role.

- Whispers with **no role** are not invited (default-deny; toggle “Require role in whisper”).
- Slot full → no invite for that role.
- Overall **Max size** (default 15) still blocks when the group is full.

## Post: LFM compose, scan, auto-repost

Open **Post** in `/alfm` (separate from Hosting to avoid crowding).

1. **Rebuild** / preview builds:
   `LFM MS {tFilled}/{tMax} Tanks {hFilled}/{hMax} Healers {aFilled}/{aMax} Aura {dFilled}/{dMax} DPS`
   from Hosting slot filled/max (`Slots.Snapshot`).
2. Pick channel: **Yell / Say / Guild / Channel** (channel name optional for custom chat channels).
3. **Post once** sends via `SendChatMessage`.
4. **Scan raid/party** recounts filled from the current roster + assigned roles; while Mode is **Hosting** (or auto-repost is on), roster events auto-refresh fills and the preview.
5. **Auto-repost** (default **OFF**): interval seconds (default **60**, minimum **30**). Only while Mode=**Hosting**. Rebuilds the message each tick; **stops** when all role caps are filled or the group hits Max size. Optional **Announce FULL** posts one public FULL line when stopping.

## RW Role Check (resync T/H/A/D places)

While **Mode = Hosting** (or Full Auto) and you are raid lead/assist (party lead → party/yell fallback):

1. `/alfm` → **Hosting** (or **Post**) → **RW Role Check**
2. Sends a configurable raid warning (default: `ROLE CHECK — whisper me tank / heal / aura / dps to sync MS slots`)
3. Opens a **listening window** (default **60s**): party/raid members who whisper a role update slot assignments live
4. Status shows `Role check active — Xs left · N responses`
5. When the window ends (if **Auto-resync** is on) — or anytime via **Resync roles now** — leavers are pruned, whisper roles re-applied, `ScanRaid` refreshes filled counts + LFM preview

RW is rate-limited (minimum **30s** between warnings). **Resync roles now** works without a prior RW (roster prune + recount only).

**Aura auto-move** (default ON, Hosting): at most one Aura-assigned player per raid subgroup (1–8); extras are moved with `SetRaidSubgroup` after assign / scan / resync.

## Full Auto Hosting (default OFF)

`/alfm` → **Hosting** → enable **Full Auto Hosting (master)**. This:

1. Sets Mode to **Hosting**
2. Turns on whisper auto-invite + LFG auto-invite + roster scan + auto-repost + reject-rewhisper

Turn it off anytime to clear that bundle (spam safety). Kick59 is never included — stays opt-in OFF on its own page.

## Queue + reject re-whisper

**Queue** lists recent hosting whispers (role + status) with **Invite** / **Reject+whisp**. Reject templates support `{role}` `{filled}` `{max}`, are rate-limited, and respect ignore lists.

## Opt-in level-59 kick

**Default OFF.** While **Hosting** and enabled:

1. Every **10 seconds**, if any party/raid member (not you) is level **≥ 59**, send a **Raid Warning** (or party/yell fallback) naming them.
2. Then **UninviteUnit** those players.
3. Log the kick (chat + UI “Recent kicks”).

Requires group leader (party) or raid leader/assist. No-ops safely otherwise.

## Parser examples

Recognized (case-insensitive), among others:

- `LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS`
- `LFG MS tank` / `lfg manastorm need heals` / `lfg ms`
- `lfm ms need tank and heals`
- `LFM Manastorm 1/2 Tank 2/3 H 0/7 DPS`
- `LFM mana storm …` / `LFM Mana-Storm …`
- Hosting whispers: `inv ms tank`, `heal`, `OT`, `HPS`, `Aura of Exp`, `exp aura`, `dps please`

Public listings need an LFM **or** LFG cue plus Manastorm (`MS` / `Manastorm` / `mana storm`). Duplicate spam from the same leader with the same slot fingerprint is suppressed for ~45s.

## Settings UI (`/alfm`)

Native DialogFrame with a left **Categories** sidebar:

| Category | Contents |
|----------|----------|
| **General** | Status (Listening ON/OFF, Full Auto) + mode Off / Notify / Seeking / Hosting |
| **Seeking** | My roles, Scan LFG MS, auto-whisper + rotating variants, leader blacklist, match sound |
| **Hosting** | Full Auto master, accept roles, invites, reject-rewhisper, presets, slots, **RW Role Check** |
| **Post** | LFM preview, channel, Post once, Scan, **RW Role Check / Resync**, auto-repost, announce FULL |
| **Queue** | Applicant whispers — Invite / Reject+rewhisper |
| **Kick** | Opt-in level-59 kick + recent kick log |
| **Log** | Match history + activity (posts / invites / rejects) |

## How to enable Full Auto Hosting

1. `/alfm` → **Hosting** → enable **Full Auto Hosting (master)** (default OFF).
2. Confirm Accept roles / slot caps (or load preset **MS 2/3/3/7**).
3. **Post** → pick channel; auto-repost is already on via Full Auto (interval ≥ 30s).
4. Watch **Queue** for applicants; reject-rewhisper is on via Full Auto.
5. `/alfm status` for a live dump. Kick59 stays off unless you enable it under **Kick**.

## How to enable hosting manually (without Full Auto)

1. `/alfm` → **General** → Mode **Hosting**.
2. **Hosting** → check **Accept roles** (Tank / Healer / Aura / DPS).
3. Set **Max T/H/A/D** slot caps (defaults 2/3/3/7) and **Max size** (15).
4. Leave **Auto-invite matching role whispers**, **Auto-invite LFG seekers**, and **Require role in whisper** on.
5. **Post** → **Scan raid/party** (optional) → pick channel → **Post once**, or enable **Auto-repost** (interval ≥ 30s).
6. Optionally **Hosting** → **RW Role Check** to resync T/H/A/D places from member whispers; or **Resync roles now**.
7. Optionally **Kick** → enable **Kick at level 59 + raid warning** (dangerous; default off).

## Safety

- Default mode is **Notify** (Log only). **Full Auto Hosting**, auto-invite, auto-whisper, auto-repost, reject-rewhisper, and level-59 kick remain **opt-in**; Full Auto, kick, and auto-repost default off.
- Never invites when the group is at **Max size** or the role **slot is full**.
- Auto-repost stops when slots are full or Max size is reached (optional FULL announce).
- Skips ignored players; rate-limits whispers/invites/rejects; kick RW cadence 10s; repost min interval 30s; Role Check RW min 30s.
- Classic chat/party APIs only (`InviteUnit`, `UninviteUnit`, `SendChatMessage`, roster APIs). No `C_*`, Draft/HoF, or Rapid Rolling hooks.

## Development

```bash
sh scripts/check.sh
```

Runs `luac5.1 -p` on all Lua files and pure Lua unit tests (parser / invite / slots / kick / poster / rolecheck / defaults).

## License

All Rights Reserved. Not affiliated with Ascension or Blizzard.
