# Takumi upstream test corpus

`takumi/` contains 1,909 files (39.93 MiB) from
[kane50613/takumi](https://github.com/kane50613/takumi) at
`ff9a5d411310c8cdd1ac76a4f106c123d309e0a4`. These are ordinary repository files, not a
submodule or a download cache. A clone of bm-engine includes this corpus.

Included: every tracked upstream test/fixture/e2e directory, named test and test-support files,
Rust source files containing unit-test declarations, shared assets, and upstream license/notice files.
The original directory structure and Git blob bytes are preserved. `takumi.manifest.json` records
the source revision and every file's size and SHA-256. No upstream `.git` metadata is included.

The PDF runners, PDF API tests, pagination tests, audit probes and external PDF validation/visual
corpus use these files directly, without reading the ignored `ref/takumi` checkout.

```sh
npm run test:takumi:verify       # offline integrity check of all imported files
npm run test:pdf:takumi         # compare bm-engine against all 136 PDF goldens
npm run test:pdf                # build PDF wasm and run public API tests
zig build test -Dpdf=true -Dtest-filter=pdf -j1 --summary all
```

The original Rust/TypeScript test sources are reference material for porting. Copying them does not
make them executable by Zig or imply they all pass with bm-engine. The executable PDF adapters are
in `scripts/pdf-compare*.mjs`, `scripts/pdf-interchange.mjs` and `scripts/pdf-tagging-fixtures.mjs`.
The upstream tests may depend on Rust crates, npm packages, browsers or external WPT inputs; those
dependencies are not downloaded by the corpus verification command.

To reproduce the import from a reference checkout at the pinned revision:

```sh
node scripts/takumi-test-corpus.mjs --import ref/takumi
```

Import refuses to overwrite a changed existing file. Preserve the vendored files and their notices;
make bm-engine-specific adaptations in bm-engine's own tests. The MIT/Apache licenses and third-party
notices are retained inside `takumi/`; font license files are retained alongside the assets. The test
corpus is not included in the npm package's `files` allowlist.
