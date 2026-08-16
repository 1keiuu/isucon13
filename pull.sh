#!/usr/bin/env bash

set -ue -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -a
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"
set +a

LANGUAGES=(go node perl php python ruby rust)

# Pull application code & nginx, mysql config file
rsync_args=(--filter=":- .gitignore" -av)
for lang in "${LANGUAGES[@]}"; do
  if [[ "${lang}" != "${LANGUAGE}" ]]; then
    rsync_args+=(--exclude "${lang}/")
  fi
done
rsync "${rsync_args[@]}" isuconapp:/home/isucon/webapp/ ./webapp/
rsync -av isuconapp:/etc/nginx/ ./nginx/
rsync -av isucondb:/etc/mysql/ ./mysql/
