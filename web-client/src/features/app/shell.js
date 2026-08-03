goog.provide('funwithactivity.app.Shell');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.app.Router');
goog.require('funwithactivity.pages.shell');
goog.require('funwithactivity.render');
goog.require('goog.Disposable');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.dom.classlist');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.Component');


/**
 * Application shell: owns the Router and the shared AppState, renders the
 * three-tab header once, and — on every route change — disposes whatever
 * screen was mounted and constructs the one the new route names.
 *
 * NOT a goog.ui.Component itself: it decorates a document that
 * funwithactivity.Main already rendered (via funwithactivity.render.element)
 * rather than rendering itself, so goog.Disposable is the right base — it
 * needs disposal bookkeeping (event keys, the current screen) but no DOM
 * lifecycle of its own.
 * @constructor
 * @extends {goog.Disposable}
 */
funwithactivity.app.Shell = function() {
  funwithactivity.app.Shell.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.AppState} */
  this.state_ = new funwithactivity.app.AppState();

  /** @private @const {!funwithactivity.app.Router} */
  this.router_ = new funwithactivity.app.Router();

  /**
   * The currently mounted screen, or null before the first route change.
   * Disposed and replaced wholesale on every navigation — see mountScreen_.
   * @private {?goog.ui.Component}
   */
  this.currentScreen_ = null;

  /** @private {?goog.events.Key} */
  this.routeChangedKey_ = null;

  /** @private {?goog.events.Key} */
  this.tabClickKey_ = null;
};
goog.inherits(funwithactivity.app.Shell, goog.Disposable);


/**
 * Maps a normalized route token to the id of the tab anchor that should be
 * marked active for it. 'add-source' has no tab of its own — it is reached
 * from the Sources screen, so the Sources tab stays highlighted.
 * @const {!Object<string, string>}
 * @private
 */
funwithactivity.app.Shell.TAB_ID_BY_ROUTE_ = {
  'recs': 'tab-recs',
  'sources': 'tab-sources',
  'add-source': 'tab-sources',
  'profile': 'tab-profile',
};


/** @return {!funwithactivity.app.Router} */
funwithactivity.app.Shell.prototype.getRouter = function() {
  return this.router_;
};


/**
 * Binds the tab bar and mounts the screen for the current URL. Does not
 * start the router — funwithactivity.Main calls router.start() itself,
 * after decorate(), so the first ROUTE_CHANGED (if any fires on start)
 * lands on an already-listening Shell.
 */
funwithactivity.app.Shell.prototype.decorate = function() {
  this.routeChangedKey_ = goog.events.listen(this.router_,
      funwithactivity.app.Router.ROUTE_CHANGED, this.handleRouteChanged_,
      false, this);

  const tabs = goog.dom.getElement('fwa-tabs');
  if (tabs) {
    this.tabClickKey_ = goog.events.listen(
        tabs, goog.events.EventType.CLICK, this.handleTabClick_, false, this);
  }

  this.handleRouteChanged_();
};


/**
 * Intercepts clicks on a `.fwa-tab` anchor and routes them through
 * router.go() instead of letting the browser perform a full navigation —
 * that full navigation would work (web-proxy serves index.html for every
 * tab route too), but it would reload the whole app instead of just
 * swapping the mounted screen.
 * @param {!goog.events.BrowserEvent} e
 * @private
 */
funwithactivity.app.Shell.prototype.handleTabClick_ = function(e) {
  const anchor = goog.dom.getAncestor(/** @type {?Node} */ (e.target),
      function(node) {
        return node.nodeType == 1 &&
            goog.dom.classlist.contains(/** @type {!Element} */ (node),
                'fwa-tab');
      }, true);
  if (!anchor) return;
  e.preventDefault();
  this.router_.go(anchor.getAttribute('href'));
};


/** @private */
funwithactivity.app.Shell.prototype.handleRouteChanged_ = function() {
  const route = this.router_.getRoute();
  this.mountScreen_(route);
  this.markActiveTab_(route);
};


/**
 * Disposes the outgoing screen and mounts the one the route names. Not
 * optional: each screen owns Closure widgets and listeners, and leaking
 * them across navigations is what makes a tab bar feel progressively
 * broken.
 * @param {string} route
 * @private
 */
funwithactivity.app.Shell.prototype.mountScreen_ = function(route) {
  if (this.currentScreen_) {
    this.currentScreen_.dispose();
    this.currentScreen_ = null;
  }

  const mount = goog.dom.getElement('screen');
  if (!mount) return;
  goog.dom.removeChildren(mount);

  const screen = this.createScreen_(route);
  screen.render(mount);
  this.currentScreen_ = screen;
};


/**
 * Screen construction is a switch on the route token. Tasks 5-7 have not
 * landed yet, so every case below mounts a
 * funwithactivity.app.PlaceholderScreen_ instead of the real screen
 * component — goog.require'ing funwithactivity.recs.RecsComponent (etc.)
 * before it exists would fail PRUNE dependency resolution and break the
 * build for everyone until all three land simultaneously. Replace each
 * case with the real component as its task lands; the intended final shape
 * (per the Task 4 brief) is:
 *
 *   case 'sources':
 *     return new funwithactivity.sources.SourcesComponent(this.router_);
 *   case 'add-source':
 *     return new funwithactivity.sources.AddSourceComponent(this.router_);
 *   case 'profile':
 *     return new funwithactivity.profile.ProfileComponent(this.state_);
 *   default:
 *     return new funwithactivity.recs.RecsComponent(this.state_);
 *
 * @param {string} route
 * @return {!goog.ui.Component}
 * @private
 */
funwithactivity.app.Shell.prototype.createScreen_ = function(route) {
  switch (route) {
    case 'sources':
      return new funwithactivity.app.PlaceholderScreen_('Sources',
          'Task 7 mounts funwithactivity.sources.SourcesComponent here.');
    case 'add-source':
      return new funwithactivity.app.PlaceholderScreen_('Add Source',
          'Task 7 mounts funwithactivity.sources.AddSourceComponent here.');
    case 'profile':
      return new funwithactivity.app.PlaceholderScreen_('Profile',
          'Task 6 mounts funwithactivity.profile.ProfileComponent here.');
    default:
      return new funwithactivity.app.PlaceholderScreen_('Recommendations',
          'Task 5 mounts funwithactivity.recs.RecsComponent here.');
  }
};


/**
 * @param {string} route
 * @private
 */
funwithactivity.app.Shell.prototype.markActiveTab_ = function(route) {
  const activeId = funwithactivity.app.Shell.TAB_ID_BY_ROUTE_[route] ||
      'tab-recs';
  const tabs = goog.dom.getElementsByClass('fwa-tab');
  for (let i = 0; i < tabs.length; i++) {
    goog.dom.classlist.enable(
        tabs[i], 'fwa-tab-active', tabs[i].id == activeId);
  }
};


/** @override */
funwithactivity.app.Shell.prototype.disposeInternal = function() {
  if (this.routeChangedKey_) {
    goog.events.unlistenByKey(this.routeChangedKey_);
    this.routeChangedKey_ = null;
  }
  if (this.tabClickKey_) {
    goog.events.unlistenByKey(this.tabClickKey_);
    this.tabClickKey_ = null;
  }
  if (this.currentScreen_) {
    this.currentScreen_.dispose();
    this.currentScreen_ = null;
  }
  funwithactivity.app.Shell.base(this, 'disposeInternal');
};


/**
 * Temporary stand-in for the real screen components Tasks 5-7 have not
 * built yet (see the doc on createScreen_ above). Renders a labeled block
 * into the mount element so each route is visibly, distinguishably
 * reachable during Task 4's own browser verification — a permanently blank
 * `#screen` would make it impossible to tell "routing works, screen is
 * unbuilt" apart from "routing is broken".
 *
 * Delete this class, and every createScreen_ case that constructs it, once
 * the real components exist.
 * @param {string} title
 * @param {string} note
 * @constructor
 * @extends {goog.ui.Component}
 * @private
 */
funwithactivity.app.PlaceholderScreen_ = function(title, note) {
  funwithactivity.app.PlaceholderScreen_.base(this, 'constructor');

  /** @private @const {string} */
  this.title_ = title;

  /** @private @const {string} */
  this.note_ = note;
};
goog.inherits(funwithactivity.app.PlaceholderScreen_, goog.ui.Component);


/** @override */
funwithactivity.app.PlaceholderScreen_.prototype.createDom = function() {
  const heading = goog.dom.createDom(
      goog.dom.TagName.H2, null, this.title_);
  const note = goog.dom.createDom(
      goog.dom.TagName.P, {'class': 'fwa-placeholder-note'}, this.note_);
  this.setElementInternal(goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-placeholder'},
      heading, note));
};
