goog.provide('funwithactivity.render');

goog.require('goog.dom.safe');


/**
 * Renders a compiled Soy template's output into `element`, replacing its
 * existing content.
 *
 * This project does not use `goog.soy.renderElement`: the vendored,
 * patched Soy runtime at web-client/third_party/soy/soyutils_usegoog.js
 * deliberately drops the `goog.soy` module dependency (see the patch
 * notes at the top of that file), so template output is coerced to
 * `goog.html.SafeHtml` here directly via the sanitized content's own
 * `toSafeHtml()` and written through `goog.dom.safe.setInnerHtml` — the
 * same XSS-audit-friendly idiom `goog.soy.renderElement` itself uses
 * internally.
 *
 * @param {!Element} element
 * @param {function(?, ?=): !goog.soy.data.SanitizedContent} templateFn A
 *     compiled Soy template function of `kind="html"`.
 * @param {?} data The template's parameter object.
 */
funwithactivity.render.element = function(element, templateFn, data) {
  const output = templateFn(data, null);
  goog.dom.safe.setInnerHtml(element, output.toSafeHtml());
};
