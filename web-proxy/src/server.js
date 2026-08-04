'use strict';

const crypto = require('crypto');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const path = require('path');

const apiRouter = require('./routes/api-routes');
const { xssiJson } = require('./xssi');

function requestContext(req, res, next) {
  req.requestId = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('x-request-id', req.requestId);
  req.log = {
    info: (msg, fields) =>
      console.log(JSON.stringify({ level: 'info', request_id: req.requestId, msg, ...fields })),
    error: (msg, fields) =>
      console.error(JSON.stringify({ level: 'error', request_id: req.requestId, msg, ...fields })),
  };
  next();
}

function buildApp({ getRecommendations, getHealthCharts }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(requestContext);
  app.use(helmet());
  // Mounted before the body parser (not just before apiRouter) so the
  // res.json() patch is already active if express.json() itself throws a
  // SyntaxError on malformed input — that error is caught by the handler
  // at the bottom of this file, and its response must carry the prefix
  // too. Path-scoped to /api so /health and the SPA shell stay plain.
  app.use('/api', xssiJson);
  app.use(express.json({ limit: '64kb' }));
  app.use(rateLimit({
    windowMs: 60 * 1000,
    max: 60,
    standardHeaders: true,
    legacyHeaders: false,
  }));

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  // web-client is a fully client-rendered SPA — there is no SSR and no
  // page router. web-client/public/ is its build output: a static
  // index.html shell, the ADVANCED-compiled JS bundle, and main.css —
  // scripts/build-css.js concatenates the stock Closure UI stylesheets
  // with web-client/css/main.css into public/main.css. public/ is
  // mounted at `/static` (and at `/` for the shell itself) *before*
  // web-client/css so the generated main.css wins over the hand-written
  // source file of the same name; css/ stays mounted after as a
  // fallback for any other asset that isn't part of the build output.
  app.use('/static', express.static(path.join(__dirname, '..', '..', 'web-client', 'public')));
  app.use('/static', express.static(path.join(__dirname, '..', '..', 'web-client', 'css')));
  app.use(express.static(path.join(__dirname, '..', '..', 'web-client', 'public')));

  app.use(apiRouter({ getRecommendations, getHealthCharts }));

  // web-client is a client-side-routed SPA (funwithactivity.app.Router,
  // Task 4): the browser can be pointed straight at /profile — a fresh
  // load, a bookmark, or an F5 reload — and there is no server-side
  // handler for that path other than this one. Without it, Express's
  // default 404 fires here and the tab "works" only until the user
  // reloads it.
  //
  // Match this explicit list of known SPA routes rather than a wildcard:
  // a blanket catch-all would swallow genuine 404s (e.g. a typo'd asset
  // path) and turn them into a confusing 200 HTML response instead of a
  // debuggable 404. Keep this list in sync with
  // funwithactivity.app.Router.normalize's routes.
  const SPA_ROUTES = new Set(['/', '/recs', '/sources', '/sources/add', '/trends', '/profile']);
  app.get(Array.from(SPA_ROUTES), (_req, res) => {
    res.sendFile(path.join(__dirname, '..', '..', 'web-client', 'public', 'index.html'));
  });

  // Source detail lives at /sources/<name>, where <name> is a provider name
  // rather than a fixed path, so it cannot go in the static list above. It
  // is still matched by an explicit pattern rather than a catch-all, for the
  // same reason the list exists: a blanket handler would answer 200 with
  // HTML for a mistyped asset path and turn a debuggable 404 into a
  // confusing one.
  //
  // Without this, the tab bar and in-app navigation work fine while F5,
  // a bookmark, or a shared link on a source detail page all 404 — a
  // failure that only appears once someone reloads, which is exactly when
  // a reviewer tries it.
  app.get('/sources/:name([A-Za-z0-9_-]+)', (_req, res) => {
    res.sendFile(path.join(__dirname, '..', '..', 'web-client', 'public', 'index.html'));
  });

  // Recommendation detail lives at /recs/<title>, same deep-link reasoning
  // as source detail above. The pattern is deliberately looser than the
  // source one: a provider name is a registry key, but a title is vendor
  // prose — "Don't eat carbs!" — so it arrives percent-encoded and can
  // contain spaces, punctuation and non-ASCII. `[^/]+` still refuses a
  // second path segment, so this stays an explicit route rather than the
  // catch-all the comment above argues against.
  app.get(/^\/recs\/[^/]+$/, (_req, res) => {
    res.sendFile(path.join(__dirname, '..', '..', 'web-client', 'public', 'index.html'));
  });

  // express.json() throws a SyntaxError on an unparseable body. Without this
  // handler that falls through to Express's default error handler, which —
  // absent NODE_ENV=production — includes the stack trace in the response
  // body. Catch it explicitly so malformed input never leaks internals,
  // regardless of how NODE_ENV is set in any given environment.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof SyntaxError && 'body' in err) {
      return res.status(400).json({ error: 'invalid_json' });
    }
    return next(err);
  });

  return app;
}

if (require.main === module) {
  const { getRecommendations, getHealthCharts } = require('./grpc-client');
  const port = parseInt(process.env.PORT || '3000', 10);

  const app = buildApp({ getRecommendations, getHealthCharts });
  app.listen(port, () =>
    console.log(JSON.stringify({ level: 'info', msg: 'web-proxy listening', port })),
  );
}

module.exports = { buildApp };
