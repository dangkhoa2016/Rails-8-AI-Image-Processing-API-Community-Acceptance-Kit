# Rails 8 AI Image Processing API — Community Acceptance Kit

[![CI](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit/actions/workflows/ci.yml/badge.svg)](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ruby 3.3](https://img.shields.io/badge/Ruby-3.3-CC342D?logo=ruby&logoColor=white)](.ruby-version)
![Black-box acceptance](https://img.shields.io/badge/acceptance-black--box-2ea44f)

> Language: **English** | [Tiếng Việt](README.vi.md)


Public, Ruby-native black-box acceptance tooling for
[Rails-8-AI-Image-Processing-API](https://github.com/dangkhoa2016/Rails-8-AI-Image-Processing-API).

This is a companion repository. It does not contain the Rails application itself.
It provides reproducible fixtures, public deployment tests, visual evidence, and
static HTML reports for community review.

## Scope

- public health and authentication boundaries;
- profile aliases and regular-user authorization;
- all public deterministic image-processing operations;
- PNG/JPEG/WebP output contracts;
- EXIF orientation normalization and metadata stripping;
- invalid/corrupt input handling;
- BiRefNet background removal;
- MobileSAM positive point, negative point, and box prompts;
- refresh-token rotation and reuse detection;
- sign-out/revocation;
- optional rate-limit and forwarded-header spoof-resistance checks;
- SHA-256 evidence integrity.

Admin-only behavior and email-confirmation delivery require separate authorities
and are reported as `SKIP`, never falsely marked PASS.

## Requirements

- Ruby 3.3
- libvips CLI (`vips`, `vipsheader`)
- network access to the deployment under test

Acceptance logic is Ruby. Shell scripts are orchestration/deployment helpers only.

## Generate fixtures

```bash
ruby scripts/generate_assets.rb
```

Authority files are written under `assets/`, including `manifest.json`,
`SHA256SUMS`, `prompts.json`, and the input contact sheet.

## Configure a target

```bash
scripts/setup_runtime_env.sh
```

By default this writes `/tmp/rails8-ai-e2e.env` with mode `600`. Credentials are
never stored in the repository.

The real `E2E_BASE_URL` is runtime-only. Public summaries, reports, and static-site
metadata persist only `E2E_TARGET_LABEL` (default: `runtime-configured deployment`),
so temporary deployment URLs are not baked into published artifacts.

## Run acceptance

```bash
scripts/run_all.sh
```

Run rate-limit tests last:

```bash
E2E_RUN_RATE_LIMITS=1 scripts/run_all.sh
```

Each run writes `evidence/<run-id>/` with JSON summaries, output images, metadata,
SHA-256 files, and three self-contained HTML reports:

- `report.html`
- `report-compact.html`
- `gallery.html`

`run_all.sh` also rebuilds the deployable static site in `site/`.

## Preview reports and static site

```bash
ruby scripts/generate_report.rb --preview --out report-preview
ruby scripts/build_site.rb --reports report-preview --out site
```

Preview mode is labeled `PREVIEW`; only live evidence may produce PASS/FAIL.

## Static hosting

### Cloudflare Pages

```bash
scripts/deploy_cloudflare.sh
```

or direct upload:

```bash
npx wrangler pages deploy site --project-name rails8-ai-image-processing-api-community-acceptance-kit
```

`wrangler.toml` declares `site/` as the Pages output directory.

### Hugging Face Static Space

```bash
ruby scripts/export_huggingface_space.rb --site site --out dist/huggingface-space
```

Push the contents of `dist/huggingface-space/` to the root of a Hugging Face
Space. The exported README uses `sdk: static` and `app_file: index.html`.

No GPU or inference runtime is needed to serve the acceptance site.

## Package a community artifact

```bash
scripts/pack_release.sh [optional-evidence-directory]
```

The packager rejects evidence that appears to contain bearer tokens, refresh
tokens, passwords, or similar credential markers.

## Publication policy

Safe to publish: fixtures, Ruby runners/generators, self-contained reports,
redacted evidence, metadata, SHA-256 checksums, and static-site output.

Never publish passwords, JWTs, refresh tokens, cookies, or raw secret-bearing
request headers.

## License

MIT. See [LICENSE](LICENSE).
