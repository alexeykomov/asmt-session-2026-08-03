goog.provide('funwithactivity.sources.AddSourceComponent');

goog.require('funwithactivity.app.Router');
goog.require('funwithactivity.components.addSourceForm');
goog.require('funwithactivity.render');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.ui.Component');
goog.require('goog.ui.Menu');
goog.require('goog.ui.MenuItem');
goog.require('goog.ui.Select');


/**
 * Stubbed add-source form, reached from the Sources screen's `+` button.
 *
 * Submitting never calls anything: this proof of concept has no way to
 * add a real provider at runtime. `service1` and `service2` each speak a
 * different request shape, item schema and error envelope (see
 * app-server/internal/providers/service1.go, service2.go, envelope.go) —
 * adding a source for real means implementing the Provider interface,
 * registering it, and adding a table test, not filling in a URL. Instead
 * of accepting the form and silently discarding it, submitting swaps the
 * form for EXPLANATION_ so the seam is stated, not implied.
 *
 * The auth token field is deliberately NEVER read anywhere in this
 * class — not into AppState, not into localStorage, not into a log. The
 * field exists only to make the extensibility story concrete (a real
 * provider would need one); this repo is public, and storing a
 * credential for a source that can never actually be called is liability
 * with no benefit.
 * @param {!funwithactivity.app.Router} router
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.sources.AddSourceComponent = function(router) {
  funwithactivity.sources.AddSourceComponent.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.Router} */
  this.router_ = router;

  /** @private {?goog.ui.Select} */
  this.typeSelect_ = null;

  /** @private {?goog.events.Key} */
  this.submitKey_ = null;
};
goog.inherits(funwithactivity.sources.AddSourceComponent, goog.ui.Component);


/**
 * Said plainly rather than left implied: adding a source at runtime is
 * not supported in this proof of concept.
 * @const {string}
 * @private
 */
funwithactivity.sources.AddSourceComponent.EXPLANATION_ =
    'Adding a source at runtime is not supported in this proof of ' +
    'concept. Each provider needs an adapter — service1 and service2 ' +
    'have different request shapes, item schemas and error envelopes — ' +
    'so a new source means implementing the Provider interface, ' +
    'registering it, and adding a table test. See ' +
    'docs/integrations/_template.md.';


/** @override */
funwithactivity.sources.AddSourceComponent.prototype.createDom = function() {
  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-add-source'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.addSourceForm.screen, {});
};


/** @override */
funwithactivity.sources.AddSourceComponent.prototype.enterDocument =
    function() {
  funwithactivity.sources.AddSourceComponent.base(this, 'enterDocument');

  // Built as a Menu/MenuItem tree in JS, then render()ed into the mount
  // div rather than decorating hand-authored menu markup — the same
  // choice ProfileComponent#bindFaultRow_ makes, for the same reason:
  // goog.ui.MenuButtonRenderer#decorate expects an exact nested DOM shape,
  // and getting that wrong by hand reproduces the "present but invisible"
  // failure this project has hit before.
  const menu = new goog.ui.Menu();
  menu.addItem(new goog.ui.MenuItem('REST', 'REST'));
  menu.addItem(new goog.ui.MenuItem('gRPC', 'gRPC'));
  this.typeSelect_ = new goog.ui.Select(null, menu);
  this.addChild(this.typeSelect_);
  const mount = goog.dom.getElement('add-source-type-mount');
  if (mount) {
    this.typeSelect_.render(mount);
    this.typeSelect_.setSelectedIndex(0);
  }

  const form = goog.dom.getElement('add-source-form');
  if (form) {
    this.submitKey_ = goog.events.listen(form,
        goog.events.EventType.SUBMIT, this.handleSubmit_, false, this);
  }
};


/**
 * @param {!goog.events.Event} e
 * @private
 */
funwithactivity.sources.AddSourceComponent.prototype.handleSubmit_ =
    function(e) {
  e.preventDefault();

  const nameEl = /** @type {?HTMLInputElement} */ (
      goog.dom.getElement('add-source-name'));
  const urlEl = /** @type {?HTMLInputElement} */ (
      goog.dom.getElement('add-source-url'));
  const name = nameEl ? nameEl.value.trim() : '';
  const url = urlEl ? urlEl.value.trim() : '';

  const errorEl = goog.dom.getElement('add-source-error');
  if (!name || !url) {
    // A validation failure must be visible, not a silent no-op — an empty
    // form that just does nothing on submit reads as broken.
    if (errorEl) errorEl.hidden = false;
    return;
  }
  if (errorEl) errorEl.hidden = true;

  this.showExplanation_();

  // Deliberately never reads #add-source-token's value — see this
  // constructor's doc for why. There is no code path in this class that
  // touches that field at all, which is the point.
};


/** @private */
funwithactivity.sources.AddSourceComponent.prototype.showExplanation_ =
    function() {
  const form = goog.dom.getElement('add-source-form');
  const explanation = goog.dom.getElement('add-source-explanation');
  if (form) form.hidden = true;
  if (explanation) {
    goog.dom.setTextContent(
        explanation, funwithactivity.sources.AddSourceComponent.EXPLANATION_);
    explanation.hidden = false;
  }
};


/** @override */
funwithactivity.sources.AddSourceComponent.prototype.disposeInternal =
    function() {
  if (this.submitKey_) {
    goog.events.unlistenByKey(this.submitKey_);
    this.submitKey_ = null;
  }
  this.typeSelect_ = null;
  // typeSelect_ was added as a child via addChild() above, so the base
  // class disposes the widget itself here.
  funwithactivity.sources.AddSourceComponent.base(this, 'disposeInternal');
};
