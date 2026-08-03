/**
 * Compile every Soy template under `ui-soy/` to JavaScript for
 * client-side rendering.
 *
 * Reference invocation: cyberfight's web-client/scripts/compile-soy.js.
 * That script's i18n/locale/merge-by-namespace machinery is dropped here —
 * this project has one locale and each .soy file already declares its own
 * unique namespace, so there is nothing to merge.
 *
 * The `--add-opens` flags below work around a JPMS/Guice clash: Soy's
 * compiler (via Guice's cglib-based fast-class generation) reflectively
 * calls ClassLoader#defineClass, which is closed off by default on
 * Java 9+. Confirmed against Java 17 while writing this script — without
 * `--add-opens` the compiler throws `InaccessibleObjectException` before
 * doing any work; with it, compilation succeeds. That means modern Java
 * is fine for *build-time* Soy compilation; the historical Java 8 pin in
 * the reference project is a runtime (soynode SSR) requirement only, and
 * this project has no SSR.
 */

'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const SOY_COMPILER_JAR = path.join(
    ROOT, 'node_modules/closure-templates/SoyToJsSrcCompiler.jar');
const SOY_SOURCE_DIR = path.join(ROOT, '..', 'ui-soy');
const SOY_OUTPUT_DIR = path.join(ROOT, 'src/templates');

/** Fails fast if the jar devDependency hasn't been installed. */
function checkSoyCompiler() {
  if (!fs.existsSync(SOY_COMPILER_JAR)) {
    throw new Error(
        `Soy compiler not found at: ${SOY_COMPILER_JAR}\n` +
        `Run "npm install" in web-client/ (closure-templates ships the jar).`);
  }
}

/** Recursively finds every .soy file under `dir`. */
function findSoyFiles(dir) {
  const found = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...findSoyFiles(full));
    } else if (entry.isFile() && entry.name.endsWith('.soy')) {
      found.push(full);
    }
  }
  return found;
}

/**
 * Compiles one .soy file to one .soy.js file, mirroring its path relative
 * to ui-soy/ under src/templates/.
 * @param {string} soyFile
 */
function compileSoyFile(soyFile) {
  const rel = path.relative(SOY_SOURCE_DIR, soyFile);
  const outputFile =
      path.join(SOY_OUTPUT_DIR, rel.replace(/\.soy$/, '.soy.js'));
  fs.mkdirSync(path.dirname(outputFile), { recursive: true });

  execSync(
      `java ` +
      `--add-opens java.base/java.lang=ALL-UNNAMED ` +
      `--add-opens java.base/java.util=ALL-UNNAMED ` +
      `-jar "${SOY_COMPILER_JAR}" ` +
      `--outputPathFormat "${outputFile}" ` +
      `--shouldGenerateJsdoc ` +
      `--shouldProvideRequireSoyNamespaces ` +
      `"${soyFile}"`,
      { stdio: 'inherit' },
  );

  console.log(`  ✓ ${path.relative(ROOT, outputFile)}`);
}

function main() {
  checkSoyCompiler();

  if (fs.existsSync(SOY_OUTPUT_DIR)) {
    fs.rmSync(SOY_OUTPUT_DIR, { recursive: true, force: true });
  }
  fs.mkdirSync(SOY_OUTPUT_DIR, { recursive: true });

  const soyFiles = findSoyFiles(SOY_SOURCE_DIR);
  if (soyFiles.length === 0) {
    throw new Error(`No .soy files found under ${SOY_SOURCE_DIR}`);
  }

  console.log(`Compiling ${soyFiles.length} Soy template(s)...`);
  for (const soyFile of soyFiles) {
    compileSoyFile(soyFile);
  }
  console.log('✓ Soy compilation complete');
}

main();
