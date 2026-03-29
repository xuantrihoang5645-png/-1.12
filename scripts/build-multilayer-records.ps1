$provinceBaseRecords = @($provinceRecords)
$provinceRecordById = @{}
foreach ($province in $provinceBaseRecords) { $provinceRecordById[$province.id] = $province }

$factCityRecords = @($enrichedCityRecords)
$factCityById = @{}
$factCityByCode6 = @{}
$factCityByName = @{}
$factCitiesByProvince = @{}
foreach ($city in $factCityRecords) {
  $factCityById[$city.id] = $city
  if (-not [string]::IsNullOrWhiteSpace([string]$city.officialCode) -and $city.officialCode.Length -ge 6) {
    $factCityByCode6[$city.officialCode.Substring(0, 6)] = $city
  }
  $factCityByName[(Normalize-Place-Name $city.name)] = $city
  if (-not $factCitiesByProvince.ContainsKey($city.provinceId)) { $factCitiesByProvince[$city.provinceId] = @() }
  $factCitiesByProvince[$city.provinceId] += $city
}

$cityFieldNames = @($factCityRecords[0].PSObject.Properties.Name)
$referenceProvinceNameByPrefix = @{}
foreach ($provinceRow in $referenceProvinceRows) {
  $prefix = First-NonNull @([string]$provinceRow.province, ([string]$provinceRow.code).Substring(0, 2))
  if (-not [string]::IsNullOrWhiteSpace([string]$prefix)) { $referenceProvinceNameByPrefix[[string]$prefix] = $provinceRow.name }
}

$expandedCityRecords = @()
$seenCityIds = @{}
foreach ($referenceCity in $referenceCityRows) {
  $cityId = To-Admin12 ([string]$referenceCity.code)
  $provinceId = To-Admin12 ([string]$referenceCity.province)
  $province = $provinceRecordById[$provinceId]
  $fact = $null
  if ($factCityByCode6.ContainsKey([string]$referenceCity.code)) {
    $fact = $factCityByCode6[[string]$referenceCity.code]
  } elseif ($factCityById.ContainsKey($cityId)) {
    $fact = $factCityById[$cityId]
  } elseif ($factCityByName.ContainsKey((Normalize-Place-Name $referenceCity.name))) {
    $fact = $factCityByName[(Normalize-Place-Name $referenceCity.name)]
  }

  $record = [ordered]@{}
  foreach ($field in $cityFieldNames) { $record[$field] = $null }
  if ($fact) {
    foreach ($prop in $fact.PSObject.Properties) { $record[$prop.Name] = $prop.Value }
  }

  $socialSeed = if ($socialSeedById.ContainsKey($cityId)) { $socialSeedById[$cityId] } else { $null }
  $factCompleteness = if ($fact) {
    [math]::Round((Count-NonNull @(
          $fact.effectiveMonthlyIncome,
          $fact.annualConsumptionPerCapita,
          $fact.resolvedAirSignal,
          $fact.officialServiceSignal,
          $fact.totalCostIndex,
          $fact.rentBurdenProxy,
          $fact.commuteIndex,
          $fact.officialBalanceScore
        )) / 8, 2)
  } else { 0.0 }
  $socialCompleteness = if ($socialSeed) { 0.65 } else { 0.0 }
  $inferenceCompleteness = if ($factCompleteness -ge 0.65) { 0.86 } elseif ($province) { 0.58 } else { 0.32 }
  $coverageScore = if ($fact) { $fact.coverageScore } else { [math]::Round(0.12 + ($inferenceCompleteness * 0.35) + ($socialCompleteness * 0.15), 2) }
  $coordinates = if ($fact -and $fact.coordinates) { $fact.coordinates } elseif ($cityReference.ContainsKey($cityId)) { $cityReference[$cityId].coordinates } else { $null }

  $record.id = First-NonNull @($record.id, $cityId)
  $record.officialCode = First-NonNull @($record.officialCode, $cityId)
  $record.name = First-NonNull @($record.name, $referenceCity.name)
  $record.pinyin = First-NonNull @($record.pinyin, $null)
  $record.province = First-NonNull @($record.province, $(if ($province) { $province.name }), $referenceProvinceNameByPrefix[[string]$referenceCity.province])
  $record.provinceId = $provinceId
  $record.parentProvinceId = $provinceId
  $record.parentCityId = $null
  $record.region = First-NonNull @($record.region, $(if ($province) { $province.region }))
  $record.tier = First-NonNull @($record.tier, $(if ($cityReference.ContainsKey($cityId)) { $cityReference[$cityId].tier }), 'unclassified')
  $record.adminLevel = 'prefecture-level'
  $record.coordinates = $coordinates
  $record.layerType = First-NonNull @($record.layerType, 'directory-reference')
  $record.primaryDataClass = $(if ($factCompleteness -gt 0) { 'fact' } else { 'ai_inference' })
  $record.displayPriority = $(if ($factCompleteness -ge 0.6) { 1 } elseif ($factCompleteness -gt 0) { 2 } else { 3 })
  $record.shortDescription = First-NonNull @($record.shortDescription, ('{0} is currently directory-first and fact-light.' -f $record.name))
  $record.longDescription = First-NonNull @($record.longDescription, ('{0} currently shows directory coverage plus AI inference until a richer fact layer is added.' -f $record.name))
  $record.tags = Distinct-Array @(@($record.tags) + $(if (-not $fact) { @('directory-layer', 'ai-inference') }))
  $record.suitableFor = Distinct-Array @($record.suitableFor)
  $record.notIdealFor = Distinct-Array @($record.notIdealFor)
  $record.populationUnit = First-NonNull @($record.populationUnit, '10k persons')
  $record.populationScope = First-NonNull @($record.populationScope, $(if ($fact) { 'fact-layer' } else { 'fact-missing' }))
  $record.coverageScore = $coverageScore
  $record.coverageCode = First-NonNull @($record.coverageCode, $(if ($socialCompleteness -gt 0) { 'social-plus-inference' } else { 'directory-only' }))
  $record.coverageLabel = First-NonNull @($record.coverageLabel, $(if ($socialCompleteness -gt 0) { 'social + inference' } else { 'directory + inference' }))
  $record.dataCompleteness = First-NonNull @($record.dataCompleteness, $factCompleteness)
  $record.factCompleteness = $factCompleteness
  $record.socialCompleteness = $socialCompleteness
  $record.inferenceCompleteness = $inferenceCompleteness
  $record.aiEligible = [bool]($coverageScore -ge 0.25)
  $record.cityMapEligibility = [bool]($coordinates -and $coordinates.Count -eq 2)
  $record.cityRecommendationEligibility = [bool](First-NonNull @($record.cityRecommendationEligibility, $false))
  $record.displayEligibility = $true
  $record.comparisonEligibility = [bool]($factCompleteness -ge 0.35 -or $inferenceCompleteness -ge 0.45)
  $record.eligibleScopes = Distinct-Array @(@($record.eligibleScopes) + @('national', 'province', 'city', 'ai-mixed') + $(if (-not $fact) { 'directory-only' }))
  $record.sourceRefs = Distinct-Array @(@($record.sourceRefs) + @('reference-admin-city'))
  $record.qualityFlags = Distinct-Array @(@($record.qualityFlags) + $(if (-not $fact) { 'directory_reference_only' }))
  $record.periods = Distinct-Array @(@($record.periods) + $(if (-not $fact) { @('directory-reference', 'ai-inference') }))
  $record.periodValues = First-NonNull @($record.periodValues, [ordered]@{ fact = $null; social = $(if ($socialSeed) { $socialSeed.sampleWindow } else { $null }); inference = (Get-Date).ToString('yyyy-MM-dd') })
  $record.displayPeriodLabel = First-NonNull @($record.displayPeriodLabel, 'directory-first / ai-inference-ready')
  $record.lastUpdated = First-NonNull @($record.lastUpdated, (Get-Date).ToString('yyyy-MM-dd'))

  $expandedCityRecords += [pscustomobject]$record
  $seenCityIds[$record.id] = $true
}

foreach ($factOnlyCity in @($factCityRecords | Where-Object { -not $seenCityIds.ContainsKey($_.id) })) {
  $record = [ordered]@{}
  foreach ($prop in $factOnlyCity.PSObject.Properties) { $record[$prop.Name] = $prop.Value }
  $record.parentProvinceId = $factOnlyCity.provinceId
  $record.parentCityId = $null
  $record.adminLevel = 'prefecture-level'
  $record.primaryDataClass = 'fact'
  $record.displayPriority = 1
  $record.factCompleteness = [math]::Round((Count-NonNull @(
        $factOnlyCity.effectiveMonthlyIncome,
        $factOnlyCity.annualConsumptionPerCapita,
        $factOnlyCity.resolvedAirSignal,
        $factOnlyCity.officialServiceSignal,
        $factOnlyCity.totalCostIndex,
        $factOnlyCity.rentBurdenProxy,
        $factOnlyCity.commuteIndex,
        $factOnlyCity.officialBalanceScore
      )) / 8, 2)
  $record.socialCompleteness = $(if ($socialSeedById.ContainsKey($factOnlyCity.id)) { 0.65 } else { 0.0 })
  $record.inferenceCompleteness = 0.86
  $record.displayEligibility = $true
  $record.comparisonEligibility = $true
  $record.eligibleScopes = Distinct-Array @(@($factOnlyCity.eligibleScopes) + @('national', 'province', 'city', 'ai-mixed'))
  $record.sourceRefs = Distinct-Array @(@($factOnlyCity.sourceRefs) + @('reference-admin-city'))
  $expandedCityRecords += [pscustomobject]$record
}

$allCityById = New-Lookup $expandedCityRecords 'id'
$socialSignalRecords = @($socialSeedRecords | ForEach-Object {
    [pscustomobject][ordered]@{
      id = [string]$_.id
      name = $_.name
      adminLevel = First-NonNull @($_.adminLevel, 'unknown')
      parentProvinceId = $_.parentProvinceId
      parentCityId = $_.parentCityId
      dataClass = 'social_signal'
      isComparable = $false
      displayPriority = 2
      confidence = First-NonNull @((To-NullableNumber $_.confidence), 0.4)
      signalCount = First-NonNull @((To-NullableNumber $_.signalCount), 0)
      sentiment = First-NonNull @($_.sentiment, 'unknown')
      themes = Distinct-Array @($_.themes)
      sampleWindow = $_.sampleWindow
      platformBreakdown = $_.platformBreakdown
      riskNote = First-NonNull @($_.riskNote, 'Public social snapshot only.')
      sourceRefs = Distinct-Array @($_.sourceRefs)
      lastVerifiedAt = First-NonNull @($_.lastVerifiedAt, $socialSignalSeed.generatedAt)
    }
  })

$provinceInferenceRecords = @($provinceBaseRecords | ForEach-Object {
    $confidence = if ($_.coverageLevel -eq 'limited') { 0.45 } else { 0.84 }
    [pscustomobject][ordered]@{
      id = $_.id
      name = $_.name
      adminLevel = 'province-level'
      parentProvinceId = $null
      parentCityId = $null
      dataClass = 'ai_inference'
      isComparable = [bool]($_.coverageLevel -ne 'limited')
      displayPriority = 1
      confidence = $confidence
      confidenceBand = Get-Confidence-Band $confidence
      estimatedScores = [ordered]@{
        affordability = Clamp-Score (Average-Values @($_.incomeSupportScore, $_.consumptionBurdenScore))
        balance = Clamp-Score $_.overviewScore
        environment = Clamp-Score $_.environmentScore
        opportunity = Clamp-Score (Average-Values @($_.incomeSupportScore, $_.publicServiceScore))
        pressure = Clamp-Score $(if ($null -ne $_.consumptionBurdenScore) { 100 - $_.consumptionBurdenScore } else { 50 })
      }
      reasoningSummary = $(if ($_.coverageLevel -eq 'limited') { 'Limited inference only because comparability is restricted.' } else { 'Province inference is mainly anchored to province fact-layer metrics.' })
      referencePeers = Distinct-Array @($_.representativeCities)
      shouldNotBeUsedForRanking = [bool]($_.coverageLevel -eq 'limited')
      inferenceBasis = @('province-fact-layer')
      sourceRefs = Distinct-Array @($_.sourceRefs)
      lastVerifiedAt = $_.lastUpdated
    }
  })

$cityInferenceRecords = @()
foreach ($city in $expandedCityRecords) {
  $province = $provinceRecordById[$city.provinceId]
  $peerCities = if ($factCitiesByProvince.ContainsKey($city.provinceId)) { @($factCitiesByProvince[$city.provinceId]) } else { @() }
  $peerAff = Average-Values @($peerCities | ForEach-Object { First-NonNull @($_.officialAffordabilityScore, $_.savingScore, $_.effectiveMonthlyIncomeScore) })
  $peerBal = Average-Values @($peerCities | ForEach-Object { First-NonNull @($_.balancedScore, $_.officialBalanceScore, $_.baseOfficialScore) })
  $peerEnv = Average-Values @($peerCities | ForEach-Object { First-NonNull @($_.airQualityScore, $_.resolvedAirSignal) })
  $peerOpp = Average-Values @($peerCities | ForEach-Object { First-NonNull @($_.opportunityScore, $_.baseOfficialScore) })
  $peerPress = Average-Values @($peerCities | ForEach-Object { First-NonNull @($_.pressureScore, $(if ($null -ne $_.officialAffordabilityScore) { 100 - $_.officialAffordabilityScore })) })
  $aff = First-NonNull @($city.officialAffordabilityScore, $city.savingScore, $peerAff, $(if ($province) { Average-Values @($province.incomeSupportScore, $province.consumptionBurdenScore) }), 52)
  $bal = First-NonNull @($city.balancedScore, $city.officialBalanceScore, $peerBal, $(if ($province) { $province.overviewScore }), 55)
  $env = First-NonNull @($city.airQualityScore, $city.resolvedAirSignal, $peerEnv, $(if ($province) { $province.environmentScore }), 50)
  $opp = First-NonNull @($city.opportunityScore, $peerOpp, $(if ($province) { $province.incomeSupportScore }), 55)
  $press = First-NonNull @($city.pressureScore, $peerPress, $(if ($province -and $null -ne $province.consumptionBurdenScore) { 100 - $province.consumptionBurdenScore }), 50)
  $cityFactScore = First-NonNull @($city.factCompleteness, 0)
  $basis = Distinct-Array @($(if ($cityFactScore -gt 0) { 'city-fact-layer' }), $(if ($peerCities.Count) { 'same-province-fact-peers' }), $(if ($province) { 'province-fact-layer' }))
  $isCapital = $province -and (Normalize-Place-Name $city.name) -eq (Normalize-Place-Name $province.provinceCapital)
  if ($isCapital -and ($cityFactScore -lt 0.4)) {
    $opp = Clamp-Score ($opp + 8)
    $press = Clamp-Score ($press + 6)
    $bal = Clamp-Score ($bal + 3)
    $basis = Distinct-Array @($basis + @('provincial-capital-heuristic'))
  }
  $confidence = if ($cityFactScore -ge 0.7) { 0.84 } elseif ($cityFactScore -ge 0.45) { 0.72 } elseif ($peerCities.Count -ge 2) { 0.58 } elseif ($province) { 0.46 } else { 0.32 }
  $cityInferenceRecords += [pscustomobject][ordered]@{
    id = $city.id
    name = $city.name
    adminLevel = 'prefecture-level'
    parentProvinceId = $city.provinceId
    parentCityId = $null
    dataClass = 'ai_inference'
    isComparable = [bool]($cityFactScore -ge 0.35)
    displayPriority = $(if ($cityFactScore -ge 0.35) { 1 } else { 2 })
    confidence = $confidence
    confidenceBand = Get-Confidence-Band $confidence
    estimatedScores = [ordered]@{
      affordability = Clamp-Score $aff
      balance = Clamp-Score $bal
      environment = Clamp-Score $env
      opportunity = Clamp-Score $opp
      pressure = Clamp-Score $press
    }
    reasoningSummary = $(if ($cityFactScore -ge 0.55) { 'City fact layer remains primary; AI only fills interpretation gaps.' } elseif ($peerCities.Count) { 'Inference mainly uses same-province fact peers plus province facts.' } else { 'Inference mainly uses province facts and admin-level heuristics.' })
    referencePeers = Distinct-Array @($peerCities | Select-Object -First 3 -ExpandProperty name)
    shouldNotBeUsedForRanking = [bool]($cityFactScore -lt 0.45)
    inferenceBasis = $basis
    sourceRefs = Distinct-Array @($city.sourceRefs + $(if ($province) { $province.sourceRefs }))
    lastVerifiedAt = $city.lastUpdated
  }
}

$cityInferenceById = New-Lookup $cityInferenceRecords 'id'
$countyRecords = @()
$countyInferenceRecords = @()
foreach ($referenceArea in $referenceAreaRows) {
  $countyId = To-Admin12 ([string]$referenceArea.code)
  $provinceId = To-Admin12 ([string]$referenceArea.province)
  $cityId = To-Admin12 (("{0}{1}" -f [string]$referenceArea.province, [string]$referenceArea.city))
  $province = $provinceRecordById[$provinceId]
  $city = if ($allCityById.ContainsKey($cityId)) { $allCityById[$cityId] } else { $null }
  $cityInference = if ($cityInferenceById.ContainsKey($cityId)) { $cityInferenceById[$cityId] } else { $null }
  $countyType = Get-County-Type $referenceArea.name
  $baseAff = First-NonNull @($(if ($cityInference) { $cityInference.estimatedScores.affordability }), $(if ($province) { Average-Values @($province.incomeSupportScore, $province.consumptionBurdenScore) }), 50)
  $baseBal = First-NonNull @($(if ($cityInference) { $cityInference.estimatedScores.balance }), $(if ($province) { $province.overviewScore }), 52)
  $baseEnv = First-NonNull @($(if ($cityInference) { $cityInference.estimatedScores.environment }), $(if ($province) { $province.environmentScore }), 48)
  $baseOpp = First-NonNull @($(if ($cityInference) { $cityInference.estimatedScores.opportunity }), $(if ($province) { $province.incomeSupportScore }), 48)
  $basePress = First-NonNull @($(if ($cityInference) { $cityInference.estimatedScores.pressure }), 50)
  if ($countyType -eq 'district') { $baseOpp = Clamp-Score ($baseOpp + 6); $basePress = Clamp-Score ($basePress + 8); $baseAff = Clamp-Score ($baseAff - 3) }
  if ($countyType -eq 'county' -or $countyType -eq 'banner') { $baseAff = Clamp-Score ($baseAff + 7); $basePress = Clamp-Score ($basePress - 4) }
  if ($countyType -eq 'county-level-city') { $baseBal = Clamp-Score ($baseBal + 3); $baseOpp = Clamp-Score ($baseOpp + 2) }
  $inferenceCompleteness = if ($cityInference) { 0.52 } elseif ($province) { 0.38 } else { 0.22 }
  $coverageLevel = if ($inferenceCompleteness -ge 0.35) { 'social-plus-inference' } else { 'directory-only' }
  $countyRecords += [pscustomobject][ordered]@{
    id = $countyId
    officialCode = $countyId
    name = $referenceArea.name
    province = $(if ($province) { $province.name } else { $referenceProvinceNameByPrefix[[string]$referenceArea.province] })
    parentCity = $(if ($city) { $city.name } elseif ($referenceCityByCode.ContainsKey($cityId)) { $referenceCityByCode[$cityId].name } else { $null })
    parentProvinceId = $provinceId
    parentCityId = $cityId
    region = $(if ($province) { $province.region } else { Get-Region-By-Province-Code $provinceId })
    adminLevel = 'county-level'
    countyType = $countyType
    coordinates = $null
    primaryDataClass = 'ai_inference'
    factCompleteness = 0.0
    socialCompleteness = 0.0
    inferenceCompleteness = $inferenceCompleteness
    coverageScore = [math]::Round(0.08 + ($inferenceCompleteness * 0.24), 2)
    coverageLevel = $coverageLevel
    displayEligibility = $true
    comparisonEligibility = [bool]($inferenceCompleteness -ge 0.35)
    aiEligibility = [bool]($inferenceCompleteness -ge 0.35)
    sourceRefs = @('reference-admin-area')
    qualityFlags = @('county_directory_only')
    periods = @('directory-reference', 'ai-inference')
    periodValues = [ordered]@{ fact = $null; social = $null; inference = (Get-Date).ToString('yyyy-MM-dd') }
    displayPeriodLabel = 'county directory / ai inference'
    shortDescription = ('{0} currently shows county directory coverage and AI inference.' -f $referenceArea.name)
    lastUpdated = (Get-Date).ToString('yyyy-MM-dd')
  }
  $countyInferenceRecords += [pscustomobject][ordered]@{
    id = $countyId
    name = $referenceArea.name
    adminLevel = 'county-level'
    parentProvinceId = $provinceId
    parentCityId = $cityId
    dataClass = 'ai_inference'
    isComparable = $false
    displayPriority = 3
    confidence = $(if ($cityInference) { 0.5 } elseif ($province) { 0.38 } else { 0.24 })
    confidenceBand = Get-Confidence-Band $(if ($cityInference) { 0.5 } elseif ($province) { 0.38 } else { 0.24 })
    estimatedScores = [ordered]@{
      affordability = Clamp-Score $baseAff
      balance = Clamp-Score $baseBal
      environment = Clamp-Score $baseEnv
      opportunity = Clamp-Score $baseOpp
      pressure = Clamp-Score $basePress
    }
    reasoningSummary = $(if ($cityInference) { 'County inference mainly uses parent-city inference, province facts and county-type heuristics.' } else { 'County inference mainly uses province facts and county-type heuristics.' })
    referencePeers = Distinct-Array @($(if ($city) { $city.name }), $(if ($province) { $province.provinceCapital }))
    shouldNotBeUsedForRanking = $true
    inferenceBasis = Distinct-Array @($(if ($cityInference) { 'parent-city-inference' }), $(if ($province) { 'province-fact-layer' }), ('county-type-' + $countyType))
    sourceRefs = Distinct-Array @('reference-admin-area', $(if ($cityInference) { $cityInference.sourceRefs }), $(if ($province) { $province.sourceRefs }))
    lastVerifiedAt = (Get-Date).ToString('yyyy-MM-dd')
  }
}

$provinceRecords = @($provinceBaseRecords | ForEach-Object {
    $province = $_
    $factProvinceCities = @($factCityRecords | Where-Object { $_.provinceId -eq $province.id -and $_.cityMapEligibility })
    $allProvinceCities = @($expandedCityRecords | Where-Object { $_.provinceId -eq $province.id })
    $provinceCounties = @($countyRecords | Where-Object { $_.parentProvinceId -eq $province.id })
    $citySampleCount = @($factProvinceCities).Count
    $aiEligibleCityCount = @($factProvinceCities | Where-Object { $_.cityRecommendationEligibility }).Count
    $mixedAiEligibleCityCount = @($allProvinceCities | Where-Object { $_.aiEligible }).Count
    $scatterPointCount = @($factProvinceCities | Where-Object { $null -ne $_.effectiveMonthlyIncome -and $null -ne $_.rentBurdenProxy }).Count
    $missingDimensions = @()
    if (@($factProvinceCities | Where-Object { $null -ne $_.effectiveMonthlyIncome }).Count -lt 3) { $missingDimensions += 'income' }
    if (@($factProvinceCities | Where-Object { $null -ne $_.resolvedAirSignal }).Count -lt 3) { $missingDimensions += 'air' }
    if (@($factProvinceCities | Where-Object { $null -ne $_.officialServiceSignal }).Count -lt 3) { $missingDimensions += 'service' }
    if (@($factProvinceCities | Where-Object { $null -ne $_.rentBurdenProxy }).Count -lt 3) { $missingDimensions += 'rent' }
    if (@($factProvinceCities | Where-Object { $null -ne $_.commuteIndex }).Count -lt 3) { $missingDimensions += 'commute' }
    if (@($factProvinceCities | Where-Object { $null -ne $_.totalCostIndex }).Count -lt 3) { $missingDimensions += 'cost' }
    $cityCoverageLevel = if ($citySampleCount -lt 3) { 'insufficient' } elseif ($aiEligibleCityCount -ge 3) { 'deep' } else { 'official-only' }
    $record = [ordered]@{}
    foreach ($prop in $province.PSObject.Properties) { $record[$prop.Name] = $prop.Value }
    $record.primaryDataClass = 'fact'
    $record.displayPriority = 1
    $record.factCompleteness = $(if ($province.coverageLevel -eq 'limited') { 0.45 } else { 0.88 })
    $record.socialCompleteness = 0.0
    $record.inferenceCompleteness = 0.84
    $record.displayEligibility = $true
    $record.comparisonEligibility = [bool]($province.coverageLevel -ne 'limited')
    $record.aiEligibility = [bool]($province.coverageScore -ge 0.6)
    $record.citySampleCount = $citySampleCount
    $record.aiEligibleCityCount = $aiEligibleCityCount
    $record.mixedAiEligibleCityCount = $mixedAiEligibleCityCount
    $record.scatterPointCount = $scatterPointCount
    $record.sampledCities = @($factProvinceCities | Sort-Object name | ForEach-Object { $_.name })
    $record.directoryCitiesPreview = @($allProvinceCities | Sort-Object name | Select-Object -First 12 -ExpandProperty name)
    $record.directoryCityCount = @($allProvinceCities).Count
    $record.directoryCountyCount = @($provinceCounties).Count
    $record.factCountyCount = 0
    $record.aiEligibleCountyCount = @($provinceCounties | Where-Object { $_.aiEligibility }).Count
    $record.socialSeedCount = @($socialSignalRecords | Where-Object { $_.parentProvinceId -eq $province.id -or $_.id -eq $province.id }).Count
    $record.cityCoverageLevel = $cityCoverageLevel
    $record.eligibleModules = [ordered]@{ rankings = [bool]($citySampleCount -ge 3); ai = [bool]($aiEligibleCityCount -ge 3); compare = [bool]($citySampleCount -ge 3); scatter = [bool]($scatterPointCount -ge 3) }
    $record.mixedModules = [ordered]@{ cards = [bool](@($allProvinceCities).Count -gt 0 -or @($provinceCounties).Count -gt 0); compare = [bool]($mixedAiEligibleCityCount -ge 2); county = [bool](@($provinceCounties).Count -gt 0); map = $true }
    $record.missingDimensions = Distinct-Array $missingDimensions
    [pscustomobject]$record
  })

$aiInferenceRecords = @(@($provinceInferenceRecords) + @($cityInferenceRecords) + @($countyInferenceRecords))
