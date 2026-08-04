'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..', '..');

/**
 * Evaluates the real chart-geometry source in a sandbox with a minimal goog
 * shim, so the tests exercise shipped code rather than a reimplementation.
 * Mirrors test/helpers/load-router.js.
 *
 * chart-geometry.js is deliberately DOM-free — it takes numbers and returns
 * numbers — so the shim needs nothing but goog.provide.
 */
function loadChartGeometry() {
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(
      'var goog = {provide: function() {}, require: function() {}};' +
      'var funwithactivity = {charts: {geometry: {}}};', sandbox);

  const src = fs.readFileSync(
      path.join(ROOT, 'src/features/charts/chart-geometry.js'), 'utf8');
  vm.runInContext(src, sandbox);

  return vm.runInContext('funwithactivity.charts.geometry', sandbox);
}

module.exports = {loadChartGeometry};
