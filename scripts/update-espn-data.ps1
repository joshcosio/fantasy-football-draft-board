param(
  [int]$PlayerLimit = 360,
  [string]$RankType = "PPR"
)

$ErrorActionPreference = "Stop"

$sourceUrl = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/2026/segments/0/leaguedefaults/1?view=kona_player_info"
$fetchLimit = [Math]::Max($PlayerLimit + 120, 500)
$filter = @{
  players = @{
    limit = $fetchLimit
    sortDraftRanks = @{
      sortPriority = 100
      sortAsc = $true
      value = $RankType
    }
  }
} | ConvertTo-Json -Compress -Depth 10

$headers = @{
  "x-fantasy-filter" = $filter
}

$positionMap = @{
  "1" = "QB"
  "2" = "RB"
  "3" = "WR"
  "4" = "TE"
  "5" = "K"
  "16" = "D/ST"
}

$teamMap = @{
  "0" = "FA"
  "1" = "ATL"
  "2" = "BUF"
  "3" = "CHI"
  "4" = "CIN"
  "5" = "CLE"
  "6" = "DAL"
  "7" = "DEN"
  "8" = "DET"
  "9" = "GB"
  "10" = "TEN"
  "11" = "IND"
  "12" = "KC"
  "13" = "LV"
  "14" = "LAR"
  "15" = "MIA"
  "16" = "MIN"
  "17" = "NE"
  "18" = "NO"
  "19" = "NYG"
  "20" = "NYJ"
  "21" = "PHI"
  "22" = "ARI"
  "23" = "PIT"
  "24" = "LAC"
  "25" = "SF"
  "26" = "SEA"
  "27" = "TB"
  "28" = "WSH"
  "29" = "CAR"
  "30" = "JAX"
  "33" = "BAL"
  "34" = "HOU"
}

function Convert-NumberOrNull {
  param($Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal]) {
    return [double]$Value
  }

  $parsed = 0.0
  if ([double]::TryParse($Value.ToString(), [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-Rank {
  param($Player, [string]$Type)

  if ($Player.draftRanksByRankType -and $Player.draftRanksByRankType.$Type) {
    return Convert-NumberOrNull $Player.draftRanksByRankType.$Type.rank
  }

  return $null
}

function Get-AuctionValue {
  param($Player, [string]$Type)

  if ($Player.draftRanksByRankType -and $Player.draftRanksByRankType.$Type) {
    return Convert-NumberOrNull $Player.draftRanksByRankType.$Type.auctionValue
  }

  return $null
}

Write-Host "Fetching ESPN fantasy football data..."
$response = Invoke-WebRequest -Uri $sourceUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
$payload = $response.Content | ConvertFrom-Json

$players = foreach ($entry in $payload.players) {
  $player = $entry.player
  if ($null -eq $player) {
    continue
  }

  $positionKey = $player.defaultPositionId.ToString()
  if (-not $positionMap.ContainsKey($positionKey)) {
    continue
  }

  $rank = Get-Rank $player $RankType
  $adp = Convert-NumberOrNull $player.ownership.averageDraftPosition
  if ($null -eq $rank -and $null -eq $adp) {
    continue
  }

  $teamKey = $player.proTeamId.ToString()
  $team = if ($teamMap.ContainsKey($teamKey)) { $teamMap[$teamKey] } else { "NFL" }
  $position = $positionMap[$positionKey]

  [PSCustomObject]@{
    id = $player.id
    name = $player.fullName
    position = $position
    team = $team
    boardRank = $null
    espnRank = $rank
    adp = $adp
    positionRank = $null
    auctionValue = Get-AuctionValue $player $RankType
    percentOwned = Convert-NumberOrNull $player.ownership.percentOwned
    injuryStatus = $player.injuryStatus
  }
}

$players = $players |
  Sort-Object @{ Expression = { if ($null -ne $_.espnRank) { $_.espnRank } else { 9999 } } }, @{ Expression = { if ($null -ne $_.adp) { $_.adp } else { 9999 } } } |
  Select-Object -First $PlayerLimit

$positionCounters = @{}
$boardCounter = 0
foreach ($player in $players) {
  $boardCounter += 1
  $player.boardRank = $boardCounter

  if (-not $positionCounters.ContainsKey($player.position)) {
    $positionCounters[$player.position] = 0
  }

  $positionCounters[$player.position] += 1
  $player.positionRank = "$($player.position)$($positionCounters[$player.position])"
}

$data = [PSCustomObject]@{
  meta = [PSCustomObject]@{
    season = 2026
    rankType = $RankType
    source = $sourceUrl
    updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    playerCount = $players.Count
  }
  players = $players
}

$json = $data | ConvertTo-Json -Depth 8
$content = "window.DRAFT_DATA = $json;"

$dataDirectory = Join-Path $PSScriptRoot "..\data"
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
Set-Content -Path (Join-Path $dataDirectory "players.js") -Value $content -Encoding UTF8

Write-Host "Wrote $($players.Count) players to data/players.js"
