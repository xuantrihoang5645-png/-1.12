(function attachEvidenceRecommendation(global) {
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const toNumber = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);
  const ensureArray = (value) => (Array.isArray(value) ? value : value ? [value] : []);

  const ADMIN_LABELS = {
    'province-level': '省级',
    'prefecture-level': '地级市',
    'county-level': '县区',
  };

  const LENS_LABELS = {
    fact: '事实优先',
    mixed: '混合理解',
    inference: '推理解读',
  };

  const METRIC_LABELS = {
    overviewScore: '综合概览',
    incomeSupportScore: '收入支撑',
    consumptionBurdenScore: '消费负担',
    publicServiceScore: '公共服务',
    environmentScore: '环境宜居',
    effectiveMonthlyIncome: '收入参考',
    rentBurdenProxy: '房租压力',
    totalCostIndex: '综合成本',
    commuteIndex: '通勤便利',
    airQualityScore: '空气质量',
    officialBalanceScore: '官方平衡',
    balancedScore: '综合平衡',
    savingScore: '攒钱友好',
    baseOfficialScore: '基础实力',
    opportunityScore: '机会承载',
    pressureScore: '压力信号',
  };

  const QUALITY_FLAGS = {
    base_official_only: '当前只有基础官方层',
    directory_reference_only: '当前仅目录与推理',
    limited_comparability: '口径有限，仅供参考',
    rent_estimate_30sqm: '租金按示例户型折算',
    wage_scope_urban_units: '工资口径为城镇单位',
    environment_green_proxy: '环境项含绿地代理值',
    income: '收入维度仍待补',
    air: '空气维度仍待补',
    service: '基础服务维度仍待补',
    rent: '租房维度仍待补',
    commute: '通勤维度仍待补',
    cost: '生活成本维度仍待补',
  };

  const BASIS_LABELS = {
    'province-fact-layer': '锚定省级事实层',
    'city-fact-layer': '锚定城市事实层',
    'same-province-fact-peers': '参考同省事实样本',
    'parent-city-inference': '参考父级城市',
    'county-type-district': '参考区县类型规则',
    'county-type-county': '参考区县类型规则',
    'county-type-county-level-city': '参考县级市规则',
    'provincial-capital-heuristic': '参考省会/核心城市规则',
  };

  const METRIC_GROUPS = {
    province: [
      ['overviewScore', '综合概览'],
      ['incomeSupportScore', '收入支撑'],
      ['consumptionBurdenScore', '消费负担'],
      ['publicServiceScore', '公共服务'],
      ['environmentScore', '环境宜居'],
    ],
    city: [
      ['officialBalanceScore', '官方平衡'],
      ['balancedScore', '综合平衡'],
      ['savingScore', '攒钱友好'],
      ['commuteIndex', '通勤便利'],
      ['airQualityScore', '空气质量'],
    ],
    county: [
      ['balancedScore', '综合平衡'],
      ['savingScore', '攒钱友好'],
      ['airQualityScore', '空气质量'],
      ['effectiveMonthlyIncome', '收入参考'],
      ['rentBurdenProxy', '房租压力'],
    ],
  };

  const TEXT_REPLACEMENTS = [
    ['Province inference is mainly anchored to province fact-layer metrics.', '当前推理解读主要锚定省级事实层。'],
    ['County layer is directory-first and inference-heavy.', '当前县区层仍以目录与推理解读为主。'],
    ['directory-first / ai-inference-ready', '目录优先 / 可进入推理解读'],
    ['county directory / ai inference', '县区目录 / 推理解读'],
    ['directory-first', '目录优先'],
    ['ai-inference-ready', '可进入推理解读'],
    ['fact-layer', '事实层'],
    ['social + inference', '体验信号 + 推理解读'],
    ['directory + inference', '目录 + 推理解读'],
    ['official annual', '官方年度'],
  ];

  function localizeText(value) {
    if (value === null || value === undefined) return '';
    let text = String(value);
    TEXT_REPLACEMENTS.forEach(([from, to]) => {
      text = text.replaceAll(from, to);
    });
    return text;
  }

  function adminLabel(level) {
    return ADMIN_LABELS[level] || '地区';
  }

  function lensLabel(mode) {
    return LENS_LABELS[mode] || '混合理解';
  }

  function metricLabel(key) {
    return METRIC_LABELS[key] || key;
  }

  function qualityFlagLabel(flag) {
    return QUALITY_FLAGS[flag] || flag;
  }

  function inferenceBasisLabel(flag) {
    return BASIS_LABELS[flag] || flag;
  }

  function coverageLabel(entity) {
    const evidence = entity?.evidence || {};
    const fact = toNumber(evidence.factCompleteness) ?? 0;
    const social = toNumber(evidence.socialCompleteness) ?? 0;
    const inference = toNumber(evidence.inferenceCompleteness) ?? 0;

    if (fact >= 0.75) return '事实层完整';
    if (fact >= 0.35) return social > 0 ? '事实为主，含补充信号' : '事实为主';
    if (inference >= 0.45) return social > 0 ? '推理候选，含体验信号' : '推理候选';
    return '目录参考';
  }

  function valueOrNull(value) {
    const num = toNumber(value);
    return num === null ? null : num;
  }

  function factScores(entity) {
    const balance = valueOrNull(entity.officialBalanceScore ?? entity.overviewScore ?? entity.balancedScore);
    const affordability = valueOrNull(entity.savingScore ?? entity.incomeSupportScore);
    const environment = valueOrNull(entity.airQualityScore ?? entity.environmentScore);
    const opportunity = valueOrNull(entity.opportunityScore ?? entity.baseOfficialScore ?? entity.publicServiceScore ?? entity.incomeSupportScore);
    const rawPressure = valueOrNull(entity.pressureScore);
    const rentPressure = valueOrNull(entity.rentBurdenProxy);
    const pressure = rawPressure ?? (rentPressure === null ? null : clamp(rentPressure * 100, 0, 100));

    return { balance, affordability, environment, opportunity, pressure };
  }

  function inferenceScores(entity) {
    const scores = entity?.inference?.estimatedScores || {};
    return {
      balance: valueOrNull(scores.balance),
      affordability: valueOrNull(scores.affordability),
      environment: valueOrNull(scores.environment),
      opportunity: valueOrNull(scores.opportunity),
      pressure: valueOrNull(scores.pressure),
    };
  }

  function socialScores(entity) {
    const signalCount = valueOrNull(entity?.social?.signalCount) ?? 0;
    const sentiment = String(entity?.social?.sentiment || '');
    const mood = sentiment.includes('positive') ? 72 : sentiment.includes('negative') ? 38 : sentiment.includes('mixed') ? 54 : 48;
    return {
      balance: mood,
      affordability: 52,
      environment: mood,
      opportunity: clamp(signalCount * 12, 0, 100),
      pressure: clamp(100 - mood, 0, 100),
    };
  }

  function getLensScores(entity, lens = 'fact') {
    const fact = factScores(entity);
    const inference = inferenceScores(entity);
    const social = socialScores(entity);

    if (lens === 'fact') return fact;
    if (lens === 'inference') return inference;
    return {
      balance: fact.balance ?? inference.balance ?? social.balance,
      affordability: fact.affordability ?? inference.affordability ?? social.affordability,
      environment: fact.environment ?? inference.environment ?? social.environment,
      opportunity: fact.opportunity ?? inference.opportunity ?? social.opportunity,
      pressure: fact.pressure ?? inference.pressure ?? social.pressure,
    };
  }

  function defaultPreferences() {
    return {
      scope: 'city',
      budget: 'moderate',
      stage: 'earlyCareer',
      household: 'solo',
      tierPreference: 'balanced',
      savingsWeight: 58,
      commuteWeight: 60,
      airWeight: 52,
      opportunityWeight: 50,
    };
  }

  const PRESETS = {
    budget: { budget: 'tight', stage: 'earlyCareer', household: 'solo', tierPreference: 'calm', savingsWeight: 88, commuteWeight: 45, airWeight: 40, opportunityWeight: 34 },
    saving: { budget: 'tight', stage: 'stable', household: 'solo', tierPreference: 'calm', savingsWeight: 92, commuteWeight: 44, airWeight: 38, opportunityWeight: 28 },
    graduates: { budget: 'tight', stage: 'graduate', household: 'solo', tierPreference: 'balanced', savingsWeight: 70, commuteWeight: 64, airWeight: 40, opportunityWeight: 60 },
    couples: { budget: 'moderate', stage: 'stable', household: 'couple', tierPreference: 'balanced', savingsWeight: 52, commuteWeight: 52, airWeight: 66, opportunityWeight: 42 },
    environment: { budget: 'moderate', stage: 'stable', household: 'couple', tierPreference: 'calm', savingsWeight: 46, commuteWeight: 44, airWeight: 88, opportunityWeight: 34 },
    opportunity: { budget: 'comfortable', stage: 'earlyCareer', household: 'solo', tierPreference: 'big', savingsWeight: 34, commuteWeight: 48, airWeight: 32, opportunityWeight: 90 },
  };

  function applyPreset(current, presetKey) {
    return { ...current, ...(PRESETS[presetKey] || {}) };
  }

  function budgetScore(entity, prefs, scores) {
    const affordability = toNumber(scores.affordability) ?? 50;
    const pressure = toNumber(scores.pressure) ?? 50;
    if (prefs.budget === 'tight') return clamp(affordability * 0.7 + (100 - pressure) * 0.3, 0, 100);
    if (prefs.budget === 'comfortable') return clamp((toNumber(scores.balance) ?? 50) * 0.6 + (toNumber(scores.opportunity) ?? 50) * 0.4, 0, 100);
    return clamp(100 - Math.abs(affordability - 62), 0, 100);
  }

  function stageScore(entity, prefs, scores) {
    const balance = toNumber(scores.balance) ?? 50;
    const opportunity = toNumber(scores.opportunity) ?? 50;
    const environment = toNumber(scores.environment) ?? 50;
    if (prefs.stage === 'graduate') return clamp(balance * 0.4 + opportunity * 0.6, 0, 100);
    if (prefs.stage === 'stable') return clamp(balance * 0.6 + environment * 0.4, 0, 100);
    return clamp(balance * 0.55 + opportunity * 0.45, 0, 100);
  }

  function householdScore(entity, prefs, scores) {
    const balance = toNumber(scores.balance) ?? 50;
    const environment = toNumber(scores.environment) ?? 50;
    const opportunity = toNumber(scores.opportunity) ?? 50;
    if (prefs.household === 'couple') return clamp(balance * 0.56 + environment * 0.44, 0, 100);
    if (prefs.household === 'family') return clamp(balance * 0.48 + environment * 0.52, 0, 100);
    return clamp(balance * 0.52 + opportunity * 0.48, 0, 100);
  }

  function tierScore(entity, prefs) {
    const tier = entity.tier || 'unclassified';
    if (prefs.tierPreference === 'big') return ['tier1', 'newTier1'].includes(tier) ? 92 : 58;
    if (prefs.tierPreference === 'calm') return ['unclassified', 'strongTier2'].includes(tier) ? 88 : 54;
    return ['newTier1', 'strongTier2'].includes(tier) ? 90 : 68;
  }

  function evaluateEntity(entity, prefs, lens) {
    const scores = getLensScores(entity, lens);
    const savingsWeight = prefs.savingsWeight / 100;
    const commuteWeight = prefs.commuteWeight / 100;
    const airWeight = prefs.airWeight / 100;
    const opportunityWeight = prefs.opportunityWeight / 100;

    const commute = toNumber(entity.commuteIndex) ?? toNumber(scores.opportunity) ?? 50;
    const air = toNumber(entity.airQualityScore) ?? toNumber(scores.environment) ?? 50;
    const opportunity = toNumber(scores.opportunity) ?? 50;
    const balance = toNumber(scores.balance) ?? 50;
    const affordability = toNumber(scores.affordability) ?? 50;
    const pressure = toNumber(scores.pressure) ?? 50;

    const factors = [
      { label: '预算匹配', score: budgetScore(entity, prefs, scores), weight: 0.16 },
      { label: '阶段匹配', score: stageScore(entity, prefs, scores), weight: 0.14 },
      { label: '居住形态匹配', score: householdScore(entity, prefs, scores), weight: 0.1 },
      { label: '攒钱空间', score: clamp(affordability * 0.62 + (100 - pressure) * 0.38, 0, 100), weight: 0.08 + savingsWeight * 0.12 },
      { label: '综合舒适度', score: balance, weight: 0.1 },
      { label: '通勤体验', score: commute, weight: 0.06 + commuteWeight * 0.12 },
      { label: '环境质量', score: air, weight: 0.06 + airWeight * 0.12 },
      { label: '机会承载', score: opportunity, weight: 0.08 + opportunityWeight * 0.08 },
      { label: '城市级别偏好', score: tierScore(entity, prefs), weight: 0.08 },
    ];

    const totalWeight = factors.reduce((sum, factor) => sum + factor.weight, 0);
    const raw = factors.reduce((sum, factor) => sum + factor.score * factor.weight, 0) / totalWeight;
    const evidenceBoost = 0.72 + 0.28 * clamp(toNumber(entity?.evidence?.coverageScore) ?? 0, 0, 1);
    const finalScore = clamp(raw * evidenceBoost, 0, 100);

    return {
      rawScore: +raw.toFixed(1),
      finalScore: +finalScore.toFixed(1),
      factors,
      positives: [...factors].sort((a, b) => b.score - a.score).slice(0, 3),
      tradeoffs: [...factors].sort((a, b) => a.score - b.score).slice(0, 2),
      scores,
    };
  }

  function recommendEntities(entities, prefs, options = {}) {
    const { lens = 'mixed', limit = 5 } = options;
    return ensureArray(entities)
      .filter((entity) => entity && entity.displayEligibility !== false)
      .filter((entity) => {
        const fact = toNumber(entity?.evidence?.factCompleteness) ?? 0;
        const inference = toNumber(entity?.evidence?.inferenceCompleteness) ?? 0;
        if (lens === 'fact') return fact > 0;
        if (lens === 'inference') return inference >= 0.35;
        return fact > 0 || inference >= 0.35;
      })
      .map((entity) => ({ entity, evaluation: evaluateEntity(entity, prefs, lens) }))
      .sort((a, b) => b.evaluation.finalScore - a.evaluation.finalScore)
      .slice(0, limit)
      .map((item) => ({
        ...item.entity,
        finalScore: item.evaluation.finalScore,
        rawScore: item.evaluation.rawScore,
        positives: item.evaluation.positives,
        tradeoffs: item.evaluation.tradeoffs,
        scores: item.evaluation.scores,
        recommendationLabel: coverageLabel(item.entity),
        nextStep: buildNextStep(item.entity),
      }));
  }

  function buildNextStep(entity) {
    if (entity.adminLevel === 'province-level') return '下一步建议继续进入该省地级市层，确认城市层是否有足够事实样本。';
    if (entity.adminLevel === 'county-level') return '下一步建议同时核查父级城市的租房、通勤与就业面，再决定是否深入到区县。';
    return '下一步建议拉 1–2 个同级地区做对比，重点看缺失维度与来源时间。';
  }

  function buildInsightCards(entities, lens) {
    const list = ensureArray(entities).filter((entity) => entity.displayEligibility !== false);
    if (!list.length) return [];

    const scored = list.map((entity) => ({ entity, scores: getLensScores(entity, lens) }));
    const by = (predicate, sorter) => scored.filter(predicate).sort(sorter)[0]?.entity || null;

    const evidenceLeader = by(
      (item) => (toNumber(item.entity?.evidence?.factCompleteness) ?? 0) >= 0.35,
      (a, b) => (toNumber(b.scores.balance) ?? -1) - (toNumber(a.scores.balance) ?? -1),
    );

    const watchlist = by(
      (item) => (toNumber(item.entity?.evidence?.factCompleteness) ?? 0) < 0.35 && (toNumber(item.entity?.evidence?.inferenceCompleteness) ?? 0) >= 0.45,
      (a, b) => (toNumber(b.entity?.inference?.estimatedScores?.balance) ?? -1) - (toNumber(a.entity?.inference?.estimatedScores?.balance) ?? -1),
    );

    const opportunityPressure = by(
      (item) => (toNumber(item.scores.opportunity) ?? 0) >= 58 && (toNumber(item.scores.pressure) ?? 0) >= 50,
      (a, b) => ((toNumber(b.scores.opportunity) ?? 0) + (toNumber(b.scores.pressure) ?? 0)) - ((toNumber(a.scores.opportunity) ?? 0) + (toNumber(a.scores.pressure) ?? 0)),
    );

    const costFriendly = by(
      (item) => {
        const affordability = toNumber(item.scores.affordability) ?? 0;
        const pressure = toNumber(item.scores.pressure) ?? 100;
        return affordability >= 50 || pressure <= 50;
      },
      (a, b) => {
        const aValue = (toNumber(a.scores.affordability) ?? 0) + (100 - (toNumber(a.scores.pressure) ?? 100));
        const bValue = (toNumber(b.scores.affordability) ?? 0) + (100 - (toNumber(b.scores.pressure) ?? 100));
        return bValue - aValue;
      },
    );

    return [
      evidenceLeader
        ? {
            title: '事实样本优先看',
            entity: evidenceLeader,
            description: '事实层相对更厚，适合先作为比较基准。',
            risk: '不代表它一定最适合你，只代表证据链更完整。',
          }
        : null,
      watchlist
        ? {
            title: '值得继续研究',
            entity: watchlist,
            description: '目前事实层不够厚，但推理解读显示有进一步研究价值。',
            risk: '只能作为候选，不能替代事实结论。',
          }
        : null,
      opportunityPressure
        ? {
            title: '机会更强但压力更高',
            entity: opportunityPressure,
            description: '更适合愿意换更多机会、接受更高压力的人。',
            risk: '通常意味着成本、节奏或竞争会更强。',
          }
        : null,
      costFriendly
        ? {
            title: '成本更友好',
            entity: costFriendly,
            description: '更适合先看预算和可负担性的人群。',
            risk: '公开信息密度、机会面或服务面可能没那么强。',
          }
        : null,
    ].filter(Boolean);
  }

  function buildCompareNarrative(entities, lens) {
    const list = ensureArray(entities);
    if (list.length < 2) {
      return {
        facts: ['至少选择两个地区后再开始对比。'],
        summary: ['当前还没有足够样本生成结论。'],
      };
    }

    const scored = list.map((entity) => ({ entity, scores: getLensScores(entity, lens) }));
    const compareLine = (label, key, higherBetter = true) => {
      const valid = scored.filter((item) => toNumber(item.scores[key]) !== null);
      if (valid.length < 2) return `${label}：当前样本不足。`;
      valid.sort((a, b) => higherBetter ? b.scores[key] - a.scores[key] : a.scores[key] - b.scores[key]);
      return `${label}：${valid[0].entity.name} 更突出，${valid[valid.length - 1].entity.name} 相对更弱。`;
    };

    const facts = [
      compareLine('综合平衡', 'balance', true),
      compareLine('成本友好', 'pressure', false),
      compareLine('环境质量', 'environment', true),
      compareLine('机会承载', 'opportunity', true),
    ];

    const highestBalance = scored
      .filter((item) => toNumber(item.scores.balance) !== null)
      .sort((a, b) => b.scores.balance - a.scores.balance)[0];
    const lowestPressure = scored
      .filter((item) => toNumber(item.scores.pressure) !== null)
      .sort((a, b) => a.scores.pressure - b.scores.pressure)[0];

    const summary = [
      highestBalance ? `如果你更看重综合平衡，可以先看 ${highestBalance.entity.name}。` : '综合平衡结论暂时不足。',
      lowestPressure ? `如果你更在意成本与压力，${lowestPressure.entity.name} 更值得继续核查。` : '成本压力结论暂时不足。',
      '最终决策前，仍应核对最新租房、岗位、通勤线路和具体片区差异。',
    ];

    return { facts, summary };
  }

  function buildPersonaAdvice() {
    return [
      '刚毕业：先看事实层里的收入、房租压力、机会承载，再看智能解读。',
      '想攒钱：先排除高压力样本，再比较可负担性和缺失维度。',
      '情侣或小家庭：先看环境、公共服务与综合平衡，别只看工资或热度。',
      '看县区：必须把父级城市与所在省一起看，县区推理解读不能替代实地调研。',
    ];
  }

  function metricGroups(scope) {
    return METRIC_GROUPS[scope] || METRIC_GROUPS.city;
  }

  global.CityRecommendation = {
    adminLabel,
    lensLabel,
    metricLabel,
    qualityFlagLabel,
    inferenceBasisLabel,
    localizeText,
    coverageLabel,
    getLensScores,
    defaultPreferences,
    applyPreset,
    recommendEntities,
    buildInsightCards,
    buildCompareNarrative,
    buildPersonaAdvice,
    metricGroups,
  };
})(window);
