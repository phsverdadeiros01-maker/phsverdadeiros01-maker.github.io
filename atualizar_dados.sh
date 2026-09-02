#!/bin/bash
# Atualização automática do site Barcelos Hoje — 3x/dia (08:00, 12:00 e 18:00)
# - Notícias: Barcelos + Esposende + Mundo (Google News direto)
# - Mar/vento: IPMA oficial (ondas dia0-2 + estação Esposende CIM)
# Publica dados.json no GitHub Pages; o site lê este ficheiro.
cd /home/jo/barcelos-hoje-site || exit 1

python3 - <<'PY'
import json, sys, urllib.request, xml.etree.ElementTree as ET, datetime
from email.utils import parsedate_to_datetime

def fetch(url, as_json=False):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux)'})
    with urllib.request.urlopen(req, timeout=25) as r:
        data = r.read()
    return json.loads(data) if as_json else data

def news(q, n=5, topic=False):
    if topic:
        url = f'https://news.google.com/rss/headlines/section/topic/WORLD?hl=pt-PT&gl=PT&ceid=PT:pt'
    else:
        url = f'https://news.google.com/rss/search?q={q}&hl=pt-PT&gl=PT&ceid=PT:pt'
    try:
        root = ET.fromstring(fetch(url))
    except Exception as e:
        print(f'aviso: falha ao buscar {q}: {e}')
        return []
    items = []
    for it in root.iter('item'):
        t = (it.findtext('title') or '').strip()
        l = it.findtext('link') or '#'
        s = (it.findtext('source') or '').strip()
        pub = (it.findtext('pubDate') or '').strip()
        ts = None
        try:
            ts = int(parsedate_to_datetime(pub).timestamp())
        except Exception:
            pass
        if t and t not in ('Google Notícias', f'"{q}" - Google Notícias', 'Mundo - Mais recentes - Google Notícias'):
            items.append({'title': t, 'link': l, 'source': s, 'ts': ts})
        if len(items) >= n:
            break
    return items

def ipma_ofir():
    """Busca a previsão marítima horária da Praia de Ofir (IPMA local 247)."""
    try:
        import subprocess
        out = subprocess.check_output([sys.executable, 'ipma_ofir.py'], cwd='/home/jo/barcelos-hoje-site', text=True, timeout=45)
        return json.loads(out)
    except Exception as e:
        print(f'aviso: ipma_ofir: {e}')
        return {'fonte': 'IPMA · Praia de Ofir (local 247)', 'dias': [], 'erro': str(e)}

out = {
    'atualizado_em': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'mar': ipma_ofir(),
    'noticias': {
        'barcelos': news('Barcelos'),
        'esposende': news('Esposende'),
        'mundo': news('Mundo', topic=True),
    }
}
with open('dados.json', 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print(f'OK: Barcelos={len(out["noticias"]["barcelos"])} Esposende={len(out["noticias"]["esposende"])} Mundo={len(out["noticias"]["mundo"])}')
print(f'Mar: {len(out["mar"]["dias"])} dias · fonte: {out["mar"]["fonte"]}')
PY

git add dados.json
git diff --cached --quiet || { git commit -q -m "Atualização automática dados $(date '+%d/%m %H:%M')" && git push -q origin main && echo "publicado $(date '+%F %T')"; }