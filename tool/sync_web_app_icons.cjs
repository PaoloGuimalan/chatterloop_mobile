// Exports the exact web Apps icons at 4x the native 28px display size.
// Usage: node tool/sync_web_app_icons.cjs [installed-sharp-module-path]
const fs = require('node:fs/promises');
const path = require('node:path');
const { createRequire } = require('node:module');
const appRoot = path.resolve(__dirname, '..');
const webRoot = path.resolve(appRoot, '../webapp');
const webRequire = createRequire(path.join(webRoot, 'package.json'));
const ts = webRequire('typescript');
const React = webRequire('react');
const { renderToStaticMarkup } = webRequire('react-dom/server');
const sharp = require(process.argv[2] || 'sharp');
async function main() {
  const sourcePath = path.join(webRoot, 'src/app/widgets/desktopwidgets/appShortcutIcons.tsx');
  const source = await fs.readFile(sourcePath, 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: {
    jsx: ts.JsxEmit.ReactJSX, module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020,
  }}).outputText;
  const iconExports = {};
  new Function('require', 'exports', code)(webRequire, iconExports);
  for (const [name, icon] of Object.entries(iconExports.appShortcutIcons)) {
    const svg = renderToStaticMarkup(React.cloneElement(icon, {size: 112}));
    await sharp(Buffer.from(svg)).png().toFile(path.join(appRoot, 'assets/images/app-icon-' + name + '.png'));
    process.stdout.write('Exported ' + name + '\n');
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
