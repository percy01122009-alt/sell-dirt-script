# Sell Dirt — Delta Android Script

Automation suite for the Roblox game **Sell Dirt** (heuristic/recon-based — works across common Sell Dirt variants by discovering sell zones, prompts, remotes, and the crown at runtime). Built for **Delta Executor on Android**.

> **Game link (from your request):** `https://www.roblox.com/share?code=a3dece99db8e70448ac9696775b3a133&type=ExperienceDetails&stamp=1794136330896`
>
> The script does **not** hardcode object names. Use the **Exploit → Dump recon** / **Grind → Dump recon** buttons in-game to see what your server exposes, then set target overrides if needed.

## Quick start (Delta Android)

### Option A — Paste the built script (simplest)
1. Open [`dist/SellDirt.lua`](dist/SellDirt.lua) and copy its **entire** contents.
2. Join **Sell Dirt** in Roblox.
3. Open **Delta Executor** → paste the script → **Execute**.
4. The GUI appears (draggable). Start with **Grind → Dump recon to console** (F9 in desktop; on mobile use Delta's console if available) to verify targets.

### Option B — Loadstring from a hosted raw URL (recommended for updates)
Host `dist/SellDirt.lua` somewhere Delta can fetch (GitHub raw, Pastebin raw, your own HTTPS host). Then execute:

```lua
-- Set this so "Queue script on teleport/hop" can re-run after server hop/rejoin.
getgenv().SD_LOADSTRING_URL = "https://YOUR_HOST/raw/SellDirt.lua"

loadstring(game:HttpGet(getgenv().SD_LOADSTRING_URL))()
```

**Notes:**
- `loadstring` + `HttpGet` require an executor that supports HTTP requests (Delta typically does).
- `queue_on_teleport` (auto re-execute after teleport/hop) only works if your executor supports `queue_on_teleport` **and** `SD_LOADSTRING_URL` is set to a reachable URL.

## Features

### Grind / automation
- **Auto sell** — visits discovered sell zone/prompt; optional return to dig anchor; **remote sell fallback** fires sell-like remotes if no physical zone is found.
- **Auto dig** — equips a shovel/pickaxe-like tool and triggers it (remote or tool activation); configurable interval/method.
- **Auto collect** — fires nearby `ProximityPrompt`s (collectibles/rewards).
- **Auto upgrade / Auto rebirth-prestige** — heuristic discovery + interaction (manual verification recommended; rebirth can reset progress).
- **Target overrides** — manually set sell/crown/dig tool/sell remote names when heuristics miss.
- **Manual actions** — Sell now, Fire sell-like remotes now, Dump recon.

### Movement / crown grinding
- **Auto TP to crown** — teleports toward discovered crown objects or the current leaderboard leader (useful for crown-holding/leaderboard strategies when the game awards by proximity/time; behavior depends on the game's rules).
- **TP buttons** — crown, sell zone, nearest dirt, set/return anchor.
- **Speed** — WalkSpeed/JumpPower controls (client-side; may be limited by anti-cheat).

### Visuals / utility
- ESP highlights for crown/sell/dirt/players.
- Fullbright, FPS boost (disables post effects).
- Anti-AFK, auto rejoin, pause automation, session stats.
- Config save/load (executor filesystem required).

### Exploit / discovery tab (manual, diagnostic)
These tools help you **find** server-side weaknesses; they do not blindly fire everything on load.
- **Dump recon** — lists remotes/prompts/leaderstats and grind-related candidates.
- **Auto-hunt** — probes candidate remotes and measures **leaderstat/cash delta** (a positive delta suggests a weakly validated remote; results vary by game and can be risky).
- **Remote picker + Fire once / Fuzz** — manually test specific remotes with arguments.
- **Prompt spoof / Click spoof** — fires all discovered prompts/click detectors (use carefully).
- **Log client values / Write matching values** — inspects/writes client `ValueBase` instances (usually cosmetic/local; rarely authoritative).

**Safety note:** exploiting, autofarming, and remote tampering can violate Roblox rules and may result in kicks/bans. Use on accounts you accept risk on, test conservatively, and prefer manual discovery before enabling automation.

## Build from source

The modular source lives in `src/`:

```sh
sh build.sh
# outputs dist/SellDirt.lua
```

Modules: `00_core.lua`, `10_recon.lua`, `20_gui.lua`, `30_features.lua`, `40_exploits.lua`, `50_boot.lua`.

## Troubleshooting

- **Nothing happens:** run **Dump recon**, check the Delta console for `[SD]` logs, and set **Target overrides** (sell/crown names) in the Grind tab.
- **Auto sell doesn't find a zone:** enable **Remote sell fallback**, try **Fire sell-like remotes now**, or set `sell remote` override.
- **Crown TP not working:** the crown may be awarded by game logic rather than a physical object; auto TP targets the leaderboard leader or a discovered crown object — verify what "crown" means in this specific Sell Dirt server.
- **Config not saving:** some executors restrict `writefile`; settings still work for the current session.
- **Script stops after server hop:** host the script and set `getgenv().SD_LOADSTRING_URL` with `queue_on_teleport` enabled (if supported).

## Files

- `dist/SellDirt.lua` — built, single-file script (execute this).
- `src/*.lua` — modular source.
- `build.sh` — concatenates modules into `dist/SellDirt.lua`.
- `test/smoke.lua` — headless smoke test harness (requires a Lua runtime + the fake DataModel in the test; not required for in-game use).
