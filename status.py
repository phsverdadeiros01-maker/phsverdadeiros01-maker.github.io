#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Status público do Pi — gera status.json para o GitHub Pages.

Lê o estado dos serviços do Pi (igual ao dashboard.py) e escreve um JSON
simples em /home/jo/barcelos-hoje-site/status.json. O ciclo do
atualizar_dados.sh trata de commit + push.

Corre de 10 em 10 min via cron (não é pesado). Sem deps externas.
"""
import json, os, re, subprocess, datetime, shutil

BASE = '/home/jo/barcelos-hoje-site'
OUT  = os.path.join(BASE, 'status.json')
NOW  = datetime.datetime.now(datetime.timezone.utc)


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return p
    except Exception:
        return None


def out(cmd):
    p = run(cmd)
    return p.stdout.strip() if p and p.returncode == 0 else ''


def ok(cmd):
    p = run(cmd)
    return p is not None and p.returncode == 0


# ---------------------------------------------------------------- SERVIÇOS
def servicos():
    """Lista dos serviços que aparecem no painel /servidor/."""
    os.environ.setdefault('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid())
    return [
        {'nome': 'Site (GitHub Pages)', 'detalhe': 'phsverdadeiros01-maker.github.io',
         'ok': ok('curl -fsSL --max-time 6 https://phsverdadeiros01-maker.github.io/ -o /dev/null')},
        {'nome': 'IPMA · Mar de Ofir', 'detalhe': 'api.ipma.pt',
         'ok': ok('curl -fsSL --max-time 6 https://api.ipma.pt/open-data/forecast/oceanography/hp-praveira-247.json -o /dev/null')},
        {'nome': 'OpenClaw', 'detalhe': 'gateway',
         'ok': ok('systemctl --user is-active openclaw-gateway.service >/dev/null 2>&1')},
        {'nome': 'Tailscale', 'detalhe': 'mesh',
         'ok': ok('tailscale status >/dev/null 2>&1')},
        {'nome': 'Navidrome', 'detalhe': 'música',
         'ok': ok('systemctl is-active navidrome.service >/dev/null 2>&1')},
        {'nome': 'Audiobookshelf', 'detalhe': 'audiolivros',
         'ok': ok("ss -tln 2>/dev/null | grep -q ':13378 '")},
        {'nome': 'Painel admin', 'detalhe': 'túnel',
         'ok': ok('systemctl --user is-active admin-panel.service >/dev/null 2>&1')},
    ]


# ---------------------------------------------------------------- MÉTRICAS RÁPIDAS
def temp_c():
    m = re.search(r'([\d.]+)', out('vcgencmd measure_temp'))
    return float(m.group(1)) if m else None


def load():
    try:
        with open('/proc/loadavg') as f:
            return [float(x) for x in f.read().split()[:3]]
    except Exception:
        return [0.0, 0.0, 0.0]


def disk_used_pct():
    try:
        return int(out("df / | awk 'NR==2{print $5}'").rstrip('%'))
    except Exception:
        return 0


def ram_used_pct():
    try:
        line = out('free -m').splitlines()[1].split()
        return round(int(line[2]) / int(line[1]) * 100, 1)
    except Exception:
        return 0.0


# ---------------------------------------------------------------- GIT / ÚLTIMO PUSH
def ultimo_push():
    g = out("git -C %s log -1 --format=%%ci" % BASE)
    if not g:
        return None
    try:
        return g[:16].replace(' ', 'T')
    except Exception:
        return None


# ---------------------------------------------------------------- MAIN
ok_count = 0
servs = servicos()
for s in servs:
    if s['ok']:
        ok_count += 1

DADOS = {
    'host': 'pi',
    'atualizado_em': NOW.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'resumo': {
        'total': len(servs),
        'ok': ok_count,
        'falha': len(servs) - ok_count,
    },
    'servicos': servs,
    'metricas': {
        'temp_c': temp_c(),
        'load': load(),
        'ram_pct': ram_used_pct(),
        'disk_pct': disk_used_pct(),
    },
    'ultimo_push': ultimo_push(),
}

os.makedirs(BASE, exist_ok=True)
tmp = OUT + '.tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(DADOS, f, ensure_ascii=False, indent=1)
shutil.move(tmp, OUT)

print('OK %d/%d serviços ok · %s' % (ok_count, len(servs), NOW.strftime('%H:%M:%S')))
