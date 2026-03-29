$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root 'data'
$rawDir = Join-Path $dataDir 'raw'

function Read-Json($path) {
  Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Json($path, $value) {
  $value | ConvertTo-Json -Depth 30 | Set-Content -Path $path -Encoding UTF8
}

function Write-Text($path, $value) {
  Set-Content -Path $path -Value $value -Encoding UTF8
}

function Distinct-Array($items) {
  return @($items | Where-Object { $null -ne $_ -and $_ -ne '' } | Select-Object -Unique)
}

function To-NullableNumber($value) {
  if ($null -eq $value) { return $null }
  if ($value -is [int] -or $value -is [double] -or $value -is [decimal]) {
    return [double]$value
  }
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  $normalized = $text -replace ',', ''
  $parsed = 0.0
  if ([double]::TryParse($normalized, [ref]$parsed)) {
    return $parsed
  }
  return $null
}

function Normalize($values, $target, [bool]$inverse = $false) {
  $targetValue = To-NullableNumber $target
  if ($null -eq $targetValue) { return $null }

  $filtered = @($values | ForEach-Object { To-NullableNumber $_ } | Where-Object { $null -ne $_ })
  if (-not $filtered.Count) { return $null }

  $minimum = ($filtered | Measure-Object -Minimum).Minimum
  $maximum = ($filtered | Measure-Object -Maximum).Maximum
  if ($maximum -eq $minimum) { return 50.0 }

  $score = (($targetValue - $minimum) / ($maximum - $minimum)) * 100
  if ($inverse) { $score = 100 - $score }
  return [math]::Round([double]$score, 1)
}

function Weighted-Score($parts) {
  $valid = @($parts | Where-Object { $null -ne $_.value })
  if (-not $valid.Count) { return $null }

  $weightSum = 0.0
  foreach ($part in $valid) { $weightSum += [double]$part.weight }
  if ($weightSum -le 0) { return $null }

  $sum = 0.0
  foreach ($part in $valid) {
    $sum += ([double]$part.value * [double]$part.weight)
  }

  return [math]::Round($sum / $weightSum, 1)
}

function Province-Code-From-City-Code([string]$cityCode) {
  if ([string]::IsNullOrWhiteSpace($cityCode) -or $cityCode.Length -lt 2) { return $null }
  return '{0}0000000000' -f $cityCode.Substring(0, 2)
}

function Get-Region-By-Province-Code([string]$provinceCode) {
  switch ($provinceCode.Substring(0, 2)) {
    { $_ -in @('11', '12', '13', '14', '15') } { return 'northChina' }
    { $_ -in @('21', '22', '23') } { return 'northEast' }
    { $_ -in @('31', '32', '33', '34', '35', '36', '37') } { return 'eastChina' }
    { $_ -in @('41', '42', '43') } { return 'centralChina' }
    { $_ -in @('44', '45', '46') } { return 'southChina' }
    { $_ -in @('50', '51', '52', '53', '54') } { return 'southWest' }
    { $_ -in @('61', '62', '63', '64', '65') } { return 'northWest' }
    default { return 'greaterChinaLimited' }
  }
}

function Map-Existing-Region($value) {
  switch ($value) {
    '华北' { return 'northChina' }
    '东北' { return 'northEast' }
    '华东' { return 'eastChina' }
    '华中' { return 'centralChina' }
    '华南' { return 'southChina' }
    '西南' { return 'southWest' }
    '西北' { return 'northWest' }
    default { return $value }
  }
}

function Map-Existing-Tier($value) {
  switch ($value) {
    '一线' { return 'tier1' }
    '新一线' { return 'newTier1' }
    '强二线' { return 'strongTier2' }
    default { return $value }
  }
}

function New-Lookup($rows, [string]$keyName) {
  $lookup = @{}
  foreach ($row in $rows) {
    $key = $row.$keyName
    if ($null -ne $key -and $key -ne '') {
      $lookup[$key] = $row
    }
  }
  return $lookup
}

function Get-Metric-Value($metricContainer, [string]$key) {
  if ($null -eq $metricContainer) { return $null }
  $metric = $metricContainer.$key
  if ($null -eq $metric) { return $null }
  return To-NullableNumber $metric.value
}

function First-NonNull($values) {
  foreach ($value in $values) {
    if ($null -eq $value) { continue }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
    return $value
  }
  return $null
}

function Get-Profile-Object($parent, [string]$propertyName) {
  if ($null -eq $parent) { return $null }
  if ($parent.PSObject.Properties.Name -notcontains $propertyName) { return $null }
  return $parent.$propertyName
}

function Get-Profile-Number($parent, [string]$propertyName) {
  $value = Get-Profile-Object $parent $propertyName
  return To-NullableNumber $value
}

function Get-Profile-String($parent, [string]$propertyName) {
  $value = Get-Profile-Object $parent $propertyName
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
  return [string]$value
}

function Get-Profile-Array($parent, [string]$propertyName) {
  $value = Get-Profile-Object $parent $propertyName
  return Distinct-Array @($value)
}

function To-Admin12([string]$code) {
  if ([string]::IsNullOrWhiteSpace($code)) { return $null }
  $trimmed = $code.Trim()
  switch ($trimmed.Length) {
    2 { return "$trimmed" + '0000000000' }
    4 { return "$trimmed" + '00000000' }
    6 { return "$trimmed" + '000000' }
    12 { return $trimmed }
    default { return $trimmed }
  }
}

function Normalize-Place-Name([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }
  return ($name.Trim() `
    -replace '特别行政区', '' `
    -replace '维吾尔自治区|壮族自治区|回族自治区|自治区', '' `
    -replace '省|市|地区|盟', '' `
    -replace '\s+', '')
}

function Average-Values($values) {
  $valid = @($values | ForEach-Object { To-NullableNumber $_ } | Where-Object { $null -ne $_ })
  if (-not $valid.Count) { return $null }
  return [math]::Round((($valid | Measure-Object -Average).Average), 1)
}

function Count-NonNull($values) {
  return @($values | Where-Object { $null -ne $_ -and $_ -ne '' }).Count
}

function Get-Confidence-Band([double]$score) {
  if ($score -ge 0.75) { return 'high' }
  if ($score -ge 0.5) { return 'medium' }
  return 'low'
}

function Get-County-Type([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return 'county' }
  if ($name.EndsWith('区')) { return 'district' }
  if ($name.EndsWith('县')) { return 'county' }
  if ($name.EndsWith('旗')) { return 'banner' }
  if ($name.EndsWith('市')) { return 'county-level-city' }
  return 'county'
}

function Clamp-Score($value) {
  $metric = To-NullableNumber $value
  if ($null -eq $metric) { return $null }
  return [math]::Round([math]::Min(100, [math]::Max(0, [double]$metric)), 1)
}

$cityReference = @{
  '110000000000' = @{ coordinates = @(116.4074, 39.9042); tier = 'tier1' }
  '120000000000' = @{ coordinates = @(117.2000, 39.1333); tier = 'newTier1' }
  '130100000000' = @{ coordinates = @(114.5149, 38.0428); tier = 'strongTier2' }
  '140100000000' = @{ coordinates = @(112.5492, 37.8570); tier = 'strongTier2' }
  '150100000000' = @{ coordinates = @(111.7519, 40.8415); tier = 'strongTier2' }
  '210100000000' = @{ coordinates = @(123.4315, 41.8057); tier = 'strongTier2' }
  '210200000000' = @{ coordinates = @(121.6147, 38.9140); tier = 'strongTier2' }
  '220100000000' = @{ coordinates = @(125.3235, 43.8171); tier = 'strongTier2' }
  '230100000000' = @{ coordinates = @(126.5349, 45.8038); tier = 'strongTier2' }
  '310000000000' = @{ coordinates = @(121.4737, 31.2304); tier = 'tier1' }
  '320100000000' = @{ coordinates = @(118.7969, 32.0603); tier = 'newTier1' }
  '320500000000' = @{ coordinates = @(120.5853, 31.2989); tier = 'newTier1' }
  '330100000000' = @{ coordinates = @(120.1551, 30.2741); tier = 'newTier1' }
  '330200000000' = @{ coordinates = @(121.5503, 29.8746); tier = 'newTier1' }
  '340100000000' = @{ coordinates = @(117.2272, 31.8206); tier = 'strongTier2' }
  '350100000000' = @{ coordinates = @(119.2965, 26.0745); tier = 'strongTier2' }
  '350200000000' = @{ coordinates = @(118.0894, 24.4798); tier = 'strongTier2' }
  '360100000000' = @{ coordinates = @(115.8582, 28.6829); tier = 'strongTier2' }
  '370100000000' = @{ coordinates = @(117.1201, 36.6512); tier = 'strongTier2' }
  '370200000000' = @{ coordinates = @(120.3826, 36.0671); tier = 'newTier1' }
  '410100000000' = @{ coordinates = @(113.6254, 34.7466); tier = 'newTier1' }
  '420100000000' = @{ coordinates = @(114.3054, 30.5931); tier = 'newTier1' }
  '430100000000' = @{ coordinates = @(112.9389, 28.2282); tier = 'newTier1' }
  '440100000000' = @{ coordinates = @(113.2644, 23.1291); tier = 'tier1' }
  '440300000000' = @{ coordinates = @(114.0579, 22.5431); tier = 'tier1' }
  '450100000000' = @{ coordinates = @(108.3669, 22.8170); tier = 'strongTier2' }
  '460100000000' = @{ coordinates = @(110.1983, 20.0440); tier = 'strongTier2' }
  '500000000000' = @{ coordinates = @(106.5516, 29.5630); tier = 'newTier1' }
  '510100000000' = @{ coordinates = @(104.0665, 30.5728); tier = 'newTier1' }
  '520100000000' = @{ coordinates = @(106.6302, 26.6470); tier = 'strongTier2' }
  '530100000000' = @{ coordinates = @(102.8332, 24.8797); tier = 'strongTier2' }
  '540100000000' = @{ coordinates = @(91.1322, 29.6604); tier = 'strongTier2' }
  '610100000000' = @{ coordinates = @(108.9398, 34.3416); tier = 'newTier1' }
  '620100000000' = @{ coordinates = @(103.8343, 36.0611); tier = 'strongTier2' }
  '630100000000' = @{ coordinates = @(101.7782, 36.6171); tier = 'strongTier2' }
  '640100000000' = @{ coordinates = @(106.2309, 38.4872); tier = 'strongTier2' }
  '650100000000' = @{ coordinates = @(87.6168, 43.8256); tier = 'strongTier2' }
}

$deepCodeByName = @{
  '北京' = '110000000000'
  '上海' = '310000000000'
  '广州' = '440100000000'
  '深圳' = '440300000000'
  '杭州' = '330100000000'
  '南京' = '320100000000'
  '武汉' = '420100000000'
  '苏州' = '320500000000'
  '厦门' = '350200000000'
}

$sources = Read-Json (Join-Path $dataDir 'sources.json')
$aiConfig = Read-Json (Join-Path $dataDir 'ai-config.json')

$citiesRaw = Read-Json (Join-Path $dataDir 'cities.json')
$incomeRaw = Read-Json (Join-Path $dataDir 'income.json')
$costRaw = Read-Json (Join-Path $dataDir 'cost-of-living.json')
$mobilityRaw = Read-Json (Join-Path $dataDir 'mobility.json')
$environmentRaw = Read-Json (Join-Path $dataDir 'environment.json')
$generatedRaw = Read-Json (Join-Path $dataDir 'generated-metrics.json')
$personaRaw = Read-Json (Join-Path $dataDir 'persona-recommendation.json')

$provinceRaw = Read-Json (Join-Path $rawDir 'nbs-province-annual-2024.json')
$majorCityRaw = Read-Json (Join-Path $rawDir 'nbs-major-city-annual-2024.json')
$referenceProvinceRaw = if (Test-Path (Join-Path $rawDir 'reference-admin-province.json')) { Read-Json (Join-Path $rawDir 'reference-admin-province.json') } else { @() }
$referenceCityRaw = if (Test-Path (Join-Path $rawDir 'reference-admin-city.json')) { Read-Json (Join-Path $rawDir 'reference-admin-city.json') } else { @() }
$referenceAreaRaw = if (Test-Path (Join-Path $rawDir 'reference-admin-area.json')) { Read-Json (Join-Path $rawDir 'reference-admin-area.json') } else { @() }
$socialSignalSeed = if (Test-Path (Join-Path $dataDir 'social-signal-seeds.json')) { Read-Json (Join-Path $dataDir 'social-signal-seeds.json') } else { [pscustomobject]@{ generatedAt = (Get-Date).ToString('yyyy-MM-dd'); methodology = @(); records = @() } }

$profileDir = Join-Path $dataDir 'city-profiles\prefecture-level'
$profileFiles = if (Test-Path $profileDir) {
  @(Get-ChildItem -Path $profileDir -Filter '*.json' | Where-Object { $_.Name -ne '_template.json' })
} else {
  @()
}
$cityProfiles = @($profileFiles | ForEach-Object { Read-Json $_.FullName })
$cityProfileById = @{}
foreach ($profile in $cityProfiles) {
  if ($null -ne $profile.cityMeta -and -not [string]::IsNullOrWhiteSpace([string]$profile.cityMeta.id)) {
    $cityProfileById[[string]$profile.cityMeta.id] = $profile
  }
}

$countyProfileDir = Join-Path $dataDir 'county-profiles'
$countyProfileFiles = if (Test-Path $countyProfileDir) {
  @(Get-ChildItem -Path $countyProfileDir -Filter '*.json' | Where-Object { $_.Name -ne '_template.json' })
} else {
  @()
}
$countyProfiles = @($countyProfileFiles | ForEach-Object { Read-Json $_.FullName })
$countyProfileById = @{}
foreach ($profile in $countyProfiles) {
  if ($null -ne $profile.countyMeta -and -not [string]::IsNullOrWhiteSpace([string]$profile.countyMeta.id)) {
    $countyProfileById[[string]$profile.countyMeta.id] = $profile
  }
}

$cityById = New-Lookup $citiesRaw 'id'
$incomeById = New-Lookup $incomeRaw 'cityId'
$costById = New-Lookup $costRaw 'cityId'
$mobilityById = New-Lookup $mobilityRaw 'cityId'
$environmentById = New-Lookup $environmentRaw 'cityId'
$generatedById = New-Lookup $generatedRaw 'cityId'
$personaById = New-Lookup $personaRaw 'cityId'

$provinceRows = @($provinceRaw.provinces)
$provinceByCode = New-Lookup $provinceRows 'code'
$majorCityRows = @($majorCityRaw.cities)
$majorCityByCode = New-Lookup $majorCityRows 'code'
$referenceProvinceRows = @($referenceProvinceRaw)
$referenceCityRows = @($referenceCityRaw)
$referenceAreaRows = @($referenceAreaRaw)
$referenceProvinceByCode = New-Lookup @($referenceProvinceRows | ForEach-Object {
    [pscustomobject]@{
      code = (To-Admin12 ([string]$_.code)).Substring(0, 2)
      name = $_.name
    }
  }) 'code'
$referenceCityByCode = New-Lookup @($referenceCityRows | ForEach-Object {
    [pscustomobject]@{
      code = To-Admin12 ([string]$_.code)
      code6 = [string]$_.code
      name = $_.name
      province = [string]$_.province
      city = [string]$_.city
    }
  }) 'code'
$socialSeedRecords = @($socialSignalSeed.records)
$socialSeedById = New-Lookup $socialSeedRecords 'id'

$provinceComparable = @($provinceRows | Where-Object { $_.code -notin @('710000000000', '810000000000', '820000000000') })
$provinceIncomeValues = @($provinceComparable | ForEach-Object { Get-Metric-Value $_.metrics 'disposableIncome' })
$provinceConsumptionRatioValues = @($provinceComparable | ForEach-Object {
    $income = Get-Metric-Value $_.metrics 'disposableIncome'
    $consumption = Get-Metric-Value $_.metrics 'consumption'
    if ($null -ne $income -and $income -gt 0 -and $null -ne $consumption) {
      [math]::Round($consumption / $income, 4)
    }
  })
$provinceGreenValues = @($provinceComparable | ForEach-Object { Get-Metric-Value $_.metrics 'parkGreenPerCapita' })
$provinceRailValues = @($provinceComparable | ForEach-Object { Get-Metric-Value $_.metrics 'railwayLength' })
$provinceRoadValues = @($provinceComparable | ForEach-Object { Get-Metric-Value $_.metrics 'highwayLength' })

$provinceRecords = @()
foreach ($province in $provinceRows) {
  $code = $province.code
  $region = Get-Region-By-Province-Code $code
  $isLimited = $code -in @('710000000000', '810000000000', '820000000000')

  $population = Get-Metric-Value $province.metrics 'population'
  $income = Get-Metric-Value $province.metrics 'disposableIncome'
  $consumption = Get-Metric-Value $province.metrics 'consumption'
  $parkGreen = Get-Metric-Value $province.metrics 'parkGreenPerCapita'
  $gasCoverage = Get-Metric-Value $province.metrics 'gasCoverage'
  $railway = Get-Metric-Value $province.metrics 'railwayLength'
  $highway = Get-Metric-Value $province.metrics 'highwayLength'

  $consumptionRatio = if ($null -ne $income -and $income -gt 0 -and $null -ne $consumption) {
    [math]::Round($consumption / $income, 4)
  } else {
    $null
  }

  $incomeSupportScore = Normalize $provinceIncomeValues $income
  $consumptionBurdenScore = Normalize $provinceConsumptionRatioValues $consumptionRatio $true
  $greenScore = Normalize $provinceGreenValues $parkGreen
  $railScore = Normalize $provinceRailValues $railway
  $roadScore = Normalize $provinceRoadValues $highway
  $publicServiceScore = Weighted-Score @(
    @{ value = $gasCoverage; weight = 0.45 }
    @{ value = $greenScore; weight = 0.25 }
    @{ value = $railScore; weight = 0.15 }
    @{ value = $roadScore; weight = 0.15 }
  )
  $overviewScore = Weighted-Score @(
    @{ value = $incomeSupportScore; weight = 0.35 }
    @{ value = $consumptionBurdenScore; weight = 0.25 }
    @{ value = $publicServiceScore; weight = 0.20 }
    @{ value = $greenScore; weight = 0.20 }
  )

  $presentCount = @($population, $income, $consumption, $parkGreen, $gasCoverage, $railway, $highway | Where-Object { $null -ne $_ }).Count
  $coverageScore = if ($isLimited) { 0.35 } else { [math]::Round($presentCount / 7, 2) }
  $coverageLevel = if ($isLimited) { 'limited' } elseif ($coverageScore -ge 0.86) { 'full' } else { 'degraded' }

  $representativeCities = @(
    $majorCityRows |
      Where-Object { (Province-Code-From-City-Code $_.code) -eq $code } |
      Select-Object -First 3 |
      ForEach-Object {
        [pscustomobject]@{
          code = $_.code
          name = $_.name
        }
      }
  )

  $capital = if ($representativeCities.Count) { $representativeCities[0].name } else { $province.name }
  $qualityFlags = Distinct-Array @(
    $province.qualityFlags
    $(if ($isLimited) { 'limited_comparability' })
    $(if (-not $isLimited) { 'environment_green_proxy' })
  )

  $provinceRecords += [pscustomobject][ordered]@{
    id = $code
    code = $code
    name = $province.name
    region = $region
    adminLevel = 'province-level'
    provinceCapital = $capital
    representativeCities = $representativeCities
    population = $population
    populationUnit = '万人'
    disposableIncome = $income
    annualConsumptionPerCapita = $consumption
    parkGreenPerCapita = $parkGreen
    gasCoverage = $gasCoverage
    railwayLength = $railway
    highwayLength = $highway
    incomeSupportScore = $incomeSupportScore
    consumptionBurden = $consumptionRatio
    consumptionBurdenScore = $consumptionBurdenScore
    environmentScore = $greenScore
    publicServiceScore = $publicServiceScore
    overviewScore = $overviewScore
    coverageScore = $coverageScore
    coverageLevel = $coverageLevel
    sourceRefs = Distinct-Array @($province.sourceRefs)
    qualityFlags = $qualityFlags
    periods = [ordered]@{
      latest = [ordered]@{
        label = '2024 official annual province data'
        note = 'Province mode currently uses official annual 2024 fields. Environment is represented by green-space proxy, not province-level air quality.'
        aligned = $true
      }
      alignedAnnual = [ordered]@{
        label = '2024 aligned annual province data'
        note = 'Province metrics are already aligned to the 2024 annual window.'
        aligned = $true
      }
    }
    periodValues = [ordered]@{
      latest = [ordered]@{
        population = $population
        disposableIncome = $income
        annualConsumptionPerCapita = $consumption
        parkGreenPerCapita = $parkGreen
        gasCoverage = $gasCoverage
        railwayLength = $railway
        highwayLength = $highway
      }
    }
    hasComparableProxyFields = $true
    lastUpdated = $provinceRaw.generatedAt
  }
}

$provinceGenerated = @($provinceRecords | ForEach-Object {
    [pscustomobject][ordered]@{
      provinceId = $_.id
      incomeSupportScore = $_.incomeSupportScore
      consumptionBurdenScore = $_.consumptionBurdenScore
      environmentScore = $_.environmentScore
      publicServiceScore = $_.publicServiceScore
      overviewScore = $_.overviewScore
      coverageScore = $_.coverageScore
      coverageLevel = $_.coverageLevel
      sourceRefs = $_.sourceRefs
      qualityFlags = $_.qualityFlags
      periods = $_.periods
      generatedAt = $provinceRaw.generatedAt
    }
  })

$matchedOfficialCodes = @{}
$cityRecords = @()

foreach ($city in $citiesRaw) {
  $profile = $cityProfileById[$city.id]
  $profileMeta = if ($profile) { $profile.cityMeta } else { $null }
  $profileAnnual = if ($profile) { $profile.annual2024 } else { $null }
  $profilePopulation = Get-Profile-Object $profileAnnual 'population'
  $profileIncome = Get-Profile-Object $profileAnnual 'income'
  $profileCost = Get-Profile-Object $profileAnnual 'costOfLiving'
  $profileAnnualMobility = Get-Profile-Object $profileAnnual 'mobility'
  $profileAnnualEnvironment = Get-Profile-Object $profileAnnual 'environment'
  $profileLatest = if ($profile) { $profile.latestSnapshot } else { $null }
  $profileLatestCost = Get-Profile-Object $profileLatest 'costOfLiving'
  $profileLatestEnvironment = Get-Profile-Object $profileLatest 'environment'
  $profileReport = if ($profile) { $profile.supportingReport } else { $null }
  $profileReportMobility = Get-Profile-Object $profileReport 'mobility'
  $profileSourceRefs = Distinct-Array @(
    $(if ($profile) { $profile.sourceRefs })
    $(if ($profileMeta) { $profileMeta.sourceRefs })
    $(Get-Profile-Array $profileIncome 'sourceRefs')
    $(Get-Profile-Array $profileCost 'sourceRefs')
    $(Get-Profile-Array $profileAnnualMobility 'sourceRefs')
    $(Get-Profile-Array $profileAnnualEnvironment 'sourceRefs')
    $(Get-Profile-Array $profileLatestCost 'sourceRefs')
    $(Get-Profile-Array $profileLatestEnvironment 'sourceRefs')
    $(Get-Profile-Array $profileReportMobility 'sourceRefs')
  )
  $profileQualityFlags = Distinct-Array @(
    $(if ($profile) { $profile.qualityFlags })
    $(if ($profileMeta) { $profileMeta.qualityFlags })
    $(Get-Profile-Array $profileIncome 'qualityFlags')
    $(Get-Profile-Array $profileCost 'qualityFlags')
    $(Get-Profile-Array $profileAnnualMobility 'qualityFlags')
    $(Get-Profile-Array $profileAnnualEnvironment 'qualityFlags')
    $(Get-Profile-Array $profileLatestCost 'qualityFlags')
    $(Get-Profile-Array $profileLatestEnvironment 'qualityFlags')
    $(Get-Profile-Array $profileReportMobility 'qualityFlags')
  )

  $income = $incomeById[$city.id]
  $cost = $costById[$city.id]
  $mobility = $mobilityById[$city.id]
  $environment = $environmentById[$city.id]
  $generated = $generatedById[$city.id]
  $persona = $personaById[$city.id]

  $officialCode = First-NonNull @(
    $(Get-Profile-String $profileMeta 'officialCode')
    $deepCodeByName[$city.name]
  )
  if ($officialCode) { $matchedOfficialCodes[$officialCode] = $true }
  $officialRow = if ($officialCode) { $majorCityByCode[$officialCode] } else { $null }
  $provinceCode = if ($officialCode) { Province-Code-From-City-Code $officialCode } else { $null }

  $officialGdp = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'gdp' } else { $null }
  $officialRetailSales = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'retailSales' } else { $null }
  $officialStudents = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'students' } else { $null }
  $officialHospitals = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'hospitals' } else { $null }
  $officialDoctors = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'doctors' } else { $null }
  $officialRegisteredPopulation = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'registeredPopulation' } else { $null }
  $officialWageAnnual = if ($officialRow) { Get-Metric-Value $officialRow.metrics 'wageAnnual' } else { $null }

  $coverageScore = To-NullableNumber $generated.coverageScore
  $coverageCode = if ($coverageScore -ge 0.8) { 'full' } elseif ($coverageScore -ge 0.6) { 'degraded' } else { 'limited' }
  $coverageLabel = switch ($coverageCode) {
    'full' { '完整推荐' }
    'degraded' { '降级推荐' }
    default { '仅展示' }
  }

  $mergedCoordinates = if ($profileMeta -and @($profileMeta.coordinates).Count -eq 2) { @($profileMeta.coordinates) } else { @($city.coordinates) }
  $mergedPopulation = First-NonNull @(
    Get-Profile-Number $profilePopulation 'value'
    (To-NullableNumber $city.population)
  )
  $mergedPopulationUnit = First-NonNull @(
    Get-Profile-String $profilePopulation 'unit'
    $city.populationUnit
  )
  $profileWageMonthly = Get-Profile-Number $profileIncome 'wageReferenceMonthly'
  $profileWageAnnual = Get-Profile-Number $profileIncome 'wageReferenceAnnual'
  if ($null -eq $profileWageAnnual -and $null -ne $profileWageMonthly) {
    $profileWageAnnual = [math]::Round([double]$profileWageMonthly * 12, 1)
  }
  if ($null -eq $profileWageMonthly -and $null -ne $profileWageAnnual) {
    $profileWageMonthly = [math]::Round([double]$profileWageAnnual / 12, 1)
  }
  $profileRentPerSqm = Get-Profile-Number $profileLatestCost 'rentMedianPerSqm'
  $profileDwellingSize = Get-Profile-Number $profileLatestCost 'assumedDwellingSizeSqm'
  $profileRentMedian = if ($null -ne $profileRentPerSqm -and $null -ne $profileDwellingSize) {
    [math]::Round([double]$profileRentPerSqm * [double]$profileDwellingSize, 1)
  } else {
    $null
  }
  $generatedPeriods = if ($generated) { $generated.periods } else { $null }
  $displayPeriodLabel = if ($generatedPeriods) {
    $generatedPeriods.latest.label
  } elseif ($profileLatestCost -or $profileLatestEnvironment) {
    '2024 年度底座 + 最新公开快照'
  } else {
    '2024 年度官方公报底座'
  }

  $cityRecords += [pscustomobject][ordered]@{
    id = $city.id
    officialCode = $officialCode
    name = $city.name
    pinyin = $city.pinyin
    province = First-NonNull @(
      Get-Profile-String $profileMeta 'province'
      $city.province
    )
    provinceId = $provinceCode
    region = Map-Existing-Region (First-NonNull @(
      (Get-Profile-String $profileMeta 'region')
      $city.region
    ))
    tier = Map-Existing-Tier (First-NonNull @(
      (Get-Profile-String $profileMeta 'tier')
      $city.tier
    ))
    coordinates = $mergedCoordinates
    layerType = if ($officialRow) { 'deep-plus-official' } else { 'deep-snapshot' }
    shortDescription = First-NonNull @(
      (Get-Profile-String $profileMeta 'shortDescription')
      $city.shortDescription
    )
    longDescription = First-NonNull @(
      (Get-Profile-String $profileMeta 'longDescription')
      $city.longDescription
    )
    tags = Distinct-Array @($city.tags + $(Get-Profile-Array $profileMeta 'tags'))
    suitableFor = Distinct-Array @($city.suitableFor + $(Get-Profile-Array $profileMeta 'suitableFor'))
    notIdealFor = Distinct-Array @($city.notIdealFor + $(Get-Profile-Array $profileMeta 'notIdealFor'))
    population = $mergedPopulation
    populationUnit = $mergedPopulationUnit
    populationScope = 'resident'
    disposableIncome = First-NonNull @(
      (To-NullableNumber $income.disposableIncome)
      (Get-Profile-Number $profileIncome 'disposableIncome')
    )
    wageReferenceMonthly = First-NonNull @(
      (To-NullableNumber $income.wageReferenceMonthly)
      $profileWageMonthly
    )
    wageReferenceAnnual = First-NonNull @(
      $(if ($null -ne (To-NullableNumber $income.wageReferenceMonthly)) { [math]::Round([double](To-NullableNumber $income.wageReferenceMonthly) * 12, 1) } else { $null })
      $profileWageAnnual
      $officialWageAnnual
    )
    annualConsumptionPerCapita = First-NonNull @(
      (To-NullableNumber $cost.annualConsumptionPerCapita)
      (Get-Profile-Number $profileCost 'annualConsumptionPerCapita')
    )
    rentMedian = First-NonNull @(
      (To-NullableNumber $cost.rentMedian)
      $profileRentMedian
    )
    rentMedianPerSqm = First-NonNull @(
      (To-NullableNumber $cost.rentMedianPerSqm)
      $profileRentPerSqm
    )
    assumedDwellingSizeSqm = First-NonNull @(
      (To-NullableNumber $cost.assumedDwellingSizeSqm)
      $profileDwellingSize
    )
    avgCommuteTime = First-NonNull @(
      (To-NullableNumber $mobility.avgCommuteTime)
      (Get-Profile-Number $profileReportMobility 'avgCommuteTime')
    )
    commuteWithin45 = First-NonNull @(
      (To-NullableNumber $mobility.commuteWithin45)
      (Get-Profile-Number $profileReportMobility 'commuteWithin45')
    )
    publicTransportScore = To-NullableNumber $mobility.publicTransportScore
    railCoverageCommute = First-NonNull @(
      (To-NullableNumber $mobility.railCoverageCommute)
      (Get-Profile-Number $profileReportMobility 'railCoverageCommute')
    )
    bus45Service = First-NonNull @(
      (To-NullableNumber $mobility.bus45Service)
      (Get-Profile-Number $profileReportMobility 'bus45Service')
    )
    extremeCommute60 = First-NonNull @(
      (To-NullableNumber $mobility.extremeCommute60)
      (Get-Profile-Number $profileReportMobility 'extremeCommute60')
    )
    avgCommuteDistance = First-NonNull @(
      (To-NullableNumber $mobility.avgCommuteDistance)
      (Get-Profile-Number $profileReportMobility 'avgCommuteDistance')
    )
    railTransitLength = First-NonNull @(
      (To-NullableNumber $mobility.railTransitLength)
      (Get-Profile-Number $profileAnnualMobility 'railTransitLength')
    )
    reportRailTransitLength = First-NonNull @(
      (To-NullableNumber $mobility.reportRailTransitLength)
      (Get-Profile-Number $profileReportMobility 'reportRailTransitLength')
    )
    utilityCoverage = First-NonNull @(
      (To-NullableNumber $mobility.utilityCoverage)
      (Get-Profile-Number $profileAnnualMobility 'utilityCoverage')
    )
    greenPublicSpaceProxy = First-NonNull @(
      (To-NullableNumber $mobility.greenPublicSpaceProxy)
      (Get-Profile-Number $profileAnnualMobility 'greenPublicSpaceProxy')
    )
    pm25Reference = First-NonNull @(
      (To-NullableNumber $environment.pm25Reference)
      (Get-Profile-Number $profileAnnualEnvironment 'pm25Reference')
    )
    goodAirDaysRatio = First-NonNull @(
      (To-NullableNumber $environment.goodAirDaysRatio)
      (Get-Profile-Number $profileAnnualEnvironment 'goodAirDaysRatio')
    )
    latestGoodAirDaysRatio = First-NonNull @(
      (To-NullableNumber $environment.latestGoodAirDaysRatio)
      (Get-Profile-Number $profileLatestEnvironment 'goodAirDaysRatio')
    )
    latestSignalPeriod = First-NonNull @(
      $environment.latestSignalPeriod
      (Get-Profile-String $profileLatestEnvironment 'period')
    )
    rentBurdenProxy = To-NullableNumber $generated.rentBurdenProxy
    rentIndex = To-NullableNumber $generated.rentIndex
    rentBurdenIndex = To-NullableNumber $generated.rentBurdenIndex
    consumptionIndex = To-NullableNumber $generated.consumptionIndex
    transportCostIndex = To-NullableNumber $generated.transportCostIndex
    totalCostIndex = To-NullableNumber $generated.totalCostIndex
    costFriendliness = To-NullableNumber $generated.costFriendliness
    commuteIndex = To-NullableNumber $generated.commuteIndex
    basicServices = To-NullableNumber $generated.basicServices
    airQualityScore = To-NullableNumber $generated.airQualityScore
    savingScore = To-NullableNumber $generated.savingScore
    graduateScore = To-NullableNumber $generated.graduateScore
    balancedScore = To-NullableNumber $generated.balancedScore
    coupleScore = To-NullableNumber $generated.coupleScore
    officialGdp = $officialGdp
    officialRetailSales = $officialRetailSales
    officialStudents = $officialStudents
    officialHospitals = $officialHospitals
    officialDoctors = $officialDoctors
    officialRegisteredPopulation = $officialRegisteredPopulation
    baseOfficialScore = $null
    opportunityScore = $null
    pressureScore = $null
    coverageScore = $coverageScore
    coverageCode = $coverageCode
    coverageLabel = $coverageLabel
    aiEligible = [bool]($coverageScore -ge 0.6)
    cityMapEligibility = $true
    cityRecommendationEligibility = [bool]($coverageScore -ge 0.6)
    sourceRefs = Distinct-Array @(
      $city.sourceRefs + $income.sourceRefs + $cost.sourceRefs + $mobility.sourceRefs + $environment.sourceRefs + $generated.sourceRefs + $persona.sourceRefs + $(if ($officialRow) { $officialRow.sourceRefs }) + $profileSourceRefs
    )
    qualityFlags = Distinct-Array @(
      $city.qualityFlags + $income.qualityFlags + $cost.qualityFlags + $mobility.qualityFlags + $environment.qualityFlags + $generated.qualityFlags + $profileQualityFlags
    )
    periods = if ($generatedPeriods) { $generatedPeriods } else { [ordered]@{
      latest = [ordered]@{
        label = $displayPeriodLabel
        note = '当前深度城市优先使用年度底座和可核实的最新快照。'
        aligned = $false
      }
      alignedAnnual = [ordered]@{
        label = '2024 年度对齐口径'
        note = '统一年度模式优先回到 2024 年度底座。'
        aligned = $true
      }
    } }
    periodValues = [ordered]@{
      latest = [ordered]@{
        totalCostIndex = To-NullableNumber $generated.totalCostIndex
        rentBurdenProxy = To-NullableNumber $generated.rentBurdenProxy
        commuteIndex = To-NullableNumber $generated.commuteIndex
        airQualityScore = To-NullableNumber $generated.airQualityScore
      }
      alignedAnnual = [ordered]@{
        totalCostIndex = To-NullableNumber $generated.totalCostIndex
        rentBurdenProxy = To-NullableNumber $generated.rentBurdenProxy
        commuteIndex = To-NullableNumber $generated.commuteIndex
        airQualityScore = To-NullableNumber $generated.airQualityScore
      }
    }
    displayPeriodLabel = $displayPeriodLabel
    lastUpdated = First-NonNull @(
      (Get-Profile-String $profileMeta 'lastUpdated')
      $city.lastUpdated
    )
  }
}

foreach ($profile in $cityProfiles) {
  $meta = $profile.cityMeta
  if ($null -eq $meta) { continue }
  if ($cityById.ContainsKey([string]$meta.id)) { continue }

  $annual = $profile.annual2024
  $populationBlock = Get-Profile-Object $annual 'population'
  $incomeBlock = Get-Profile-Object $annual 'income'
  $costBlock = Get-Profile-Object $annual 'costOfLiving'
  $annualMobilityBlock = Get-Profile-Object $annual 'mobility'
  $annualEnvironmentBlock = Get-Profile-Object $annual 'environment'
  $latest = $profile.latestSnapshot
  $latestCostBlock = Get-Profile-Object $latest 'costOfLiving'
  $latestEnvironmentBlock = Get-Profile-Object $latest 'environment'
  $report = $profile.supportingReport
  $reportMobilityBlock = Get-Profile-Object $report 'mobility'

  $officialCode = Get-Profile-String $meta 'officialCode'
  if ($officialCode) { $matchedOfficialCodes[$officialCode] = $true }
  $provinceCode = if ($officialCode) { Province-Code-From-City-Code $officialCode } else { $null }
  $profileRentPerSqm = Get-Profile-Number $latestCostBlock 'rentMedianPerSqm'
  $profileDwellingSize = Get-Profile-Number $latestCostBlock 'assumedDwellingSizeSqm'
  $profileRentMedian = if ($null -ne $profileRentPerSqm -and $null -ne $profileDwellingSize) {
    [math]::Round([double]$profileRentPerSqm * [double]$profileDwellingSize, 1)
  } else {
    $null
  }
  $profileWageMonthly = Get-Profile-Number $incomeBlock 'wageReferenceMonthly'
  $profileWageAnnual = Get-Profile-Number $incomeBlock 'wageReferenceAnnual'
  if ($null -eq $profileWageAnnual -and $null -ne $profileWageMonthly) {
    $profileWageAnnual = [math]::Round([double]$profileWageMonthly * 12, 1)
  }
  if ($null -eq $profileWageMonthly -and $null -ne $profileWageAnnual) {
    $profileWageMonthly = [math]::Round([double]$profileWageAnnual / 12, 1)
  }

  $population = Get-Profile-Number $populationBlock 'value'
  $disposableIncome = Get-Profile-Number $incomeBlock 'disposableIncome'
  $annualConsumption = Get-Profile-Number $costBlock 'annualConsumptionPerCapita'
  $pm25 = Get-Profile-Number $annualEnvironmentBlock 'pm25Reference'
  $goodAir = Get-Profile-Number $annualEnvironmentBlock 'goodAirDaysRatio'
  $railLength = Get-Profile-Number $annualMobilityBlock 'railTransitLength'
  $utilityCoverage = Get-Profile-Number $annualMobilityBlock 'utilityCoverage'
  $greenProxy = Get-Profile-Number $annualMobilityBlock 'greenPublicSpaceProxy'
  $presentCount = @($population, $disposableIncome, $annualConsumption, $pm25, $goodAir, $railLength, $utilityCoverage, $greenProxy | Where-Object { $null -ne $_ }).Count
  $coverageScore = [math]::Round($presentCount / 8, 2)
  $coverageCode = if ($coverageScore -ge 0.6) { 'degraded' } else { 'limited' }

  $profileSourceRefs = Distinct-Array @(
    $profile.sourceRefs
    $meta.sourceRefs
    $(Get-Profile-Array $incomeBlock 'sourceRefs')
    $(Get-Profile-Array $costBlock 'sourceRefs')
    $(Get-Profile-Array $annualMobilityBlock 'sourceRefs')
    $(Get-Profile-Array $annualEnvironmentBlock 'sourceRefs')
    $(Get-Profile-Array $latestCostBlock 'sourceRefs')
    $(Get-Profile-Array $latestEnvironmentBlock 'sourceRefs')
    $(Get-Profile-Array $reportMobilityBlock 'sourceRefs')
  )
  $profileQualityFlags = Distinct-Array @(
    $profile.qualityFlags
    $meta.qualityFlags
    $(Get-Profile-Array $incomeBlock 'qualityFlags')
    $(Get-Profile-Array $costBlock 'qualityFlags')
    $(Get-Profile-Array $annualMobilityBlock 'qualityFlags')
    $(Get-Profile-Array $annualEnvironmentBlock 'qualityFlags')
    $(Get-Profile-Array $latestCostBlock 'qualityFlags')
    $(Get-Profile-Array $latestEnvironmentBlock 'qualityFlags')
    $(Get-Profile-Array $reportMobilityBlock 'qualityFlags')
    'base_official_profile'
  )

  $cityRecords += [pscustomobject][ordered]@{
    id = [string]$meta.id
    officialCode = $officialCode
    name = $meta.name
    pinyin = $meta.pinyin
    province = $meta.province
    provinceId = $provinceCode
    region = Map-Existing-Region $meta.region
    tier = Map-Existing-Tier $meta.tier
    coordinates = @($meta.coordinates)
    layerType = 'profile-official'
    shortDescription = $meta.shortDescription
    longDescription = $meta.longDescription
    tags = Distinct-Array @($meta.tags)
    suitableFor = Distinct-Array @($meta.suitableFor)
    notIdealFor = Distinct-Array @($meta.notIdealFor)
    population = $population
    populationUnit = First-NonNull @((Get-Profile-String $populationBlock 'unit'), '万人')
    populationScope = 'resident'
    disposableIncome = $disposableIncome
    wageReferenceMonthly = $profileWageMonthly
    wageReferenceAnnual = $profileWageAnnual
    annualConsumptionPerCapita = $annualConsumption
    rentMedian = $profileRentMedian
    rentMedianPerSqm = $profileRentPerSqm
    assumedDwellingSizeSqm = $profileDwellingSize
    avgCommuteTime = Get-Profile-Number $reportMobilityBlock 'avgCommuteTime'
    commuteWithin45 = Get-Profile-Number $reportMobilityBlock 'commuteWithin45'
    publicTransportScore = $null
    railCoverageCommute = Get-Profile-Number $reportMobilityBlock 'railCoverageCommute'
    bus45Service = Get-Profile-Number $reportMobilityBlock 'bus45Service'
    extremeCommute60 = Get-Profile-Number $reportMobilityBlock 'extremeCommute60'
    avgCommuteDistance = Get-Profile-Number $reportMobilityBlock 'avgCommuteDistance'
    railTransitLength = $railLength
    reportRailTransitLength = Get-Profile-Number $reportMobilityBlock 'reportRailTransitLength'
    utilityCoverage = $utilityCoverage
    greenPublicSpaceProxy = $greenProxy
    pm25Reference = $pm25
    goodAirDaysRatio = $goodAir
    latestGoodAirDaysRatio = Get-Profile-Number $latestEnvironmentBlock 'goodAirDaysRatio'
    latestSignalPeriod = Get-Profile-String $latestEnvironmentBlock 'period'
    rentBurdenProxy = $null
    rentIndex = $null
    rentBurdenIndex = $null
    consumptionIndex = $null
    transportCostIndex = $null
    totalCostIndex = $null
    costFriendliness = $null
    commuteIndex = $null
    basicServices = $null
    airQualityScore = $null
    savingScore = $null
    graduateScore = $null
    balancedScore = $null
    coupleScore = $null
    officialGdp = $null
    officialRetailSales = $null
    officialStudents = $null
    officialHospitals = $null
    officialDoctors = $null
    officialRegisteredPopulation = $null
    baseOfficialScore = $null
    opportunityScore = $null
    pressureScore = $null
    coverageScore = $coverageScore
    coverageCode = $coverageCode
    coverageLabel = '基础官方分析'
    aiEligible = $false
    cityMapEligibility = $true
    cityRecommendationEligibility = $false
    sourceRefs = $profileSourceRefs
    qualityFlags = $profileQualityFlags
    periods = [ordered]@{
      latest = [ordered]@{
        label = if ($latestCostBlock -or $latestEnvironmentBlock) { '2024 年度底座 + 最新公开快照' } else { '2024 年度官方公报底座' }
        note = '当前城市仅补入官方年度底座或单项公开快照，尚未进入完整城市推荐。'
        aligned = $false
      }
      alignedAnnual = [ordered]@{
        label = '2024 年度官方公报底座'
        note = '统一年度模式只使用 2024 年官方公报字段。'
        aligned = $true
      }
    }
    periodValues = [ordered]@{
      latest = [ordered]@{}
      alignedAnnual = [ordered]@{}
    }
    displayPeriodLabel = if ($latestCostBlock -or $latestEnvironmentBlock) { '2024 年度底座 + 最新公开快照' } else { '2024 年度官方公报底座' }
    lastUpdated = First-NonNull @((Get-Profile-String $meta 'lastUpdated'), (Get-Date).ToString('yyyy-MM-dd'))
  }
}

foreach ($officialCity in $majorCityRows) {
  if ($matchedOfficialCodes.ContainsKey($officialCity.code)) { continue }

  $provinceCode = Province-Code-From-City-Code $officialCity.code
  $province = $provinceByCode[$provinceCode]
  $ref = $cityReference[$officialCity.code]
  $gdp = Get-Metric-Value $officialCity.metrics 'gdp'
  $wageAnnual = Get-Metric-Value $officialCity.metrics 'wageAnnual'
  $wageMonthly = if ($null -ne $wageAnnual) { [math]::Round($wageAnnual / 12, 1) } else { $null }
  $registeredPopulation = Get-Metric-Value $officialCity.metrics 'registeredPopulation'
  $retailSales = Get-Metric-Value $officialCity.metrics 'retailSales'
  $students = Get-Metric-Value $officialCity.metrics 'students'
  $hospitals = Get-Metric-Value $officialCity.metrics 'hospitals'
  $doctors = Get-Metric-Value $officialCity.metrics 'doctors'
  $presentCount = @($gdp, $wageAnnual, $registeredPopulation, $retailSales, $students, $hospitals, $doctors | Where-Object { $null -ne $_ }).Count
  $coverageScore = [math]::Round($presentCount / 7, 2)
  $coverageCode = if ($coverageScore -ge 0.75) { 'degraded' } else { 'limited' }
  $coverageLabel = if ($coverageCode -eq 'degraded') { '基础官方分析' } else { '仅展示' }

  $cityRecords += [pscustomobject][ordered]@{
    id = $officialCity.code
    officialCode = $officialCity.code
    name = $officialCity.name
    pinyin = ''
    province = $province.name
    provinceId = $provinceCode
    region = Get-Region-By-Province-Code $provinceCode
    tier = if ($ref) { $ref.tier } else { '强二线' }
    coordinates = if ($ref) { $ref.coordinates } else { @() }
    layerType = 'major-city-official'
    shortDescription = $null
    longDescription = $null
    tags = @('主要城市', '官方年度层')
    suitableFor = @('先看省会/主要城市基本面')
    notIdealFor = @('需要租金与通勤完整快照')
    population = $registeredPopulation
    populationUnit = if ($null -ne $registeredPopulation) { '万人' } else { $null }
    populationScope = if ($null -ne $registeredPopulation) { 'registered' } else { $null }
    disposableIncome = $null
    wageReferenceMonthly = $wageMonthly
    wageReferenceAnnual = $wageAnnual
    annualConsumptionPerCapita = $null
    rentMedian = $null
    rentMedianPerSqm = $null
    assumedDwellingSizeSqm = $null
    avgCommuteTime = $null
    commuteWithin45 = $null
    publicTransportScore = $null
    railCoverageCommute = $null
    bus45Service = $null
    extremeCommute60 = $null
    avgCommuteDistance = $null
    railTransitLength = $null
    reportRailTransitLength = $null
    utilityCoverage = $null
    greenPublicSpaceProxy = $null
    pm25Reference = $null
    goodAirDaysRatio = $null
    latestGoodAirDaysRatio = $null
    latestSignalPeriod = $null
    rentBurdenProxy = $null
    rentIndex = $null
    rentBurdenIndex = $null
    consumptionIndex = $null
    transportCostIndex = $null
    totalCostIndex = $null
    costFriendliness = $null
    commuteIndex = $null
    basicServices = $null
    airQualityScore = $null
    savingScore = $null
    graduateScore = $null
    balancedScore = $null
    coupleScore = $null
    officialGdp = $gdp
    officialRetailSales = $retailSales
    officialStudents = $students
    officialHospitals = $hospitals
    officialDoctors = $doctors
    officialRegisteredPopulation = $registeredPopulation
    baseOfficialScore = $null
    opportunityScore = $null
    pressureScore = $null
    coverageScore = $coverageScore
    coverageCode = $coverageCode
    coverageLabel = $coverageLabel
    aiEligible = $false
    cityMapEligibility = $true
    cityRecommendationEligibility = $false
    sourceRefs = Distinct-Array @($officialCity.sourceRefs)
    qualityFlags = Distinct-Array @($officialCity.qualityFlags + @('base_official_only') + $(if ($null -ne $registeredPopulation) { 'population_registered_only' }))
    periods = [ordered]@{
      latest = [ordered]@{
        label = '2024 official major-city annual data'
        note = 'This city currently provides official annual fundamentals only. Rent, commute, air and cost snapshots are not complete.'
        aligned = $true
      }
      alignedAnnual = [ordered]@{
        label = '2024 official major-city annual data'
        note = 'This city currently provides official annual fundamentals only. Rent, commute, air and cost snapshots are not complete.'
        aligned = $true
      }
    }
    periodValues = [ordered]@{
      latest = [ordered]@{
        officialGdp = $gdp
        wageReferenceAnnual = $wageAnnual
        officialRetailSales = $retailSales
        officialStudents = $students
        officialHospitals = $hospitals
        officialDoctors = $doctors
      }
    }
    displayPeriodLabel = '2024 official major-city annual data'
    lastUpdated = $majorCityRaw.generatedAt
  }
}

$cityEffectiveIncomeValues = @($cityRecords | ForEach-Object {
    if ($null -ne $_.wageReferenceMonthly) { $_.wageReferenceMonthly }
    elseif ($null -ne $_.wageReferenceAnnual) { [math]::Round([double]$_.wageReferenceAnnual / 12, 1) }
    elseif ($null -ne $_.disposableIncome) { [math]::Round([double]$_.disposableIncome / 12, 1) }
  })
$cityGdpValues = @($cityRecords | ForEach-Object { $_.officialGdp })
$cityStudentValues = @($cityRecords | ForEach-Object { $_.officialStudents })
$cityDoctorValues = @($cityRecords | ForEach-Object { $_.officialDoctors })
$cityHospitalValues = @($cityRecords | ForEach-Object { $_.officialHospitals })
$cityCostValues = @($cityRecords | ForEach-Object { $_.totalCostIndex })
$cityRentValues = @($cityRecords | ForEach-Object { $_.rentBurdenProxy })
$cityDisposableValues = @($cityRecords | ForEach-Object { $_.disposableIncome })
$cityConsumptionBurdenValues = @($cityRecords | ForEach-Object {
    if ($null -ne $_.disposableIncome -and $_.disposableIncome -gt 0 -and $null -ne $_.annualConsumptionPerCapita) {
      [math]::Round([double]$_.annualConsumptionPerCapita / [double]$_.disposableIncome, 4)
    }
  })
$cityGoodAirValues = @($cityRecords | ForEach-Object { $_.goodAirDaysRatio })
$cityPm25Values = @($cityRecords | ForEach-Object { $_.pm25Reference })
$cityRailValues = @($cityRecords | ForEach-Object { $_.railTransitLength })
$cityUtilityValues = @($cityRecords | ForEach-Object { $_.utilityCoverage })
$cityGreenValues = @($cityRecords | ForEach-Object { $_.greenPublicSpaceProxy })

$enrichedCityRecords = @()
foreach ($city in $cityRecords) {
  $effectiveMonthlyIncome = if ($null -ne $city.wageReferenceMonthly) {
    $city.wageReferenceMonthly
  } elseif ($null -ne $city.wageReferenceAnnual) {
    [math]::Round([double]$city.wageReferenceAnnual / 12, 1)
  } elseif ($null -ne $city.disposableIncome) {
    [math]::Round([double]$city.disposableIncome / 12, 1)
  } else {
    $null
  }
  $effectiveMonthlyIncomeScore = Normalize $cityEffectiveIncomeValues $effectiveMonthlyIncome
  $consumptionBurdenRatio = if ($null -ne $city.disposableIncome -and $city.disposableIncome -gt 0 -and $null -ne $city.annualConsumptionPerCapita) {
    [math]::Round([double]$city.annualConsumptionPerCapita / [double]$city.disposableIncome, 4)
  } else {
    $null
  }
  $consumptionBurdenScore = Normalize $cityConsumptionBurdenValues $consumptionBurdenRatio $true
  $fallbackAirSignal = Weighted-Score @(
    @{ value = Normalize $cityGoodAirValues $city.goodAirDaysRatio; weight = 0.60 }
    @{ value = Normalize $cityPm25Values $city.pm25Reference $true; weight = 0.40 }
  )
  $resolvedAirSignal = First-NonNull @($city.airQualityScore, $fallbackAirSignal)
  $fallbackServiceSignal = Weighted-Score @(
    @{ value = Normalize $cityRailValues $city.railTransitLength; weight = 0.35 }
    @{ value = Normalize $cityUtilityValues $city.utilityCoverage; weight = 0.30 }
    @{ value = Normalize $cityGreenValues $city.greenPublicSpaceProxy; weight = 0.35 }
  )
  $serviceSignal = First-NonNull @($city.basicServices, $fallbackServiceSignal)

  $baseOfficialScore = Weighted-Score @(
    @{ value = $effectiveMonthlyIncomeScore; weight = 0.35 }
    @{ value = Normalize $cityGdpValues $city.officialGdp; weight = 0.25 }
    @{ value = Normalize $cityDoctorValues $city.officialDoctors; weight = 0.15 }
    @{ value = Normalize $cityHospitalValues $city.officialHospitals; weight = 0.15 }
    @{ value = Normalize $cityStudentValues $city.officialStudents; weight = 0.10 }
  )

  $opportunityScore = Weighted-Score @(
    @{ value = $effectiveMonthlyIncomeScore; weight = 0.35 }
    @{ value = Normalize $cityGdpValues $city.officialGdp; weight = 0.40 }
    @{ value = Normalize $cityStudentValues $city.officialStudents; weight = 0.25 }
  )

  $pressureScore = if ($null -ne $city.totalCostIndex -or $null -ne $city.rentBurdenProxy) {
    Weighted-Score @(
      @{ value = Normalize $cityCostValues $city.totalCostIndex; weight = 0.55 }
      @{ value = Normalize $cityRentValues $city.rentBurdenProxy; weight = 0.45 }
    )
  } elseif ($null -ne $consumptionBurdenScore) {
    100 - $consumptionBurdenScore
  } else {
    50.0
  }

  $officialAffordabilityScore = Weighted-Score @(
    @{ value = $effectiveMonthlyIncomeScore; weight = 0.55 }
    @{ value = $consumptionBurdenScore; weight = 0.45 }
  )
  $officialBalanceScore = Weighted-Score @(
    @{ value = $officialAffordabilityScore; weight = 0.42 }
    @{ value = $resolvedAirSignal; weight = 0.24 }
    @{ value = $serviceSignal; weight = 0.18 }
    @{ value = $baseOfficialScore; weight = 0.16 }
  )
  $dataCompleteness = [math]::Round(
    @(
      $effectiveMonthlyIncome,
      $city.disposableIncome,
      $city.annualConsumptionPerCapita,
      $resolvedAirSignal,
      $serviceSignal,
      $city.totalCostIndex,
      $city.rentBurdenProxy,
      $city.commuteIndex,
      $baseOfficialScore | Where-Object { $null -ne $_ }
    ).Count / 9,
    2
  )
  $eligibleScopes = Distinct-Array @(
    'national',
    'province'
    $(if ($city.cityRecommendationEligibility) { 'city-ai' } else { 'official-only' })
  )

  $isBaseOfficialLayer = $city.layerType -in @('major-city-official', 'profile-official')
  $fallbackShort = if ($city.layerType -eq 'major-city-official') {
    '{0} 当前仅覆盖 2024 官方基础面，租金与通勤仍待补全。' -f $city.name
  } elseif ($city.layerType -eq 'profile-official') {
    '{0} 当前已补入地级市官方年度层，可做省内基础比较，但租金与通勤仍未补齐。' -f $city.name
  } else {
    $city.shortDescription
  }
  $fallbackLong = if ($city.layerType -eq 'major-city-official') {
    '{0} 已纳入主要城市年度官方层，可比较工资、GDP、医院、医生和高校在校生；租金、通勤、空气与生活成本快照尚不足以进入完整城市推荐。' -f $city.name
  } elseif ($city.layerType -eq 'profile-official') {
    '{0} 已纳入地级市官方公报层，可比较常住人口、收入、消费和已公开环境信号；租金、通勤与深度快照仍不足，因此当前只进入基础比较，不进入完整城市 AI 推荐。' -f $city.name
  } else {
    $city.longDescription
  }
  $tags = if ($city.layerType -eq 'major-city-official') {
    Distinct-Array @($city.tags + @('基础官方层', '主要城市'))
  } elseif ($city.layerType -eq 'profile-official') {
    Distinct-Array @($city.tags + @('基础官方层', '地级市公报层'))
  } else {
    $city.tags
  }

  $enrichedCityRecords += [pscustomobject][ordered]@{
    id = $city.id
    officialCode = $city.officialCode
    name = $city.name
    pinyin = $city.pinyin
    province = $city.province
    provinceId = $city.provinceId
    region = $city.region
    tier = $city.tier
    coordinates = $city.coordinates
    layerType = $city.layerType
    shortDescription = $fallbackShort
    longDescription = $fallbackLong
    tags = $tags
    suitableFor = $city.suitableFor
    notIdealFor = $city.notIdealFor
    population = $city.population
    populationUnit = $city.populationUnit
    populationScope = $city.populationScope
    disposableIncome = $city.disposableIncome
    wageReferenceMonthly = $city.wageReferenceMonthly
    wageReferenceAnnual = $city.wageReferenceAnnual
    effectiveMonthlyIncome = $effectiveMonthlyIncome
    effectiveMonthlyIncomeScore = $effectiveMonthlyIncomeScore
    annualConsumptionPerCapita = $city.annualConsumptionPerCapita
    consumptionBurdenRatio = $consumptionBurdenRatio
    consumptionBurdenScore = $consumptionBurdenScore
    rentMedian = $city.rentMedian
    rentMedianPerSqm = $city.rentMedianPerSqm
    assumedDwellingSizeSqm = $city.assumedDwellingSizeSqm
    avgCommuteTime = $city.avgCommuteTime
    commuteWithin45 = $city.commuteWithin45
    publicTransportScore = $city.publicTransportScore
    railCoverageCommute = $city.railCoverageCommute
    bus45Service = $city.bus45Service
    extremeCommute60 = $city.extremeCommute60
    avgCommuteDistance = $city.avgCommuteDistance
    railTransitLength = $city.railTransitLength
    reportRailTransitLength = $city.reportRailTransitLength
    utilityCoverage = $city.utilityCoverage
    greenPublicSpaceProxy = $city.greenPublicSpaceProxy
    pm25Reference = $city.pm25Reference
    goodAirDaysRatio = $city.goodAirDaysRatio
    latestGoodAirDaysRatio = $city.latestGoodAirDaysRatio
    latestSignalPeriod = $city.latestSignalPeriod
    rentBurdenProxy = $city.rentBurdenProxy
    rentIndex = $city.rentIndex
    rentBurdenIndex = $city.rentBurdenIndex
    consumptionIndex = $city.consumptionIndex
    transportCostIndex = $city.transportCostIndex
    totalCostIndex = $city.totalCostIndex
    costFriendliness = $city.costFriendliness
    commuteIndex = $city.commuteIndex
    basicServices = $city.basicServices
    airQualityScore = $city.airQualityScore
    resolvedAirSignal = $resolvedAirSignal
    officialServiceSignal = $serviceSignal
    officialAffordabilityScore = $officialAffordabilityScore
    officialBalanceScore = $officialBalanceScore
    savingScore = $city.savingScore
    graduateScore = $city.graduateScore
    balancedScore = $city.balancedScore
    coupleScore = $city.coupleScore
    officialGdp = $city.officialGdp
    officialRetailSales = $city.officialRetailSales
    officialStudents = $city.officialStudents
    officialHospitals = $city.officialHospitals
    officialDoctors = $city.officialDoctors
    officialRegisteredPopulation = $city.officialRegisteredPopulation
    baseOfficialScore = $baseOfficialScore
    opportunityScore = $opportunityScore
    pressureScore = $pressureScore
    coverageScore = $city.coverageScore
    coverageCode = $city.coverageCode
    coverageLabel = $city.coverageLabel
    dataCompleteness = $dataCompleteness
    aiEligible = $city.aiEligible
    cityMapEligibility = $city.cityMapEligibility
    cityRecommendationEligibility = $city.cityRecommendationEligibility
    eligibleScopes = $eligibleScopes
    sourceRefs = $city.sourceRefs
    qualityFlags = $city.qualityFlags
    periods = $city.periods
    periodValues = $city.periodValues
    displayPeriodLabel = $city.displayPeriodLabel
    lastUpdated = $city.lastUpdated
  }
}

. (Join-Path $PSScriptRoot 'build-multilayer-records.ps1')
. (Join-Path $PSScriptRoot 'build-multilayer-output.ps1')
& (Join-Path $PSScriptRoot 'build-evidence-packs.ps1')
return

$provinceRecords = @($provinceRecords | ForEach-Object {
    $province = $_
    $provinceCities = @($enrichedCityRecords | Where-Object { $_.provinceId -eq $province.id -and $_.cityMapEligibility })
    $citySampleCount = @($provinceCities).Count
    $aiEligibleCityCount = @($provinceCities | Where-Object { $_.cityRecommendationEligibility }).Count
    $scatterPointCount = @($provinceCities | Where-Object { $null -ne $_.effectiveMonthlyIncome -and $null -ne $_.rentBurdenProxy }).Count
    $sampledCities = @($provinceCities | Sort-Object name | ForEach-Object { $_.name })
    $missingDimensions = @()
    if (@($provinceCities | Where-Object { $null -ne $_.effectiveMonthlyIncome }).Count -lt 3) { $missingDimensions += '收入参考' }
    if (@($provinceCities | Where-Object { $null -ne $_.resolvedAirSignal }).Count -lt 3) { $missingDimensions += '空气质量' }
    if (@($provinceCities | Where-Object { $null -ne $_.officialServiceSignal }).Count -lt 3) { $missingDimensions += '基础服务' }
    if (@($provinceCities | Where-Object { $null -ne $_.rentBurdenProxy }).Count -lt 3) { $missingDimensions += '房租压力' }
    if (@($provinceCities | Where-Object { $null -ne $_.commuteIndex }).Count -lt 3) { $missingDimensions += '通勤便利' }
    if (@($provinceCities | Where-Object { $null -ne $_.totalCostIndex }).Count -lt 3) { $missingDimensions += '生活成本' }
    $cityCoverageLevel = if ($citySampleCount -lt 3) {
      'insufficient'
    } elseif ($aiEligibleCityCount -ge 3) {
      'deep'
    } else {
      'official-only'
    }
    $eligibleModules = [ordered]@{
      rankings = [bool]($citySampleCount -ge 3)
      ai = [bool]($aiEligibleCityCount -ge 3)
      compare = [bool]($citySampleCount -ge 3)
      scatter = [bool]($scatterPointCount -ge 3)
    }

    [pscustomobject][ordered]@{
      id = $province.id
      code = $province.code
      name = $province.name
      region = $province.region
      adminLevel = $province.adminLevel
      provinceCapital = $province.provinceCapital
      representativeCities = $province.representativeCities
      population = $province.population
      populationUnit = $province.populationUnit
      disposableIncome = $province.disposableIncome
      annualConsumptionPerCapita = $province.annualConsumptionPerCapita
      parkGreenPerCapita = $province.parkGreenPerCapita
      gasCoverage = $province.gasCoverage
      railwayLength = $province.railwayLength
      highwayLength = $province.highwayLength
      incomeSupportScore = $province.incomeSupportScore
      consumptionBurden = $province.consumptionBurden
      consumptionBurdenScore = $province.consumptionBurdenScore
      environmentScore = $province.environmentScore
      publicServiceScore = $province.publicServiceScore
      overviewScore = $province.overviewScore
      coverageScore = $province.coverageScore
      coverageLevel = $province.coverageLevel
      sourceRefs = $province.sourceRefs
      qualityFlags = $province.qualityFlags
      periods = $province.periods
      periodValues = $province.periodValues
      hasComparableProxyFields = $province.hasComparableProxyFields
      citySampleCount = $citySampleCount
      aiEligibleCityCount = $aiEligibleCityCount
      scatterPointCount = $scatterPointCount
      sampledCities = $sampledCities
      cityCoverageLevel = $cityCoverageLevel
      eligibleModules = $eligibleModules
      missingDimensions = Distinct-Array $missingDimensions
      lastUpdated = $province.lastUpdated
    }
  })

$cityDirectory = @($enrichedCityRecords | ForEach-Object {
    [pscustomobject][ordered]@{
      cityCode = First-NonNull @($_.officialCode, $_.id)
      id = $_.id
      name = $_.name
      provinceId = $_.provinceId
      province = $_.province
      adminLevel = 'prefecture-level'
      coordinates = $_.coordinates
      sourceStatus = $_.layerType
      coverageLevel = $_.coverageLabel
      lastUpdated = $_.lastUpdated
    }
  })

$provinceGenerated = @($provinceRecords | ForEach-Object {
    [pscustomobject][ordered]@{
      provinceId = $_.id
      incomeSupportScore = $_.incomeSupportScore
      consumptionBurdenScore = $_.consumptionBurdenScore
      environmentScore = $_.environmentScore
      publicServiceScore = $_.publicServiceScore
      overviewScore = $_.overviewScore
      coverageScore = $_.coverageScore
      coverageLevel = $_.coverageLevel
      citySampleCount = $_.citySampleCount
      aiEligibleCityCount = $_.aiEligibleCityCount
      scatterPointCount = $_.scatterPointCount
      cityCoverageLevel = $_.cityCoverageLevel
      eligibleModules = $_.eligibleModules
      missingDimensions = $_.missingDimensions
      sourceRefs = $_.sourceRefs
      qualityFlags = $_.qualityFlags
      periods = $_.periods
      generatedAt = $provinceRaw.generatedAt
    }
  })

$provinceViewModel = [ordered]@{
  generatedAt = $provinceRaw.generatedAt
  summary = [ordered]@{
    totalProvinces = @($provinceRecords).Count
    comparableMainlandProvinces = @($provinceRecords | Where-Object { $_.coverageLevel -ne 'limited' }).Count
    limitedProvinces = @($provinceRecords | Where-Object { $_.coverageLevel -eq 'limited' }).Count
    provincesWithCityRankings = @($provinceRecords | Where-Object { $_.eligibleModules.rankings }).Count
    provincesWithCityAi = @($provinceRecords | Where-Object { $_.eligibleModules.ai }).Count
    coreMetricCount = 5
  }
  enums = [ordered]@{
    regions = Distinct-Array @($provinceRecords.region)
    mapMetrics = @(
      [ordered]@{ key = 'incomeSupportScore'; label = '收入支撑力'; direction = 'higherBetter' }
      [ordered]@{ key = 'consumptionBurdenScore'; label = '消费负担'; direction = 'higherBetter' }
      [ordered]@{ key = 'environmentScore'; label = '环境宜居'; direction = 'higherBetter' }
      [ordered]@{ key = 'publicServiceScore'; label = '基础公共服务'; direction = 'higherBetter' }
      [ordered]@{ key = 'overviewScore'; label = '综合省级概览'; direction = 'higherBetter' }
    )
  }
  provinces = $provinceRecords
}

$cityViewModel = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  summary = [ordered]@{
    totalCities = @($enrichedCityRecords).Count
    deepSnapshotCities = @($enrichedCityRecords | Where-Object { $_.layerType -in @('deep-plus-official', 'deep-snapshot') }).Count
    majorOfficialCities = @($enrichedCityRecords | Where-Object { $_.layerType -eq 'major-city-official' }).Count
    profileOfficialCities = @($enrichedCityRecords | Where-Object { $_.layerType -eq 'profile-official' }).Count
    aiEligibleCities = @($enrichedCityRecords | Where-Object { $_.cityRecommendationEligibility }).Count
    cityMapEligibleCities = @($enrichedCityRecords | Where-Object { $_.cityMapEligibility }).Count
    coreMetricCount = 9
  }
  enums = [ordered]@{
    tiers = Distinct-Array @($enrichedCityRecords.tier)
    regions = Distinct-Array @($enrichedCityRecords.region)
    mapMetrics = @(
      [ordered]@{ key = 'balancedScore'; label = '综合平衡'; direction = 'higherBetter' }
      [ordered]@{ key = 'savingScore'; label = '攒钱友好'; direction = 'higherBetter' }
      [ordered]@{ key = 'commuteIndex'; label = '通勤便利'; direction = 'higherBetter' }
      [ordered]@{ key = 'airQualityScore'; label = '空气质量'; direction = 'higherBetter' }
      [ordered]@{ key = 'totalCostIndex'; label = '综合生活成本'; direction = 'lowerBetter' }
      [ordered]@{ key = 'rentBurdenProxy'; label = '房租压力'; direction = 'lowerBetter' }
      [ordered]@{ key = 'effectiveMonthlyIncome'; label = '收入参考'; direction = 'higherBetter' }
      [ordered]@{ key = 'officialBalanceScore'; label = '官方平衡'; direction = 'higherBetter' }
      [ordered]@{ key = 'officialGdp'; label = 'GDP'; direction = 'higherBetter' }
      [ordered]@{ key = 'baseOfficialScore'; label = '基础官方实力'; direction = 'higherBetter' }
    )
  }
  cities = $enrichedCityRecords
}

$metaOut = [ordered]@{
  siteGeneratedAt = (Get-Date).ToString('yyyy-MM-dd')
  majorDataPeriods = @(
    '省级模式优先使用国家数据 API 的 2024 年度分省官方数据。',
    '城市模式结合 2024 主要城市年度官方层、湖北首批地级市公报层与现有深度快照城市层。',
    '租金快照仍只作用于深度覆盖城市。',
    '通勤和空气质量仍按覆盖度分层展示。'
  )
  updateStrategy = @(
    '先运行 scripts/fetch-official-national-data.ps1 刷新官方省级与主要城市年度快照。',
    '再运行 scripts/build-derived.ps1 读取 city-profiles、生成 province-view-model、view-model、city-directory 与 bootstrap。',
    '发布前运行 scripts/validate-data.ps1。'
  )
  aiMode = 'rule-engine-local-dual-layer'
  coverageSummary = [ordered]@{
    includedProvinces = $provinceViewModel.summary.totalProvinces
    comparableMainlandProvinces = $provinceViewModel.summary.comparableMainlandProvinces
    includedCities = $cityViewModel.summary.totalCities
    aiEligibleCities = $cityViewModel.summary.aiEligibleCities
    profileOfficialCities = $cityViewModel.summary.profileOfficialCities
    provincesWithCityRankings = $provinceViewModel.summary.provincesWithCityRankings
    provincesWithCityAi = $provinceViewModel.summary.provincesWithCityAi
    nationalMapMode = 'dual-layer-province-choropleth-and-city-layer'
    cityLayerScope = 'official-major-cities-plus-prefecture-profiles-plus-deep-snapshots'
  }
  disclaimer = @(
    '省级层已覆盖 31 个大陆省级地区；港澳台因口径差异标记为有限比较。',
    '城市层当前是主要城市官方年度层 + 首批地级市公报层 + 站内深度快照城市，不是完整全国所有地级市。',
    '省内城市样本不足或完整推荐城市少于 3 个时，省内 AI 会被禁用，不再让单一城市代表全省。',
    '省级环境目前使用绿地代理，不等同于省级空气质量事实。',
    'AI 只解释已有数据与覆盖等级，不补造缺失事实。'
  )
}

Write-Json (Join-Path $dataDir 'province-generated-metrics.json') $provinceGenerated
Write-Json (Join-Path $dataDir 'province-view-model.json') $provinceViewModel
Write-Json (Join-Path $dataDir 'view-model.json') $cityViewModel
Write-Json (Join-Path $dataDir 'city-directory.json') $cityDirectory
Write-Json (Join-Path $dataDir 'meta.json') $metaOut

$bootstrap = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  meta = $metaOut
  sources = $sources
  provinceViewModel = $provinceViewModel
  viewModel = $cityViewModel
  recommendationConfig = $aiConfig
}

$bootstrapJson = $bootstrap | ConvertTo-Json -Depth 40
Write-Text (Join-Path $dataDir 'bootstrap.js') ("window.CITY_SITE_DATA = $bootstrapJson;")

Write-Host 'Built province-view-model.json, view-model.json, city-directory.json, meta.json and bootstrap.js'
