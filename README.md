# AscensionLFM

WotLK **3.3.5a** addon for Ascension that scans chat and whispers for **Manastorm Level Run** **LFM** and **LFG** messages, notifies you of matches, and optionally auto-whispers leaders or auto-invites applicants when you host — with per-role slot caps and an opt-in level-59 auto-kick.

## Install

1. Download `AscensionLFM.zip` from [Releases](https://github.com/Lzra2000/AscensionLFM/releases).
2. Extract so you have `Interface/AddOns/AscensionLFM/AscensionLFM.toc`.
3. Restart the client (or `/reload`).

## Slash commands

| Command | Action |
|---------|--------|
| `/alfm` | Open settings |
| `/mslfm` | Same |
| `/alfm status` | Print current mode |

## Modes (default: **Off**)

1. **Off** — no scanning side effects (addon still loads).
2. **Notify only** — print matching Manastorm LFM/LFG lines to chat and list them in the UI.
3. **Seeking** — notify when a listing still needs one of **your** roles; optional **auto-whisper** the LFM leader (rate-limited, respect ignore list). LFG lines are notified when **Scan LFG MS** is on (no auto-whisper to seekers).
4. **Hosting** — scan incoming whispers for tank/heal/aura/dps (incl. Aura of Exp / OT / MT / HPS) and **InviteUnit** only when that role is accepted **and** a host slot remains.

## Hosting: slots + invites

Default Manastorm level-run caps: **2 tank / 3 healer / 3 aura / 7 DPS** (editable in UI). The filled/max row updates as invites assign roles from whispers. Party/raid roster changes drop leavers from the assignment map; unknown roles for manually invited players stay uncounted until they whisper a role.

- Whispers with **no role** are not invited (default-deny; toggle “Require role in whisper”).
- Slot full → no invite for that role.
- Overall **Max size** (default 15) still blocks when the group is full.

## Opt-in level-59 kick

**Default OFF.** While **Hosting** and enabled:

1. Every **10 seconds**, if any party/raid member (not you) is level **≥ 59**, send a **Raid Warning** (or party/yell fallback) naming them.
2. Then **UninviteUnit** those players.
3. Log the kick (chat + UI “Recent kicks”).

Requires group leader (party) or raid leader/assist. No-ops safely otherwise.

## Parser examples

Recognized (case-insensitive), among others:

- `LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS`
- `LFG MS tank` / `lfg manastorm need heals`
- `lfm ms need tank and heals`
- `LFM Manastorm 1/2 Tank 2/3 H 0/7 DPS`
- Hosting whispers: `inv ms tank`, `heal`, `OT`, `HPS`, `Aura of Exp`, `exp aura`, `dps please`

Public listings need an LFM **or** LFG cue plus Manastorm (`MS` / `Manastorm`). Duplicate spam from the same leader with the same slot fingerprint is suppressed for ~45s.

## Settings UI (`/alfm`)

Native DialogFrame with a left **Categories** sidebar:

| Category | Contents |
|----------|----------|
| **General** | Status + mode Off / Notify / Seeking / Hosting |
| **Seeking** | My roles, Scan LFG MS, auto-whisper + message |
| **Hosting** | Accept roles, auto-invite, require-role, max size, slot caps T/H/A/D + filled |
| **Kick** | Opt-in level-59 kick + recent kick log |
| **Log** | Recent LFM/LFG matches (Clear) |

## How to enable hosting + slots + 59-kick

1. `/alfm` → **General** → Mode **Hosting**.
2. **Hosting** → check **Accept roles** (Tank / Healer / Aura / DPS).
3. Set **Max T/H/A/D** slot caps (defaults 2/3/3/7) and **Max size** (15).
4. Leave **Auto-invite matching role whispers** and **Require role in whisper** on.
5. Optionally **Kick** → enable **Kick at level 59 + raid warning** (dangerous; default off).

## Safety

- Auto-invite, auto-whisper, and level-59 kick are **opt-in**; default mode is Off; kick defaults off.
- Never invites when the group is at **Max size** or the role **slot is full**.
- Skips ignored players; rate-limits whispers/invites; kick RW cadence 10s.
- Classic chat/party APIs only (`InviteUnit`, `UninviteUnit`, `SendChatMessage`, roster APIs). No `C_*`, Draft/HoF, or Rapid Rolling hooks.

## Development

```bash
sh scripts/check.sh
```

Runs `luac5.1 -p` on all Lua files and pure Lua unit tests (parser / invite / slots / kick).

## License

All Rights Reserved. Not affiliated with Ascension or Blizzard.
