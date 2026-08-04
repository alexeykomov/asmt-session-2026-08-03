goog.provide('funwithactivity.app.Router');

goog.require('goog.events');
goog.require('goog.events.EventTarget');
goog.require('goog.history.EventType');
goog.require('goog.history.Html5History');


/**
 * Path-based routing over goog.history.Html5History.
 *
 * Paths rather than hashes: these are real URLs a viewer can be sent, and
 * web-proxy serves index.html for each of them (see web-proxy/src/server.js).
 * Hash routing would avoid that server change but produces URLs that read
 * as a toy.
 * @constructor
 * @extends {goog.events.EventTarget}
 */
funwithactivity.app.Router = function() {
  funwithactivity.app.Router.base(this, 'constructor');

  /** @private @const */
  this.history_ = new goog.history.Html5History();
  this.history_.setUseFragment(false);
  this.history_.setPathPrefix('');

  goog.events.listen(this.history_, goog.history.EventType.NAVIGATE,
      this.handleNavigate_, false, this);
};
goog.inherits(funwithactivity.app.Router, goog.events.EventTarget);


/** @const {string} */
funwithactivity.app.Router.ROUTE_CHANGED = 'route-changed';


/**
 * Matches `/sources/<name>` for any name other than literal 'add' (that
 * exact path is handled as its own case in normalize(), below, and never
 * reaches this pattern). `[^/]+` deliberately does not allow a further
 * path segment — `/sources/foo/bar` falls through to the 'recs' default
 * like any other unrecognized path, rather than silently truncating to
 * 'foo'.
 * @const {!RegExp}
 * @private
 */
funwithactivity.app.Router.SOURCE_DETAIL_RE_ = /^\/sources\/([^/]+)$/;


/**
 * Matches `/recs/<title>` — the recommendation detail route. Same
 * single-segment rule as SOURCE_DETAIL_RE_: `/recs/a/b` is not a detail
 * route and falls through to the 'recs' default rather than truncating.
 *
 * The key is the recommendation's title, URL-encoded. Titles are safe as
 * keys because the server deduplicates by exact title before ranking
 * (app-server/internal/ranking/dedupe.go), so a title identifies exactly
 * one row of a response — and unlike a list index, a title still refers to
 * the same recommendation after goog.ui.TableSorter re-sorts the table.
 * @const {!RegExp}
 * @private
 */
funwithactivity.app.Router.REC_DETAIL_RE_ = /^\/recs\/([^/]+)$/;


/**
 * Maps a URL path to a route token. Unknown paths fall back to 'recs'
 * rather than rendering nothing — a blank screen on a typo'd deep link is
 * worse than a sensible default.
 *
 * `/sources/<name>` (any name but 'add') maps to the token
 * `'sources/' + name`, carrying the provider name straight through so
 * Shell.prototype.createScreen_ can mount the detail screen for it without
 * a second lookup — see that method's `route.indexOf('sources/') === 0`
 * branch.
 * @param {string} path
 * @return {string}
 */
funwithactivity.app.Router.normalize = function(path) {
  const clean = String(path || '').replace(/\/+$/, '');
  switch (clean) {
    case '/sources/add': return 'add-source';
    case '/sources': return 'sources';
    case '/profile': return 'profile';
    case '/recs': return 'recs';
    case '/charts': return 'charts';
    default: {
      const match = funwithactivity.app.Router.SOURCE_DETAIL_RE_.exec(clean);
      if (match) {
        const name = decodeURIComponent(match[1]);
        if (name) return 'sources/' + name;
      }
      const recMatch = funwithactivity.app.Router.REC_DETAIL_RE_.exec(clean);
      if (recMatch) {
        const title = decodeURIComponent(recMatch[1]);
        if (title) return 'recs/' + title;
      }
      return 'recs';
    }
  }
};


/** @return {string} */
funwithactivity.app.Router.prototype.getRoute = function() {
  return funwithactivity.app.Router.normalize(window.location.pathname);
};


/** @param {string} path */
funwithactivity.app.Router.prototype.go = function(path) {
  this.history_.setToken(path);
};


/** Starts dispatching navigation events. */
funwithactivity.app.Router.prototype.start = function() {
  this.history_.setEnabled(true);
};


/** @private */
funwithactivity.app.Router.prototype.handleNavigate_ = function() {
  this.dispatchEvent(funwithactivity.app.Router.ROUTE_CHANGED);
};
