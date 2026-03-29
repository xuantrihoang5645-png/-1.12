(function attachEvidenceApp(global) {
  const Charts = global.CityCharts;
  const Recommendation = global.CityRecommendation;

  const byId = (id) => document.getElementById(id);
  const qsa = (selector) => Array.from(document.querySelectorAll(selector));
  const ensureArray = (value) => (Array.isArray(value) ? value : value ? [value] : []);
  const toNumber = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

  const state = {
    data: {
      siteSummary: null,
      sources: null,
      coverage: null,
      provinces: [],
      cityLite: [],
      registry: [],
      metricDefinitions: [],
      derived: null,
      cityPacks: new Map(),
      countyPacks: new Map(),
    },
    ui: {
      adminLevel: 'province',
      dataLens: 'fact',
      periodMode: 'latest',
      selectedProvinceId: null,
      selectedCityId: null,
      activeEntityId: null,
      compareIds: [],
      preferences: Recommendation.defaultPreferences(),
    },
    charts: {
      map: null,
      compare: null,
    },
  };

  const PREFERENCE_LABELS = {
    budget: { tight: '预算偏紧', moderate: '预算中等', comfortable: '预算较宽松' },
    stage: { graduate: '刚毕业', earlyCareer: '工作 1-3 年', stable: '相对稳定' },
    household: { solo: '单人', couple: '情侣', family: '小家庭' },
  };

  function showBanner(type, message) {
    const node = byId('global-banner');
    if (!node) return;
    node.className = `status-banner status-banner-${type}`;
    node.textContent = message;
  }

  function hideBanner() {
    const node = byId('global-banner');
    if (!node) return;
    node.className = 'status-banner status-banner-hidden';
    node.textContent = '';
  }

  function setModuleState(id, type, message) {
    const node = byId(id);
    if (!node) return;
    node.className = `module-state module-state-${type}`;
    node.textContent = message;
  }

  function hideModuleState(id) {
    const node = byId(id);
    if (!node) return;
    node.className = 'module-state module-state-hidden';
    node.textContent = '';
  }

  async function fetchJson(path) {
    const response = await fetch(path, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`Failed to load ${path}: ${response.status}`);
    }
    return response.json();
  }

  function currentProvince() {
    return state.data.provinces.find((item) => item.id === state.ui.selectedProvinceId) || null;
  }

  function currentProvinceCoverage() {
    return ensureArray(state.data.coverage?.provinces).find((item) => item.provinceId === state.ui.selectedProvinceId) || null;
  }

  function currentCityEntities() {
    if (state.ui.selectedProvinceId) {
      return state.data.cityLite.filter((item) => item.provinceId === state.ui.selectedProvinceId);
    }
    return state.data.cityLite;
  }

  function currentCountyPack() {
    if (!state.ui.selectedProvinceId) return null;
    return state.data.countyPacks.get(state.ui.selectedProvinceId) || null;
  }

  function currentCountyEntities() {
    return ensureArray(currentCountyPack()?.counties);
  }

  function currentEntities() {
    if (state.ui.adminLevel === 'province') return state.data.provinces;
    if (state.ui.adminLevel === 'city') return currentCityEntities();
    return currentCountyEntities();
  }

  function currentScopeLabel() {
    if (state.ui.adminLevel === 'province') return '全国省级范围';
    if (state.ui.adminLevel === 'city') return currentProvince() ? `${currentProvince().name} · 地级市范围` : '地级市范围';
    if (currentProvince()) return `${currentProvince().name} · 县区范围`;
    return '县区范围';
  }

  function currentMetricKey() {
    if (state.ui.adminLevel === 'province') return byId('map-metric-province')?.value || 'overviewScore';
    if (state.ui.adminLevel === 'city') return byId('map-metric-city')?.value || 'officialBalanceScore';
    return 'balancedScore';
  }

  function normalizeQuery(value) {
    return String(value || '')
      .replace(/特别行政区/g, '')
      .replace(/维吾尔自治区|壮族自治区|回族自治区|自治区/g, '')
      .replace(/省|市|区|县|盟/g, '')
      .replace(/\s+/g, '')
      .toLowerCase();
  }

  function formatNumber(value, digits = 1) {
    const num = toNumber(value);
    return num === null ? '暂无' : num.toFixed(digits);
  }

  function formatCount(value) {
    const num = toNumber(value);
    return num === null ? '—' : Math.round(num).toLocaleString('zh-CN');
  }

  function preferenceLabel(group, value) {
    return PREFERENCE_LABELS[group]?.[value] || value;
  }

  function buildQueryString() {
    const params = new URLSearchParams();
    params.set('level', state.ui.adminLevel);
    params.set('lens', state.ui.dataLens);
    params.set('period', state.ui.periodMode);
    if (state.ui.selectedProvinceId) params.set('province', state.ui.selectedProvinceId);
    if (state.ui.selectedCityId) params.set('city', state.ui.selectedCityId);
    if (state.ui.activeEntityId) params.set('focus', state.ui.activeEntityId);
    return `?${params.toString()}`;
  }

  function syncUrl() {
    global.history.replaceState({}, '', buildQueryString());
  }

  function restoreFromUrl() {
    const params = new URLSearchParams(global.location.search);
    state.ui.adminLevel = params.get('level') || state.ui.adminLevel;
    state.ui.dataLens = params.get('lens') || state.ui.dataLens;
    state.ui.periodMode = params.get('period') || state.ui.periodMode;
    state.ui.selectedProvinceId = params.get('province') || state.ui.selectedProvinceId;
    state.ui.selectedCityId = params.get('city') || state.ui.selectedCityId;
    state.ui.activeEntityId = params.get('focus') || state.ui.activeEntityId;
  }

  async function loadBaseData() {
    const [siteSummary, sources, coverage, provincesPack, cityLite, registry, metricDefinitions, derived] = await Promise.all([
      fetchJson('./data/site-summary.json'),
      fetchJson('./data/sources.json'),
      fetchJson('./data/coverage-view-model.json'),
      fetchJson('./data/packs/provinces.json'),
      fetchJson('./data/packs/cities-lite.json'),
      fetchJson('./data/evidence/entity-registry.json'),
      fetchJson('./data/evidence/metric-definitions.json'),
      fetchJson('./data/evidence/derived-recommendations.json'),
    ]);

    state.data.siteSummary = siteSummary;
    state.data.sources = sources;
    state.data.coverage = coverage;
    state.data.provinces = ensureArray(provincesPack.provinces);
    state.data.cityLite = ensureArray(cityLite.cities);
    state.data.registry = ensureArray(registry.records);
    state.data.metricDefinitions = ensureArray(metricDefinitions.metrics);
    state.data.derived = derived;

    if (!state.ui.selectedProvinceId) {
      state.ui.selectedProvinceId = state.data.provinces.find((item) => item.evidence?.coverageLevel !== 'limited')?.id || state.data.provinces[0]?.id || null;
    }
    if (!state.ui.selectedCityId) {
      state.ui.selectedCityId = currentCityEntities()[0]?.id || null;
    }
    if (!state.ui.activeEntityId) {
      state.ui.activeEntityId = state.ui.selectedProvinceId;
    }
  }

  async function ensureCountyPack(provinceId) {
    if (!provinceId) return null;
    if (state.data.countyPacks.has(provinceId)) return state.data.countyPacks.get(provinceId);
    const pack = await fetchJson(`./data/packs/counties/by-province/${provinceId}.json`);
    state.data.countyPacks.set(provinceId, pack);
    return pack;
  }

  async function ensureCityPack(provinceId) {
    if (!provinceId) return null;
    if (state.data.cityPacks.has(provinceId)) return state.data.cityPacks.get(provinceId);
    const pack = await fetchJson(`./data/packs/cities/by-province/${provinceId}.json`);
    state.data.cityPacks.set(provinceId, pack);
    return pack;
  }

  function currentScopeEligibility() {
    if (state.ui.adminLevel === 'province') {
      return { compareReady: state.data.provinces.length >= 2, recommendReady: state.data.provinces.length >= 3, note: '省级层以事实概览为主。' };
    }

    if (state.ui.adminLevel === 'city') {
      const coverage = currentProvinceCoverage();
      const total = currentCityEntities().length;
      const factCount = currentCityEntities().filter((item) => (toNumber(item?.evidence?.factCompleteness) ?? 0) >= 0.35).length;
      const recommendCount = currentCityEntities().filter((item) => item.cityRecommendationEligibility || (toNumber(item?.evidence?.inferenceCompleteness) ?? 0) >= 0.45).length;
      return {
        compareReady: total >= 2,
        recommendReady: recommendCount >= 3,
        note: coverage?.cityCoverageLevel === 'insufficient'
          ? `当前省内样本偏薄：已收录 ${total} 个城市，事实较完整样本 ${factCount} 个。`
          : `当前省内已收录 ${total} 个城市，事实较完整样本 ${factCount} 个。`,
      };
    }

    const total = currentCountyEntities().length;
    return {
      compareReady: total >= 2,
      recommendReady: total >= 3,
      note: total ? `当前省内已加载 ${total} 个县区目录。县区结论必须结合父级城市一起看。` : '当前县区数据仍在加载。',
    };
  }

  function summaryCount(key) {
    return toNumber(state.data.siteSummary?.coverageSummary?.[key]) ?? 0;
  }

  function syncToggleButtons() {
    qsa('[data-admin-level]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.adminLevel === state.ui.adminLevel);
    });
    qsa('[data-data-lens]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.dataLens === state.ui.dataLens);
    });
    qsa('[data-period-mode]').forEach((button) => {
      button.classList.toggle('is-active', button.dataset.periodMode === state.ui.periodMode);
    });
    qsa('input[type="range"]').forEach((input) => {
      const output = document.querySelector(`[data-range-output="${input.name}"]`);
      if (output) output.textContent = input.value;
    });
  }

  function renderHeader() {
    byId('hero-title-meta').textContent = `生成于 ${state.data.siteSummary?.generatedAt || '—'} · ${Recommendation.lensLabel(state.ui.dataLens)} · ${state.ui.periodMode === 'latest' ? '最新快照' : '统一年度'}`;
    byId('hero-scope-note').textContent = currentScopeLabel();
    byId('hero-province-count').textContent = formatCount(summaryCount('includedProvinces'));
    byId('hero-city-count').textContent = formatCount(summaryCount('includedCities'));
    byId('hero-county-count').textContent = formatCount(summaryCount('includedCounties'));
    byId('hero-fact-count').textContent = formatCount(summaryCount('cityFactLayerCount'));
    byId('hero-evidence-pill').textContent = `${Recommendation.lensLabel(state.ui.dataLens)} · ${currentScopeLabel()}`;
    byId('hero-update-pill').textContent = state.data.siteSummary?.generatedAt || '—';
  }

  function renderKpis() {
    const entities = currentEntities();
    const factEligible = entities.filter((item) => (toNumber(item?.evidence?.factCompleteness) ?? 0) >= 0.35);
    const inferenceEligible = entities.filter((item) => (toNumber(item?.evidence?.inferenceCompleteness) ?? 0) >= 0.45);
    const leader = [...factEligible].sort((a, b) => (toNumber(b.officialBalanceScore ?? b.overviewScore) ?? 0) - (toNumber(a.officialBalanceScore ?? a.overviewScore) ?? 0))[0];
    const watchlist = [...inferenceEligible].sort((a, b) => (toNumber(b?.inference?.estimatedScores?.balance) ?? 0) - (toNumber(a?.inference?.estimatedScores?.balance) ?? 0))[0];
    const coverage = currentProvinceCoverage();

    byId('kpi-current-count').textContent = formatCount(entities.length);
    byId('kpi-current-note').textContent = currentScopeLabel();
    byId('kpi-fact-leader').textContent = leader?.name || '暂无';
    byId('kpi-fact-note').textContent = leader ? Recommendation.coverageLabel(leader) : '当前范围暂无厚证据样本';
    byId('kpi-watchlist').textContent = watchlist?.name || '暂无';
    byId('kpi-watchlist-note').textContent = watchlist ? '证据偏薄，但值得继续研究' : '当前没有明显补充候选';
    byId('kpi-coverage').textContent = state.ui.adminLevel === 'province' ? `${summaryCount('comparableMainlandProvinces')} 个可比省级` : `${currentEntities().filter((item) => (toNumber(item?.evidence?.factCompleteness) ?? 0) > 0).length} 个事实样本`;
    byId('kpi-coverage-note').textContent = coverage?.cityCoverageLevel ? `省内覆盖：${coverage.cityCoverageLevel}` : '按当前层级统计';
    byId('kpi-source-count').textContent = formatCount(ensureArray(state.data.sources?.sources).length);
    byId('kpi-source-note').textContent = '来源登记条目';
    byId('kpi-generated-at').textContent = state.data.siteSummary?.generatedAt || '—';
    byId('kpi-generated-note').textContent = '静态快照';
  }

  function renderScopePanel() {
    const coverage = currentProvinceCoverage();
    const province = currentProvince();
    const entities = currentEntities();
    const note = currentScopeEligibility().note;
    const sources = new Set();
    entities.slice(0, 12).forEach((item) => ensureArray(item?.evidence?.sourceRefs).forEach((ref) => sources.add(ref)));

    byId('scope-panel-title').textContent = state.ui.adminLevel === 'province' ? '全国概览说明' : province ? province.name : '当前范围';
    byId('scope-panel-note').textContent = note;
    byId('scope-panel-stats').innerHTML = [
      `<li>当前对象：${formatCount(entities.length)}</li>`,
      `<li>事实较完整：${formatCount(entities.filter((item) => (toNumber(item?.evidence?.factCompleteness) ?? 0) >= 0.35).length)}</li>`,
      `<li>可进入推理解读：${formatCount(entities.filter((item) => (toNumber(item?.evidence?.inferenceCompleteness) ?? 0) >= 0.45).length)}</li>`,
      coverage ? `<li>缺失维度：${ensureArray(coverage.missingDimensions).map((item) => Recommendation.qualityFlagLabel(item)).join('、') || '暂无'}</li>` : '<li>缺失维度：按当前层级查看</li>',
    ].join('');

    byId('scope-panel-sources').innerHTML = [...sources]
      .slice(0, 6)
      .map((ref) => {
        const source = ensureArray(state.data.sources?.sources).find((item) => item.sourceId === ref);
        return `<li>${source?.name || ref}</li>`;
      })
      .join('') || '<li>当前模块暂无来源摘要</li>';
  }

  function renderMap() {
    const metricKey = currentMetricKey();

    if (state.ui.adminLevel === 'province') {
      const ok = Charts.renderProvinceMap(state.charts.map, state.data.provinces, metricKey, state.ui.selectedProvinceId);
      if (ok) hideModuleState('map-state');
      else setModuleState('map-state', 'warning', '地图资源未加载成功，请先看下面的榜单与解读。');
      return;
    }

    if (state.ui.adminLevel === 'city') {
      const ok = Charts.renderCityMap(state.charts.map, currentProvince(), currentCityEntities(), metricKey, state.ui.selectedCityId);
      if (ok) hideModuleState('map-state');
      else setModuleState('map-state', 'warning', '当前省份还没有足够点位，先看右侧说明和下方对比。');
      return;
    }

    state.charts.map?.clear();
    setModuleState('map-state', 'loading', '县区层当前以目录与证据卡片为主，地图不会强行渲染空白点位。');
  }

  function comparePool() {
    const entities = currentEntities().filter((item) => item.displayEligibility !== false);
    return entities
      .slice()
      .sort((a, b) => a.name.localeCompare(b.name, 'zh-CN'))
      .slice(0, state.ui.adminLevel === 'county' ? 120 : entities.length);
  }

  function renderComparePicker() {
    const pool = comparePool();
    byId('compare-picker-title').textContent = `${currentScopeLabel()} · 选择对比对象`;
    byId('compare-picker-list').innerHTML = pool.map((entity) => `
      <label class="picker-item">
        <span>
          <input type="checkbox" value="${entity.id}" ${state.ui.compareIds.includes(entity.id) ? 'checked' : ''} />
          <strong>${entity.name}</strong>
          <small>${Recommendation.coverageLabel(entity)}</small>
        </span>
        <button type="button" data-open-entity="${entity.id}">详情</button>
      </label>
    `).join('');
  }

  function selectedCompareEntities() {
    const pool = comparePool();
    return state.ui.compareIds.map((id) => pool.find((item) => item.id === id)).filter(Boolean);
  }

  function renderCompare() {
    const eligibility = currentScopeEligibility();
    const entities = selectedCompareEntities();
    const metrics = Recommendation.metricGroups(state.ui.adminLevel);
    if (!eligibility.compareReady) {
      setModuleState('compare-state', 'warning', eligibility.note);
      byId('compare-facts').innerHTML = `<p class="empty-state">${eligibility.note}</p>`;
      byId('compare-summary').innerHTML = '<p class="empty-state">当前样本不足，暂不输出强结论。</p>';
      state.charts.compare?.clear();
      return;
    }

    if (entities.length < 2) {
      setModuleState('compare-state', 'loading', '至少选择两个对象后再开始对比。');
      byId('compare-facts').innerHTML = '<p class="empty-state">请选择 2–4 个对象后再开始对比。</p>';
      byId('compare-summary').innerHTML = '<p class="empty-state">系统会先给事实差异，再给简洁结论。</p>';
      state.charts.compare?.clear();
      return;
    }

    const ok = Charts.renderCompareChart(state.charts.compare, entities, metrics, state.ui.dataLens);
    if (ok) hideModuleState('compare-state');
    else setModuleState('compare-state', 'warning', '当前对比图暂不可用，请先看文字总结。');

    const narrative = Recommendation.buildCompareNarrative(entities, state.ui.dataLens);
    byId('compare-facts').innerHTML = `<ul class="bullet-list">${narrative.facts.map((line) => `<li>${line}</li>`).join('')}</ul>`;
    byId('compare-summary').innerHTML = `<ul class="bullet-list">${narrative.summary.map((line) => `<li>${line}</li>`).join('')}</ul>`;
  }

  function readPreferences() {
    const form = byId('interpret-form');
    const data = new FormData(form);
    return {
      scope: data.get('scope') || 'city',
      budget: data.get('budget') || 'moderate',
      stage: data.get('stage') || 'earlyCareer',
      household: data.get('household') || 'solo',
      tierPreference: data.get('tierPreference') || 'balanced',
      savingsWeight: Number(data.get('savingsWeight') || 58),
      commuteWeight: Number(data.get('commuteWeight') || 60),
      airWeight: Number(data.get('airWeight') || 52),
      opportunityWeight: Number(data.get('opportunityWeight') || 50),
    };
  }

  function writePreferences(preferences) {
    const form = byId('interpret-form');
    if (!form) return;
    Object.entries(preferences).forEach(([key, value]) => {
      const field = form.elements.namedItem(key);
      if (field) field.value = value;
    });
    state.ui.preferences = { ...preferences };
    syncToggleButtons();
  }

  function recommendationScopeEntities() {
    if (state.ui.preferences.scope === 'province') return state.data.provinces;
    if (state.ui.preferences.scope === 'county') return currentCountyEntities();
    return currentCityEntities();
  }

  function renderInterpretation() {
    const prefs = state.ui.preferences;
    const eligibility = currentScopeEligibility();
    const scopeEntities = recommendationScopeEntities();
    const scopeText = prefs.scope === 'province' ? '省级智能解读' : prefs.scope === 'county' ? '县区智能解读' : '城市智能解读';
    byId('interpret-weight-note').innerHTML = `<ul class="bullet-list">
      <li>当前模式：${scopeText} · ${Recommendation.lensLabel(state.ui.dataLens)}</li>
      <li>权重偏好：攒钱 ${prefs.savingsWeight}% · 通勤 ${prefs.commuteWeight}% · 空气 ${prefs.airWeight}% · 机会 ${prefs.opportunityWeight}%</li>
      <li>基础条件：${preferenceLabel('budget', prefs.budget)} · ${preferenceLabel('stage', prefs.stage)} · ${preferenceLabel('household', prefs.household)}</li>
    </ul>`;

    if (!eligibility.recommendReady && prefs.scope !== 'province') {
      byId('interpret-results').innerHTML = `<div class="empty-state">${eligibility.note} 当前只提供事实说明，不输出强推荐。</div>`;
      return;
    }

    const results = Recommendation.recommendEntities(scopeEntities, prefs, { lens: state.ui.dataLens, limit: 4 });
    if (!results.length) {
      byId('interpret-results').innerHTML = '<div class="empty-state">当前条件下没有合适对象，请放宽权重或切换层级。</div>';
      return;
    }

    byId('interpret-results').innerHTML = results.map((item) => `
      <article class="recommendation-card">
        <div class="recommendation-head">
          <div>
            <h3>${item.name}</h3>
            <p class="section-note">${Recommendation.adminLabel(item.adminLevel)} · ${item.recommendationLabel}</p>
          </div>
          <strong>${item.finalScore.toFixed(1)}</strong>
        </div>
        <div class="tag-row">
          <span class="data-badge">事实 ${Math.floor((toNumber(item?.evidence?.factCompleteness) ?? 0) * 100)}%</span>
          <span class="data-badge">推理 ${Math.floor((toNumber(item?.evidence?.inferenceCompleteness) ?? 0) * 100)}%</span>
        </div>
        <p><strong>为什么值得看：</strong>${item.positives.map((factor) => `${factor.label} ${factor.score.toFixed(0)}`).join('；')}</p>
        <p><strong>代价与风险：</strong>${item.tradeoffs.map((factor) => `${factor.label} ${factor.score.toFixed(0)}`).join('；')}</p>
        <p><strong>智能解读：</strong>${Recommendation.localizeText(item?.inference?.reasoningSummary || '当前以事实层为主，推理解读较少。')}</p>
        <p><strong>下一步：</strong>${item.nextStep}</p>
        <div class="recommendation-actions">
          <button class="btn btn-secondary btn-compact" type="button" data-open-entity="${item.id}">查看证据</button>
        </div>
      </article>
    `).join('');
  }

  function renderInsightCards() {
    const cards = Recommendation.buildInsightCards(currentEntities(), state.ui.dataLens);
    if (!cards.length) {
      byId('insight-cards').innerHTML = '<div class="empty-state">当前范围还没有足够样本生成提示卡。</div>';
      return;
    }
    byId('insight-cards').innerHTML = cards.map((card) => `
      <article class="insight-card">
        <div class="analysis-card-head">
          <h3>${card.title}</h3>
          <span class="data-badge">${Recommendation.coverageLabel(card.entity)}</span>
        </div>
        <strong>${card.entity.name}</strong>
        <p>${card.description}</p>
        <p class="section-note">${card.risk}</p>
        <button class="link-button" type="button" data-open-entity="${card.entity.id}">查看证据</button>
      </article>
    `).join('');
  }

  function renderMethodPreview() {
    const lines = ensureArray(state.data.siteSummary?.meta?.disclaimer || []).slice(0, 4);
    byId('method-preview-list').innerHTML = lines.map((line) => `<li>${Recommendation.localizeText(line)}</li>`).join('');
    byId('persona-advice').innerHTML = Recommendation.buildPersonaAdvice().map((line) => `<li>${line}</li>`).join('');
  }

  function renderCoveragePreview() {
    const rows = ensureArray(state.data.coverage?.provinces)
      .slice()
      .sort((a, b) => (b.cityDirectoryCount || 0) - (a.cityDirectoryCount || 0))
      .slice(0, 10);

    byId('coverage-preview-table').innerHTML = rows.map((row) => `
      <tr>
        <td>${row.name}</td>
        <td>${row.cityDirectoryCount || 0}</td>
        <td>${row.cityFactCount || 0}</td>
        <td>${row.cityAiCount || 0}</td>
        <td>${ensureArray(row.missingDimensions).map((item) => Recommendation.qualityFlagLabel(item)).join('、') || '暂无'}</td>
      </tr>
    `).join('');
  }

  function renderSourcePreview() {
    byId('source-preview').innerHTML = ensureArray(state.data.sources?.researchSummary)
      .slice(0, 4)
      .map((item) => `
        <article class="source-item">
          <strong>${item.name}</strong>
          <p>${item.typeLabel} · ${item.coverage} · ${item.updateFrequency}</p>
          <p class="section-note">${Recommendation.localizeText(item.limitations || '')}</p>
        </article>
      `).join('');
  }

  function renderSearchFeedback(text) {
    byId('search-feedback').textContent = text;
  }

  function findRegistryHit(query) {
    const normalized = normalizeQuery(query);
    if (!normalized) return null;
    return state.data.registry.find((item) => {
      const keys = [item.name, item.searchLabel, ...ensureArray(item.searchKeywords)].map(normalizeQuery);
      return keys.some((key) => key.includes(normalized));
    }) || null;
  }

  async function focusRegistryItem(item, openDetail = true) {
    if (!item) return;
    state.ui.selectedProvinceId = item.adminLevel === 'province-level' ? item.id : item.provinceId || item.parentProvinceId;
    if (item.adminLevel === 'province-level') {
      state.ui.adminLevel = 'province';
      state.ui.activeEntityId = item.id;
      state.ui.selectedCityId = currentCityEntities()[0]?.id || null;
      await renderAll();
      return;
    }

    if (item.adminLevel === 'prefecture-level') {
      state.ui.adminLevel = 'city';
      state.ui.selectedCityId = item.id;
      state.ui.activeEntityId = item.id;
      await renderAll();
      if (openDetail) openDrawer(item.id);
      return;
    }

    state.ui.adminLevel = 'county';
    await ensureCountyPack(state.ui.selectedProvinceId);
    state.ui.activeEntityId = item.id;
    state.ui.selectedCityId = item.parentCityId || null;
    await renderAll();
    if (openDetail) openDrawer(item.id);
  }

  async function runSearch() {
    const input = byId('global-search');
    const query = input?.value || '';
    if (!query.trim()) {
      renderSearchFeedback('请输入省、市或县区名称。');
      return;
    }
    const hit = findRegistryHit(query);
    if (!hit) {
      renderSearchFeedback('没有找到匹配对象，请换个关键词。');
      return;
    }
    renderSearchFeedback(`已定位到 ${hit.name}。`);
    await focusRegistryItem(hit, true);
  }

  async function resolveEntity(id) {
    if (!id) return null;
    const province = state.data.provinces.find((item) => item.id === id);
    if (province) return province;
    const city = state.data.cityLite.find((item) => item.id === id);
    if (city) {
      const pack = await ensureCityPack(city.provinceId);
      return ensureArray(pack?.cities).find((item) => item.id === id) || city;
    }
    const registry = state.data.registry.find((item) => item.id === id);
    if (registry?.provinceId) {
      const pack = await ensureCountyPack(registry.provinceId);
      return ensureArray(pack?.counties).find((item) => item.id === id) || null;
    }
    return null;
  }

  function closeDrawer() {
    const drawer = byId('detail-drawer');
    if (!drawer) return;
    drawer.classList.remove('is-open');
    drawer.setAttribute('aria-hidden', 'true');
  }

  function openDrawer(id) {
    resolveEntity(id).then((entity) => {
      if (!entity) return;
      const drawer = byId('detail-drawer');
      const panel = byId('drawer-content');
      const factLines = [];
      if (toNumber(entity.effectiveMonthlyIncome) !== null) factLines.push(`收入参考：${Math.round(entity.effectiveMonthlyIncome)} 元/月`);
      if (toNumber(entity.annualConsumptionPerCapita) !== null) factLines.push(`消费支出：${Math.round(entity.annualConsumptionPerCapita)} 元/年`);
      if (toNumber(entity.officialGdp) !== null) factLines.push(`GDP：${entity.officialGdp.toFixed(1)} 亿元`);
      if (toNumber(entity.rentBurdenProxy) !== null) factLines.push(`房租压力：${(entity.rentBurdenProxy * 100).toFixed(1)}%`);
      if (toNumber(entity.totalCostIndex) !== null) factLines.push(`综合成本：${entity.totalCostIndex.toFixed(1)}`);
      if (toNumber(entity.commuteIndex) !== null) factLines.push(`通勤便利：${entity.commuteIndex.toFixed(1)}`);
      if (toNumber(entity.airQualityScore) !== null) factLines.push(`空气质量：${entity.airQualityScore.toFixed(1)}`);
      if (toNumber(entity.officialBalanceScore ?? entity.overviewScore) !== null) factLines.push(`事实层主分：${formatNumber(entity.officialBalanceScore ?? entity.overviewScore)}`);

      const supplementLines = [];
      if (toNumber(entity.social?.signalCount) > 0) supplementLines.push(`公开体验信号：${entity.social.signalCount} 条`);
      if (ensureArray(entity.social?.themes).length) supplementLines.push(`体验主题：${ensureArray(entity.social.themes).join('、')}`);
      if (entity.evidence?.displayPeriodLabel) supplementLines.push(`当前周期：${Recommendation.localizeText(entity.evidence.displayPeriodLabel)}`);

      const qualityFlags = ensureArray(entity?.evidence?.qualityFlags).map((flag) => Recommendation.qualityFlagLabel(flag)).join('、') || '暂无';
      const sourceRefs = ensureArray(entity?.evidence?.sourceRefs)
        .map((ref) => ensureArray(state.data.sources?.sources).find((item) => item.sourceId === ref)?.name || ref)
        .join('、') || '暂无';
      const basis = ensureArray(entity?.inference?.inferenceBasis).map((flag) => Recommendation.inferenceBasisLabel(flag)).join('、') || '暂无';

      panel.innerHTML = `
        <div class="drawer-header">
          <div>
            <p class="eyebrow">${Recommendation.adminLabel(entity.adminLevel)}</p>
            <h2>${entity.name}</h2>
            <p class="section-note">${Recommendation.coverageLabel(entity)} · ${Recommendation.localizeText(entity?.evidence?.displayPeriodLabel || '查看来源')}</p>
          </div>
        </div>
        <div class="tag-row">
          <span class="data-badge">事实 ${Math.round((toNumber(entity?.evidence?.factCompleteness) ?? 0) * 100)}%</span>
          <span class="data-badge">推理 ${Math.round((toNumber(entity?.evidence?.inferenceCompleteness) ?? 0) * 100)}%</span>
        </div>
        <section class="drawer-section">
          <h3>核心事实</h3>
          ${factLines.length ? `<ul class="bullet-list">${factLines.map((line) => `<li>${line}</li>`).join('')}</ul>` : '<p class="empty-state">当前没有足够厚的事实层字段。</p>'}
        </section>
        <section class="drawer-section">
          <h3>补充快照</h3>
          ${supplementLines.length ? `<ul class="bullet-list">${supplementLines.map((line) => `<li>${line}</li>`).join('')}</ul>` : '<p class="empty-state">当前没有额外快照或体验信号。</p>'}
        </section>
        <section class="drawer-section">
          <h3>智能解读</h3>
          <p>${Recommendation.localizeText(entity?.inference?.reasoningSummary || '当前主要依赖事实层，没有额外推理解读。')}</p>
          <ul class="bullet-list">
            <li>推理可信度：${entity?.inference?.confidenceBand || '暂无'}${toNumber(entity?.inference?.confidence) !== null ? `（${Math.round(entity.inference.confidence * 100)}%）` : ''}</li>
            <li>推理依据：${basis}</li>
            <li>下一步建议：${Recommendation.coverageLabel(entity) === '目录参考' ? '先核查父级城市和最新公开资料。' : '再拉 1–2 个同级地区做对比。'}</li>
          </ul>
        </section>
        <section class="drawer-section">
          <h3>来源与可信度</h3>
          <p><strong>来源：</strong>${sourceRefs}</p>
          <p><strong>限制：</strong>${qualityFlags}</p>
          <p><strong>更新时间：</strong>${entity?.evidence?.lastUpdated || '暂无'}</p>
        </section>
      `;

      drawer.classList.add('is-open');
      drawer.setAttribute('aria-hidden', 'false');
    });
  }

  async function onMapClick(params) {
    if (!params?.data?.id) return;
    const province = state.data.provinces.find((item) => item.id === params.data.id);
    const city = state.data.cityLite.find((item) => item.id === params.data.id);
    if (province) {
      state.ui.selectedProvinceId = province.id;
      state.ui.selectedCityId = currentCityEntities()[0]?.id || null;
      state.ui.adminLevel = 'city';
      state.ui.activeEntityId = province.id;
      await renderAll();
      return;
    }
    if (city) {
      state.ui.selectedProvinceId = city.provinceId;
      state.ui.selectedCityId = city.id;
      state.ui.activeEntityId = city.id;
      await renderAll();
      openDrawer(city.id);
    }
  }

  function updateScopeSelect() {
    const scope = byId('interpret-scope');
    if (!scope) return;
    scope.value = state.ui.adminLevel === 'province' ? 'province' : state.ui.adminLevel === 'county' ? 'county' : 'city';
  }

  function exportCurrentScope() {
    const payload = {
      generatedAt: state.data.siteSummary?.generatedAt,
      scope: currentScopeLabel(),
      dataLens: state.ui.dataLens,
      entities: currentEntities(),
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `scope-export-${state.ui.adminLevel}-${Date.now()}.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  async function renderAll() {
    syncToggleButtons();
    if (state.ui.adminLevel === 'county' && state.ui.selectedProvinceId) {
      setModuleState('compare-state', 'loading', '正在加载当前省份的县区目录…');
      await ensureCountyPack(state.ui.selectedProvinceId);
      hideModuleState('compare-state');
    }
    renderHeader();
    renderKpis();
    renderScopePanel();
    renderMap();
    renderComparePicker();
    renderCompare();
    renderInterpretation();
    renderInsightCards();
    renderMethodPreview();
    renderCoveragePreview();
    renderSourcePreview();
    updateScopeSelect();
    syncUrl();
  }

  function bindControls() {
    qsa('[data-admin-level]').forEach((button) => button.addEventListener('click', async () => {
      state.ui.adminLevel = button.dataset.adminLevel;
      state.ui.compareIds = [];
      if (state.ui.adminLevel === 'city' && !state.ui.selectedProvinceId) {
        state.ui.selectedProvinceId = state.data.provinces[0]?.id || null;
      }
      await renderAll();
    }));

    qsa('[data-data-lens]').forEach((button) => button.addEventListener('click', async () => {
      state.ui.dataLens = button.dataset.dataLens;
      await renderAll();
    }));

    qsa('[data-period-mode]').forEach((button) => button.addEventListener('click', async () => {
      state.ui.periodMode = button.dataset.periodMode;
      await renderAll();
    }));

    qsa('[data-preset]').forEach((button) => button.addEventListener('click', async () => {
      writePreferences(Recommendation.applyPreset(readPreferences(), button.dataset.preset));
      await renderAll();
    }));

    byId('map-metric-province')?.addEventListener('change', renderMap);
    byId('map-metric-city')?.addEventListener('change', renderMap);
    byId('global-search-button')?.addEventListener('click', runSearch);
    byId('global-search')?.addEventListener('keydown', async (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        await runSearch();
      }
    });
    byId('back-to-province')?.addEventListener('click', async () => {
      state.ui.adminLevel = 'province';
      state.ui.compareIds = [];
      await renderAll();
    });
    byId('export-scope')?.addEventListener('click', exportCurrentScope);

    byId('interpret-form')?.addEventListener('input', async () => {
      state.ui.preferences = readPreferences();
      if (state.ui.preferences.scope !== state.ui.adminLevel) {
        state.ui.adminLevel = state.ui.preferences.scope;
      }
      syncToggleButtons();
      await renderAll();
    });

    byId('compare-picker-list')?.addEventListener('change', async (event) => {
      const input = event.target.closest('input[type="checkbox"]');
      if (!input) return;
      if (input.checked) {
        if (state.ui.compareIds.length >= 4) {
          input.checked = false;
          return;
        }
        state.ui.compareIds.push(input.value);
      } else {
        state.ui.compareIds = state.ui.compareIds.filter((id) => id !== input.value);
      }
      renderCompare();
    });

    document.body.addEventListener('click', async (event) => {
      const openButton = event.target.closest('[data-open-entity]');
      if (openButton) {
        await openDrawer(openButton.dataset.openEntity);
        return;
      }
      if (event.target.closest('[data-close-drawer]') || event.target.classList.contains('drawer-backdrop')) {
        closeDrawer();
      }
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') closeDrawer();
    });

    const navToggle = document.querySelector('[data-nav-toggle]');
    const nav = document.querySelector('[data-nav]');
    if (navToggle && nav) {
      navToggle.addEventListener('click', () => {
        const expanded = navToggle.getAttribute('aria-expanded') === 'true';
        navToggle.setAttribute('aria-expanded', String(!expanded));
        nav.classList.toggle('is-open', !expanded);
      });
    }
  }

  function initCharts() {
    state.charts.map = Charts.createMap('main-map', onMapClick);
    state.charts.compare = Charts.createCompare('compare-chart');
  }

  async function init() {
    try {
      if (!Charts || !Recommendation) throw new Error('核心脚本未加载成功。');
      restoreFromUrl();
      await loadBaseData();
      initCharts();
      writePreferences(state.ui.preferences);
      bindControls();
      hideBanner();
      await renderAll();
    } catch (error) {
      console.error(error);
      showBanner('error', '页面初始化失败，请确认已通过本地 HTTP 服务或 GitHub Pages 打开站点。');
    }
  }

  document.addEventListener('DOMContentLoaded', init);
})(window);
