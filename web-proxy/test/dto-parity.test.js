'use strict';

const fs = require('fs');
const path = require('path');
const { expect } = require('chai');
const { SLOTS } = require('../src/dto');

/**
 * Extracts a Fields enum from a Closure DTO source file by parsing it, so the
 * test reads the same definition the browser compiles rather than a copy.
 */
function readFieldsEnum(file) {
  const src = fs.readFileSync(
      path.join(__dirname, '../../api/dto', file), 'utf8');
  const block = src.match(/Fields = \{([^}]+)\}/);
  if (!block) throw new Error('no Fields enum in ' + file);
  const out = {};
  for (const line of block[1].split('\n')) {
    const m = line.match(/([A-Z_]+):\s*(\d+)/);
    if (m) out[m[1]] = Number(m[2]);
  }
  return out;
}

describe('DTO slot parity between web-proxy and api/dto', () => {
  it('Recommendation slots match', () => {
    expect(SLOTS.Recommendation).to.deep.equal(
        readFieldsEnum('recommendation.js'));
  });

  it('ProviderStatus slots match', () => {
    expect(SLOTS.ProviderStatus).to.deep.equal(
        readFieldsEnum('provider-status.js'));
  });

  it('RecommendationsResponse slots match', () => {
    expect(SLOTS.RecommendationsResponse).to.deep.equal(
        readFieldsEnum('recommendations-response.js'));
  });
});
