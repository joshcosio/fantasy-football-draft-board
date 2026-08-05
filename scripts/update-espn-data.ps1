param(
  [int]$PlayerLimit = 420,
  [string]$RankType = "PPR",
  [int]$CurrentSeason = 2026,
  [int]$PreviousSeason = 2025,
  [int]$ComparisonLimit = 1000,
  [int]$InjuryHistoryLimit = 180
)

$ErrorActionPreference = "Stop"

$sourceUrl = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$CurrentSeason/segments/0/leaguedefaults/1?view=kona_player_info"
$previousSourceUrl = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$PreviousSeason/segments/0/leaguedefaults/1?view=kona_player_info"
$previousAdpSourceUrl = "https://fantasydata.com/nfl/ppr-adp?season=$PreviousSeason"
$previousAdpPositionPaths = @("qb", "rb", "wr", "te", "k", "dst")
$injurySourceUrl = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/injuries"
$injuryHistoryBaseUrl = "https://www.playerprofiler.com/nfl/"
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
$dataDirectory = Join-Path $PSScriptRoot "..\data"
$pprReceptionStatId = "41"
$playerProfilerSlugOverrides = @{
  "4432708" = "marvin-harrison-2"
  "4241985" = "j-k-dobbins"
  "4688380" = "cameron-ward"
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

function Get-RoundedNumberOrNull {
  param($Value, [int]$Decimals = 1)

  $number = Convert-NumberOrNull $Value
  if ($null -eq $number) {
    return $null
  }

  return [Math]::Round($number, $Decimals)
}

function Get-NormalizedPlayerName {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return ""
  }

  $decoded = [System.Net.WebUtility]::HtmlDecode($Name)
  $normalized = $decoded.Normalize([System.Text.NormalizationForm]::FormD)
  $withoutMarks = [regex]::Replace($normalized, "\p{Mn}", "")
  $withoutTeamName = $withoutMarks -replace '\s+D/ST$', ''
  $withoutSuffix = [regex]::Replace($withoutTeamName, "\s+(Jr\.?|Sr\.?|II|III|IV|V)$", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  return ([regex]::Replace($withoutSuffix.ToLowerInvariant(), "[^a-z0-9]", ""))
}

function Get-PlayerLookupKey {
  param([string]$Name, [string]$Position)

  return "$(Get-NormalizedPlayerName $Name)|$Position"
}

function Get-PlayerProfilerSlug {
  param($Player)

  $playerId = $Player.id.ToString()
  if ($playerProfilerSlugOverrides.ContainsKey($playerId)) {
    return $playerProfilerSlugOverrides[$playerId]
  }

  $decoded = [System.Net.WebUtility]::HtmlDecode($Player.name)
  $normalized = $decoded.Normalize([System.Text.NormalizationForm]::FormD)
  $withoutMarks = [regex]::Replace($normalized, "\p{Mn}", "")
  $withoutSuffix = [regex]::Replace($withoutMarks, "\s+(Jr\.?|Sr\.?|II|III|IV|V)$", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $withoutInitialDots = $withoutSuffix -replace "\.", ""
  $withoutApostrophes = $withoutInitialDots -replace "['’]", ""
  $slug = [regex]::Replace($withoutApostrophes.ToLowerInvariant(), "[^a-z0-9]+", "-").Trim("-")

  return $slug
}

function Get-PlayerProfilerInjuryUrl {
  param($Player)

  $slug = Get-PlayerProfilerSlug $Player
  if ([string]::IsNullOrWhiteSpace($slug)) {
    return $null
  }

  return "$injuryHistoryBaseUrl$slug/"
}

function Get-PositionFromRank {
  param([string]$PositionRank)

  if ([string]::IsNullOrWhiteSpace($PositionRank)) {
    return $null
  }

  $base = [regex]::Match($PositionRank.Trim().ToUpperInvariant(), "^[A-Z/]+").Value
  if ($base -eq "DST") {
    return "D/ST"
  }

  return $base
}

function Get-DisplayPositionRank {
  param([string]$PositionRank)

  if ([string]::IsNullOrWhiteSpace($PositionRank)) {
    return $null
  }

  $trimmed = $PositionRank.Trim().ToUpperInvariant()
  if ($trimmed -match '^DST(\d+)$') {
    return "D/ST$($Matches[1])"
  }

  return $trimmed
}

function Get-HtmlTableCellText {
  param([string]$CellHtml)

  if ([string]::IsNullOrWhiteSpace($CellHtml)) {
    return ""
  }

  $withoutTags = [regex]::Replace($CellHtml, "<[^>]+>", "")
  $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
  return ([regex]::Replace($decoded, "\s+", " ")).Trim()
}

function Get-HtmlTableCells {
  param([string]$RowHtml)

  return @(
    [regex]::Matches($RowHtml, "<td\b[^>]*>(.*?)</td>", [System.Text.RegularExpressions.RegexOptions]::Singleline) |
      ForEach-Object { Get-HtmlTableCellText $_.Groups[1].Value }
  )
}

function Convert-SeverityColor {
  param([string]$Color)

  $normalized = ($Color -replace "[^a-fA-F0-9]", "").ToLowerInvariant()
  if ($normalized -eq "72cf6b") {
    return "low"
  }

  if ($normalized -eq "feea5e") {
    return "medium"
  }

  return "high"
}

function Get-InjuryHistoryRowText {
  param([string]$Html)

  $withoutTags = [regex]::Replace($Html, "<[^>]+>", " ")
  $decoded = [System.Net.WebUtility]::HtmlDecode($withoutTags)
  return ([regex]::Replace($decoded, "\s+", " ")).Trim()
}

function Get-PprFantasyPointTotal {
  param($Stat)

  $standardTotal = Convert-NumberOrNull $Stat.appliedTotal
  if ($null -eq $standardTotal) {
    return $null
  }

  $receptions = 0.0
  if ($Stat.stats) {
    $receptionProperty = $Stat.stats.PSObject.Properties[$pprReceptionStatId]
    if ($null -ne $receptionProperty) {
      $receptionTotal = Convert-NumberOrNull $receptionProperty.Value
      if ($null -ne $receptionTotal) {
        $receptions = $receptionTotal
      }
    }
  }

  return $standardTotal + $receptions
}

function Get-ExistingDraftData {
  $playersPath = Join-Path $dataDirectory "players.js"

  if (-not (Test-Path $playersPath)) {
    return $null
  }

  try {
    $raw = Get-Content -Raw -Path $playersPath
    $match = [regex]::Match($raw, "^\s*window\.DRAFT_DATA\s*=\s*(.*);\s*$", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
      return $null
    }

    return ($match.Groups[1].Value | ConvertFrom-Json)
  } catch {
    Write-Warning "Existing player data could not be read."
    return $null
  }
}

function Get-ExistingInjuryHistoryCache {
  $cache = @{}
  $existingData = Get-ExistingDraftData
  if ($null -eq $existingData) {
    return $cache
  }

  foreach ($existingPlayer in @($existingData.players)) {
    if ($null -ne $existingPlayer.injuryHistory) {
      $cache[$existingPlayer.id.ToString()] = $existingPlayer.injuryHistory
    }
  }

  return $cache
}

function Get-ExistingInjuryReportCache {
  $cache = @{
    reports = @{}
    updatedAt = $null
  }
  $existingData = Get-ExistingDraftData
  if ($null -eq $existingData) {
    return $cache
  }

  $cache.updatedAt = $existingData.meta.injuryUpdatedAt
  foreach ($existingPlayer in @($existingData.players)) {
    if ($null -ne $existingPlayer.injuryReport) {
      $cache.reports[$existingPlayer.id.ToString()] = $existingPlayer.injuryReport
    }
  }

  return $cache
}

function Get-PlayerProfilerInjuryHistory {
  param($Player, [string]$FetchedAt)

  $sourceUrl = Get-PlayerProfilerInjuryUrl $Player
  if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
    return $null
  }

  try {
    $response = Invoke-WebRequest -Uri $sourceUrl -UseBasicParsing -TimeoutSec 30
    $content = $response.Content
    $rowPattern = '<div class="player-page-injury-table-row"[^>]*>[\s\S]*?border-left:\s*8px solid\s*(?<color>#[0-9A-Fa-f]+)[\s\S]*?<div class="font-display[^"]*">\s*(?<injury>.*?)\s*</div>\s*<div class="text-xs font-bold text-blue-light">\s*(?<period>.*?)\s*</div>[\s\S]*?<span>\s*(?<gamesMissed>\d+)\s*</span>[\s\S]*?<div class="w-16 text-center">\s*(?<reports>\d+)\s*</div>'
    $items = @()

    foreach ($rowMatch in [regex]::Matches($content, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
      $period = Get-InjuryHistoryRowText $rowMatch.Groups["period"].Value
      $season = $null
      $week = $period

      if ($period -match "^(?<week>.+?)\s+\((?<season>\d{4})\)$") {
        $week = $Matches["week"]
        $season = [int]$Matches["season"]
      }

      $items += [PSCustomObject]@{
        injury = Get-InjuryHistoryRowText $rowMatch.Groups["injury"].Value
        period = $period
        week = $week
        season = $season
        severity = Convert-SeverityColor $rowMatch.Groups["color"].Value
        severityColor = $rowMatch.Groups["color"].Value
        gamesMissed = [int]$rowMatch.Groups["gamesMissed"].Value
        injuryReports = [int]$rowMatch.Groups["reports"].Value
      }
    }

    return [PSCustomObject]@{
      source = "PlayerProfiler"
      sourceUrl = $sourceUrl
      available = $true
      fetchedAt = $FetchedAt
      items = @($items)
    }
  } catch {
    return [PSCustomObject]@{
      source = "PlayerProfiler"
      sourceUrl = $sourceUrl
      available = $false
      fetchedAt = $FetchedAt
      error = "History unavailable"
      items = @()
    }
  }
}

function Get-WeeklyFantasySummary {
  param($Player, [int[]]$Weeks)

  $points = @()
  foreach ($stat in @($Player.stats)) {
    if ($null -eq $stat -or $stat.statSourceId -ne 0 -or $stat.statSplitTypeId -ne 1) {
      continue
    }

    $week = [int]$stat.scoringPeriodId
    if ($Weeks -notcontains $week) {
      continue
    }

    $pointTotal = Get-PprFantasyPointTotal $stat
    if ($null -ne $pointTotal) {
      $points += $pointTotal
    }
  }

  if ($points.Count -eq 0) {
    return $null
  }

  $total = ($points | Measure-Object -Sum).Sum
  return [PSCustomObject]@{
    ppg = Get-RoundedNumberOrNull ($total / $points.Count)
    total = Get-RoundedNumberOrNull $total
    games = $points.Count
    positionRank = $null
  }
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
  Write-Warning "ESPN injury reports could not be fetched. Cached injury reports will be reused if available."
}

$injuryByPlayerId = @{}
$injuryUpdatedAt = if ($null -ne $injuryPayload) { $injuryPayload.timestamp } else { $null }
if ($null -eq $injuryPayload) {
  $existingInjuryReports = Get-ExistingInjuryReportCache
  $injuryByPlayerId = $existingInjuryReports.reports
  $injuryUpdatedAt = $existingInjuryReports.updatedAt
  if ($injuryByPlayerId.Count -gt 0) {
    Write-Warning "Using $($injuryByPlayerId.Count) cached ESPN injury reports from $injuryUpdatedAt."
  }
}
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

$previousAdpByKey = @{}
$previousAdpEntries = New-Object System.Collections.Generic.List[object]
Write-Host "Fetching FantasyData $PreviousSeason preseason ADP..."

foreach ($positionPath in $previousAdpPositionPaths) {
  $positionAdpUrl = "https://fantasydata.com/nfl/ppr-adp/${positionPath}?season=$PreviousSeason"

  try {
    $previousAdpResponse = Invoke-WebRequest -Uri $positionAdpUrl -UseBasicParsing -TimeoutSec 30
    $rowMatches = [regex]::Matches($previousAdpResponse.Content, "<tr\b[^>]*>.*?</tr>", [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($rowMatch in $rowMatches) {
      $cells = Get-HtmlTableCells $rowMatch.Value
      if ($cells.Count -eq 0) {
        continue
      }

      $name = $null
      $team = $null
      $position = $null
      $positionRank = $null
      $adp = $null

      if ($positionPath -eq "dst") {
        if ($cells.Count -lt 5) {
          continue
        }

        $team = $cells[1]
        $name = "$team D/ST"
        $position = "D/ST"
        $positionRank = Get-DisplayPositionRank $cells[3]
        $adp = Get-RoundedNumberOrNull $cells[4] 1
      } else {
        if ($cells.Count -lt 8) {
          continue
        }

        $name = $cells[1]
        $team = $cells[2]
        $position = $cells[5].Trim().ToUpperInvariant()
        $positionRank = Get-DisplayPositionRank $cells[6]
        $adp = Get-RoundedNumberOrNull $cells[7] 1
      }

      if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($position) -or $null -eq $adp) {
        continue
      }

      $lookupName = if ($position -eq "D/ST") { $team } else { $name }
      $lookupKey = Get-PlayerLookupKey $lookupName $position
      if ([string]::IsNullOrWhiteSpace($lookupKey)) {
        continue
      }

      [void]$previousAdpEntries.Add([PSCustomObject]@{
        lookupKey = $lookupKey
        data = [PSCustomObject]@{
          source = "FantasyData historical $PreviousSeason PPR ADP"
          sourceUrl = $positionAdpUrl
          overallRank = $null
          positionRank = $positionRank
          average = $adp
        }
      })
    }
  } catch {
    Write-Warning "FantasyData $positionPath ADP could not be fetched."
  }
}

$overallAdpRank = 0
foreach ($entry in $previousAdpEntries | Sort-Object @{ Expression = { $_.data.average } }, lookupKey) {
  $overallAdpRank += 1
  $entry.data.overallRank = $overallAdpRank
}

foreach ($entry in $previousAdpEntries) {
  if (-not $previousAdpByKey.ContainsKey($entry.lookupKey)) {
    $previousAdpByKey[$entry.lookupKey] = $entry.data
  }
}

if ($previousAdpByKey.Count -eq 0) {
  Write-Warning "FantasyData ADP rows could not be found. Previous-season ADP will be unavailable."
}

$previousFantasyPlayers = @(
  $previousPayload.players.player | Where-Object {
    $null -ne $_ -and $positionMap.ContainsKey($_.defaultPositionId.ToString())
  }
)

$previousPlayerById = @{}
$previousPerformanceById = @{}
foreach ($previousPlayer in $previousFantasyPlayers) {
  $position = $positionMap[$previousPlayer.defaultPositionId.ToString()]
  $previousPlayerById[$previousPlayer.id.ToString()] = $previousPlayer

  $previousPerformanceById[$previousPlayer.id.ToString()] = [PSCustomObject]@{
    id = $previousPlayer.id
    name = $previousPlayer.fullName
    position = $position
    start = Get-WeeklyFantasySummary $previousPlayer (1..9)
    finish = Get-WeeklyFantasySummary $previousPlayer (9..18)
  }
}

foreach ($splitName in @("start", "finish")) {
  foreach ($position in $positionMap.Values | Sort-Object -Unique) {
    $rank = 0
    $positionPlayers = @(
      $previousPerformanceById.Values |
        Where-Object { $_.position -eq $position -and $null -ne $_.$splitName } |
        Sort-Object @{ Expression = { $_.$splitName.ppg }; Descending = $true }, @{ Expression = { $_.$splitName.total }; Descending = $true }, name
    )

    foreach ($rankedPlayer in $positionPlayers) {
      $rank += 1
      $rankedPlayer.$splitName.positionRank = "$position$rank"
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
  $previousAdpLookupName = if ($position -eq "D/ST") { $team } else { $player.fullName }
  $previousAdp = $previousAdpByKey[(Get-PlayerLookupKey $previousAdpLookupName $position)]
  $previousPerformance = $previousPerformanceById[$player.id.ToString()]

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
    injuryHistory = $null
    previousSeason = [PSCustomObject]@{
      season = $PreviousSeason
      adp = $previousAdp
      splits = [PSCustomObject]@{
        start = if ($null -ne $previousPerformance) { $previousPerformance.start } else { $null }
        finish = if ($null -ne $previousPerformance) { $previousPerformance.finish } else { $null }
      }
    }
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

$injuryHistoryFetchedAt = (Get-Date).ToUniversalTime().ToString("o")
$injuryHistoryCache = Get-ExistingInjuryHistoryCache
$injuryHistoryCandidates = @($players | Where-Object { $_.position -ne "D/ST" } | Select-Object -First $InjuryHistoryLimit)
$injuryHistoryCandidateIds = @{}
foreach ($candidate in $injuryHistoryCandidates) {
  $injuryHistoryCandidateIds[$candidate.id.ToString()] = $true
}

Write-Host "Fetching PlayerProfiler injury histories..."
$injuryHistoryFetchCount = 0
foreach ($player in $players) {
  if ($player.position -eq "D/ST") {
    continue
  }

  $playerId = $player.id.ToString()
  $cachedHistory = $injuryHistoryCache[$playerId]
  $status = if ($null -ne $player.injuryStatus) { $player.injuryStatus.ToString().ToUpperInvariant() } else { "" }
  $hasCurrentInjury = $status -and @("ACTIVE", "SUSPENSION") -notcontains $status
  $shouldFetch = $injuryHistoryCandidateIds.ContainsKey($playerId) -and ($null -eq $cachedHistory -or $cachedHistory.available -ne $true -or $hasCurrentInjury)

  if ($shouldFetch) {
    $injuryHistoryFetchCount += 1
    if ($injuryHistoryFetchCount -eq 1 -or $injuryHistoryFetchCount % 20 -eq 0) {
      Write-Host "Fetching PlayerProfiler injury history $injuryHistoryFetchCount of $($injuryHistoryCandidates.Count)..."
    }

    $player.injuryHistory = Get-PlayerProfilerInjuryHistory $player $injuryHistoryFetchedAt
  } elseif ($null -ne $cachedHistory) {
    $player.injuryHistory = $cachedHistory
  } else {
    $player.injuryHistory = [PSCustomObject]@{
      source = "PlayerProfiler"
      sourceUrl = Get-PlayerProfilerInjuryUrl $player
      available = $false
      fetchedAt = $injuryHistoryFetchedAt
      error = "History not fetched"
      items = @()
    }
  }
}

Write-Host "PlayerProfiler injury histories fetched: $injuryHistoryFetchCount; cached or skipped: $($players.Count - $injuryHistoryFetchCount)"

$updatedAt = (Get-Date).ToUniversalTime().ToString("o")
$data = [PSCustomObject]@{
  meta = [PSCustomObject]@{
    season = $CurrentSeason
    rankType = $RankType
    rankSource = "ESPN Live Draft Trends order by average draft position"
    source = $sourceUrl
    previousSeason = $PreviousSeason
    previousSeasonStatsSource = $previousSourceUrl
    previousSeasonScoring = "PPR: ESPN appliedTotal plus 1 point per reception"
    previousSeasonAdpSource = $previousAdpSourceUrl
    injurySource = $injurySourceUrl
    injuryHistorySource = $injuryHistoryBaseUrl
    injuryHistoryUpdatedAt = $injuryHistoryFetchedAt
    injuryUpdatedAt = $injuryUpdatedAt
    updatedAt = $updatedAt
    playerCount = $players.Count
  }
  players = $players
}

$json = $data | ConvertTo-Json -Depth 8
$content = "window.DRAFT_DATA = $json;"

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
