(function attachEvidenceCharts(global) {
  const runtime = () => global.echarts || null;
  const ensureNumber = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

  function hasChinaMap() {
    return Boolean(runtime()?.getMap?.('china'));
  }

  function createChart(domId, clickHandler) {
    const echarts = runtime();
    const dom = document.getElementById(domId);
    if (!echarts || !dom) return null;

    let chart = echarts.getInstanceByDom(dom);
    if (!chart) {
      chart = echarts.init(dom, null, {
        renderer: 'canvas',
        useDirtyRect: true,
        useCoarsePointer: true,
      });
    }

    chart.off('click');
    if (typeof clickHandler === 'function') {
      chart.on('click', (params) => clickHandler(params));
    }

    if (!dom.dataset.resizeBound) {
      const resize = () => chart.resize({ animation: { duration: 0 } });
      if (typeof ResizeObserver !== 'undefined') {
        const observer = new ResizeObserver(() => resize());
        observer.observe(dom);
      }
      global.addEventListener('resize', resize, { passive: true });
      dom.dataset.resizeBound = 'true';
    }

    return chart;
  }

  function stableSetOption(chart, option) {
    if (!chart) return false;
    chart.clear();
    chart.setOption(option, { notMerge: true, lazyUpdate: true });
    return true;
  }

  function createMap(domId, clickHandler) {
    return createChart(domId, clickHandler);
  }

  function createCompare(domId) {
    return createChart(domId);
  }

  function metricRange(values) {
    const valid = values.filter((value) => value !== null);
    if (!valid.length) return { min: 0, max: 100 };
    const min = Math.min(...valid);
    const max = Math.max(...valid);
    return { min, max: min === max ? min + 1 : max };
  }

  function renderProvinceMap(chart, provinces, metricKey, selectedProvinceId) {
    if (!chart || !hasChinaMap()) return false;

    const values = provinces.map((item) => ensureNumber(item[metricKey]));
    const range = metricRange(values);

    return stableSetOption(chart, {
      animation: false,
      tooltip: {
        trigger: 'item',
        formatter: (params) => {
          const item = params?.data;
          if (!item) return params?.name || '暂无';
          const value = ensureNumber(item.value);
          return [
            `<strong>${item.name}</strong>`,
            `${item.metricLabel}：${value === null ? '暂无' : value.toFixed(1)}`,
            `覆盖：${item.coverageLabel || '待说明'}`,
            '点击进入省内城市层',
          ].join('<br />');
        },
      },
      visualMap: {
        min: range.min,
        max: range.max,
        left: 'center',
        bottom: 6,
        orient: 'horizontal',
        calculable: true,
        inRange: {
          color: ['#edf4ff', '#bed8ff', '#70aaff', '#2563eb'],
        },
        text: ['高', '低'],
        textStyle: { color: '#5f6f85' },
      },
      series: [
        {
          type: 'map',
          map: 'china',
          roam: false,
          selectedMode: false,
          label: { show: false },
          itemStyle: {
            areaColor: '#eef4fb',
            borderColor: '#9fb5cb',
            borderWidth: 1,
          },
          emphasis: {
            label: { show: false },
            itemStyle: { areaColor: '#d8e9ff' },
          },
          data: provinces.map((item) => ({
            id: item.id,
            name: item.name,
            value: ensureNumber(item[metricKey]),
            metricLabel: global.CityRecommendation?.metricLabel?.(metricKey) || metricKey,
            coverageLabel: global.CityRecommendation?.coverageLabel?.(item) || '',
          })),
          regions: selectedProvinceId
            ? provinces
                .filter((province) => province.id === selectedProvinceId)
                .map((province) => ({
                  name: province.name,
                  itemStyle: {
                    areaColor: '#dbeafe',
                    borderColor: '#1d4ed8',
                    borderWidth: 1.8,
                  },
                }))
            : [],
        },
      ],
    });
  }

  function renderCityMap(chart, province, cities, metricKey, activeCityId) {
    if (!chart || !hasChinaMap() || !province) return false;

    const points = cities
      .filter((item) => Array.isArray(item.coordinates) && item.coordinates.length === 2)
      .map((item) => {
        const metric = ensureNumber(item[metricKey]);
        return {
          id: item.id,
          name: item.name,
          value: [...item.coordinates, metric === null ? 0 : metric],
          metric,
          coverageLabel: global.CityRecommendation?.coverageLabel?.(item) || '',
          periodLabel: item?.evidence?.displayPeriodLabel || '查看详情',
          itemStyle: activeCityId === item.id ? { color: '#1d4ed8' } : undefined,
        };
      });

    if (!points.length) {
      chart.clear();
      return false;
    }

    const range = metricRange(points.map((item) => item.metric));

    return stableSetOption(chart, {
      animation: false,
      tooltip: {
        trigger: 'item',
        formatter: (params) => {
          const item = params?.data;
          if (!item) return params?.name || '暂无';
          if (item.entityType === 'province') {
            return `<strong>${item.name}</strong><br />点击切换到该省城市层`;
          }
          return [
            `<strong>${item.name}</strong>`,
            `${global.CityRecommendation?.metricLabel?.(metricKey) || metricKey}：${item.metric === null ? '暂无' : item.metric.toFixed(1)}`,
            `覆盖：${item.coverageLabel}`,
            item.periodLabel,
          ].join('<br />');
        },
      },
      visualMap: {
        min: range.min,
        max: range.max,
        show: true,
        left: 'center',
        bottom: 6,
        orient: 'horizontal',
        seriesIndex: 1,
        inRange: {
          color: ['#e0fbf4', '#9fe6d6', '#2cc29f', '#2563eb'],
        },
        text: ['更优', '较弱'],
        textStyle: { color: '#5f6f85' },
      },
      geo: {
        map: 'china',
        roam: false,
        silent: true,
        itemStyle: {
          areaColor: '#f4f8fd',
          borderColor: '#c5d7e8',
          borderWidth: 1,
        },
        regions: [
          {
            name: province.name,
            itemStyle: {
              areaColor: '#dbeafe',
              borderColor: '#1d4ed8',
              borderWidth: 1.8,
            },
          },
        ],
      },
      series: [
        {
          type: 'map',
          map: 'china',
          roam: false,
          selectedMode: false,
          label: { show: false },
          tooltip: { show: false },
          itemStyle: {
            areaColor: 'rgba(255,255,255,0.01)',
            borderColor: '#bfd0e1',
            borderWidth: 1,
          },
          emphasis: {
            itemStyle: { areaColor: 'rgba(37,99,235,0.08)' },
          },
          data: [],
        },
        {
          type: 'scatter',
          coordinateSystem: 'geo',
          progressive: 300,
          progressiveThreshold: 600,
          symbolSize: (value) => {
            const metric = typeof value?.[2] === 'number' ? value[2] : range.min;
            const ratio = (metric - range.min) / Math.max(range.max - range.min, 1);
            return 10 + ratio * 14;
          },
          itemStyle: {
            color: '#18b59d',
            borderColor: '#ffffff',
            borderWidth: 1.4,
          },
          emphasis: { scale: 1.12 },
          data: points,
        },
      ],
    });
  }

  function renderCompareChart(chart, entities, metricDefs, lens) {
    if (!chart) return false;
    if (!entities.length) {
      chart.clear();
      return false;
    }

    return stableSetOption(chart, {
      animationDuration: 180,
      animationDurationUpdate: 120,
      legend: { top: 4 },
      tooltip: { trigger: 'axis' },
      grid: { left: 42, right: 18, top: 52, bottom: 26 },
      xAxis: {
        type: 'category',
        data: metricDefs.map((item) => item[1]),
        axisLabel: { color: '#5f6f85' },
      },
      yAxis: {
        type: 'value',
        max: 100,
        axisLabel: { color: '#5f6f85' },
        splitLine: { lineStyle: { color: '#e6eef7' } },
      },
      series: entities.map((entity) => ({
        type: 'bar',
        name: entity.name,
        barMaxWidth: 22,
        data: metricDefs.map(([key]) => {
          const scores = global.CityRecommendation?.getLensScores?.(entity, lens) || {};
          if (key === 'officialBalanceScore' || key === 'balancedScore' || key === 'savingScore' || key === 'commuteIndex' || key === 'airQualityScore') {
            if (key === 'officialBalanceScore') return ensureNumber(entity.officialBalanceScore) ?? 0;
            if (key === 'balancedScore') return ensureNumber(scores.balance) ?? 0;
            if (key === 'savingScore') return ensureNumber(scores.affordability) ?? 0;
            if (key === 'commuteIndex') return ensureNumber(entity.commuteIndex ?? scores.opportunity) ?? 0;
            if (key === 'airQualityScore') return ensureNumber(entity.airQualityScore ?? scores.environment) ?? 0;
          }
          return ensureNumber(entity[key]) ?? 0;
        }),
      })),
    });
  }

  global.CityCharts = {
    hasChinaMap,
    createMap,
    createCompare,
    renderProvinceMap,
    renderCityMap,
    renderCompareChart,
  };
})(window);
