#!/usr/bin/env bash
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site="${1:-$repo/site}"
project="${CLOUDFLARE_PAGES_PROJECT:-rails8-ai-image-processing-api-community-acceptance-kit}"

[[ -f "$site/index.html" ]] || {
  echo "Missing static site: $site/index.html" >&2
  exit 66
}

command -v npx >/dev/null 2>&1 || {
  echo "npx is required for Wrangler direct upload." >&2
  exit 69
}

npx wrangler pages deploy "$site" --project-name "$project"
