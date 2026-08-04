'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const DTO_DIR = path.join(__dirname, '../../../api/dto');

/**
 * Evaluates the Closure DTO sources in a sandbox with a minimal goog shim, so
 * Node tests can exercise the same source the browser bundle compiles. This
 * keeps one definition of slot order rather than a Node-only copy that drifts.
 * @return {!Object} map of short class name to constructor
 */
function loadClosureDtos() {
  const ns = {};
  const sandbox = {
    goog: {
      provide() {},
      require() {},
    },
    funwithactivity: {dto: {}},
  };
  vm.createContext(sandbox);

  // Order matters: the response DTO references the other two.
  for (const f of ['recommendation.js', 'provider-status.js',
    'recommendations-response.js']) {
    vm.runInContext(fs.readFileSync(path.join(DTO_DIR, f), 'utf8'), sandbox, f);
  }

  ns.Recommendation = sandbox.funwithactivity.dto.Recommendation;
  ns.ProviderStatus = sandbox.funwithactivity.dto.ProviderStatus;
  ns.RecommendationsResponse = sandbox.funwithactivity.dto.RecommendationsResponse;
  return ns;
}

/**
 * Loads the DTOs plus the classifier, for the presentation-order test.
 * @return {!Object}
 */
function loadClassifier() {
  const ns = {};
  const sandbox = {
    goog: {provide() {}, require() {}},
    funwithactivity: {dto: {}, features: {recommendations: {}}},
  };
  vm.createContext(sandbox);
  for (const f of ['recommendation.js', 'provider-status.js',
    'recommendations-response.js']) {
    vm.runInContext(fs.readFileSync(path.join(DTO_DIR, f), 'utf8'), sandbox, f);
  }
  vm.runInContext(
      fs.readFileSync(path.join(__dirname,
          '../../src/features/recommendations/provider-status-presentation.js'),
      'utf8'),
      sandbox, 'provider-status-presentation.js');

  ns.ProviderStatus = sandbox.funwithactivity.dto.ProviderStatus;
  ns.classify = sandbox.funwithactivity.features.recommendations.classify;
  ns.shortReason = sandbox.funwithactivity.features.recommendations.shortReason;
  return ns;
}

module.exports = {loadClosureDtos, loadClassifier};
