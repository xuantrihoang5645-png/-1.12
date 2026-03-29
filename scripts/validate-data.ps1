$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Read-Json($path) {
  Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Read-Text($path) {
  Get-Content -Path $path -Raw -Encoding UTF8
}

function Ensure-Array($value) {
  if ($null -eq $value) { return @() }
  if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) { return @($value) }
  return @($value)
}

$required = @(
  'index.html',
  'about.html',
  'css/style.css',
  'js/about.js',
  'js/app.js',
  'js/charts.js',
  'js/recommendation.js',
  'assets/vendor/echarts.min.js',
  'assets/vendor/china.js',
  'data/meta.json',
  'data/sources.json',
  'data/site-summary.json',
  'data/bootstrap.js',
  'data/province-view-model.json',
  'data/view-model.json',
  'data/county-view-model.json',
  'data/coverage-view-model.json',
  'data/social-signal-view-model.json',
  'data/ai-inference-view-model.json',
  'data/packs/provinces.json',
  'data/packs/cities-lite.json',
  'data/evidence/entity-registry.json',
  'data/evidence/metric-definitions.json',
  'data/evidence/metric-observations-provinces.json',
  'data/evidence/metric-observations-cities.json',
  'data/evidence/metric-observations-counties.json',
  'data/evidence/derived-recommendations.json',
  'scripts/build-derived.ps1',
  'scripts/build-evidence-packs.ps1'
)

$missing = @($required | Where-Object { -not (Test-Path (Join-Path $root $_)) })
if ($missing.Count) {
  throw "Missing required files: $($missing -join ', ')"
}

$siteSummary = Read-Json (Join-Path $root 'data/site-summary.json')
$meta = Read-Json (Join-Path $root 'data/meta.json')
$sources = Read-Json (Join-Path $root 'data/sources.json')
$provinceView = Read-Json (Join-Path $root 'data/province-view-model.json')
$cityView = Read-Json (Join-Path $root 'data/view-model.json')
$countyView = Read-Json (Join-Path $root 'data/county-view-model.json')
$coverageView = Read-Json (Join-Path $root 'data/coverage-view-model.json')
$provincePack = Read-Json (Join-Path $root 'data/packs/provinces.json')
$cityLite = Read-Json (Join-Path $root 'data/packs/cities-lite.json')
$entityRegistry = Read-Json (Join-Path $root 'data/evidence/entity-registry.json')
$metricDefinitions = Read-Json (Join-Path $root 'data/evidence/metric-definitions.json')
$provinceObs = Read-Json (Join-Path $root 'data/evidence/metric-observations-provinces.json')
$cityObs = Read-Json (Join-Path $root 'data/evidence/metric-observations-cities.json')
$countyObs = Read-Json (Join-Path $root 'data/evidence/metric-observations-counties.json')
$derived = Read-Json (Join-Path $root 'data/evidence/derived-recommendations.json')
$bootstrap = Read-Text (Join-Path $root 'data/bootstrap.js')

if (@($provinceView.provinces).Count -lt 34) { throw 'province-view-model.json must include at least 34 province records.' }
if (@($cityView.cities).Count -lt 330) { throw 'view-model.json must include at least 330 city records.' }
if (@($countyView.counties).Count -lt 3000) { throw 'county-view-model.json must include at least 3000 county records.' }
if (@($provincePack.provinces).Count -lt 34) { throw 'packs/provinces.json is incomplete.' }
if (@($cityLite.cities).Count -lt 330) { throw 'packs/cities-lite.json is incomplete.' }
if (@($entityRegistry.records).Count -lt 3600) { throw 'entity-registry.json should cover province/city/county records.' }
if (@($metricDefinitions.metrics).Count -lt 8) { throw 'metric-definitions.json is unexpectedly small.' }
if (@($provinceObs.records).Count -lt 100) { throw 'Province observations are unexpectedly small.' }
if (@($cityObs.records).Count -lt 100) { throw 'City observations are unexpectedly small.' }
if ($null -eq $countyObs.records) { throw 'County observations file is missing the records field.' }
if (@($derived.provinceLeaders).Count -lt 5) { throw 'Derived province leaders are unexpectedly small.' }
if (@($sources.researchSummary).Count -lt 4) { throw 'Research summary should contain multiple rows.' }

if ($siteSummary.initialState.adminLevel -ne 'province') { throw 'site-summary.json must default to province mode.' }
if (-not $siteSummary.packManifest.provinces -or -not $siteSummary.packManifest.cityLite) { throw 'site-summary pack manifest is incomplete.' }
if ($meta.coverageSummary.includedCities -lt 330) { throw 'meta coverage summary city count is too small.' }
if ($bootstrap -notmatch 'CITY_SITE_SUMMARY') { throw 'bootstrap.js should expose a minimal CITY_SITE_SUMMARY object.' }

$sourceIds = @($sources.sources | ForEach-Object { $_.sourceId })

foreach ($record in ($provincePack.provinces | Select-Object -First 20)) {
  foreach ($field in @('id', 'name', 'adminLevel', 'evidence', 'inference', 'social', 'citySampleCount', 'cityCoverageLevel')) {
    if (-not ($record.PSObject.Properties.Name -contains $field)) { throw "Province pack record missing field '$field': $($record.id)" }
  }
  foreach ($ref in Ensure-Array $record.evidence.sourceRefs) {
    if ($sourceIds -notcontains $ref) { throw "Unknown province sourceRef '$ref' in $($record.id)" }
  }
}

foreach ($record in ($cityLite.cities | Select-Object -First 80)) {
  foreach ($field in @('id', 'name', 'provinceId', 'adminLevel', 'evidence', 'inference', 'social', 'comparisonEligibility', 'displayEligibility')) {
    if (-not ($record.PSObject.Properties.Name -contains $field)) { throw "City lite record missing field '$field': $($record.id)" }
  }
  foreach ($ref in Ensure-Array $record.evidence.sourceRefs) {
    if ($sourceIds -notcontains $ref) { throw "Unknown city sourceRef '$ref' in $($record.id)" }
  }
}

foreach ($record in ($entityRegistry.records | Select-Object -First 100)) {
  foreach ($field in @('id', 'name', 'adminLevel', 'provinceId', 'coverageLevel', 'displayEligibility', 'searchKeywords')) {
    if (-not ($record.PSObject.Properties.Name -contains $field)) { throw "Registry record missing field '$field': $($record.id)" }
  }
}

$cityPackFiles = @(Get-ChildItem -Path (Join-Path $root 'data/packs/cities/by-province') -Filter '*.json')
if ($cityPackFiles.Count -lt 30) { throw 'City packs by province are incomplete.' }
$countyPackFiles = @(Get-ChildItem -Path (Join-Path $root 'data/packs/counties/by-province') -Filter '*.json')
if ($countyPackFiles.Count -lt 30) { throw 'County packs by province are incomplete.' }

$sampleCityPack = Read-Json $cityPackFiles[0].FullName
if (-not $sampleCityPack.summary -or -not $sampleCityPack.cities) { throw 'Sample province city pack is malformed.' }
$sampleCountyPack = Read-Json $countyPackFiles[0].FullName
if (-not $sampleCountyPack.summary -or -not $sampleCountyPack.counties) { throw 'Sample province county pack is malformed.' }

$textFiles = @(
  'index.html',
  'about.html',
  'css/style.css',
  'js/about.js',
  'js/app.js',
  'js/charts.js',
  'js/recommendation.js',
  'scripts/build-derived.ps1',
  'scripts/build-evidence-packs.ps1'
)

foreach ($file in $textFiles) {
  $content = Read-Text (Join-Path $root $file)
  if ($content.Contains([char]0xFFFD)) {
    throw "Potential replacement-character corruption found in $file"
  }
}

Write-Host 'Validation passed for the evidence-first site data structure.'
