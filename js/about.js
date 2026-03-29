(function attachAbout(global) {
  const byId = (id) => document.getElementById(id);
  const ensureArray = (value) => (Array.isArray(value) ? value : value ? [value] : []);
  const Recommendation = global.CityRecommendation;

  function showBanner(type, message) {
    const node = byId('about-banner');
    if (!node) return;
    node.className = `status-banner status-banner-${type}`;
    node.textContent = message;
  }

  async function fetchJson(path) {
    const response = await fetch(path, { cache: 'no-store' });
    if (!response.ok) throw new Error(`Failed to load ${path}`);
    return response.json();
  }

  function renderStats(siteSummary, sources, coverage) {
    byId('about-generated-at').textContent = siteSummary.generatedAt || '—';
    byId('about-entity-count').textContent = `${siteSummary.coverageSummary.includedProvinces} / ${siteSummary.coverageSummary.includedCities} / ${siteSummary.coverageSummary.includedCounties}`;
    byId('about-source-count').textContent = ensureArray(sources.sources).length;
    byId('about-fact-count').textContent = `${siteSummary.coverageSummary.cityFactLayerCount} 城`;
    byId('about-coverage-note').textContent = `当前省级覆盖 ${ensureArray(coverage.provinces).length} 条。`;
  }

  function renderMethod(siteSummary) {
    byId('about-method-list').innerHTML = ensureArray(siteSummary.meta.updateStrategy)
      .map((line) => `<li>${Recommendation.localizeText(line)}</li>`)
      .join('');
    byId('about-limit-list').innerHTML = ensureArray(siteSummary.meta.disclaimer)
      .map((line) => `<li>${Recommendation.localizeText(line)}</li>`)
      .join('');
  }

  function renderResearchTable(sources) {
    byId('about-research-table').innerHTML = ensureArray(sources.researchSummary).map((item) => `
      <tr>
        <td>${item.name || '暂无'}</td>
        <td>${item.typeLabel || '暂无'}</td>
        <td>${ensureArray(item.fields).join('、') || '暂无'}</td>
        <td>${item.coverage || '暂无'}</td>
        <td>${item.updateFrequency || '暂无'}</td>
        <td>${item.suitableForMvp ? '是' : '否'}</td>
        <td>${item.staticFriendly ? '是' : '否'}</td>
        <td>${item.comparable ? '是' : '否'}</td>
        <td>${Recommendation.localizeText(item.limitations || '暂无')}</td>
      </tr>
    `).join('');
  }

  function renderCoverageTable(coverage) {
    byId('about-coverage-table').innerHTML = ensureArray(coverage.provinces)
      .slice()
      .sort((a, b) => (b.cityDirectoryCount || 0) - (a.cityDirectoryCount || 0))
      .map((province) => `
        <tr>
          <td>${province.name}</td>
          <td>${province.cityDirectoryCount || 0}</td>
          <td>${province.cityFactCount || 0}</td>
          <td>${province.cityAiCount || 0}</td>
          <td>${province.countyDirectoryCount || 0}</td>
          <td>${province.countyAiCount || 0}</td>
          <td>${ensureArray(province.missingDimensions).map((item) => Recommendation.qualityFlagLabel(item)).join('、') || '暂无'}</td>
        </tr>
      `).join('');
  }

  function renderMetricDefinitions(metricDefinitions) {
    byId('about-metric-table').innerHTML = ensureArray(metricDefinitions.metrics).map((metric) => `
      <tr>
        <td>${metric.metricId}</td>
        <td>${metric.label}</td>
        <td>${metric.scope}</td>
        <td>${metric.comparableScope}</td>
        <td>${metric.allowsProxy ? '允许' : '不允许'}</td>
        <td>${metric.rankingEligible ? '可' : '不可'}</td>
        <td>${metric.calculation}</td>
      </tr>
    `).join('');
  }

  function renderAssets() {
    const assets = [
      ['./data/site-summary.json', '站点摘要'],
      ['./data/packs/provinces.json', '省级数据包'],
      ['./data/packs/cities-lite.json', '城市轻量包'],
      ['./data/evidence/entity-registry.json', '统一主数据'],
      ['./data/evidence/metric-definitions.json', '指标定义'],
      ['./data/evidence/derived-recommendations.json', '派生解读结果'],
    ];

    byId('about-assets').innerHTML = assets.map(([href, label]) => `
      <a class="asset-link" href="${href}" target="_blank" rel="noreferrer">${label}</a>
    `).join('');
  }

  function bindNav() {
    const toggle = document.querySelector('[data-nav-toggle]');
    const nav = document.querySelector('[data-nav]');
    if (!toggle || !nav) return;
    toggle.addEventListener('click', () => {
      const expanded = toggle.getAttribute('aria-expanded') === 'true';
      toggle.setAttribute('aria-expanded', String(!expanded));
      nav.classList.toggle('is-open', !expanded);
    });
  }

  async function init() {
    try {
      const [siteSummary, sources, coverage, metricDefinitions] = await Promise.all([
        fetchJson('./data/site-summary.json'),
        fetchJson('./data/sources.json'),
        fetchJson('./data/coverage-view-model.json'),
        fetchJson('./data/evidence/metric-definitions.json'),
      ]);

      renderStats(siteSummary, sources, coverage);
      renderMethod(siteSummary);
      renderResearchTable(sources);
      renderCoverageTable(coverage);
      renderMetricDefinitions(metricDefinitions);
      renderAssets();
      bindNav();
    } catch (error) {
      console.error(error);
      showBanner('error', '方法说明页加载失败，请确认数据包已经构建。');
    }
  }

  document.addEventListener('DOMContentLoaded', init);
})(window);
