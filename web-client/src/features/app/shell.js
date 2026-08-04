goog.provide('funwithactivity.app.Shell');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.app.Router');
goog.require('funwithactivity.pages.shell');
goog.require('funwithactivity.profile.ProfileComponent');
goog.require('funwithactivity.charts.ChartsComponent');
goog.require('funwithactivity.recs.RecDetailComponent');
goog.require('funwithactivity.recs.RecsComponent');
goog.require('funwithactivity.render');
goog.require('funwithactivity.sources.AddSourceComponent');
goog.require('funwithactivity.sources.SourceDetailComponent');
goog.require('funwithactivity.sources.SourcesComponent');
goog.require('goog.Disposable');
goog.require('goog.dom');
goog.require('goog.events');
goog.require('goog.ui.Component');
goog.require('goog.ui.Tab');
goog.require('goog.ui.TabBar');


/**
 * Application shell: owns the Router and the shared AppState, renders the
 * three-tab header once (as a real goog.ui.TabBar, not hand-authored
 * anchors — see decorate() and buildTabBar_), and — on every route
 * change — disposes whatever screen was mounted and constructs the one
 * the new route names.
 *
 * NOT a goog.ui.Component itself: it decorates a document that
 * funwithactivity.Main already rendered (via funwithactivity.render.element)
 * rather than rendering itself, so goog.Disposable is the right base — it
 * needs disposal bookkeeping (event keys, the tab bar, the current screen)
 * but no DOM lifecycle of its own.
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

  /**
   * Route token of the currently mounted screen, so mountScreen_ can skip a
   * redundant remount. See the note there.
   * @private {?string}
   */
  this.currentRoute_ = null;

  /**
   * Owned and disposed by Shell (see disposeInternal): built once in
   * decorate(), holding one goog.ui.Tab child per entry in TAB_DEFS_.
   * Disposing the TabBar disposes its Tab children too — goog.ui.Component
   * disposes every child added via addChild() — so there is nothing extra
   * to tear down for the tabs themselves.
   * @private {?goog.ui.TabBar}
   */
  this.tabBar_ = null;

  /**
   * Route token (TAB_DEFS_[i].route) -> the goog.ui.Tab built for it, so
   * markActiveTab_ can find which Tab to select without a linear scan of
   * the TabBar's children on every navigation.
   * @private {!Object<string, !goog.ui.Tab>}
   */
  this.tabsByRoute_ = {};

  /** @private {?goog.events.Key} */
  this.routeChangedKey_ = null;

  /** @private {?goog.events.Key} */
  this.tabActionKey_ = null;
};
goog.inherits(funwithactivity.app.Shell, goog.Disposable);


/**
 * The three tabs, in display order. `path` is what gets passed to
 * router.go() on a genuine user click (see handleTabAction_); `route` is
 * the normalized token markActiveTab_ matches against to decide which tab
 * to visually select.
 * @const {!Array<{route: string, path: string, label: string}>}
 * @private
 */
funwithactivity.app.Shell.TAB_DEFS_ = [
  {route: 'recs', path: '/recs', label: 'Recommendations'},
  {route: 'sources', path: '/sources', label: 'Sources'},
  // Charts sits between Sources and Profile: it and Sources are both
  // read-only views of what the system knows, while Profile is where
  // things change. Inserting rather than appending shifts Profile from
  // index 2 to 3 — safe here because tabsByRoute_ is keyed by route, not
  // position, but that had to be checked rather than assumed.
  {route: 'charts', path: '/charts', label: 'Charts'},
  {route: 'profile', path: '/profile', label: 'Profile'},
];


/** @return {!funwithactivity.app.Router} */
funwithactivity.app.Shell.prototype.getRouter = function() {
  return this.router_;
};


/**
 * Builds the tab bar and mounts the screen for the current URL. Does not
 * start the router — funwithactivity.Main calls router.start() itself,
 * after decorate(), so the first ROUTE_CHANGED (if any fires on start)
 * lands on an already-listening Shell.
 */
funwithactivity.app.Shell.prototype.decorate = function() {
  this.routeChangedKey_ = goog.events.listen(this.router_,
      funwithactivity.app.Router.ROUTE_CHANGED, this.handleRouteChanged_,
      false, this);

  this.buildTabBar_();
  this.handleRouteChanged_();
};


/**
 * Builds a real goog.ui.TabBar with one goog.ui.Tab child per TAB_DEFS_
 * entry and renders it into `#fwa-tabs` (an empty mount div — see
 * ui-soy/pages/shell.soy — decorated rather than hand-authoring the
 * `.goog-tab`/`.goog-tab-bar` DOM: same reasoning as ProfileComponent's
 * Select widgets, applied to the single most visible control in the app).
 *
 * Routing is wired to Component.EventType.ACTION, not SELECT: ACTION
 * fires only on a genuine user click or keyboard activation (see
 * goog.ui.Control#performActionInternal), whereas SELECT also fires from
 * a programmatic setSelectedTab() call — which markActiveTab_ makes on
 * every route change, including ones that originated from a tab click
 * itself. Wiring routing to SELECT would re-invoke router.go() for the
 * path the router just navigated to; ACTION does not have that problem,
 * so no re-entrancy guard is needed here at all.
 * @private
 */
funwithactivity.app.Shell.prototype.buildTabBar_ = function() {
  this.tabBar_ = new goog.ui.TabBar();

  funwithactivity.app.Shell.TAB_DEFS_.forEach(function(def) {
    const tab = new goog.ui.Tab(def.label);
    tab.setModel(def.path);
    this.tabBar_.addChild(tab, true);
    this.tabsByRoute_[def.route] = tab;
  }, this);

  const mount = goog.dom.getElement('fwa-tabs');
  if (mount) this.tabBar_.render(mount);

  this.tabActionKey_ = goog.events.listen(this.tabBar_,
      goog.ui.Component.EventType.ACTION, this.handleTabAction_, false,
      this);
};


/**
 * @param {!goog.events.Event} e
 * @private
 */
funwithactivity.app.Shell.prototype.handleTabAction_ = function(e) {
  const tab = /** @type {!goog.ui.Tab} */ (e.target);
  const path = /** @type {string} */ (tab.getModel());
  if (path) this.router_.go(path);
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
  // Remounting the route that is already mounted is never useful, and it is
  // actively harmful: it disposes a live screen and builds a replacement,
  // which for Recs means a second identical fetch. That happens on boot —
  // decorate() mounts the initial route, then Html5History.setEnabled(true)
  // fires NAVIGATE for the same path — so without this guard every cold
  // load issued two requests to the vendors.
  if (this.currentRoute_ === route && this.currentScreen_) return;
  this.currentRoute_ = route;

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
 * Screen construction is a switch on the route token, plus a prefix check
 * for source detail routes (`sources/<name>` — see Router.normalize,
 * which is what produces that token shape from `/sources/<name>`).
 * @param {string} route
 * @return {!goog.ui.Component}
 * @private
 */
funwithactivity.app.Shell.prototype.createScreen_ = function(route) {
  if (route.indexOf('sources/') === 0) {
    const name = route.substring('sources/'.length);
    return new funwithactivity.sources.SourceDetailComponent(name);
  }
  if (route.indexOf('recs/') === 0) {
    const title = route.substring('recs/'.length);
    return new funwithactivity.recs.RecDetailComponent(title);
  }
  switch (route) {
    case 'sources':
      return new funwithactivity.sources.SourcesComponent(
          this.state_, this.router_);
    case 'add-source':
      return new funwithactivity.sources.AddSourceComponent(this.router_);
    case 'charts':
      return new funwithactivity.charts.ChartsComponent(this.state_);
    case 'profile':
      return new funwithactivity.profile.ProfileComponent(this.state_);
    default:
      return new funwithactivity.recs.RecsComponent(this.state_, this.router_);
  }
};


/**
 * Selects the tab that corresponds to `route`, including the two route
 * shapes that have no tab of their own: 'add-source' (reached from the
 * Sources screen's `+` button) and any `sources/<name>` detail route
 * (reached by drilling into a row) both keep the Sources tab highlighted,
 * since both are conceptually "still in Sources".
 *
 * goog.ui.Control#setSelected (which TabBar#setSelectedTab calls
 * internally) already no-ops when the target is already selected, so
 * calling this on every route change — even ones that didn't touch tab
 * selection — is safe and never dispatches a redundant SELECT.
 * @param {string} route
 * @private
 */
funwithactivity.app.Shell.prototype.markActiveTab_ = function(route) {
  if (!this.tabBar_) return;
  let activeRoute = route;
  if (route === 'add-source' || route.indexOf('sources/') === 0) {
    activeRoute = 'sources';
  } else if (route.indexOf('recs/') === 0) {
    activeRoute = 'recs';
  }
  const tab = this.tabsByRoute_[activeRoute] || this.tabsByRoute_['recs'];
  if (tab) this.tabBar_.setSelectedTab(tab);
};


/** @override */
funwithactivity.app.Shell.prototype.disposeInternal = function() {
  if (this.routeChangedKey_) {
    goog.events.unlistenByKey(this.routeChangedKey_);
    this.routeChangedKey_ = null;
  }
  if (this.tabActionKey_) {
    goog.events.unlistenByKey(this.tabActionKey_);
    this.tabActionKey_ = null;
  }
  if (this.tabBar_) {
    // Disposes every goog.ui.Tab added via addChild() in buildTabBar_ too.
    this.tabBar_.dispose();
    this.tabBar_ = null;
  }
  this.tabsByRoute_ = {};
  if (this.currentScreen_) {
    this.currentScreen_.dispose();
    this.currentScreen_ = null;
  }
  funwithactivity.app.Shell.base(this, 'disposeInternal');
};
