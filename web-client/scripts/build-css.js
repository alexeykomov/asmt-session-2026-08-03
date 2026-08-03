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
const postcss = require('postcss');
const cssnano = require('cssnano');

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

const concatenated = parts.join('\n\n') + '\n';

fs.mkdirSync(path.dirname(OUT), {recursive: true});

// PostCSS + cssnano. The edge already compresses (DigitalOcean App
// Platform's ingress serves Brotli), and compression collapses most of
// what minification removes — so this is the smaller of the two wins, not
// a substitute for the other. It is worth having anyway: minify-then-
// compress beats compress-alone, and the JS half of this build is already
// ADVANCED-compiled, so shipping hand-formatted CSS beside it was the
// inconsistent part.
//
// cssnano's default preset is deliberately conservative — it will not
// merge or reorder rules in ways that change the cascade. That matters
// more than usual here: 12 stock Closure stylesheets are concatenated
// ahead of main.css, and this app's overrides depend on source order and
// on several `!important` declarations to beat them.
postcss([cssnano({preset: 'default'})])
    .process(concatenated, {from: undefined})
    .then((result) => {
      fs.writeFileSync(OUT, result.css);
      const bytes = fs.statSync(OUT).size;
      const saved = concatenated.length - bytes;
      console.log('main.css ' + (bytes / 1024).toFixed(1) + ' KiB minified (' +
                  CLOSURE_SHEETS.length + ' Closure sheets + main.css, ' +
                  (saved / 1024).toFixed(1) + ' KiB saved)');
    })
    .catch((err) => {
      // Fail loudly rather than silently shipping unminified CSS: a build
      // step that quietly degrades is worse than one that stops.
      console.error('CSS minification failed: ' + err.message);
      process.exit(1);
    });
