#!/bin/bash
# Mantém o link /admin apontado para o túnel ATUAL do painel.
# O túnel gratuito (trycloudflare) muda de URL a cada reinício — por isso este
# script extrai SEMPRE o URL vivo do processo/log do cloudflared e publica
# link.json quando deteta mudança. Assim nunca fica com o link desatualizado.
cd /home/jo/barcelos-hoje-site || exit 1

URL=""

# 1. URL vivo: procura no log do cloudflared a linha mais recente com o endereço
LOG=${CLOUDFLARE_LOG:-/tmp/admin-tunnel.log}
if [ -f "$LOG" ]; then
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | tail -1)
fi

# 2. fallback: do processo em execução
if [ -z "$URL" ]; then
  URL=$(ps aux | grep '[c]loudflared tunnel' | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
fi

# 3. último recurso: ficheiro com o último URL conhecido
[ -z "$URL" ] && URL=$(cat admin/tunnel_url.txt 2>/dev/null)
[ -z "$URL" ] && exit 0

# Mantém o tunnel_url.txt a par do URL vivo (para não ficar desatualizado)
if [ "$URL" != "$(cat admin/tunnel_url.txt 2>/dev/null)" ]; then
  printf '%s' "$URL" > admin/tunnel_url.txt
fi

CUR=$(python3 -c "import json;print(json.load(open('admin/link.json'))['tunnel'])" 2>/dev/null)
[ "$URL" = "$CUR" ] && exit 0

python3 - "$URL" <<'PY'
import json, sys, datetime
p = 'admin/link.json'
d = json.load(open(p))
d['tunnel'] = sys.argv[1]
d['updated'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
json.dump(d, open(p, 'w'), indent=2)
PY

git add admin/link.json admin/tunnel_url.txt && git commit -q -m "Atualiza link do túnel admin: $URL" && git push -q origin main
echo "$(date '+%F %T') link atualizado: $URL"
