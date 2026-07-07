# 2026 Fantasy Football Draft Board

A personal draft board for organizing 2026 fantasy football player notes by round.

## Features

- ESPN live draft rank and ADP display
- Round-based draft board layout
- Good Pick / Bad Pick labels saved in the browser
- Clickable team abbreviations with 2025-to-2026 fantasy roster changes
- Search, position filtering, status filtering, and league-size controls
- Local ESPN data updater script

https://joshcosio.github.io/fantasy-football-draft-board/

## Run Locally

```powershell
node .\scripts\serve-static.mjs 4173
```

Then open:

```text
http://127.0.0.1:4173/
```

## Refresh ESPN Data

This updates both the player rankings and all 32 team comparisons.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-espn-data.ps1 -PlayerLimit 420 -RankType PPR
```
