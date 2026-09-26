#!/bin/bash
set -euo pipefail
# Atualização automática do site Barcelos Hoje — 3x/dia (08:00, 12:00 e 18:00)
# - Notícias locais (Barcelos/Esposende): O MINHO + E24 (filtro por keyword) → fallback Google News
# - Notícias Mundo: Google News direto
# - Mar/vento: IPMA oficial (ondas dia0-2 + estação Esposende CIM)
# Gera dados.json; com --publish também cria commit e publica.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

python3 - <<'PY'
import json, os, sys, urllib.request, xml.etree.ElementTree as ET, datetime
from email.utils import parsedate_to_datetime

def fetch(url, as_json=False):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux)'})
    with urllib.request.urlopen(req, timeout=25) as r:
        data = r.read()
    return json.loads(data) if as_json else data

def parse_feed(url, source_name, q, n=20):
    """Parse RSS feed, returns list of items matching keyword q (case-insensitive)."""
    try:
        root = ET.fromstring(fetch(url))
    except Exception as e:
        print(f'  aviso: {source_name} falhou ({e})')
        return []
    items = []
    for it in root.iter('item'):
        t = (it.findtext('title') or '').strip()
        l = it.findtext('link') or '#'
        pub = (it.findtext('pubDate') or '').strip()
        ts = None
        try:
            ts = int(parsedate_to_datetime(pub).timestamp())
        except Exception:
            pass
        if t and q.lower() in t.lower():
            items.append({'title': t, 'link': l, 'source': source_name, 'ts': ts})
    items.sort(key=lambda x: x.get('ts') or 0, reverse=True)
    return items[:n]

def news_local(q, n=6, max_age_h=72):
    """Busca notícias locais com cascata: O MINHO → E24 → Google News fallback."""
    all_items = []
    sources = [
        ('O MINHO', 'https://ominho.pt/feed/'),
        ('E24',     'https://e24.pt/feed/'),
    ]
    for name, url in sources:
        all_items.extend(parse_feed(url, name, q, n=10))
    # Dedup por título
    seen = set()
    deduped = []
    for it in all_items:
        key = it['title'].lower()[:80]
        if key in seen: continue
        seen.add(key)
        deduped.append(it)
    deduped.sort(key=lambda x: x.get('ts') or 0, reverse=True)
    # Fallback Google News se locais não chegam a n
    if len(deduped) < n:
        gn = news_google(q, n - len(deduped))
        for it in gn:
            key = it['title'].lower()[:80]
            if key not in seen:
                seen.add(key)
                deduped.append(it)
    # Cortar por idade (default 72h para locais)
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    deduped = [it for it in deduped if (not it.get('ts')) or (now - it['ts']) <= max_age_h*3600]
    return deduped[:n]

def news_google(q, n=5, topic=False):
    """Busca notícias via Google News RSS (fallback e Mundo)."""
    if topic:
        url = f'https://news.google.com/rss/headlines/section/topic/WORLD?hl=pt-PT&gl=PT&ceid=PT:pt'
    else:
        url = f'https://news.google.com/rss/search?q={q}&hl=pt-PT&gl=PT&ceid=PT:pt'
    try:
        root = ET.fromstring(fetch(url))
    except Exception as e:
        print(f'aviso: google news falhou para {q}: {e}')
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

def dedup_categories(categories):
    """Remove a mesma notícia entre categorias, preservando a primeira ocorrência."""
    seen_links = set()
    seen_titles = set()
    for category in categories:
        unique = []
        for it in category:
            title = ' '.join((it.get('title') or '').lower().split())
            title_key = ''.join(ch for ch in title if ch.isalnum())
            link = (it.get('link') or '').split('&')[0]
            if (link and link in seen_links) or (title_key and title_key in seen_titles):
                continue
            if link: seen_links.add(link)
            if title_key: seen_titles.add(title_key)
            unique.append(it)
        category[:] = unique

def ipma_ofir():
    """Busca a previsão marítima horária da Praia de Ofir (IPMA local 247)."""
    try:
        import subprocess
        out = subprocess.check_output([sys.executable, 'ipma_ofir.py'], cwd=os.getcwd(), text=True, timeout=45)
        return json.loads(out)
    except Exception as e:
        print(f'aviso: ipma_ofir: {e}')
        return {'fonte': 'IPMA · Praia de Ofir (local 247)', 'dias': [], 'erro': str(e)}

out = {
    'atualizado_em': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'mar': ipma_ofir(),
    'noticias': {
        'barcelos':  news_local('Barcelos',  n=6, max_age_h=72),
        'esposende': news_local('Esposende', n=6, max_age_h=72),
        'mundo':     news_google('Mundo', n=5, topic=True),
    }
}
dedup_categories([
    out['noticias']['barcelos'],
    out['noticias']['esposende'],
    out['noticias']['mundo'],
])
with open('dados.json.tmp', 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
os.replace('dados.json.tmp', 'dados.json')
print(f'OK: Barcelos={len(out["noticias"]["barcelos"])} Esposende={len(out["noticias"]["esposende"])} Mundo={len(out["noticias"]["mundo"])}')

# Reportar fontes usadas
for cat, items in out['noticias'].items():
    fontes = {}
    for it in items:
        s = it.get('source','?')
        fontes[s] = fontes.get(s, 0) + 1
    print(f'  {cat}: {dict(fontes)}')
print(f'Mar: {len(out["mar"]["dias"])} dias · fonte: {out["mar"]["fonte"]}')
PY

if [[ "${1:-}" == "--publish" ]]; then
  git add dados.json
  git diff --cached --quiet || {
    git commit -q -m "Atualização automática dados $(TZ=Europe/Lisbon date '+%d/%m %H:%M')"
    git push -q origin main
    echo "publicado $(TZ=Europe/Lisbon date '+%F %T')"
  }
fi
