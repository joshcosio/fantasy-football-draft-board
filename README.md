# 2026 Fantasy Football Draft Board

A personal draft board for organizing 2026 fantasy football player notes by round.

## Features

- ESPN PPR rank and ADP display
- Round-based draft board layout
- Good Pick / Bad Pick labels saved in the browser
- Search, position filtering, status filtering, and league-size controls
- Local ESPN data updater script

## Run Locally

```powershell
node .\scripts\serve-static.mjs 4173
```

Then open:

```text
http://127.0.0.1:4173/
```

## Refresh ESPN Data

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update-espn-data.ps1 -PlayerLimit 360 -RankType PPR
```
