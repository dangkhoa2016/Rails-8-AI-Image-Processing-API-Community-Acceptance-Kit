#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_dir="${1:-}"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
name="Rails-8-AI-Image-Processing-API-Community-Acceptance-Kit"
out="$root/release/${name}-$stamp.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stage="$tmp/$name"
mkdir -p "$stage"

cp -a "$root/README.md" "$root/README.vi.md" "$root/.gitignore" "$stage/"
cp -a "$root/assets" "$stage/"
cp -a "$root/scripts" "$stage/"
cp -a "$root/deploy" "$stage/"
cp -a "$root/wrangler.toml" "$stage/"

if [[ -d "$root/site" ]]; then
  cp -a "$root/site" "$stage/"
fi

if [[ -n "$evidence_dir" ]]; then
  [[ -d "$evidence_dir" ]] || {
    echo "Evidence dir not found: $evidence_dir" >&2
    exit 66
  }

  mkdir -p "$stage/evidence"
  cp -a "$evidence_dir" "$stage/evidence/"

  if grep -RIlE 'Authorization:|Bearer |refresh_token|E2E_PASSWORD|password='     "$stage/evidence" 2>/dev/null | grep -q .; then
    echo "Potential secret-bearing evidence detected; refusing to package." >&2
    exit 1
  fi
fi

mkdir -p "$root/release"
tar -C "$tmp" -czf "$out" "$name"
sha256sum "$out" > "$out.sha256"

echo "$out"
cat "$out.sha256"
