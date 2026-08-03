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
 * Maps a URL path to a route token. Unknown paths fall back to 'recs'
 * rather than rendering nothing — a blank screen on a typo'd deep link is
 * worse than a sensible default.
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
    default: return 'recs';
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
