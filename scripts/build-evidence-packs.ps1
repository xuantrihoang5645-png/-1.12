$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root 'data'
$packsDir = Join-Path $dataDir 'packs'
$cityPackDir = Join-Path $packsDir 'cities\by-province'
$countyPackDir = Join-Path $packsDir 'counties\by-province'
$evidenceDir = Join-Path $dataDir 'evidence'

foreach ($dir in @($packsDir, $cityPackDir, $countyPackDir, $evidenceDir)) {
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

function Read-Json($path) {
  Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Json($path, $value) {
  $value | ConvertTo-Json -Depth 40 | Set-Content -Path $path -Encoding UTF8
}

function Write-Text($path, $value) {
  Set-Content -Path $path -Value $value -Encoding UTF8
}

function Ensure-Array($value) {
  if ($null -eq $value) { return @() }
  if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) { return @($value) }
  return @($value)
}

function Distinct-Array($items) {
  return @(
    Ensure-Array $items |
      Where-Object { $null -ne $_ -and [string]$_ -ne '' } |
      Select-Object -Unique
  )
}

function First-NonNull($values) {
  foreach ($value in $values) {
    if ($null -eq $value) { continue }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
    return $value
  }
  return $null
}

function To-NullableNumber($value) {
  if ($null -eq $value) { return $null }
  if ($value -is [int] -or $value -is [double] -or $value -is [decimal]) { return [double]$value }
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  $parsed = 0.0
  if ([double]::TryParse(($text -replace ',', ''), [ref]$parsed)) { return $parsed }
  return $null
}

function New-Lookup($items, [string]$keyName) {
  $lookup = @{}
  foreach ($item in $items) {
    $key = [string]$item.$keyName
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $lookup[$key] = $item
    }
  }
  return $lookup
}

function Resolve-PeriodLabel($record) {
  if ($record.periods -and $record.periods.PSObject.Properties.Name -contains 'latest' -and $record.periods.latest.label) {
    return [string]$record.periods.latest.label
  }
  if ($record.displayPeriodLabel) { return [string]$record.displayPeriodLabel }
  return 'latest snapshot'
}

function Normalize-SourceRefList($values) {
  $expanded = @()
  foreach ($ref in (Ensure-Array $values)) {
    $text = [string]$ref
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    if ($script:KnownSourceIds -contains $text) {
      $expanded += $text
      continue
    }

    $matches = @($script:KnownSourceIds | Where-Object { $text.Contains($_) })
    if ($matches.Count) {
      $expanded += $matches
    } else {
      $expanded += $text
    }
  }

  return Distinct-Array $expanded
}

function Resolve-SourceRefs($record, $inference, $social) {
  return Normalize-SourceRefList @(
    Ensure-Array $record.sourceRefs
    Ensure-Array $inference.sourceRefs
    Ensure-Array $social.sourceRefs
  )
}

function Merge-Record($record, $inference, $social, $coverage) {
  $sourceRefs = Resolve-SourceRefs $record $inference $social
  $qualityFlags = Distinct-Array @(
    Ensure-Array $record.qualityFlags
    Ensure-Array $coverage.missingDimensions
  )

  return [pscustomobject][ordered]@{
    id = $record.id
    name = $record.name
    adminLevel = $record.adminLevel
    provinceId = First-NonNull @($record.provinceId, $record.parentProvinceId, $record.id)
    province = $record.province
    parentProvinceId = $record.parentProvinceId
    parentCityId = $record.parentCityId
    region = $record.region
    tier = $record.tier
    countyType = $record.countyType
    coordinates = $record.coordinates
    shortDescription = $record.shortDescription
    tags = Ensure-Array $record.tags
    effectiveMonthlyIncome = To-NullableNumber $record.effectiveMonthlyIncome
    annualConsumptionPerCapita = To-NullableNumber $record.annualConsumptionPerCapita
    rentBurdenProxy = To-NullableNumber $record.rentBurdenProxy
    totalCostIndex = To-NullableNumber $record.totalCostIndex
    commuteIndex = To-NullableNumber $record.commuteIndex
    airQualityScore = To-NullableNumber $record.airQualityScore
    balancedScore = To-NullableNumber $record.balancedScore
    savingScore = To-NullableNumber $record.savingScore
    officialBalanceScore = To-NullableNumber $record.officialBalanceScore
    baseOfficialScore = To-NullableNumber $record.baseOfficialScore
    opportunityScore = To-NullableNumber $record.opportunityScore
    pressureScore = To-NullableNumber $record.pressureScore
    officialGdp = To-NullableNumber $record.officialGdp
    cityMapEligibility = [bool]$record.cityMapEligibility
    cityRecommendationEligibility = [bool]$record.cityRecommendationEligibility
    aiEligibility = [bool](First-NonNull @($record.aiEligibility, $record.aiEligible, $false))
    comparisonEligibility = [bool]$record.comparisonEligibility
    displayEligibility = [bool]$record.displayEligibility
    eligibleScopes = Ensure-Array $record.eligibleScopes
    evidence = [ordered]@{
      dataClass = $record.primaryDataClass
      coverageScore = To-NullableNumber $record.coverageScore
      coverageLevel = First-NonNull @($record.coverageLevel, $record.coverageCode, 'unknown')
      coverageLabel = $record.coverageLabel
      factCompleteness = To-NullableNumber $record.factCompleteness
      socialCompleteness = To-NullableNumber $record.socialCompleteness
      inferenceCompleteness = To-NullableNumber $record.inferenceCompleteness
      displayPeriodLabel = Resolve-PeriodLabel $record
      qualityFlags = $qualityFlags
      sourceRefs = $sourceRefs
      lastUpdated = $record.lastUpdated
    }
    social = [ordered]@{
      signalCount = To-NullableNumber $social.signalCount
      sentiment = $social.sentiment
      themes = Ensure-Array $social.themes
      sampleWindow = $social.sampleWindow
      platformBreakdown = $social.platformBreakdown
      riskNote = $social.riskNote
      sourceRefs = Normalize-SourceRefList (Ensure-Array $social.sourceRefs)
    }
    inference = [ordered]@{
      confidence = To-NullableNumber $inference.confidence
      confidenceBand = $inference.confidenceBand
      estimatedScores = $inference.estimatedScores
      reasoningSummary = $inference.reasoningSummary
      referencePeers = Ensure-Array $inference.referencePeers
      inferenceBasis = Ensure-Array $inference.inferenceBasis
      shouldNotBeUsedForRanking = [bool]$inference.shouldNotBeUsedForRanking
      sourceRefs = Normalize-SourceRefList (Ensure-Array $inference.sourceRefs)
      lastVerifiedAt = $inference.lastVerifiedAt
    }
  }
}

function Add-Observations($list, $record, $metricSpecs) {
  foreach ($metric in $metricSpecs) {
    $value = To-NullableNumber $record.($metric.key)
    if ($null -eq $value) { continue }
    $list.Add([pscustomobject][ordered]@{
      entityId = $record.id
      entityName = $record.name
      adminLevel = $record.adminLevel
      metricId = $metric.key
      value = $value
      unit = $metric.unit
      period = Resolve-PeriodLabel $record
      sourceRefs = Ensure-Array $record.sourceRefs
      dataClass = $record.primaryDataClass
      confidence = To-NullableNumber $record.factCompleteness
      qualityFlags = Ensure-Array $record.qualityFlags
      lastVerifiedAt = $record.lastUpdated
    })
  }
}

$provinceView = Read-Json (Join-Path $dataDir 'province-view-model.json')
$cityView = Read-Json (Join-Path $dataDir 'view-model.json')
$countyView = Read-Json (Join-Path $dataDir 'county-view-model.json')
$coverageView = Read-Json (Join-Path $dataDir 'coverage-view-model.json')
$sources = Read-Json (Join-Path $dataDir 'sources.json')
$meta = Read-Json (Join-Path $dataDir 'meta.json')
$socialView = Read-Json (Join-Path $dataDir 'social-signal-view-model.json')
$inferenceView = Read-Json (Join-Path $dataDir 'ai-inference-view-model.json')

$coverageByProvince = New-Lookup (Ensure-Array $coverageView.provinces) 'provinceId'
$socialById = New-Lookup (Ensure-Array $socialView.records) 'id'
$inferenceById = New-Lookup (Ensure-Array $inferenceView.records) 'id'
$script:KnownSourceIds = @(Ensure-Array $sources.sources | ForEach-Object { [string]$_.sourceId } | Sort-Object Length -Descending)

$provinceMetricSpecs = @(
  @{ key = 'population'; unit = '10k-persons' }
  @{ key = 'disposableIncome'; unit = 'cny-year' }
  @{ key = 'annualConsumptionPerCapita'; unit = 'cny-year' }
  @{ key = 'incomeSupportScore'; unit = 'score' }
  @{ key = 'consumptionBurdenScore'; unit = 'score' }
  @{ key = 'environmentScore'; unit = 'score' }
  @{ key = 'publicServiceScore'; unit = 'score' }
  @{ key = 'overviewScore'; unit = 'score' }
)

$cityMetricSpecs = @(
  @{ key = 'effectiveMonthlyIncome'; unit = 'cny-month' }
  @{ key = 'annualConsumptionPerCapita'; unit = 'cny-year' }
  @{ key = 'rentBurdenProxy'; unit = 'ratio' }
  @{ key = 'totalCostIndex'; unit = 'score' }
  @{ key = 'commuteIndex'; unit = 'score' }
  @{ key = 'airQualityScore'; unit = 'score' }
  @{ key = 'balancedScore'; unit = 'score' }
  @{ key = 'savingScore'; unit = 'score' }
  @{ key = 'officialBalanceScore'; unit = 'score' }
  @{ key = 'baseOfficialScore'; unit = 'score' }
  @{ key = 'officialGdp'; unit = 'billion-cny' }
)

$countyMetricSpecs = @(
  @{ key = 'effectiveMonthlyIncome'; unit = 'cny-month' }
  @{ key = 'rentBurdenProxy'; unit = 'ratio' }
  @{ key = 'airQualityScore'; unit = 'score' }
  @{ key = 'balancedScore'; unit = 'score' }
)

$provincePackRecords = [System.Collections.Generic.List[object]]::new()
$cityLiteRecords = [System.Collections.Generic.List[object]]::new()
$entityRegistry = [System.Collections.Generic.List[object]]::new()
$provinceObservations = [System.Collections.Generic.List[object]]::new()
$cityObservations = [System.Collections.Generic.List[object]]::new()
$countyObservations = [System.Collections.Generic.List[object]]::new()
$citiesByProvince = @{}
$countiesByProvince = @{}

foreach ($province in (Ensure-Array $provinceView.provinces)) {
  $coverage = $coverageByProvince[[string]$province.id]
  $merged = Merge-Record $province $inferenceById[[string]$province.id] $socialById[[string]$province.id] $coverage
  $merged | Add-Member -NotePropertyName provinceCapital -NotePropertyValue $province.provinceCapital
  $merged | Add-Member -NotePropertyName representativeCities -NotePropertyValue (Ensure-Array $province.representativeCities)
  $merged | Add-Member -NotePropertyName citySampleCount -NotePropertyValue (First-NonNull @($province.citySampleCount, $coverage.cityDirectoryCount, 0))
  $merged | Add-Member -NotePropertyName aiEligibleCityCount -NotePropertyValue (First-NonNull @($province.aiEligibleCityCount, $coverage.cityAiCount, 0))
  $merged | Add-Member -NotePropertyName cityCoverageLevel -NotePropertyValue (First-NonNull @($province.cityCoverageLevel, $coverage.cityCoverageLevel, 'unknown'))
  $merged | Add-Member -NotePropertyName missingDimensions -NotePropertyValue (Distinct-Array (First-NonNull @($province.missingDimensions, $coverage.missingDimensions, @())))
  $provincePackRecords.Add($merged)

  $entityRegistry.Add([pscustomobject][ordered]@{
    id = $province.id
    name = $province.name
    searchLabel = $province.name
    adminLevel = 'province-level'
    provinceId = $province.id
    parentProvinceId = $null
    parentCityId = $null
    region = $province.region
    tier = 'province'
    coordinates = $null
    coverageLevel = $province.coverageLevel
    factCompleteness = 1
    displayEligibility = $true
    searchKeywords = Distinct-Array @($province.name, $province.provinceCapital, @($province.representativeCities | ForEach-Object { $_.name }))
  })

  Add-Observations $provinceObservations $province $provinceMetricSpecs
}

foreach ($city in (Ensure-Array $cityView.cities)) {
  $provinceId = [string]$city.provinceId
  if (-not $citiesByProvince.ContainsKey($provinceId)) {
    $citiesByProvince[$provinceId] = [System.Collections.Generic.List[object]]::new()
  }

  $merged = Merge-Record $city $inferenceById[[string]$city.id] $socialById[[string]$city.id] $coverageByProvince[$provinceId]
  $cityLiteRecords.Add($merged)
  $citiesByProvince[$provinceId].Add($merged)

  $entityRegistry.Add([pscustomobject][ordered]@{
    id = $city.id
    name = $city.name
    searchLabel = "$($city.name) · $($city.province)"
    adminLevel = 'prefecture-level'
    provinceId = $city.provinceId
    parentProvinceId = $city.parentProvinceId
    parentCityId = $null
    region = $city.region
    tier = $city.tier
    coordinates = $city.coordinates
    coverageLevel = $city.coverageCode
    factCompleteness = $city.factCompleteness
    displayEligibility = [bool]$city.displayEligibility
    searchKeywords = Distinct-Array @($city.name, $city.province, $city.pinyin, @($city.tags))
  })

  Add-Observations $cityObservations $city $cityMetricSpecs
}

foreach ($county in (Ensure-Array $countyView.counties)) {
  $provinceId = [string]$county.parentProvinceId
  if (-not $countiesByProvince.ContainsKey($provinceId)) {
    $countiesByProvince[$provinceId] = [System.Collections.Generic.List[object]]::new()
  }

  $merged = Merge-Record $county $inferenceById[[string]$county.id] $socialById[[string]$county.id] $coverageByProvince[$provinceId]
  $countiesByProvince[$provinceId].Add($merged)

  $entityRegistry.Add([pscustomobject][ordered]@{
    id = $county.id
    name = $county.name
    searchLabel = $county.name
    adminLevel = 'county-level'
    provinceId = $county.parentProvinceId
    parentProvinceId = $county.parentProvinceId
    parentCityId = $county.parentCityId
    region = $county.region
    tier = $county.countyType
    coordinates = $county.coordinates
    coverageLevel = $county.coverageLevel
    factCompleteness = $county.factCompleteness
    displayEligibility = [bool]$county.displayEligibility
    searchKeywords = Distinct-Array @($county.name, $county.province, $county.parentCity)
  })

  Add-Observations $countyObservations $county $countyMetricSpecs
}

$metricDefinitions = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  metrics = @(
    [ordered]@{ metricId = 'overviewScore'; label = 'Province Overview'; scope = 'province'; comparableScope = 'province annual'; calculation = 'weighted province overview'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'incomeSupportScore'; label = 'Income Support'; scope = 'province'; comparableScope = 'province annual'; calculation = 'normalized disposable income'; rankingEligible = $true; allowsProxy = $false }
    [ordered]@{ metricId = 'publicServiceScore'; label = 'Public Service'; scope = 'province'; comparableScope = 'province annual'; calculation = 'service proxy bundle'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'effectiveMonthlyIncome'; label = 'Monthly Income Reference'; scope = 'city/county'; comparableScope = 'fact snapshot'; calculation = 'monthly income reference'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'rentBurdenProxy'; label = 'Rent Burden Proxy'; scope = 'city/county'; comparableScope = 'deep snapshot'; calculation = 'rent to income proxy'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'totalCostIndex'; label = 'Total Cost Index'; scope = 'city/county'; comparableScope = 'deep snapshot'; calculation = 'derived cost index'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'commuteIndex'; label = 'Commute Index'; scope = 'city/county'; comparableScope = 'official/report subset'; calculation = 'normalized commute proxy'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'airQualityScore'; label = 'Air Quality Score'; scope = 'city/county'; comparableScope = 'city environment'; calculation = 'public environment fields'; rankingEligible = $true; allowsProxy = $false }
    [ordered]@{ metricId = 'officialBalanceScore'; label = 'Official Balance Score'; scope = 'city'; comparableScope = 'city official layer'; calculation = 'official city basics bundle'; rankingEligible = $true; allowsProxy = $false }
    [ordered]@{ metricId = 'balancedScore'; label = 'Balanced Score'; scope = 'city'; comparableScope = 'mixed city layer'; calculation = 'fact plus snapshot composite'; rankingEligible = $true; allowsProxy = $true }
    [ordered]@{ metricId = 'savingScore'; label = 'Saving Score'; scope = 'city'; comparableScope = 'mixed city layer'; calculation = 'saving-friendly composite'; rankingEligible = $true; allowsProxy = $true }
  )
}

$derivedRecommendations = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  summary = [ordered]@{
    provinceFactComparable = @($provincePackRecords | Where-Object { $_.evidence.coverageLevel -ne 'limited' }).Count
    cityFactComparable = @($cityLiteRecords | Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -ge 0.35 }).Count
    cityMixedEligible = @($cityLiteRecords | Where-Object { $_.cityRecommendationEligibility -or $_.aiEligibility }).Count
    countyDirectoryReady = @(Ensure-Array $countyView.counties).Count
  }
  provinceLeaders = @(
    $provincePackRecords |
      Where-Object { $_.evidence.coverageLevel -ne 'limited' } |
      Sort-Object overviewScore -Descending |
      Select-Object -First 8 |
      ForEach-Object {
        [pscustomobject][ordered]@{
          id = $_.id
          name = $_.name
          score = $_.overviewScore
          reason = 'use as province baseline'
        }
      }
  )
  cityEvidenceLeaders = @(
    $cityLiteRecords |
      Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -ge 0.35 } |
      Sort-Object officialBalanceScore -Descending |
      Select-Object -First 12 |
      ForEach-Object {
        [pscustomobject][ordered]@{
          id = $_.id
          name = $_.name
          provinceId = $_.provinceId
          score = $_.officialBalanceScore
          reason = 'fact-first sample'
        }
      }
  )
  cityWatchlist = @(
    $cityLiteRecords |
      Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -lt 0.35 -and (To-NullableNumber $_.inference.confidence) -ge 0.5 } |
      Sort-Object @{ Expression = { $_.inference.estimatedScores.balance } ; Descending = $true } |
      Select-Object -First 12 |
      ForEach-Object {
        [pscustomobject][ordered]@{
          id = $_.id
          name = $_.name
          provinceId = $_.provinceId
          score = $_.inference.estimatedScores.balance
          reason = 'inference watchlist'
        }
      }
  )
}

$siteSummary = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  initialState = [ordered]@{
    adminLevel = 'province'
    dataLens = 'fact'
    periodMode = 'latest'
  }
  meta = $meta
  coverageSummary = $meta.coverageSummary
  sourcesSummary = [ordered]@{
    researchSummaryCount = @(Ensure-Array $sources.researchSummary).Count
    sourceCount = @(Ensure-Array $sources.sources).Count
  }
  packManifest = [ordered]@{
    provinces = './packs/provinces.json'
    cityLite = './packs/cities-lite.json'
    entityRegistry = './evidence/entity-registry.json'
    metricDefinitions = './evidence/metric-definitions.json'
    derivedRecommendations = './evidence/derived-recommendations.json'
    coverage = './coverage-view-model.json'
    sources = './sources.json'
    countiesBase = './packs/counties/by-province'
    citiesBase = './packs/cities/by-province'
  }
}

$provincePack = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  summary = $provinceView.summary
  provinces = @($provincePackRecords)
}

$cityLitePack = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  summary = [ordered]@{
    total = @($cityLiteRecords).Count
    factComparable = @($cityLiteRecords | Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -ge 0.35 }).Count
    mixedEligible = @($cityLiteRecords | Where-Object { $_.cityRecommendationEligibility -or $_.aiEligibility }).Count
  }
  cities = @($cityLiteRecords)
}

Write-Json (Join-Path $dataDir 'site-summary.json') $siteSummary
Write-Json (Join-Path $packsDir 'provinces.json') $provincePack
Write-Json (Join-Path $packsDir 'cities-lite.json') $cityLitePack
Write-Json (Join-Path $evidenceDir 'entity-registry.json') ([ordered]@{ generatedAt = $meta.siteGeneratedAt; records = @($entityRegistry) })
Write-Json (Join-Path $evidenceDir 'metric-definitions.json') $metricDefinitions
Write-Json (Join-Path $evidenceDir 'metric-observations-provinces.json') ([ordered]@{ generatedAt = $meta.siteGeneratedAt; records = @($provinceObservations) })
Write-Json (Join-Path $evidenceDir 'metric-observations-cities.json') ([ordered]@{ generatedAt = $meta.siteGeneratedAt; records = @($cityObservations) })
Write-Json (Join-Path $evidenceDir 'metric-observations-counties.json') ([ordered]@{ generatedAt = $meta.siteGeneratedAt; records = @($countyObservations) })
Write-Json (Join-Path $evidenceDir 'derived-recommendations.json') $derivedRecommendations

foreach ($province in (Ensure-Array $provinceView.provinces)) {
  $provinceId = [string]$province.id
  $provinceName = [string]$province.name

  Write-Json (Join-Path $cityPackDir "$provinceId.json") ([ordered]@{
    generatedAt = $meta.siteGeneratedAt
    provinceId = $provinceId
    provinceName = $provinceName
    summary = [ordered]@{
      total = @($citiesByProvince[$provinceId]).Count
      factComparable = @($citiesByProvince[$provinceId] | Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -ge 0.35 }).Count
      mixedEligible = @($citiesByProvince[$provinceId] | Where-Object { $_.cityRecommendationEligibility -or $_.aiEligibility }).Count
      mapped = @($citiesByProvince[$provinceId] | Where-Object { $_.cityMapEligibility }).Count
    }
    cities = @($citiesByProvince[$provinceId])
  })

  Write-Json (Join-Path $countyPackDir "$provinceId.json") ([ordered]@{
    generatedAt = $meta.siteGeneratedAt
    provinceId = $provinceId
    provinceName = $provinceName
    summary = [ordered]@{
      total = @($countiesByProvince[$provinceId]).Count
      factComparable = @($countiesByProvince[$provinceId] | Where-Object { (To-NullableNumber $_.evidence.factCompleteness) -gt 0 }).Count
      mixedEligible = @($countiesByProvince[$provinceId] | Where-Object { $_.aiEligibility }).Count
    }
    counties = @($countiesByProvince[$provinceId])
  })
}

$bootstrap = [ordered]@{
  generatedAt = $meta.siteGeneratedAt
  coverageSummary = $meta.coverageSummary
  packManifest = $siteSummary.packManifest
}

Write-Text (Join-Path $dataDir 'bootstrap.js') ("window.CITY_SITE_SUMMARY = " + ($bootstrap | ConvertTo-Json -Depth 20) + ";")
Write-Host 'Built evidence-first packs and summary.'
