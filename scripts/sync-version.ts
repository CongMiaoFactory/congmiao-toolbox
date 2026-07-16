const input = process.argv[2]?.trim().replace(/^v/, '');

if (!input || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(input)) {
  console.error('Usage: bun run version:sync <vMAJOR.MINOR.PATCH>');
  process.exit(1);
}

const updateJsonVersion = async (path: string) => {
  const json = await Bun.file(path).json();
  json.version = input;
  await Bun.write(path, `${JSON.stringify(json, null, 2)}\n`);
};

const replaceRequired = async (path: string, pattern: RegExp, replacement: string) => {
  const original = await Bun.file(path).text();
  const updated = original.replace(pattern, replacement);
  if (updated === original && !original.includes(`version = "${input}"`)) {
    throw new Error(`Could not update version in ${path}`);
  }
  await Bun.write(path, updated);
};

await updateJsonVersion('package.json');
await updateJsonVersion('src-tauri/tauri.conf.json');
await replaceRequired(
  'src-tauri/Cargo.toml',
  /(\[package\][\s\S]*?\nversion = ")[^"]+("\r?\n)/,
  `$1${input}$2`,
);
await replaceRequired(
  'src-tauri/Cargo.lock',
  /(\[\[package\]\]\r?\nname = "congmiao-toolbox"\r?\nversion = ")[^"]+("\r?\n)/,
  `$1${input}$2`,
);

console.log(`Synchronized application version to ${input}`);
