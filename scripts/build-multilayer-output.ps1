$cityDirectory = @($expandedCityRecords | ForEach-Object {
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
      primaryDataClass = $_.primaryDataClass
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
      mixedAiEligibleCityCount = $_.mixedAiEligibleCityCount
      scatterPointCount = $_.scatterPointCount
      cityCoverageLevel = $_.cityCoverageLevel
      eligibleModules = $_.eligibleModules
      mixedModules = $_.mixedModules
      missingDimensions = $_.missingDimensions
      sourceRefs = $_.sourceRefs
      qualityFlags = $_.qualityFlags
      periods = $_.periods
      generatedAt = $provinceRaw.generatedAt
    }
  })

$coverageViewModel = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  summary = [ordered]@{
    provinces = @($provinceRecords).Count
    cities = @($expandedCityRecords).Count
    counties = @($countyRecords).Count
    cityFactLayerCount = @($expandedCityRecords | Where-Object { $_.factCompleteness -gt 0 }).Count
    countyFactLayerCount = @($countyRecords | Where-Object { $_.factCompleteness -gt 0 }).Count
    cityAiLayerCount = @($expandedCityRecords | Where-Object { $_.aiEligible }).Count
    countyAiLayerCount = @($countyRecords | Where-Object { $_.aiEligibility }).Count
    socialRecordCount = @($socialSignalRecords).Count
  }
  provinces = @($provinceRecords | ForEach-Object {
      [pscustomobject][ordered]@{
        provinceId = $_.id
        name = $_.name
        cityDirectoryCount = $_.directoryCityCount
        cityFactCount = $_.citySampleCount
        cityAiCount = $_.mixedAiEligibleCityCount
        countyDirectoryCount = $_.directoryCountyCount
        countyFactCount = $_.factCountyCount
        countyAiCount = $_.aiEligibleCountyCount
        socialSignalCount = $_.socialSeedCount
        missingDimensions = $_.missingDimensions
        cityCoverageLevel = $_.cityCoverageLevel
        lastUpdated = $_.lastUpdated
      }
    })
}

$socialSignalViewModel = [ordered]@{
  generatedAt = First-NonNull @($socialSignalSeed.generatedAt, (Get-Date).ToString('yyyy-MM-dd'))
  methodology = $socialSignalSeed.methodology
  summary = [ordered]@{
    totalRecords = @($socialSignalRecords).Count
    provinceRecords = @($socialSignalRecords | Where-Object { $_.adminLevel -eq 'province-level' }).Count
    cityRecords = @($socialSignalRecords | Where-Object { $_.adminLevel -eq 'prefecture-level' }).Count
    countyRecords = @($socialSignalRecords | Where-Object { $_.adminLevel -eq 'county-level' }).Count
  }
  records = $socialSignalRecords
}

$aiInferenceViewModel = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  summary = [ordered]@{
    provinceRecords = @($provinceInferenceRecords).Count
    cityRecords = @($cityInferenceRecords).Count
    countyRecords = @($countyInferenceRecords).Count
    lowConfidenceRecords = @($aiInferenceRecords | Where-Object { $_.confidenceBand -eq 'low' }).Count
  }
  records = $aiInferenceRecords
}

$provinceViewModel = [ordered]@{
  generatedAt = $provinceRaw.generatedAt
  summary = [ordered]@{
    totalProvinces = @($provinceRecords).Count
    comparableMainlandProvinces = @($provinceRecords | Where-Object { $_.coverageLevel -ne 'limited' }).Count
    limitedProvinces = @($provinceRecords | Where-Object { $_.coverageLevel -eq 'limited' }).Count
    provincesWithCityRankings = @($provinceRecords | Where-Object { $_.eligibleModules.rankings }).Count
    provincesWithCityAi = @($provinceRecords | Where-Object { $_.eligibleModules.ai }).Count
    provincesWithMixedCards = @($provinceRecords | Where-Object { $_.mixedModules.cards }).Count
    coreMetricCount = 5
  }
  enums = [ordered]@{
    regions = Distinct-Array @($provinceRecords.region)
    mapMetrics = @(
      [ordered]@{ key = 'incomeSupportScore'; label = 'Income Support'; direction = 'higherBetter' }
      [ordered]@{ key = 'consumptionBurdenScore'; label = 'Consumption Burden'; direction = 'higherBetter' }
      [ordered]@{ key = 'environmentScore'; label = 'Environment'; direction = 'higherBetter' }
      [ordered]@{ key = 'publicServiceScore'; label = 'Public Services'; direction = 'higherBetter' }
      [ordered]@{ key = 'overviewScore'; label = 'Province Overview'; direction = 'higherBetter' }
    )
  }
  provinces = $provinceRecords
}

$cityViewModel = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  summary = [ordered]@{
    totalCities = @($expandedCityRecords).Count
    factLayerCities = @($expandedCityRecords | Where-Object { $_.factCompleteness -gt 0 }).Count
    deepSnapshotCities = @($expandedCityRecords | Where-Object { $_.layerType -in @('deep-plus-official', 'deep-snapshot') }).Count
    majorOfficialCities = @($expandedCityRecords | Where-Object { $_.layerType -eq 'major-city-official' }).Count
    profileOfficialCities = @($expandedCityRecords | Where-Object { $_.layerType -eq 'profile-official' }).Count
    pureFactAiEligibleCities = @($expandedCityRecords | Where-Object { $_.cityRecommendationEligibility }).Count
    aiEligibleCities = @($expandedCityRecords | Where-Object { $_.aiEligible }).Count
    cityMapEligibleCities = @($expandedCityRecords | Where-Object { $_.cityMapEligibility }).Count
    directoryOnlyCities = @($expandedCityRecords | Where-Object { $_.coverageCode -eq 'directory-only' }).Count
    coreMetricCount = 9
  }
  enums = [ordered]@{
    tiers = Distinct-Array @($expandedCityRecords.tier)
    regions = Distinct-Array @($expandedCityRecords.region)
    mapMetrics = @(
      [ordered]@{ key = 'balancedScore'; label = 'Balance'; direction = 'higherBetter' }
      [ordered]@{ key = 'savingScore'; label = 'Saving'; direction = 'higherBetter' }
      [ordered]@{ key = 'commuteIndex'; label = 'Commute'; direction = 'higherBetter' }
      [ordered]@{ key = 'airQualityScore'; label = 'Air'; direction = 'higherBetter' }
      [ordered]@{ key = 'totalCostIndex'; label = 'Total Cost'; direction = 'lowerBetter' }
      [ordered]@{ key = 'rentBurdenProxy'; label = 'Rent Burden'; direction = 'lowerBetter' }
      [ordered]@{ key = 'effectiveMonthlyIncome'; label = 'Income'; direction = 'higherBetter' }
      [ordered]@{ key = 'officialBalanceScore'; label = 'Official Balance'; direction = 'higherBetter' }
      [ordered]@{ key = 'officialGdp'; label = 'GDP'; direction = 'higherBetter' }
      [ordered]@{ key = 'baseOfficialScore'; label = 'Official Base'; direction = 'higherBetter' }
    )
  }
  cities = $expandedCityRecords
}

$countyViewModel = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  summary = [ordered]@{
    totalCounties = @($countyRecords).Count
    factAvailableCounties = @($countyRecords | Where-Object { $_.factCompleteness -gt 0 }).Count
    socialPlusInferenceCounties = @($countyRecords | Where-Object { $_.coverageLevel -eq 'social-plus-inference' }).Count
    directoryOnlyCounties = @($countyRecords | Where-Object { $_.coverageLevel -eq 'directory-only' }).Count
    aiEligibleCounties = @($countyRecords | Where-Object { $_.aiEligibility }).Count
  }
  enums = [ordered]@{
    countyTypes = Distinct-Array @($countyRecords.countyType)
    coverageLevels = Distinct-Array @($countyRecords.coverageLevel)
  }
  counties = $countyRecords
}

$metaOut = [ordered]@{
  siteGeneratedAt = (Get-Date).ToString('yyyy-MM-dd')
  majorDataPeriods = @(
    'Province layer uses 2024 annual fact snapshots first.',
    'Prefecture layer uses national directory plus fact layer plus AI inference.',
    'County layer is directory-first and inference-heavy.',
    'Social layer only keeps public web snapshots when available.'
  )
  updateStrategy = @(
    'Run scripts/fetch-official-national-data.ps1 to refresh official annual snapshots.',
    'Run scripts/build-derived.ps1 to rebuild multi-layer outputs.',
    'Run scripts/validate-data.ps1 before publishing.'
  )
  aiMode = 'rule-engine-local-multi-layer-fact-social-inference'
  coverageSummary = [ordered]@{
    includedProvinces = $provinceViewModel.summary.totalProvinces
    comparableMainlandProvinces = $provinceViewModel.summary.comparableMainlandProvinces
    includedCities = $cityViewModel.summary.totalCities
    includedCounties = $countyViewModel.summary.totalCounties
    cityFactLayerCount = $cityViewModel.summary.factLayerCities
    countyFactLayerCount = $countyViewModel.summary.factAvailableCounties
    cityAiEligibleCount = $cityViewModel.summary.aiEligibleCities
    countyAiEligibleCount = $countyViewModel.summary.aiEligibleCounties
    socialRecordCount = $socialSignalViewModel.summary.totalRecords
    nationalMapMode = 'multi-layer-fact-social-inference'
    cityLayerScope = 'national-prefecture-directory-plus-fact-layer-plus-ai-inference'
    countyLayerScope = 'national-county-directory-plus-ai-inference'
  }
  disclaimer = @(
    'National prefecture coverage means directory coverage first, not equal fact depth everywhere.',
    'County layer is mostly directory plus AI inference for now.',
    'Social signals are not official platform statistics.',
    'AI inference never replaces fact-layer values.'
  )
}

Write-Json (Join-Path $dataDir 'province-generated-metrics.json') $provinceGenerated
Write-Json (Join-Path $dataDir 'province-view-model.json') $provinceViewModel
Write-Json (Join-Path $dataDir 'view-model.json') $cityViewModel
Write-Json (Join-Path $dataDir 'city-directory.json') $cityDirectory
Write-Json (Join-Path $dataDir 'county-view-model.json') $countyViewModel
Write-Json (Join-Path $dataDir 'coverage-view-model.json') $coverageViewModel
Write-Json (Join-Path $dataDir 'social-signal-view-model.json') $socialSignalViewModel
Write-Json (Join-Path $dataDir 'ai-inference-view-model.json') $aiInferenceViewModel
Write-Json (Join-Path $dataDir 'meta.json') $metaOut

$bootstrap = [ordered]@{
  generatedAt = (Get-Date).ToString('yyyy-MM-dd')
  meta = $metaOut
  sources = $sources
  provinceViewModel = $provinceViewModel
  viewModel = $cityViewModel
  countyViewModel = $countyViewModel
  coverageViewModel = $coverageViewModel
  socialSignalViewModel = $socialSignalViewModel
  aiInferenceViewModel = $aiInferenceViewModel
  recommendationConfig = $aiConfig
}

$bootstrapJson = $bootstrap | ConvertTo-Json -Depth 40
Write-Text (Join-Path $dataDir 'bootstrap.js') ("window.CITY_SITE_DATA = $bootstrapJson;")
Write-Host 'Built multi-layer province/city/county view-models and bootstrap.js'
