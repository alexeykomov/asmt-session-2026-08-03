goog.provide('funwithactivity.Main');

goog.require('funwithactivity.app.Shell');
goog.require('funwithactivity.pages.shell');
goog.require('funwithactivity.render');
goog.require('goog.dom');

/**
 * Entry point. Instantiated and run at module scope so ADVANCED dead-code
 * elimination cannot strip the methods — the same trap cyberfight documents
 * for its Loader.
 *
 * There is no SSR in this project: web-client/public/index.html is a
 * minimal static shell (doctype, head, stylesheet link, an empty #app
 * mount element, bundle script tag). This class renders the app shell
 * client-side by invoking the compiled Soy template function directly,
 * then hands off to funwithactivity.app.Shell, which owns routing and
 * mounts exactly one screen at a time into the shell's #screen element.
 *
 * Previously this rendered funwithactivity.pages.recommendations.page
 * directly into #app and bound
 * funwithactivity.features.recommendations.Controller against it — the
 * single-screen predecessor to the three-tab shell built here. That
 * template and controller are unreferenced now but deliberately left in
 * place; Task 8 removes them once the Recs/Sources/Profile screens
 * (Tasks 5-7) genuinely replace what they did.
 * @constructor
 */
funwithactivity.Main = function() {
  /** @private @const */
  this.shell_ = new funwithactivity.app.Shell();
};

/**
 * Renders the shell page into the #app mount element, decorates it (which
 * binds the tab bar and mounts the screen for the current URL), then
 * starts the router so subsequent navigations — clicks and back/forward —
 * are handled.
 */
funwithactivity.Main.prototype.run = function() {
  const mount = goog.dom.getElement('app');
  if (!mount) return;
  funwithactivity.render.element(
      mount, funwithactivity.pages.shell.page, {});
  this.shell_.decorate();
  this.shell_.getRouter().start();
};

new funwithactivity.Main().run();
