'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..', '..');

/**
 * Evaluates the real recs-component source in a sandbox with a minimal
 * goog shim, so the tests exercise shipped code rather than a
 * reimplementation. Mirrors test/helpers/load-app-state.js and
 * test/helpers/load-router.js.
 *
 * funwithactivity.recs.shouldFetch is a pure, DOM-free static function —
 * the only thing this helper's callers exercise — so the shim only needs
 * to be enough for the file to load (define the constructor, satisfy every
 * goog.require as a no-op) without ever constructing a RecsComponent or
 * touching a real DOM.
 */
function loadRefetchPolicy() {
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
      features: {recommendations: {api: {}, classify: function() {}}},
      recs: {},
      render: {element: function() {}}
    };
  `;
  vm.runInContext(googShim, sandbox);

  const src = fs.readFileSync(
      path.join(ROOT, 'src/features/recs/recs-component.js'), 'utf8');
  vm.runInContext(src, sandbox);

  return vm.runInContext('funwithactivity.recs.shouldFetch', sandbox);
}

module.exports = {loadRefetchPolicy};
