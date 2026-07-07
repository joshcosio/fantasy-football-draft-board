param(
  [int]$PlayerLimit = 420,
  [string]$RankType = "PPR",
  [int]$CurrentSeason = 2026,
  [int]$PreviousSeason = 2025,
  [int]$ComparisonLimit = 1000
)

$ErrorActionPreference = "Stop"

$sourceUrl = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$CurrentSeason/segments/0/leaguedefaults/1?view=kona_player_info"
$previousSourceUrl = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$PreviousSeason/segments/0/leaguedefaults/1?view=kona_player_info"
$injurySourceUrl = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/injuries"
$fetchLimit = [Math]::Max([Math]::Max($PlayerLimit + 120, 500), $ComparisonLimit)
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

$teamNameMap = @{
  "1" = "Atlanta Falcons"
  "2" = "Buffalo Bills"
  "3" = "Chicago Bears"
  "4" = "Cincinnati Bengals"
  "5" = "Cleveland Browns"
  "6" = "Dallas Cowboys"
  "7" = "Denver Broncos"
  "8" = "Detroit Lions"
  "9" = "Green Bay Packers"
  "10" = "Tennessee Titans"
  "11" = "Indianapolis Colts"
  "12" = "Kansas City Chiefs"
  "13" = "Las Vegas Raiders"
  "14" = "Los Angeles Rams"
  "15" = "Miami Dolphins"
  "16" = "Minnesota Vikings"
  "17" = "New England Patriots"
  "18" = "New Orleans Saints"
  "19" = "New York Giants"
  "20" = "New York Jets"
  "21" = "Philadelphia Eagles"
  "22" = "Arizona Cardinals"
  "23" = "Pittsburgh Steelers"
  "24" = "Los Angeles Chargers"
  "25" = "San Francisco 49ers"
  "26" = "Seattle Seahawks"
  "27" = "Tampa Bay Buccaneers"
  "28" = "Washington Commanders"
  "29" = "Carolina Panthers"
  "30" = "Jacksonville Jaguars"
  "33" = "Baltimore Ravens"
  "34" = "Houston Texans"
}

$comparisonPositions = @("QB", "RB", "WR", "TE", "K")

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

function Get-NewsSnippet {
  param([string]$Text, [int]$WordLimit = 24)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
  }

  $words = @($Text -split '\s+' | Where-Object { $_ })
  if ($words.Count -le $WordLimit) {
    return $Text
  }

  return (($words | Select-Object -First $WordLimit) -join " ") + "..."
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

function Get-PlayerSortValue {
  param($Player, [string]$Type)

  $adp = Convert-NumberOrNull $Player.ownership.averageDraftPosition
  if ($null -ne $adp) {
    return $adp
  }

  $rank = Get-Rank $Player $Type
  if ($null -ne $rank) {
    return $rank
  }

  return 9999
}

function New-TeamChangePlayer {
  param(
    $Player,
    [string]$Status,
    [string]$Detail,
    [string]$Type
  )

  $positionKey = $Player.defaultPositionId.ToString()

  return [PSCustomObject]@{
    id = $Player.id
    name = $Player.fullName
    position = $positionMap[$positionKey]
    status = $Status
    detail = $Detail
    espnRank = Get-Rank $Player $Type
    adp = Convert-NumberOrNull $Player.ownership.averageDraftPosition
    sortValue = Get-PlayerSortValue $Player $Type
  }
}

Write-Host "Fetching ESPN fantasy football data..."
$response = Invoke-WebRequest -Uri $sourceUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
$payload = $response.Content | ConvertFrom-Json

Write-Host "Fetching ESPN $PreviousSeason comparison data..."
$previousResponse = Invoke-WebRequest -Uri $previousSourceUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
$previousPayload = $previousResponse.Content | ConvertFrom-Json

$injuryPayload = $null
try {
  Write-Host "Fetching ESPN NFL injury reports..."
  $injuryResponse = Invoke-WebRequest -Uri $injurySourceUrl -UseBasicParsing -TimeoutSec 60
  $injuryPayload = $injuryResponse.Content | ConvertFrom-Json
} catch {
  Write-Warning "ESPN injury reports could not be fetched. Player statuses will still be updated."
}

$injuryByPlayerId = @{}
if ($null -ne $injuryPayload) {
  foreach ($teamInjuries in $injuryPayload.injuries) {
    foreach ($injury in $teamInjuries.injuries) {
      $playerLink = $injury.athlete.links |
        Where-Object { $_.href -match '/id/(\d+)' -and $_.rel -contains "playercard" } |
        Select-Object -First 1

      if ($null -eq $playerLink -or $playerLink.href -notmatch '/id/(\d+)') {
        continue
      }

      $playerId = $Matches[1]
      $newsLink = $injury.athlete.links |
        Where-Object { $_.href -like "https://*" -and $_.rel -contains "news" } |
        Select-Object -First 1
      $note = $injury.athlete.notes.items | Select-Object -First 1
      $existingReport = $injuryByPlayerId[$playerId]

      if ($null -ne $existingReport -and [DateTime]$existingReport.date -ge [DateTime]$injury.date) {
        continue
      }

      $injuryByPlayerId[$playerId] = [PSCustomObject]@{
        id = $injury.id
        status = $injury.status
        date = $injury.date
        headline = Get-NewsSnippet $injury.shortComment
        source = if ($null -ne $note.source) { $note.source } else { "ESPN" }
        newsUrl = if ($null -ne $newsLink) { $newsLink.href } else { $playerLink.href }
        type = $injury.details.type
        location = $injury.details.location
        detail = $injury.details.detail
        side = $injury.details.side
        returnDate = $injury.details.returnDate
      }
    }
  }
}

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
    espnRank = $null
    draftRank = $rank
    adp = $adp
    positionRank = $null
    auctionValue = Get-AuctionValue $player $RankType
    percentOwned = Convert-NumberOrNull $player.ownership.percentOwned
    injuryStatus = $player.injuryStatus
    injuryReport = $injuryByPlayerId[$player.id.ToString()]
  }
}

$players = $players |
  Sort-Object @{ Expression = { if ($null -ne $_.adp) { $_.adp } else { 9999 } } }, @{ Expression = { if ($null -ne $_.draftRank) { $_.draftRank } else { 9999 } } }, name |
  Select-Object -First $PlayerLimit

$positionCounters = @{}
$boardCounter = 0
foreach ($player in $players) {
  $boardCounter += 1
  $player.boardRank = $boardCounter
  $player.espnRank = $boardCounter

  if (-not $positionCounters.ContainsKey($player.position)) {
    $positionCounters[$player.position] = 0
  }

  $positionCounters[$player.position] += 1
  $player.positionRank = "$($player.position)$($positionCounters[$player.position])"
}

$updatedAt = (Get-Date).ToUniversalTime().ToString("o")
$data = [PSCustomObject]@{
  meta = [PSCustomObject]@{
    season = $CurrentSeason
    rankType = $RankType
    rankSource = "ESPN Live Draft Trends order by average draft position"
    source = $sourceUrl
    injurySource = $injurySourceUrl
    injuryUpdatedAt = if ($null -ne $injuryPayload) { $injuryPayload.timestamp } else { $null }
    updatedAt = $updatedAt
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

$currentComparisonPlayers = @(
  $payload.players.player | Where-Object {
    $null -ne $_ -and
    $positionMap.ContainsKey($_.defaultPositionId.ToString()) -and
    $comparisonPositions -contains $positionMap[$_.defaultPositionId.ToString()]
  }
)

$previousComparisonPlayers = @(
  $previousPayload.players.player | Where-Object {
    $null -ne $_ -and
    $positionMap.ContainsKey($_.defaultPositionId.ToString()) -and
    $comparisonPositions -contains $positionMap[$_.defaultPositionId.ToString()]
  }
)

$currentById = @{}
foreach ($player in $currentComparisonPlayers) {
  $currentById[$player.id.ToString()] = $player
}

$previousById = @{}
foreach ($player in $previousComparisonPlayers) {
  $previousById[$player.id.ToString()] = $player
}

$teams = [ordered]@{}
$teamIds = $teamMap.Keys | Where-Object { $_ -ne "0" } | Sort-Object { [int]$_ }

foreach ($teamId in $teamIds) {
  $teamAbbreviation = $teamMap[$teamId]
  $positions = [ordered]@{}

  foreach ($position in $comparisonPositions) {
    $currentPlayers = foreach ($player in $currentComparisonPlayers) {
      if ($player.proTeamId.ToString() -ne $teamId -or $positionMap[$player.defaultPositionId.ToString()] -ne $position) {
        continue
      }

      $previousPlayer = $previousById[$player.id.ToString()]
      if ($null -ne $previousPlayer -and $previousPlayer.proTeamId.ToString() -eq $teamId) {
        New-TeamChangePlayer $player "returning" "Returning" $RankType
        continue
      }

      $previousTeamId = if ($null -ne $previousPlayer) { $previousPlayer.proTeamId.ToString() } else { "0" }
      $detail = if ($teamMap.ContainsKey($previousTeamId) -and $previousTeamId -ne "0") {
        "From $($teamMap[$previousTeamId])"
      } else {
        "New in $CurrentSeason"
      }

      New-TeamChangePlayer $player "joined" $detail $RankType
    }

    $departedPlayers = foreach ($player in $previousComparisonPlayers) {
      if ($player.proTeamId.ToString() -ne $teamId -or $positionMap[$player.defaultPositionId.ToString()] -ne $position) {
        continue
      }

      $currentPlayer = $currentById[$player.id.ToString()]
      if ($null -ne $currentPlayer -and $currentPlayer.proTeamId.ToString() -eq $teamId) {
        continue
      }

      $currentTeamId = if ($null -ne $currentPlayer) { $currentPlayer.proTeamId.ToString() } else { "0" }
      $detail = if ($teamMap.ContainsKey($currentTeamId) -and $currentTeamId -ne "0") {
        "To $($teamMap[$currentTeamId])"
      } else {
        "Left roster"
      }

      New-TeamChangePlayer $player "departed" $detail $RankType
    }

    $positions[$position] = [PSCustomObject]@{
      current = @($currentPlayers | Sort-Object sortValue, name | Select-Object id, name, position, status, detail, espnRank, adp)
      departed = @($departedPlayers | Sort-Object sortValue, name | Select-Object id, name, position, status, detail, espnRank, adp)
    }
  }

  $teams[$teamAbbreviation] = [PSCustomObject]@{
    id = [int]$teamId
    name = $teamNameMap[$teamId]
    abbreviation = $teamAbbreviation
    logo = "https://a.espncdn.com/i/teamlogos/nfl/500/$($teamAbbreviation.ToLower()).png"
    espnDepthChart = "https://www.espn.com/nfl/team/depth/_/name/$($teamAbbreviation.ToLower())"
    positions = $positions
  }
}

$teamChangesData = [PSCustomObject]@{
  meta = [PSCustomObject]@{
    currentSeason = $CurrentSeason
    previousSeason = $PreviousSeason
    rankType = $RankType
    updatedAt = $updatedAt
    currentSource = $sourceUrl
    previousSource = $previousSourceUrl
  }
  teams = $teams
}

$teamChangesJson = $teamChangesData | ConvertTo-Json -Depth 10 -Compress
$teamChangesContent = "window.TEAM_CHANGES = $teamChangesJson;"
Set-Content -Path (Join-Path $dataDirectory "team-changes.js") -Value $teamChangesContent -Encoding UTF8

Write-Host "Wrote $($teams.Count) team comparisons to data/team-changes.js"
