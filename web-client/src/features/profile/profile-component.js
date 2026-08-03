goog.provide('funwithactivity.profile.ProfileComponent');

goog.require('funwithactivity.app.AppState');
goog.require('funwithactivity.components.profileScreen');
goog.require('funwithactivity.render');
goog.require('goog.date.Date');
goog.require('goog.dom');
goog.require('goog.dom.TagName');
goog.require('goog.events');
goog.require('goog.events.EventType');
goog.require('goog.i18n.DateTimeFormat');
goog.require('goog.i18n.DateTimeParse');
goog.require('goog.ui.Button');
goog.require('goog.ui.Checkbox');
goog.require('goog.ui.Component');
goog.require('goog.ui.DatePicker');
goog.require('goog.ui.InputDatePicker');
goog.require('goog.ui.Menu');
goog.require('goog.ui.MenuItem');
goog.require('goog.ui.Select');
goog.requireType('goog.ui.DatePickerEvent');
goog.requireType('goog.ui.PopupDatePicker');


/**
 * The closed set of fault modes web-proxy accepts (web-proxy/src/routes/
 * api-routes.js VALID_FAULT_MODES). Reproduced here rather than fetched:
 * the wire contract is fixed for Phase 1, and a client-side Select can
 * only offer choices that are actually valid to send.
 * @const {!Array<{value: string, label: string}>}
 * @private
 */
funwithactivity.profile.ProfileComponent.FAULT_MODES_ = [
  {value: 'error', label: 'Error'},
  {value: 'timeout', label: 'Timeout'},
  {value: 'malformed', label: 'Malformed'},
];


/**
 * The two providers the DEVELOPER section exposes a fault toggle for,
 * matching the ids profile-screen.soy renders (fault-service1,
 * fault-service2) and the provider keys app-server's stub registry and
 * web-proxy both key faults by.
 * @const {!Array<{provider: string, label: string}>}
 * @private
 */
funwithactivity.profile.ProfileComponent.FAULT_PROVIDERS_ = [
  {provider: 'service1', label: 'Service 1'},
  {provider: 'service2', label: 'Service 2'},
];


/**
 * Unambiguous, locale-independent pattern for the birth date input, shared
 * by the formatter (picker -> text) and parser (text -> picker). ISO order
 * (yyyy-MM-dd) rather than a locale-specific one avoids the demo ever
 * showing an ambiguous 03/04 that a presenter has to explain.
 * @const {string}
 * @private
 */
funwithactivity.profile.ProfileComponent.DATE_PATTERN_ = 'yyyy-MM-dd';


/**
 * Profile screen: MEASUREMENTS (height, weight, birth date) and DEVELOPER
 * (a fault toggle + mode per provider), both settings-table style. Every
 * edit writes straight through to the shared AppState, which is what sets
 * the dirty flag funwithactivity.recs.RecsComponent reads to decide
 * whether a tab switch back to Recs is worth a fetch.
 *
 * Constructed fresh on every navigation to /profile (funwithactivity.app.
 * Shell disposes and rebuilds the mounted screen on each route change —
 * see Shell.prototype.mountScreen_), so enterDocument() always seeds every
 * widget from the CURRENT AppState rather than assuming a blank slate;
 * otherwise tabbing away and back would visibly discard whatever the
 * presenter just entered.
 * @param {!funwithactivity.app.AppState} state
 * @constructor
 * @extends {goog.ui.Component}
 */
funwithactivity.profile.ProfileComponent = function(state) {
  funwithactivity.profile.ProfileComponent.base(this, 'constructor');

  /** @private @const {!funwithactivity.app.AppState} */
  this.state_ = state;

  /** @private {?Element} */
  this.heightInput_ = null;

  /** @private {?Element} */
  this.weightInput_ = null;

  /**
   * Unix seconds, or 0 for "not supplied". Tracked separately from the
   * native inputs (which have no equivalent widget) so commitMeasurements_
   * has a single source of truth for the value the InputDatePicker last
   * settled on, including the null/None case, which must produce exactly
   * 0 rather than a parsed 1970-01-01.
   * @private {number}
   */
  this.birthDateUnix_ = 0;

  /** @private {?goog.ui.InputDatePicker} */
  this.datePicker_ = null;

  /**
   * One goog.ui.Checkbox and one goog.ui.Select per fault provider, keyed
   * by provider id. Populated by bindFaultRow_.
   * @private {!Object<string, !goog.ui.Checkbox>}
   */
  this.faultCheckboxes_ = {};

  /** @private {!Object<string, !goog.ui.Select>} */
  this.faultSelects_ = {};

  /**
   * Native-DOM listener keys (height/weight inputs, the Clear button's
   * underlying click is a goog.ui.Button so it doesn't need one) plus the
   * InputDatePicker's popup-level date-change listener. Everything else
   * (checkboxes, selects) is a goog.ui.Control and gets its listeners torn
   * down for free when the widget itself is disposed via addChild.
   * @private @const {!Array<?goog.events.Key>}
   */
  this.eventKeys_ = [];
};
goog.inherits(funwithactivity.profile.ProfileComponent, goog.ui.Component);


/** @override */
funwithactivity.profile.ProfileComponent.prototype.createDom = function() {
  const el = goog.dom.createDom(
      goog.dom.TagName.DIV, {'class': 'fwa-screen-profile'});
  this.setElementInternal(el);
  funwithactivity.render.element(
      el, funwithactivity.components.profileScreen.screen, {});
};


/** @override */
funwithactivity.profile.ProfileComponent.prototype.enterDocument = function() {
  funwithactivity.profile.ProfileComponent.base(this, 'enterDocument');

  const measurements = this.state_.getMeasurements();
  this.birthDateUnix_ = measurements.birthDateUnix;

  this.bindMeasurementInputs_(measurements);
  this.bindBirthDate_(measurements.birthDateUnix);

  const faults = this.state_.getFaults();
  funwithactivity.profile.ProfileComponent.FAULT_PROVIDERS_.forEach(
      function(entry) {
        this.bindFaultRow_(entry.provider, faults[entry.provider] || null);
      }, this);
};


/**
 * Wires the two native number inputs and seeds them from the current
 * AppState. Native <input type="number"> rather than a Closure widget —
 * Closure has no numeric-input control, and goog.ui.LabelInput only
 * emulates the placeholder text HTML5 already provides on these.
 * @param {{heightCm: number, weightKg: number, birthDateUnix: number}}
 *     measurements
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.bindMeasurementInputs_ =
    function(measurements) {
  this.heightInput_ = goog.dom.getElement('profile-height');
  this.weightInput_ = goog.dom.getElement('profile-weight');

  if (this.heightInput_) {
    this.heightInput_.value =
        measurements.heightCm ? String(measurements.heightCm) : '';
    this.eventKeys_.push(goog.events.listen(this.heightInput_,
        goog.events.EventType.INPUT, this.handleMeasurementInput_, false,
        this));
  }
  if (this.weightInput_) {
    this.weightInput_.value =
        measurements.weightKg ? String(measurements.weightKg) : '';
    this.eventKeys_.push(goog.events.listen(this.weightInput_,
        goog.events.EventType.INPUT, this.handleMeasurementInput_, false,
        this));
  }
};


/** @private */
funwithactivity.profile.ProfileComponent.prototype.handleMeasurementInput_ =
    function() {
  this.commitMeasurements_();
};


/**
 * Decorates #profile-birth-date with a goog.ui.InputDatePicker and
 * #profile-birth-date-clear with a goog.ui.Button that clears it in one
 * click — the data-minimisation demo beat.
 *
 * Both the calendar's own built-in "None" link (goog.ui.DatePicker ships
 * one by default; see allowNone_ in goog/ui/datepicker.js) and the Clear
 * button end up calling the exact same goog.ui.DatePicker#setDate(null),
 * which is what makes a single change listener on the popup date picker
 * (not on InputDatePicker itself, which does not re-dispatch CHANGE)
 * sufficient to catch every way the date can change.
 * @param {number} birthDateUnix
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.bindBirthDate_ = function(
    birthDateUnix) {
  const dateEl = goog.dom.getElement('profile-birth-date');
  const clearEl = goog.dom.getElement('profile-birth-date-clear');
  if (!dateEl) return;

  const pattern = funwithactivity.profile.ProfileComponent.DATE_PATTERN_;
  const formatter = new goog.i18n.DateTimeFormat(pattern);
  const parser = new goog.i18n.DateTimeParse(pattern);

  this.datePicker_ = new goog.ui.InputDatePicker(formatter, parser);
  this.addChild(this.datePicker_);
  this.datePicker_.decorate(dateEl);

  // goog.ui.DatePicker.Events.CHANGE fires on the internal DatePicker and
  // is forwarded verbatim by goog.ui.PopupDatePicker (see onDateChanged_
  // in goog/ui/popupdatepicker.js) — that forwarding is why listening on
  // getPopupDatePicker() here, rather than on this.datePicker_ itself,
  // catches picker clicks, "None", and the Clear button below alike.
  this.eventKeys_.push(goog.events.listen(
      this.datePicker_.getPopupDatePicker(), goog.ui.DatePicker.Events.CHANGE,
      this.handleDateChanged_, false, this));

  if (birthDateUnix) {
    this.datePicker_.setDate(
        new goog.date.Date(new Date(birthDateUnix * 1000)));
  }

  if (clearEl) {
    const clearButton = new goog.ui.Button(null);
    this.addChild(clearButton);
    clearButton.decorate(clearEl);
    this.eventKeys_.push(goog.events.listen(clearButton,
        goog.ui.Component.EventType.ACTION, this.handleClearDateClick_,
        false, this));
  }
};


/**
 * @param {!goog.ui.DatePickerEvent} e
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.handleDateChanged_ =
    function(e) {
  // e.date is a goog.date.Date, or null for "no date" (the calendar's
  // "None" link, or handleClearDateClick_ below via setDate(null)). 0 is
  // the wire's own "not supplied" sentinel — never a parsed 1970-01-01 —
  // so an explicit null->0 mapping here, not Math.floor(0 / 1000), is what
  // keeps that convention intact.
  this.birthDateUnix_ = e.date ? Math.floor(e.date.getTime() / 1000) : 0;
  this.commitMeasurements_();
};


/** @private */
funwithactivity.profile.ProfileComponent.prototype.handleClearDateClick_ =
    function() {
  if (this.datePicker_) {
    this.datePicker_.setDate(null);
  }
};


/**
 * Reads the two native inputs, combines them with the last known
 * birthDateUnix_, and writes through to AppState. AppState itself no-ops
 * (and stays clean) when nothing actually changed, so calling this
 * liberally — on every keystroke and on initial seeding alike — is safe.
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.commitMeasurements_ =
    function() {
  const heightCm =
      this.heightInput_ ? (Number(this.heightInput_.value) || 0) : 0;
  const weightKg =
      this.weightInput_ ? (Number(this.weightInput_.value) || 0) : 0;
  this.state_.setMeasurements(heightCm, weightKg, this.birthDateUnix_);
};


/**
 * Decorates `fault-<provider>` as a goog.ui.Checkbox and builds a
 * goog.ui.Select (backed by a goog.ui.Menu of goog.ui.MenuItems, one per
 * funwithactivity.profile.ProfileComponent.FAULT_MODES_) rendered into
 * `fault-<provider>-mode`. The Select starts disabled and only becomes
 * enabled while its checkbox is checked — ticking the box without ever
 * touching the mode select must still produce a valid fault (defaulting to
 * index 0, "error"), not an unset value web-proxy would silently drop.
 * @param {string} provider
 * @param {?string} currentMode The provider's current fault mode from
 *     AppState, or null if no fault is set for it.
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.bindFaultRow_ = function(
    provider, currentMode) {
  const checkboxEl = goog.dom.getElement('fault-' + provider);
  const selectMount = goog.dom.getElement('fault-' + provider + '-mode');
  if (!checkboxEl || !selectMount) return;

  const checkbox = new goog.ui.Checkbox();
  this.addChild(checkbox);
  checkbox.decorate(checkboxEl);

  const menu = new goog.ui.Menu();
  funwithactivity.profile.ProfileComponent.FAULT_MODES_.forEach(
      function(mode) {
        menu.addItem(new goog.ui.MenuItem(mode.label, mode.value));
      });

  const select = new goog.ui.Select(null, menu);
  this.addChild(select);
  select.render(selectMount);
  select.setSelectedIndex(0);

  const isFaulted = !!currentMode;
  checkbox.setChecked(isFaulted);
  select.setEnabled(isFaulted);
  if (isFaulted) {
    select.setValue(currentMode);
  }

  this.eventKeys_.push(goog.events.listen(checkbox,
      goog.ui.Component.EventType.CHANGE,
      goog.bind(this.handleFaultCheckboxChange_, this, provider, checkbox,
          select)));
  this.eventKeys_.push(goog.events.listen(select,
      goog.ui.Component.EventType.CHANGE,
      goog.bind(this.handleFaultModeChange_, this, provider, checkbox,
          select)));

  this.faultCheckboxes_[provider] = checkbox;
  this.faultSelects_[provider] = select;
};


/**
 * @param {string} provider
 * @param {!goog.ui.Checkbox} checkbox
 * @param {!goog.ui.Select} select
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype
    .handleFaultCheckboxChange_ = function(provider, checkbox, select) {
  const checked = checkbox.isChecked();
  select.setEnabled(checked);
  if (checked) {
    this.state_.setFault(provider, /** @type {string} */ (select.getValue()));
  } else {
    this.state_.clearFault(provider);
  }
};


/**
 * @param {string} provider
 * @param {!goog.ui.Checkbox} checkbox
 * @param {!goog.ui.Select} select
 * @private
 */
funwithactivity.profile.ProfileComponent.prototype.handleFaultModeChange_ =
    function(provider, checkbox, select) {
  // A disabled Select cannot be opened by the user, but guard anyway: a
  // stray CHANGE while unchecked must never resurrect a cleared fault.
  if (!checkbox.isChecked()) return;
  this.state_.setFault(provider, /** @type {string} */ (select.getValue()));
};


/** @override */
funwithactivity.profile.ProfileComponent.prototype.disposeInternal =
    function() {
  this.eventKeys_.forEach(goog.events.unlistenByKey);
  this.eventKeys_.length = 0;
  this.heightInput_ = null;
  this.weightInput_ = null;
  this.datePicker_ = null;
  this.faultCheckboxes_ = {};
  this.faultSelects_ = {};
  // Checkbox/Select/InputDatePicker/Button widgets are all children added
  // via addChild() above, so the base class disposes them here.
  funwithactivity.profile.ProfileComponent.base(this, 'disposeInternal');
};
