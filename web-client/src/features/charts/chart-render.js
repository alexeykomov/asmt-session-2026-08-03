goog.provide('funwithactivity.charts.render');

goog.require('funwithactivity.charts.geometry');
goog.require('funwithactivity.dto.Chart');
goog.require('goog.dom');


/**
 * @fileoverview Turns a Chart DTO into an SVG element.
 *
 * Raw SVG, no charting library — the customer's brief rules out third-party
 * UI components, and the deck commits to exactly this ("raw SVG for stats
 * charts"). SVG rather than canvas because these are static: it scales to any
 * DPI with no manual devicePixelRatio arithmetic, and the result is
 * inspectable in devtools, which canvas pixels are not.
 *
 * Colour never comes from the wire. Each series carries a stable `key`, and
 * the CSS class built from it resolves to a custom property in main.css —
 * the same arrangement provider status colours already use. A copy edit to a
 * series' display label therefore cannot recolour a chart.
 *
 * These functions create elements and never query or mutate the document.
 */


/** @const {string} @private */
funwithactivity.charts.render.SVG_NS_ = 'http://www.w3.org/2000/svg';


/**
 * Viewport the charts are drawn into. Fixed rather than measured: an SVG
 * viewBox scales to whatever width CSS gives it, so drawing to a constant
 * coordinate space keeps the geometry identical at every screen size and
 * removes any dependence on layout having settled before drawing.
 * @const @private
 */
funwithactivity.charts.render.VIEW_ = {
  width: 640,
  height: 260,
  padTop: 16,
  padRight: 12,
  padBottom: 28,
  padLeft: 48,
};


/**
 * @param {string} name
 * @param {!Object<string, string|number>} attrs
 * @return {!Element}
 * @private
 */
funwithactivity.charts.render.el_ = function(name, attrs) {
  const node = document.createElementNS(
      funwithactivity.charts.render.SVG_NS_, name);
  const names = Object.keys(attrs);
  for (let i = 0; i < names.length; i++) {
    node.setAttribute(names[i], String(attrs[names[i]]));
  }
  return node;
};


/**
 * @param {string} key Series key from the wire.
 * @return {string} Class name whose colour is defined in main.css.
 * @private
 */
funwithactivity.charts.render.seriesClass_ = function(key) {
  // Sanitised rather than interpolated raw: the key arrives from the server,
  // and building a class name (or later a CSS selector) from unfiltered input
  // is the kind of thing that is harmless until it is not.
  const safe = String(key).replace(/[^a-z0-9_-]/gi, '');
  return 'chart-series chart-series-' + safe;
};


/**
 * Renders one chart, dispatching on its declared type.
 *
 * An unrecognised type renders the title and an explanatory line rather than
 * nothing: a server that later adds a chart shape must not blank a screen on
 * a client that predates it.
 * @param {!funwithactivity.dto.Chart} chart
 * @return {!Element} A container div holding the heading and the SVG.
 */
funwithactivity.charts.render.chart = function(chart) {
  const Type = funwithactivity.dto.Chart.Type;
  const container = goog.dom.createDom('div', 'chart-card');
  container.appendChild(goog.dom.createDom('h3', 'chart-title', chart.title));

  let body;
  if (!funwithactivity.charts.render.hasData_(chart)) {
    body = goog.dom.createDom('p', 'chart-empty', 'No data for this chart.');
  } else if (chart.type === Type.BAR || chart.type === Type.GROUPED_BAR) {
    body = funwithactivity.charts.render.barChart_(chart);
  } else if (chart.type === Type.PIE) {
    body = funwithactivity.charts.render.pieChart_(chart);
  } else {
    body = goog.dom.createDom(
        'p', 'chart-empty', 'This chart type is not supported by this client.');
  }
  container.appendChild(body);

  if (chart.series.length > 1) {
    container.appendChild(funwithactivity.charts.render.legend_(chart));
  }
  return container;
};


/**
 * @param {!funwithactivity.dto.Chart} chart
 * @return {boolean}
 * @private
 */
funwithactivity.charts.render.hasData_ = function(chart) {
  for (let i = 0; i < chart.series.length; i++) {
    if (chart.series[i].values.length > 0) return true;
  }
  return false;
};


/**
 * @param {!funwithactivity.dto.Chart} chart
 * @return {!Element}
 * @private
 */
funwithactivity.charts.render.legend_ = function(chart) {
  const list = goog.dom.createDom('ul', 'chart-legend');
  for (let i = 0; i < chart.series.length; i++) {
    const s = chart.series[i];
    const item = goog.dom.createDom('li', 'chart-legend-item');
    item.appendChild(goog.dom.createDom(
        'span', funwithactivity.charts.render.seriesClass_(s.key) +
            ' chart-legend-swatch'));
    item.appendChild(goog.dom.createDom(
        'span', 'chart-legend-label', s.label));
    list.appendChild(item);
  }
  return list;
};


/**
 * Bar and grouped-bar share a renderer: a single-series bar chart is just a
 * grouped chart with one bar per group, so splitting them would duplicate the
 * axis, scaling and label logic for no behavioural difference.
 * @param {!funwithactivity.dto.Chart} chart
 * @return {!Element}
 * @private
 */
funwithactivity.charts.render.barChart_ = function(chart) {
  const V = funwithactivity.charts.render.VIEW_;
  const G = funwithactivity.charts.geometry;
  const el = funwithactivity.charts.render.el_;

  const plotWidth = V.width - V.padLeft - V.padRight;
  const plotHeight = V.height - V.padTop - V.padBottom;

  let all = [];
  for (let i = 0; i < chart.series.length; i++) {
    all = all.concat(chart.series[i].values);
  }
  const axisMax = G.axisMax(all);

  const svg = el('svg', {
    'viewBox': '0 0 ' + V.width + ' ' + V.height,
    'class': 'chart-svg',
    'role': 'img',
    'aria-label': chart.title,
  });

  // Gridlines first so bars paint over them.
  for (let i = 0; i <= 4; i++) {
    const y = V.padTop + plotHeight - (plotHeight * i / 4);
    svg.appendChild(el('line', {
      'x1': V.padLeft, 'y1': y, 'x2': V.padLeft + plotWidth, 'y2': y,
      'class': 'chart-gridline',
    }));
    const label = el('text', {
      'x': V.padLeft - 8, 'y': y + 4, 'class': 'chart-axis-label',
      'text-anchor': 'end',
    });
    label.textContent =
        funwithactivity.charts.render.axisText_(axisMax * i / 4);
    svg.appendChild(label);
  }

  const slotWidth = plotWidth / Math.max(chart.categories.length, 1);
  const groupPadding = Math.min(slotWidth * 0.18, 10);

  for (let c = 0; c < chart.categories.length; c++) {
    for (let s = 0; s < chart.series.length; s++) {
      const values = chart.series[s].values;
      if (c >= values.length) continue;
      const slot = G.groupedBarSlot(
          c, s, chart.series.length, slotWidth, groupPadding);
      const height = G.barHeight(values[c], axisMax, plotHeight);
      svg.appendChild(el('rect', {
        'x': V.padLeft + slot.x,
        'y': V.padTop + plotHeight - height,
        'width': Math.max(slot.width - 1, 1),
        'height': height,
        'class': funwithactivity.charts.render.seriesClass_(
            chart.series[s].key) + ' chart-bar',
      }));
    }

    const tick = el('text', {
      'x': V.padLeft + c * slotWidth + slotWidth / 2,
      'y': V.height - 8,
      'class': 'chart-axis-label',
      'text-anchor': 'middle',
    });
    tick.textContent = chart.categories[c];
    svg.appendChild(tick);
  }

  return svg;
};


/**
 * @param {number} value
 * @return {string}
 * @private
 */
funwithactivity.charts.render.axisText_ = function(value) {
  if (value >= 1000) return Math.round(value / 100) / 10 + 'k';
  return String(Math.round(value));
};


/**
 * Pie slices are drawn as SVG paths: move to centre, line to the start of the
 * arc, arc to its end, close. `largeArcFlag` is what stops a slice over 180°
 * from being drawn as its own complement — the classic silent pie bug, where
 * a 70% slice renders as 30% and still looks like a perfectly good chart.
 * @param {!funwithactivity.dto.Chart} chart
 * @return {!Element}
 * @private
 */
funwithactivity.charts.render.pieChart_ = function(chart) {
  const V = funwithactivity.charts.render.VIEW_;
  const G = funwithactivity.charts.geometry;
  const el = funwithactivity.charts.render.el_;

  const cx = V.width / 2;
  const cy = V.height / 2;
  const radius = Math.min(V.width, V.height) / 2 - 20;

  // One value per series for a pie — the first, by contract.
  const values = [];
  for (let i = 0; i < chart.series.length; i++) {
    values.push(chart.series[i].values.length ? chart.series[i].values[0] : 0);
  }
  const angles = G.pieAngles(values);

  const svg = el('svg', {
    'viewBox': '0 0 ' + V.width + ' ' + V.height,
    'class': 'chart-svg',
    'role': 'img',
    'aria-label': chart.title,
  });

  if (angles.length === 0) {
    const text = el('text', {
      'x': cx, 'y': cy, 'class': 'chart-axis-label', 'text-anchor': 'middle',
    });
    text.textContent = 'No data';
    svg.appendChild(text);
    return svg;
  }

  let start = 0;
  for (let i = 0; i < angles.length; i++) {
    const end = start + angles[i];
    const from = G.pointOnCircle(cx, cy, radius, start);
    const to = G.pointOnCircle(cx, cy, radius, end);
    const largeArc = angles[i] > 180 ? 1 : 0;

    // A single slice covering the whole circle cannot be expressed as one
    // arc — start and end coincide, so the path collapses to nothing. Draw a
    // full circle instead.
    if (angles[i] >= 359.999) {
      svg.appendChild(el('circle', {
        'cx': cx, 'cy': cy, 'r': radius,
        'class': funwithactivity.charts.render.seriesClass_(
            chart.series[i].key) + ' chart-slice',
      }));
      break;
    }

    const d = 'M ' + cx + ' ' + cy +
        ' L ' + from.x + ' ' + from.y +
        ' A ' + radius + ' ' + radius + ' 0 ' + largeArc + ' 1 ' +
        to.x + ' ' + to.y + ' Z';
    svg.appendChild(el('path', {
      'd': d,
      'class': funwithactivity.charts.render.seriesClass_(
          chart.series[i].key) + ' chart-slice',
    }));
    start = end;
  }

  return svg;
};
