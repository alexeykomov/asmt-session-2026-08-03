'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..', '..');

/**
 * Evaluates the real app-state source in a sandbox with a minimal goog
 * shim, so the tests exercise shipped code rather than a reimplementation.
 * Mirrors test/helpers/load-dtos.js.
 */
function loadAppState() {
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
      events: {EventTarget: function() {}}
    };
    goog.events.EventTarget.prototype.dispatchEvent = function() {};
    var funwithactivity = {app: {}};
  `;
  vm.runInContext(googShim, sandbox);

  const src = fs.readFileSync(
      path.join(ROOT, 'src/features/app/app-state.js'), 'utf8');
  vm.runInContext(src, sandbox);

  return vm.runInContext('funwithactivity.app.AppState', sandbox);
}

module.exports = {loadAppState};
