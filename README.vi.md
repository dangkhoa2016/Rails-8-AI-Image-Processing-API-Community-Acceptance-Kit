# Rails 8 AI Image Processing API — Community Acceptance Kit

[![CI](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit/actions/workflows/ci.yml/badge.svg)](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ruby 3.3](https://img.shields.io/badge/Ruby-3.3-CC342D?logo=ruby&logoColor=white)](.ruby-version)
![Black-box acceptance](https://img.shields.io/badge/acceptance-black--box-2ea44f)

> Ngôn ngữ: [English](README.md) | **Tiếng Việt**


Repository public, thuần Ruby để chạy black-box acceptance cho
[Rails-8-AI-Image-Processing-API](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API).

Đây là companion repository, không chứa source Rails application. Repo cung cấp
fixtures có thể tái tạo, public deployment tests, visual evidence và static HTML
reports để cộng đồng sử dụng/review độc lập.

## Phạm vi

- public health và authentication boundary;
- profile aliases và regular-user authorization;
- toàn bộ deterministic image-processing operations;
- output PNG/JPEG/WebP;
- EXIF orientation normalization và metadata stripping;
- invalid/corrupt input;
- BiRefNet background removal;
- MobileSAM positive point, negative point và box prompt;
- refresh-token rotation/reuse detection;
- sign-out/revocation;
- tùy chọn rate-limit và chống spoof forwarded header;
- SHA-256 evidence integrity.

Admin-only behavior và email-confirmation delivery cần authority riêng nên được
ghi `SKIP`, không giả mạo thành PASS.

## Yêu cầu

- Ruby 3.3
- libvips CLI (`vips`, `vipsheader`)
- network access tới deployment cần test

Acceptance logic được viết bằng Ruby; shell chỉ dùng cho orchestration/deploy.

## Tạo fixtures

```bash
ruby scripts/generate_assets.rb
```

Authority files nằm trong `assets/` gồm manifest, SHA256SUMS, prompts và contact
sheet.

## Cấu hình target

```bash
scripts/setup_runtime_env.sh
```

Mặc định tạo `/tmp/rails8-ai-e2e.env` với mode `600`; credential không được lưu
trong repository.

`E2E_BASE_URL` thật chỉ được dùng ở runtime. Public summary, report và static-site
metadata chỉ lưu `E2E_TARGET_LABEL` (mặc định: `runtime-configured deployment`),
vì vậy URL deployment tạm không bị đóng cứng vào artifact công khai.

## Chạy full acceptance

```bash
scripts/run_all.sh
```

Chỉ bật rate-limit ở cuối:

```bash
E2E_RUN_RATE_LIMITS=1 scripts/run_all.sh
```

Mỗi run tạo `evidence/<run-id>/` gồm JSON summary, output images, metadata,
SHA-256 và ba self-contained HTML reports: `report.html`,
`report-compact.html`, `gallery.html`.

`run_all.sh` đồng thời rebuild static site trong `site/`.

## Preview

```bash
ruby scripts/generate_report.rb --preview --out report-preview
ruby scripts/build_site.rb --reports report-preview --out site
```

Preview luôn được gắn nhãn `PREVIEW`; chỉ live evidence mới có PASS/FAIL.

## Static hosting

### Cloudflare Pages

```bash
scripts/deploy_cloudflare.sh
```

hoặc direct upload thư mục `site/` bằng Wrangler.

### Hugging Face Static Space

```bash
ruby scripts/export_huggingface_space.rb --site site --out dist/huggingface-space
```

Push nội dung `dist/huggingface-space/` lên root của Hugging Face Space. Bundle
đã có `sdk: static` và `app_file: index.html`.

Static site không cần GPU và không chạy inference.

## Đóng gói community artifact

```bash
scripts/pack_release.sh [optional-evidence-directory]
```

Packager từ chối evidence nếu phát hiện marker có khả năng chứa bearer token,
refresh token hoặc password.

## Chính sách publish

Có thể public fixtures, Ruby runners/generators, visual reports, redacted
evidence, metadata, SHA-256 và static-site output.

Không public password, JWT, refresh token, cookie hoặc raw header chứa secret.

## License

MIT. Xem [LICENSE](LICENSE).
