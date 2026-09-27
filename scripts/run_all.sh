#!/usr/bin/env bash
set -Eeuo pipefail

env_file="${E2E_ENV_FILE:-/tmp/rails8-ai-e2e.env}"
[[ -f "$env_file" ]] || {
  echo "Missing $env_file" >&2
  echo "Run scripts/setup_runtime_env.sh first." >&2
  exit 64
}

# shellcheck disable=SC1090
source "$env_file"
: "${E2E_BASE_URL:?}"
: "${E2E_EMAIL:?}"
: "${E2E_PASSWORD:?}"
export E2E_TARGET_LABEL="${E2E_TARGET_LABEL:-runtime-configured deployment}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
out="$root/evidence/$run_id"
mkdir -p "$out"

ruby "$root/scripts/run_functional.rb"   --base-url "$E2E_BASE_URL"   --email "$E2E_EMAIL"   --password "$E2E_PASSWORD"   --out "$out"

ruby "$root/scripts/run_auth_lifecycle.rb"   --base-url "$E2E_BASE_URL"   --email "$E2E_EMAIL"   --password "$E2E_PASSWORD"   --out "$out"

if [[ "${E2E_RUN_RATE_LIMITS:-0}" == "1" ]]; then
  ruby "$root/scripts/run_rate_limits.rb"     --base-url "$E2E_BASE_URL"     --email "$E2E_EMAIL"     --password "$E2E_PASSWORD"     --out "$out"
fi

ruby "$root/scripts/generate_report.rb"   --evidence "$out"   --out "$out"

ruby "$root/scripts/build_site.rb"   --reports "$out"   --evidence "$out"   --out "$root/site"

echo "Evidence directory: $out"
echo "Visual report: $out/report.html"
echo "Compact report: $out/report-compact.html"
echo "Gallery: $out/gallery.html"
echo "Static site: $root/site/index.html"
