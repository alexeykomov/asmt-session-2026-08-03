goog.provide('funwithactivity.Main');

goog.require('funwithactivity.features.recommendations.Controller');
goog.require('funwithactivity.pages.recommendations');
goog.require('funwithactivity.render');
goog.require('goog.dom');

/**
 * Entry point. Instantiated and run at module scope so ADVANCED dead-code
 * elimination cannot strip the methods — the same trap cyberfight documents
 * for its Loader.
 *
 * There is no SSR in this project: web-client/public/index.html is a
 * minimal static shell (doctype, head, stylesheet link, an empty #app
 * mount element, bundle script tag). This class renders the entire page
 * client-side by invoking the compiled Soy template function directly,
 * then binds the interactive controller against the DOM it just created.
 * @constructor
 */
funwithactivity.Main = function() {
  /** @private @const */
  this.recommendations_ = new funwithactivity.features.recommendations.Controller();
};

/**
 * Renders the recommendations page into the #app mount element and binds
 * the form/table/banner controller against the freshly rendered DOM. First
 * render ships with an empty recommendations list — the form drives all
 * subsequent updates via XHR, so no upstream call is needed up front.
 */
funwithactivity.Main.prototype.run = function() {
  const mount = goog.dom.getElement('app');
  if (!mount) return;
  funwithactivity.render.element(
      mount, funwithactivity.pages.recommendations.page,
      {recommendations: []});
  this.recommendations_.decorate();
};

new funwithactivity.Main().run();
