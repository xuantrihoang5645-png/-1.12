$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root 'data'
$rawDir = Join-Path $dataDir 'raw'

if (-not (Test-Path $rawDir)) {
  New-Item -ItemType Directory -Path $rawDir | Out-Null
}

function Write-Json($path, $value) {
  $value | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding UTF8
}

function To-NullableNumber($value) {
  if ($null -eq $value) { return $null }
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  $normalized = $text -replace ',', ''
  $parsed = 0.0
  if ([double]::TryParse($normalized, [ref]$parsed)) {
    return $parsed
  }
  return $null
}

function Get-Headers([string]$channelCode) {
  return @{
    'Referer'    = "https://data.stats.gov.cn/easyquery.htm?cn=$channelCode"
    'User-Agent' = 'Mozilla/5.0'
    'Accept'     = 'application/json, text/plain, */*'
  }
}

function Invoke-NbsGet([string]$url, [string]$channelCode) {
  $response = Invoke-WebRequest -Uri $url -Headers (Get-Headers $channelCode) -UseBasicParsing
  return ($response.Content | ConvertFrom-Json)
}

function Invoke-NbsPost([hashtable]$payload, [string]$channelCode) {
  $response = Invoke-WebRequest `
    -Uri 'https://data.stats.gov.cn/dg/website/publicrelease/web/external/getEsDataByCidAndDt' `
    -Method Post `
    -Headers (Get-Headers $channelCode) `
    -ContentType 'application/json;charset=UTF-8' `
    -Body ($payload | ConvertTo-Json -Depth 10) `
    -UseBasicParsing

  return ($response.Content | ConvertFrom-Json)
}

function Get-ProvinceDataRows([hashtable]$indicator) {
  $payload = @{
    cid         = $indicator.cid
    rootId      = 'c4d82af16c3d4f0cb4f09d4af7d5888e'
    indicatorIds = @($indicator.id)
    daCatalogId = 'a10dceae75d245008bf4b9a0e6fe1d55'
    das         = @()
    showType    = 2
    dts         = @('2024YY')
  }

  return @((Invoke-NbsPost $payload 'E0103').data)
}

function Get-MajorCityDataRows([hashtable]$indicator) {
  $payload = @{
    cid         = $indicator.cid
    rootId      = '2d06bab01494417e9052ef0f8d93e23e'
    indicatorIds = @($indicator.id)
    daCatalogId = '5772e42228f948149cf5d6a11d07bce1'
    das         = @()
    showType    = 2
    dts         = @('2024YY')
  }

  return @((Invoke-NbsPost $payload 'E0108').data)
}

$provinceIndicators = @(
  @{ key = 'population'; cid = '1b8b3021a931466d99b65cac34d89ee3'; id = '4810ad6e9ddc41fc804a66134afe587f'; label = 'Resident population'; unit = '10k persons' },
  @{ key = 'disposableIncome'; cid = 'b8a6a78e15684f47b1c340cdb0ff8a23'; id = 'bda568266e4c445b867d25626e1f6b8a'; label = 'Disposable income per capita'; unit = 'CNY' },
  @{ key = 'consumption'; cid = 'b8a6a78e15684f47b1c340cdb0ff8a23'; id = '462f6c41041b4721b78e50397b358af8'; label = 'Consumption expenditure per capita'; unit = 'CNY' },
  @{ key = 'parkGreenPerCapita'; cid = '425718c96f084a4ab57e95936eeaad68'; id = 'e1ade4f905b8478c8aff53ec62f11c09'; label = 'Park green area per capita'; unit = 'sqm/person' },
  @{ key = 'gasCoverage'; cid = '956f3900294044aabf32f831d255f93b'; id = '9a4e5d533e2f469ca2caab68e911f83b'; label = 'Urban gas coverage'; unit = '%' },
  @{ key = 'railwayLength'; cid = 'd180695e985243c994eef6a7c3e58090'; id = '6191622eacb64d2eb5a34dd85659a1fb'; label = 'Railway length'; unit = '10k km' },
  @{ key = 'highwayLength'; cid = 'd180695e985243c994eef6a7c3e58090'; id = 'e56b0012f8c94a00bc16b040310561b0'; label = 'Highway length'; unit = '10k km' }
)

$majorCityIndicators = @(
  @{ key = 'gdp'; cid = '75a85abe58c749e0ad1d85be343e9056'; id = '35613910b9ad47e19cf79ae041ccb7ed'; label = 'GDP'; unit = '100m CNY' },
  @{ key = 'wageAnnual'; cid = 'b13e73d4a4734a46bf358aa1baff2649'; id = '38ab34487419483b9e826c5d80a9c3ce'; label = 'Average wage in urban non-private units'; unit = 'CNY' },
  @{ key = 'registeredPopulation'; cid = 'b13e73d4a4734a46bf358aa1baff2649'; id = '3825c2d7a32b4cf6b3d72fc5ed9e62c6'; label = 'Registered population'; unit = '10k persons' },
  @{ key = 'retailSales'; cid = 'e4703d312cd44d498c168a10d2337f4a'; id = '06eac78eee1c4eac9fcaeb0e8b5b108d'; label = 'Retail sales of consumer goods'; unit = '100m CNY' },
  @{ key = 'students'; cid = 'b5590334491d4247af1313190d960fe4'; id = '991b24f307ce4cbeb3fba62db4fa79c9'; label = 'College students enrolled'; unit = '10k persons' },
  @{ key = 'hospitals'; cid = 'b5590334491d4247af1313190d960fe4'; id = 'a3ebd177379e4f59a4fde46c7e17b3d2'; label = 'Hospitals'; unit = 'count' },
  @{ key = 'doctors'; cid = 'b5590334491d4247af1313190d960fe4'; id = '4e21cb7e40b2412fa60b45c2a64f0f4d'; label = 'Doctors'; unit = '10k persons' }
)

$allProvinceResponse = Invoke-NbsGet 'https://data.stats.gov.cn/dg/website/publicrelease/web/external/getAllProvince' 'E0103'
$allProvinces = @($allProvinceResponse.data)

$provinceIndex = @{}
foreach ($item in $allProvinces) {
  $provinceIndex[$item.value] = [ordered]@{
    code = $item.value
    name = $item.text
    metrics = [ordered]@{}
    sourceRefs = @('nbs-api-province-annual-2024')
    qualityFlags = @()
  }
}

foreach ($indicator in $provinceIndicators) {
  $rows = Get-ProvinceDataRows $indicator
  foreach ($row in $rows) {
    if (-not $provinceIndex.ContainsKey($row.code)) { continue }
    $metricValue = $null
    $metricUnit = $indicator.unit
    $metricDt = '2024YY'
    if ($row.values -and $row.values[0]) {
      $metricValue = To-NullableNumber $row.values[0].value
      if ($row.values[0].du_name) { $metricUnit = $row.values[0].du_name }
      if ($row.values[0].dt) { $metricDt = $row.values[0].dt }
    }

    $provinceIndex[$row.code].metrics[$indicator.key] = [ordered]@{
      label = $indicator.label
      value = $metricValue
      unit = $metricUnit
      dt = $metricDt
      indicatorId = $indicator.id
      cid = $indicator.cid
    }
  }
}

$provinceRecords = @()
foreach ($province in $allProvinces) {
  $record = $provinceIndex[$province.value]
  if (-not $record.metrics.Count) {
    $record.qualityFlags = @('limited_comparability')
  }
  $provinceRecords += [pscustomobject]$record
}

$majorCityCatalogResponse = Invoke-NbsGet 'https://data.stats.gov.cn/dg/website/publicrelease/web/external/getDasByDaCatalogId?daCid=5772e42228f948149cf5d6a11d07bce1' 'E0108'
$majorCityAreas = @($majorCityCatalogResponse.data)

$majorCityIndex = @{}
foreach ($area in $majorCityAreas) {
  $majorCityIndex[$area.name_value] = [ordered]@{
    code = $area.name_value
    name = $area.show_name
    fullName = $area.name_text
    metrics = [ordered]@{}
    sourceRefs = @('nbs-api-major-city-annual-2024')
    qualityFlags = @('major_city_official_layer')
  }
}

foreach ($indicator in $majorCityIndicators) {
  $rows = Get-MajorCityDataRows $indicator
  foreach ($row in $rows) {
    if (-not $majorCityIndex.ContainsKey($row.code)) { continue }
    $metricValue = $null
    $metricUnit = $indicator.unit
    $metricDt = '2024YY'
    if ($row.values -and $row.values[0]) {
      $metricValue = To-NullableNumber $row.values[0].value
      if ($row.values[0].du_name) { $metricUnit = $row.values[0].du_name }
      if ($row.values[0].dt) { $metricDt = $row.values[0].dt }
    }
    $majorCityIndex[$row.code].metrics[$indicator.key] = [ordered]@{
      label = $indicator.label
      value = $metricValue
      unit = $metricUnit
      dt = $metricDt
      indicatorId = $indicator.id
      cid = $indicator.cid
    }
  }
}

$majorCityRecords = @()
foreach ($area in $majorCityAreas) {
  $record = $majorCityIndex[$area.name_value]
  $majorCityRecords += [pscustomobject]$record
}

$provincePayload = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  period = '2024'
  sourceId = 'nbs-api-province-annual-2024'
  scope = '31-mainland-provinces-plus-hmt-stubs'
  indicators = $provinceIndicators
  provinces = $provinceRecords
}

$majorCityPayload = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  period = '2024'
  sourceId = 'nbs-api-major-city-annual-2024'
  scope = '36-major-cities'
  daCatalogId = '5772e42228f948149cf5d6a11d07bce1'
  indicators = $majorCityIndicators
  cities = $majorCityRecords
}

Write-Json (Join-Path $rawDir 'nbs-province-annual-2024.json') $provincePayload
Write-Json (Join-Path $rawDir 'nbs-major-city-annual-2024.json') $majorCityPayload

Write-Host 'Saved province raw snapshot:' (Join-Path $rawDir 'nbs-province-annual-2024.json')
Write-Host 'Saved major-city raw snapshot:' (Join-Path $rawDir 'nbs-major-city-annual-2024.json')
