# Phát hành một bản release (dành cho maintainer)

[English](../en/publishing.md) · [Tiếng Việt](publishing.md)

Một bản release của bm-render là **chín package npm cùng một version**: `bm-render` (JavaScript, typings và
các binary wasm) và tám platform package `@hunghg255/bm-render-<platform>`, mỗi cái chứa một bản build Node-API
native. `bm-render` liệt kê tám package này trong `optionalDependencies`, ghim đúng version của chính nó,
nên tất cả phải có mặt trên registry, ở đúng version đó, trước khi người dùng cài. Trang này là quy trình;
thiết kế nằm trong [docs/NATIVE.md](../NATIVE.md), hành vi phía người dùng nằm trong
[Bắt đầu](getting-started.md#native-trên-nodejs-webassembly-ở-mọi-nơi-khác).

| Package | Build từ | Nội dung |
|:--|:--|:--|
| `bm-render` | thư mục gốc của repository (`files` trong `package.json`) | `js/`, bốn file `.wasm`, README, license; **không có file `.node`** |
| `@hunghg255/bm-render-win32-x64-msvc`, `-win32-arm64-msvc`, `-linux-x64-gnu`, `-linux-x64-musl`, `-linux-arm64-gnu`, `-linux-arm64-musl`, `-darwin-x64`, `-darwin-arm64` | `npm/<platform>/`, sinh bởi `npm run build:npm` | `bm-render.<platform>.node` (là `main` của nó), `package.json` với `os` / `cpu` / `libc`, README, license |

`npm/<platform>/package.json` và `README.md` được commit; các file `.node` và bản sao license trong `npm/`
là output của bước build (bị git bỏ qua). Các `package.json` của platform package được sinh từ
`package.json` gốc (version, license, author, repository, ...), nên đừng bao giờ sửa tay.

## Thiết lập một lần

1. `author`, `homepage`, `repository` và `bugs` đã được đặt trong `package.json` gốc (hunghg255,
   https://github.com/BM-Hospital/bm-render). Sau khi đổi bất kỳ trường nào, chạy `npm run build:npm` để
   chép chúng sang `npm/*/package.json`.
2. Một tài khoản npm có xác thực hai lớp. Lần `npm publish` đầu tiên của mỗi tên sẽ tạo package và đặt
   bạn làm owner; thêm đồng maintainer cho **cả chín** package bằng `npm owner add <user> <pkg>`. Ngày
   2026-11-12, chưa có tên nào trong chín tên này tồn tại trên registry (`npm view <name>` trả về 404).
3. Zig 0.17.1 trong `PATH` (hoặc `ZIG=<path>`), và `npm install --ignore-scripts` ở thư mục gốc của
   repository để có `wasm-opt` (binaryen).

## Quy trình release

**Cách ngắn: một lệnh.** Khi code đã commit:

```sh
npm run release:dry -- 0.1.1   # chạy thử: mọi bước bên dưới với `npm publish --dry-run`, rồi hoàn tác
npm run release -- 0.1.1       # release thật
```

`npm run release -- <version>` (scripts/publish.mjs) đặt version ở mọi nơi, build lại wasm và manifest
(`npm run build`), commit `Release <version>`, build addon native cho 8 nền tảng và các thư mục
`npm/<platform>/`, chạy mọi kiểm tra (`npm run release:check`: verify, test Zig, test PDF, test native,
pack test), publish 8 platform package trước và bm-render sau cùng, rồi gắn tag `v<version>` và push commit
cùng tag. Script từ chối chạy khi còn thay đổi chưa commit hoặc chưa `npm login`. Gói nào đã publish ở
version đó thì bỏ qua, nên một lần release bị ngắt (OTP hết hạn, mạng) chỉ cần chạy lại đúng lệnh đó. Tuỳ
chọn: `--otp=<mã>`, `--tag=<dist-tag>` (ví dụ `next`), `--skip-checks`, `--publish-only` (chỉ chạy lại bước publish khi các kiểm tra đã qua trên commit này). Không có `--otp` thì npm hỏi mã OTP
(hoặc mở trình duyệt) ở mỗi lần publish. `prepublishOnly` chạy cùng các kiểm tra đó, nên `npm publish` trực
tiếp cho bm-render không bỏ qua được chúng. Các bước dưới đây là từng việc script làm.

### 1. Đặt version (một lệnh)

```sh
npm run version:set -- 0.2.0
```

Lệnh này ghi lại cùng lúc: `version` trong `package.json`, tám `optionalDependencies` (đúng `0.2.0`),
`package-lock.json` (mục gốc; các mục `node_modules/bm-render-*` cũ bị bỏ đi), và mọi
`npm/<platform>/package.json` + `README.md`. `npm run verify` sẽ thất bại bất cứ khi nào chúng không khớp
nhau (`node scripts/npm-platform-packages.mjs --check`). Đừng chỉ dùng `npm version`: lệnh đó không đụng
tới optional dependency hay các platform package.

### 2. Build mọi thứ

```sh
npm run build          # wasm: core, standard, full, woff + js/build-manifest.json (records the version)
npm run build:native   # 8 native targets -> native/dist/<platform>/, structurally verified, manifest.json
npm run build:npm      # npm/<platform>/: copies each .node (checked against native/dist/manifest.json)
```

`build:native` cross-compile cả tám target từ một máy bất kỳ và thất bại khi có bất kỳ lỗi cấu trúc nào
(xem [NATIVE.md](../NATIVE.md#what-is-verified)). `build:npm` thất bại nếu thiếu một binary, binary không
khớp manifest, hoặc chưa được kiểm tra.

### 3. Kiểm tra

```sh
npm run verify                 # version sync + wasm manifest + no placeholders
npm run test:pack              # packs everything, installs it in scratch projects (~5 min)
npm run test:native            # the native test suite, on this machine's addon
node bench/native-identity.mjs # byte identity native vs wasm (needs bench/node_modules)
npm pack --dry-run             # main package file list: no .node, ~32 files, ~1.3 MB
for d in npm/*/; do npm pack --dry-run "$d"; done
```

`test:pack` chạy các kịch bản cài đặt với tarball thật: npm chọn đúng platform package, fallback sang wasm
khi không có nó (`--omit=optional`, thiếu, binary hỏng hoặc của hệ điều hành khác), `BM_RENDER_BACKEND`,
`bm-render/native`, worker thread, bundler. Trên máy cục bộ chỉ binary của máy đó chạy được; các binary
còn lại được chạy bởi ma trận test của CI ([con đường CI](#con-đường-ci-release-thủ-công-từ-github-actions)). **Đừng phát hành một nền tảng
chưa từng qua `native-identity.mjs` và `native-tests.mjs` trên đúng hệ điều hành và CPU của nó**, trừ khi
bạn chấp nhận rằng người dùng nền tảng đó có thể lặng lẽ nhận wasm (fallback), hoặc tệ hơn, một binary nạp
được nhưng chạy sai.

### 4. Commit và gắn tag

```sh
git commit -am "Release 0.2.0" && git tag v0.2.0
```

### 5. Publish: platform package trước, rồi tới bm-render

Thứ tự là quan trọng. Nếu `bm-render@0.2.0` được publish trước, các lần cài trong vài phút sau đó sẽ bỏ qua
những optional dependency chưa tồn tại (lặng lẽ: wasm), và lockfile tạo ra lúc đó sẽ không có chúng.

```sh
npm publish ./npm/win32-x64-msvc --access public
npm publish ./npm/win32-arm64-msvc --access public
npm publish ./npm/linux-x64-gnu --access public
npm publish ./npm/linux-x64-musl --access public
npm publish ./npm/linux-arm64-gnu --access public
npm publish ./npm/linux-arm64-musl --access public
npm publish ./npm/darwin-x64 --access public
npm publish ./npm/darwin-arm64 --access public
npm view @hunghg255/bm-render-darwin-arm64@0.2.0 version   # repeat for the others if in doubt
npm publish --access public                     # bm-render itself (prepublishOnly runs npm run release:check)
```

`--access public` đã có sẵn trong `publishConfig` của mỗi package, nó được lặp lại cho rõ.

**2FA / OTP.** Với 2FA chế độ "auth and writes", mỗi lệnh `npm publish` sẽ hỏi mật khẩu một lần, hoặc nhận
`--otp=<code>`. Một mã chỉ có hiệu lực khoảng 30 giây, nên chín lần publish cần vài mã; con đường CI bên dưới
tránh việc này bằng token.

**Provenance.** `npm publish --provenance` gắn kèm một chứng nhận có chữ ký nối tarball với commit nguồn và
lần build. Nó chỉ chạy được từ một nhà cung cấp CI được hỗ trợ (GitHub Actions với
`permissions: id-token: write`, GitLab), không chạy từ laptop, và npm kiểm tra rằng `repository.url` trong
mỗi `package.json` đúng là repository mà workflow đang chạy (thêm một lý do để điền các placeholder).

### 6. Kiểm tra bản release

```sh
npm view bm-render@0.2.0 optionalDependencies
mkdir /tmp/check && cd /tmp/check && npm init -y && npm i bm-render@0.2.0
node --input-type=module -e 'const m = await import("bm-render"); console.log(m.backend)'   # native
```

## Khi có sự cố

- **Một lần publish platform package thất bại** (mạng, OTP hết hạn, gõ sai tên): chưa có gì hỏng,
  `bm-render` chưa được publish. Sửa nguyên nhân rồi publish các platform package còn lại; những package
  đã publish sẽ trả lời `You cannot publish over the previously published versions` và có thể bỏ qua. Chỉ
  publish `bm-render` khi đủ cả tám.
- **`bm-render` đã ra, thiếu một platform package**: người dùng nền tảng đó nhận wasm (fallback), không
  phải lỗi. Publish package còn thiếu với **cùng** version càng sớm càng tốt; các lần cài mới sẽ nhận nó.
  Lockfile được ghi trong khoảng thời gian đó có thể thiếu nó: những người dùng này cần cài lại.
- **Một binary platform đã publish bị hỏng**: một version trên npm không bao giờ ghi đè được, và việc
  unpublish chỉ làm được trong vòng 72 giờ và khóa vĩnh viễn số version đó. Thay vào đó hãy deprecate:
  `npm deprecate @hunghg255/bm-render-<platform>@0.2.0 "broken, use 0.2.1"` (và cả `bm-render@0.2.0`), rồi release
  0.2.1 cho **cả chín** package (các version luôn đi cùng nhau; `version:set` làm việc đó). Trong lúc chờ,
  người dùng có thể ép wasm bằng `BM_RENDER_BACKEND=wasm`.
- **Lệch version** không thể xảy ra qua các script (`verify` kiểm tra), nhưng nếu một platform package của
  version khác được cài, addon của nó chỉ được nạp khi version giao diện nội bộ (`abi`) bằng đúng giá trị
  mà `bm-render` mong đợi; nếu không, `bm-render` dùng wasm.

## Prerelease và dist-tag

```sh
npm run version:set -- 0.3.0-beta.1
# build, verify, tag v0.3.0-beta.1 as above, then the same nine publishes with a tag:
npm publish ./npm/win32-x64-msvc --access public --tag next   # ... all eight
npm publish --access public --tag next
```

Luôn truyền `--tag next` (hoặc `beta`) cho một prerelease, trên cả chín package, để `latest` vẫn trỏ tới bản
ổn định; người dùng chủ động chọn bằng `npm i bm-render@next`. Vì optional dependency ghim đúng version, tag
của các platform package không ảnh hưởng tới việc resolve, nhưng hãy giữ chúng nhất quán. Để nâng một
version lên sau này: `npm dist-tag add bm-render@0.3.0 latest` (và tương tự cho tám platform package).

## Con đường CI: release thủ công từ GitHub Actions

`.github/workflows/release.yml` release mà không cần đăng nhập npm hay OTP trên máy bạn. Chạy từ
**Actions → release → Run workflow**:

| Tham số | Ý nghĩa |
|:--|:--|
| `version` | ví dụ `0.1.1` hoặc `0.2.0-beta.0`; để trống = version đang có trong `package.json` |
| `dist_tag` | `auto` (`next` cho bản prerelease, `latest` cho bản thường), `latest` hoặc `next` |
| `dry_run` | build + test + `npm publish --dry-run`: không commit, không gắn tag, không publish |
| `skip_tests` | bỏ qua test trên từng nền tảng, chỉ dùng để chạy lại bước publish khi test đã qua |

Workflow làm gì: một job Linux đổi version (khi `version` khác), build wasm và cross-compile 8 addon bằng Zig
0.17.1 (đã kiểm checksum), chạy test Zig; 8 job test **chạy thật** từng addon trên đúng nền tảng của nó
(Ubuntu x64 / arm64, Alpine x64 / arm64 trong Docker, macOS x64 / arm64, Windows x64 / arm64:
`native-identity.mjs`, `native-tests.mjs`, các kịch bản cài đặt); chỉ khi tất cả đều xanh, job publish mới
commit `Release <version>`, push tag `v<version>`, rồi publish 8 gói `@hunghg255/bm-render-<platform>` và
sau cùng là `bm-render`, kèm provenance, bỏ qua các version đã có trên registry (nên một lần chạy lỗi chỉ cần
chạy lại).

**Thiết lập một lần: npm trusted publishing.** Trên npmjs.com, với từng gói trong 9 gói (`bm-render` và 8
gói `@hunghg255/bm-render-*`, khi chúng đã có trên registry): **Settings → Trusted Publisher → GitHub
Actions**, user/organization `BM-Hospital`, repository `bm-render`, workflow `release.yml`, environment
`npm`. Từ đó npm nhận publish từ workflow này qua OIDC, không cần token. (Cách khác: repository secret
`NPM_TOKEN` chứa một granular token được phép publish các gói đó; workflow dùng nó khi có.) Nếu `main` là
nhánh được bảo vệ, cho phép GitHub Actions push commit release, hoặc đổi version ở máy rồi để trống `version`.

::: warning Lần chạy đầu
SHA của các action được lấy từ tag release ngày 2026-11-12, nhưng workflow chưa từng chạy trên GitHub. Lần
đầu hãy chạy với `dry_run`, hoặc với một version prerelease.
:::
