# AscensionLFM

WotLK **3.3.5a** addon for Ascension / Project Ebonhold that scans chat and whispers for **Manastorm Level Run** LFM messages, notifies you of matches, and optionally auto-whispers leaders or auto-invites applicants when you host.

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
2. **Notify only** — print matching Manastorm LFM lines to chat and list them in the UI.
3. **Seeking** — notify when a listing still needs one of **your** roles; optional **auto-whisper** the leader (rate-limited, respect ignore list).
4. **Hosting** — scan incoming whispers for tank/heal/aura/dps requests and **InviteUnit** when that role is enabled and the party is not full.

## Parser examples

Recognized (case-insensitive), among others:

- `LFM MS 0/2 Tanks 0/3 Healers 0/3 Aura 0/7 DPS`
- `lfm ms need tank and heals`
- `LFM Manastorm 1/2 Tank 2/3 H 0/7 DPS`
- `LFM MS 0/7 DPS 0/3 Heals 0/2 Tanks` (shuffled roles)
- Hosting whispers: `inv ms tank`, `heal`, `dps please`

Requires both an LFM-style cue (`LFM`, `LF#M`, “looking for more”) and a Manastorm cue (`MS` / `Manastorm`) for public listings. Duplicate spam from the same leader with the same slot fingerprint is suppressed for ~45s.

## Safety

- Auto-invite and auto-whisper are **opt-in** (mode + toggles); default mode is Off.
- Never invites when the group is at **Max size**.
- Skips ignored players; rate-limits whispers/invites.
- Classic chat/party APIs only (`InviteUnit`, `SendChatMessage`, `GetNumPartyMembers` / raid equivalents). No `C_Wildcard`, Draft/HoF, or Rapid Rolling hooks.

## Development

```bash
sh scripts/check.sh
```

Runs `luac5.1 -p` on all Lua files and pure Lua parser/invite unit tests.

## License

All Rights Reserved. Not affiliated with Ascension or Blizzard.
