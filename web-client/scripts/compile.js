/**
 * Closure Compiler build for the FunWithActivity web client.
 *
 * One ADVANCED bundle. Flag set simplified from cyberfight's compile.js —
 * the per-cell, per-locale, revisioning and translation machinery there is
 * not needed for a single-page PoC.
 */

'use strict';

const compiler = require('google-closure-compiler').compiler;
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const PUBLIC_DIR = path.join(ROOT, 'public');

fs.mkdirSync(PUBLIC_DIR, { recursive: true });

const options = {
  compilation_level: 'ADVANCED',
  dependency_mode: 'PRUNE',
  entry_point: 'goog:funwithactivity.Main',
  language_in: 'ECMASCRIPT_2020',
  language_out: 'ECMASCRIPT_2015',
  warning_level: 'VERBOSE',
  jscomp_error: [
    'checkTypes',
    'missingProperties',
    'missingReturn',
    'undefinedVars',
    'uselessCode',
    'visibility',
  ],
  assume_function_wrapper: true,
  js: [
    path.join(ROOT, 'node_modules/google-closure-library/closure/goog/**.js'),
    '!' + path.join(ROOT, 'node_modules/google-closure-library/closure/goog/**_test.js'),
    // Soy runtime (goog.provide'd 'soy', 'soydata', etc.) that generated
    // template code depends on. A vendored, patched copy — not the
    // node_modules/closure-templates original — because that vintage
    // (2016) runtime goog.requires goog.soy.data.UnsanitizedText and
    // SanitizedContentKind.TEXT, both removed from google-closure-library
    // by the version this project pins (^20230802.0.0), and its
    // soy.renderElement/renderAsFragment/renderAsElement aliases no
    // longer type-match modern goog.soy. See the patch notes at the top
    // of the vendored file for exactly what changed and why; pointing
    // here instead of at node_modules means `npm install` can never
    // silently revert the patch.
    path.join(ROOT, 'third_party/soy/soyutils_usegoog.js'),
    path.join(ROOT, '../api/dto/**.js'),
    // Generated template JS from scripts/compile-soy.js lives under
    // src/templates/ and is already matched by the src/**.js glob below —
    // do not list it again here. Doing so previously passed every
    // template file to the compiler twice, which the compiler rejected
    // with "already exist in chunk $strong$". Each template file is
    // goog.provide'd (--shouldProvideRequireSoyNamespaces), so Closure's
    // dependency resolution — not file order here — decides what's
    // actually bundled; PRUNE drops anything the entry point never
    // transitively requires.
    path.join(ROOT, 'src/**.js'),
  ],
  js_output_file: path.join(PUBLIC_DIR, 'main.min.js'),
};

new compiler(options).run((exitCode, _stdout, stderr) => {
  if (stderr) process.stderr.write(stderr);
  if (exitCode !== 0) process.exit(exitCode);
  const bytes = fs.statSync(options.js_output_file).size;
  console.log(`main.min.js ${(bytes / 1024).toFixed(1)} KiB`);
});
