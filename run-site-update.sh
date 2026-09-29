#!/usr/bin/env bash
set -euo pipefail

repo=/home/jo/barcelos-hoje-site
state=/home/jo/.openclaw-v82/workspace/admin-panel/site-update-state.json
lock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/barcelos-site-update.lock"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_state() {
  local result="$1" detail="$2"
  python3 - "$state" "$started" "$result" "$detail" <<'PY'
import json, os, sys, tempfile
path, started, result, detail = sys.argv[1:]
data = {"started_at": started, "finished_at": __import__('datetime').datetime.now(__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), "result": result, "detail": detail}
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.site-update-', text=True)
with os.fdopen(fd, 'w', encoding='utf-8') as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
os.replace(tmp, path)
PY
}

exec 9>"$lock"
if ! flock -n 9; then
  write_state skipped "já existe uma atualização em curso"
  exit 0
fi

cd "$repo"
trap 'rc=$?; if (( rc != 0 )); then write_state failed "código de saída $rc; dados anteriores preservados"; fi' EXIT
git pull --ff-only origin main
./atualizar_dados.sh --publish
write_state success "dados validados e publicados"
