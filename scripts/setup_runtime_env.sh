#!/usr/bin/env bash
set -Eeuo pipefail

target="${E2E_ENV_FILE:-/tmp/rails8-ai-e2e.env}"

read -r -p 'E2E base URL (runtime only): ' base_url
read -r -p 'Public target label [runtime-configured deployment]: ' target_label
read -r -p 'E2E email: ' email
read -r -s -p 'E2E password: ' password
printf '\n'

target_label="${target_label:-runtime-configured deployment}"

umask 077
cat > "$target" <<EOF
E2E_BASE_URL=$(printf '%q' "$base_url")
E2E_TARGET_LABEL=$(printf '%q' "$target_label")
E2E_EMAIL=$(printf '%q' "$email")
E2E_PASSWORD=$(printf '%q' "$password")
EOF
chmod 600 "$target"

unset password base_url
echo "Runtime credential file created: $target"
echo "Mode: $(stat -c '%a' "$target")"
echo "Public target label: $target_label"
echo "The raw E2E base URL is used for requests only and is not persisted into public evidence."
