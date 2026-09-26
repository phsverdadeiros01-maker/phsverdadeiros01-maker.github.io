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
import json, os, sys, urllib.request, urllib.parse, xml.etree.ElementTree as ET, datetime
import difflib, html, re, unicodedata
from email.utils import parsedate_to_datetime

def fetch(url, as_json=False):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux)'})
    with urllib.request.urlopen(req, timeout=25) as r:
        data = r.read()
    return json.loads(data) if as_json else data

def normalized_title(item):
    """Normaliza a manchete e remove o sufixo com o nome da fonte."""
    title = html.unescape(str(item.get('title') or '')).strip()
    source = html.unescape(str(item.get('source') or '')).strip()
    if source:
        title = re.sub(r'\s+[-–—|]\s+' + re.escape(source) + r'\s*$', '', title, flags=re.I)
    title = unicodedata.normalize('NFKD', title).encode('ascii', 'ignore').decode().lower()
    return ' '.join(re.findall(r'[a-z0-9]+', title))

def canonical_link(item):
    link = str(item.get('link') or '').strip()
    if not link or link == '#':
        return ''
    try:
        parsed = urllib.parse.urlsplit(link)
        return urllib.parse.urlunsplit((parsed.scheme.lower(), parsed.netloc.lower(), parsed.path.rstrip('/'), '', ''))
    except Exception:
        return link.split('?', 1)[0].split('#', 1)[0].rstrip('/')

STOPWORDS = {
    'a','ao','aos','as','com','da','das','de','do','dos','e','em','na','nas','no','nos',
    'o','os','para','por','que','se','um','uma','uns','umas','ate','apos','mais','novo','nova'
}

EVENT_PATTERNS = {
    'furto': ('furt', 'assalt', 'roub'),
    'veiculo': ('carro', 'automovel', 'viatura', 'mota'),
    'droga': ('droga', 'haxixe', 'estupefac', 'trafic', 'dose'),
    'detencao': ('detid', 'retid', 'gnr', 'polic'),
    'violencia': ('agress', 'pontape', 'inconsciente', 'ferid'),
    'desporto': ('jogador', 'futebol', 'jogo', 'clube'),
    'incendio': ('incend', 'fogo', 'chamas'),
    'acidente': ('acidente', 'colis', 'despist', 'atropel'),
}

def meaningful_words(item):
    return {word for word in normalized_title(item).split() if word not in STOPWORDS and len(word) > 2}

def event_tags(item):
    words = meaningful_words(item)
    return {tag for tag, patterns in EVENT_PATTERNS.items()
            if any(any(word.startswith(pattern) for pattern in patterns) for word in words)}

def same_story(a, b):
    """Deteta o mesmo artigo e manchetes muito semelhantes entre fontes."""
    link_a, link_b = canonical_link(a), canonical_link(b)
    if link_a and link_b and link_a == link_b:
        return True
    title_a, title_b = normalized_title(a), normalized_title(b)
    if not title_a or not title_b:
        return False
    if title_a == title_b:
        return True
    if difflib.SequenceMatcher(None, title_a, title_b).ratio() >= 0.88:
        return True
    words_a, words_b = meaningful_words(a), meaningful_words(b)
    if words_a == words_b and len(words_a) >= 2:
        return True
    common = len(words_a & words_b)
    overlap = common / max(1, min(len(words_a), len(words_b)))
    ts_a, ts_b = a.get('ts'), b.get('ts')
    close_in_time = not ts_a or not ts_b or abs(ts_a - ts_b) <= 48 * 3600
    if close_in_time and common >= 3 and overlap >= 0.35:
        return True
    locations_a = words_a & {'barcelos', 'esposende'}
    locations_b = words_b & {'barcelos', 'esposende'}
    shared_events = event_tags(a) & event_tags(b)
    return close_in_time and bool(locations_a & locations_b) and len(shared_events) >= 2

def dedupe_items(items):
    ordered = sorted(items, key=lambda x: x.get('ts') or 0, reverse=True)
    parents = list(range(len(ordered)))
    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index
    def union(a, b):
        root_a, root_b = find(a), find(b)
        if root_a != root_b:
            parents[root_b] = root_a
    for i, item in enumerate(ordered):
        for j in range(i):
            if same_story(item, ordered[j]):
                union(i, j)
    chosen = set()
    unique = []
    for i, item in enumerate(ordered):
        root = find(i)
        if root in chosen:
            continue
        chosen.add(root)
        unique.append(item)
    return unique

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
    deduped = dedupe_items(all_items)
    # Fallback Google News se locais não chegam a n
    if len(deduped) < n:
        deduped = dedupe_items(deduped + news_google(q, max(30, n * 5)))
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
    seen = []
    for category in categories:
        unique = []
        for it in category:
            if any(same_story(it, previous) for previous in seen):
                continue
            seen.append(it)
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
        'mundo':     dedupe_items(news_google('Mundo', n=15, topic=True))[:5],
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
