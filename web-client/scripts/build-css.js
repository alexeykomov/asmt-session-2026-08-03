/**
 * Concatenates the stock Closure UI stylesheets with our own main.css.
 *
 * Closure widgets are unstyled without these — goog.ui.Select in particular
 * renders a menu that is present but INVISIBLE, so clicks land on nothing and
 * the control looks dead. That failure is silent on screen and absent from
 * logs, so this step is not optional.
 *
 * The stock files use Closure Stylesheets syntax (`@provide`, `@require`),
 * which is not CSS. Browsers ignore unknown at-rules so they would be
 * harmless, but we strip them rather than ship noise.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const GOOG_CSS = path.join(
    ROOT, 'node_modules/google-closure-library/closure/goog/css');
const OUT = path.join(ROOT, 'public/main.css');

// Order matters: common.css defines the base rules the others build on.
const CLOSURE_SHEETS = [
  'common.css',
  'button.css',
  'custombutton.css',
  'checkbox.css',
  'menu.css',
  'menuitem.css',
  'menuseparator.css',
  'menubutton.css',
  'datepicker.css',
  'popupdatepicker.css',
  'inputdatepicker.css',
  'tablesorter.css',
  // goog.ui.TabBar / goog.ui.Tab (funwithactivity.app.Shell). Missing
  // these produces the exact "present in the DOM but invisible" failure
  // this whole list exists to prevent: the tab bar would render, clicks
  // would land on real Tab elements, but nothing would be visibly
  // painted — no error anywhere.
  'tab.css',
  'tabbar.css',
];

/** Strips Closure Stylesheets directives that are not valid CSS. */
function stripGssDirectives(css) {
  return css.replace(/^\s*@(provide|require)\s+[^;]+;\s*$/gm, '');
}

const parts = [];
for (const name of CLOSURE_SHEETS) {
  const file = path.join(GOOG_CSS, name);
  if (!fs.existsSync(file)) {
    throw new Error('missing stock Closure stylesheet: ' + file);
  }
  parts.push('/* --- closure/goog/css/' + name + ' --- */');
  parts.push(stripGssDirectives(fs.readFileSync(file, 'utf8')).trim());
}

const mainCssFile = path.join(ROOT, 'css/main.css');
if (!fs.existsSync(mainCssFile)) {
  throw new Error('missing web-client/css/main.css: ' + mainCssFile);
}
parts.push('/* --- web-client/css/main.css --- */');
parts.push(fs.readFileSync(mainCssFile, 'utf8').trim());

fs.mkdirSync(path.dirname(OUT), {recursive: true});
fs.writeFileSync(OUT, parts.join('\n\n') + '\n');

const bytes = fs.statSync(OUT).size;
console.log('main.css ' + (bytes / 1024).toFixed(1) + ' KiB (' +
            CLOSURE_SHEETS.length + ' Closure sheets + main.css)');
