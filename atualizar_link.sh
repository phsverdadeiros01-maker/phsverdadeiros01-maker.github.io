#!/bin/bash
# Mantém o link /admin do site apontado para o túnel atual do painel.
# Corre de hora a hora (ou a pedido): se o URL mudou, atualiza e publica.
cd /home/jo/.openclaw/workspace-glm/site || exit 1

URL=$(cat /home/jo/.openclaw/workspace-glm/site/admin/tunnel_url.txt 2>/dev/null)
[ -z "$URL" ] && URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/admin-tunnel.log 2>/dev/null | head -1)
if [ -z "$URL" ]; then
  # tenta descobrir do processo ativo
  URL=$(ps aux | grep '[c]loudflared tunnel' | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
fi
[ -z "$URL" ] && exit 0

CUR=$(python3 -c "import json;print(json.load(open('admin/link.json'))['tunnel'])" 2>/dev/null)
if [ "$URL" = "$CUR" ]; then
  exit 0
fi

python3 - "$URL" <<'PY'
import json, sys, datetime
p = 'admin/link.json'
d = json.load(open(p))
d['tunnel'] = sys.argv[1]
d['updated'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
json.dump(d, open(p, 'w'), indent=2)
PY

git add admin/link.json && git commit -q -m "Atualiza link do túnel admin: $URL" && git push -q origin main
echo "$(date '+%F %T') link atualizado: $URL"