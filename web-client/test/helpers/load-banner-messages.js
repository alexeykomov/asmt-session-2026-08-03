'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..', '..');
const DTO_DIR = path.join(ROOT, '..', 'api', 'dto');

/**
 * Evaluates the real recs-component source — plus the real DTOs and the
 * real funwithactivity.features.recommendations.classify, not stubs — in a
 * sandbox with a minimal goog shim, so this test exercises the shipped
 * classify() decision (skipped-vs-degraded has caused four defects in this
 * project) together with funwithactivity.recs.bannerMessages, the pure,
 * DOM-free function that decides banner wording. Mirrors
 * test/helpers/load-refetch-policy.js and test/helpers/load-dtos.js's
 * loadClassifier.
 * @return {!Object} {bannerMessages, ProviderStatus}
 */
function loadBannerMessages() {
  const sandbox = {goog: null};
  vm.createContext(sandbox);

  const googShim = `
    var goog = {
      provide: function() {},
      require: function() {},
      inherits: function(child, parent) {
        function Tmp() {}
        Tmp.prototype = parent.prototype;
        child.prototype = new Tmp();
        child.prototype.constructor = child;
        child.base = function(me, name) {
          var args = Array.prototype.slice.call(arguments, 2);
          return parent.prototype[name].apply(me, args);
        };
      },
      dom: {
        createDom: function() { return {}; },
        TagName: {DIV: 'div'},
        getElement: function() { return null; }
      },
      events: {
        EventType: {CLICK: 'click'},
        listen: function() {},
        unlistenByKey: function() {}
      },
      ui: {
        Component: function() {},
        TableSorter: function() {}
      }
    };
    goog.ui.Component.prototype = {};
    var funwithactivity = {
      app: {},
      components: {recommendationsTable: {}, recsScreen: {}},
      dto: {},
      features: {recommendations: {api: {}}},
      recs: {},
      render: {element: function() {}}
    };
  `;
  vm.runInContext(googShim, sandbox);

  for (const f of ['recommendation.js', 'provider-status.js',
    'recommendations-response.js']) {
    vm.runInContext(
        fs.readFileSync(path.join(DTO_DIR, f), 'utf8'), sandbox, f);
  }
  vm.runInContext(
      fs.readFileSync(path.join(ROOT,
          'src/features/recommendations/provider-status-presentation.js'),
      'utf8'),
      sandbox, 'provider-status-presentation.js');
  vm.runInContext(
      fs.readFileSync(
          path.join(ROOT, 'src/features/recs/recs-component.js'), 'utf8'),
      sandbox, 'recs-component.js');

  return {
    bannerMessages: vm.runInContext('funwithactivity.recs.bannerMessages', sandbox),
    ProviderStatus: sandbox.funwithactivity.dto.ProviderStatus,
  };
}

module.exports = {loadBannerMessages};
