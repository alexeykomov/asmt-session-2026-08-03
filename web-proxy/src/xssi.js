'use strict';

/**
 * Anti-XSSI prefix prepended to every JSON response under /api/*.
 *
 * This API's wire format (see dto.js) is a bare JSON array — the classic
 * XSSI vector: a bare array literal is valid JavaScript, so it can be
 * pulled cross-origin via a <script src> tag and its contents read back
 * through constructor/prototype tricks, bypassing same-origin JSON
 * protections that only work for object literals. Prefixing the body
 * with this string makes it invalid JavaScript (a syntax error) while
 * remaining trivially stripped and parsed by a client that knows the
 * convention. Same prefix Gmail has used for years.
 *
 * Mirrors the reference implementation's convention
 * (cyberfight.core.ApiClient.XSSI_PREFIX in
 * cyberfight/web-client/src/core/api/api-client.js) so both this
 * project's web-client (funwithactivity.features.recommendations.api,
 * via goog.net.XhrIo's built-in prefix stripping) and web-proxy agree on
 * the same literal string.
 * @const {string}
 */
const XSSI_PREFIX = ")]}'\n";

/**
 * Express middleware that makes `res.json()` prepend XSSI_PREFIX for the
 * remainder of this request — including error responses sent later in the
 * chain (e.g. api-routes.js's 400/502 paths, and server.js's malformed-JSON
 * handler for a request under /api/*). A defense that only covers the
 * success path is not a defense: the reference client strips the prefix on
 * the error path too, so the two sides must agree there as well.
 *
 * Mount with `app.use('/api', xssiJson)` so only /api/* responses carry the
 * prefix — /health and the SPA shell must stay plain, unprefixed
 * responses for tooling (health probes, curl) that doesn't know this
 * convention.
 */
function xssiJson(_req, res, next) {
  res.json = function json(body) {
    res.type('application/json');
    return res.send(XSSI_PREFIX + JSON.stringify(body));
  };
  next();
}

module.exports = { XSSI_PREFIX, xssiJson };
