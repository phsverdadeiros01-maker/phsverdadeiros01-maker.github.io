#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dashboard do servidor — recolhe o estado do Pi e publica dashboard.json no GitHub Pages.

Corre via cron (de 10 em 10 min). Sem dependências externas (só libs standard).
O site (index.html) lê dashboard.json e desenha o painel + gráfico de histórico.
"""
import json, os, re, subprocess, time, datetime, glob, sys

BASE = '/home/jo/barcelos-hoje-site'
OUT  = os.path.join('/home/jo/barcelos-hoje-admin-panel/servidor', 'dashboard.json')
NOW  = datetime.datetime.now(datetime.timezone.utc)

def run(cmd, timeout=12):
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

# ---------------------------------------------------------------- CPU
def cpu_pct():
    def read():
        with open('/proc/stat') as f:
            return [int(x) for x in f.readline().split()[1:]]
    a = read(); time.sleep(0.15); b = read()
    idle_a, idle_b = a[3] + a[4], b[3] + b[4]
    total_a, total_b = sum(a), sum(b)
    idle_d, total_d = idle_b - idle_a, total_b - total_a
    return round(100 * (1 - idle_d / total_d), 1) if total_d else 0.0

# ---------------------------------------------------------------- RAM / DISCO / TEMP / UPTIME / LOAD
def ram():
    line = out('free -m').splitlines()
    if len(line) < 2: return {'used_mb': 0, 'total_mb': 0}
    parts = line[1].split()
    return {'used_mb': int(parts[2]), 'total_mb': int(parts[1])}

def disk():
    free_gb = out("df -BG / | awk 'NR==2{print $4}'").rstrip('G')
    used_pct = out("df / | awk 'NR==2{print $5}'").rstrip('%')
    try: return {'free_gb': int(float(free_gb)), 'used_pct': int(used_pct)}
    except Exception: return {'free_gb': 0, 'used_pct': 0}

def temp_c():
    m = re.search(r'([\d.]+)', out('vcgencmd measure_temp'))
    return float(m.group(1)) if m else None

def uptime_h():
    try:
        with open('/proc/uptime') as f:
            return round(float(f.read().split()[0]) / 3600, 1)
    except Exception:
        return 0.0

def load():
    try:
        with open('/proc/loadavg') as f:
            return [float(x) for x in f.read().split()[:3]]
    except Exception:
        return [0.0, 0.0, 0.0]

# ---------------------------------------------------------------- SERVIÇOS
def servicos():
    # assegura que systemctl --user funciona a partir do cron
    os.environ.setdefault('XDG_RUNTIME_DIR', '/run/user/%d' % os.getuid())
    return [
        {'nome': 'Raspberry Pi',    'ok': True},
        {'nome': 'Tailscale',       'ok': ok('tailscale status >/dev/null 2>&1')},
        {'nome': 'Audiobookshelf',  'ok': ok("ss -tln 2>/dev/null | grep -q ':13378 '")},
        {'nome': 'Navidrome',       'ok': ok('systemctl is-active navidrome.service >/dev/null 2>&1')},
        {'nome': 'Media Hub',       'ok': ok('systemctl is-active portal.service >/dev/null 2>&1')},
        {'nome': 'OpenClaw',        'ok': ok('systemctl --user is-active openclaw-gateway.service >/dev/null 2>&1')},
        {'nome': 'Painel admin',    'ok': ok('systemctl --user is-active admin-panel.service >/dev/null 2>&1')},
        {'nome': 'GitHub',          'ok': True},
    ]

# ---------------------------------------------------------------- AUTOMAÇÕES
def fmt_dt(dt, no_date=False):
    try:
        d = datetime.datetime.fromisoformat(dt)
        if no_date:
            return d.strftime('%H:%M')
        return d.strftime('%d %b %H:%M')
    except Exception:
        return dt

def automacoes():
    items = []

    # 1. Site update (atualizar_dados.sh — 08h/18h)
    info, ok_up = '—', True
    try:
        with open('/tmp/atualizar_dados.log') as f:
            for line in reversed(f.read().splitlines()):
                if 'publicado' in line:
                    m = re.search(r'publicado\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
                    if m:
                        info = fmt_dt(m.group(1).replace(' ', 'T'))
                        ok_up = (datetime.datetime.now() - datetime.datetime.fromisoformat(m.group(1).replace(' ', 'T'))).days <= 2
                    break
    except Exception:
        pass
    items.append({'nome': 'Site update', 'ok': ok_up, 'info': info})

    # 2. Backup OpenClaw
    baks = sorted(glob.glob('/home/jo/*openclaw-backup*.tar.gz'), key=os.path.getmtime, reverse=True)
    if baks:
        mt = datetime.datetime.fromtimestamp(os.path.getmtime(baks[0]))
        items.append({'nome': 'Backup', 'ok': (datetime.datetime.now() - mt).days <= 3, 'info': mt.strftime('%d %b %H:%M')})
    else:
        items.append({'nome': 'Backup', 'ok': False, 'info': 'nunca'})

    # 3. Último git push (site)
    g = out("git -C %s log -1 --format=%%ci" % BASE)
    if g:
        items.append({'nome': 'Último git push', 'ok': True, 'info': fmt_dt(g[:16].replace(' ', 'T'), no_date=False)})
    else:
        items.append({'nome': 'Último git push', 'ok': False, 'info': '—'})

    # 4. Manutenção (última verificação doctor)
    doc = '/tmp/doctor-fix-restart.log'
    if os.path.exists(doc):
        mt = datetime.datetime.fromtimestamp(os.path.getmtime(doc))
        items.append({'nome': 'Manutenção', 'ok': (datetime.datetime.now() - mt).days <= 7, 'info': mt.strftime('%d %b %H:%M')})
    else:
        items.append({'nome': 'Manutenção', 'ok': False, 'info': '—'})

    return items

# ---------------------------------------------------------------- HISTÓRICO (gráfico)
def historico():
    hist = []
    try:
        with open(OUT) as f:
            hist = json.load(f).get('hist', [])
    except Exception:
        pass
    hist.append({
        'ts': NOW.strftime('%H:%M'),
        'cpu': DADOS['cpu'],
        'ram': DADOS['ram']['used_mb'],
        'temp': DADOS['temp_c'] if DADOS['temp_c'] is not None else 0,
    })
    return hist[-48:]  # 48 pontos × 10 min ≈ 8 horas

# ---------------------------------------------------------------- MAIN
DADOS = {
    'host': 'pi',
    'atualizado_em': NOW.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'uptime_h': uptime_h(),
    'load': load(),
    'cpu': cpu_pct(),
    'ram': ram(),
    'disk': disk(),
    'temp_c': temp_c(),
}

# monta com as restantes partes
DADOS['servicos'] = servicos()
DADOS['automacoes'] = automacoes()
DADOS['hist'] = historico()

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(DADOS, f, ensure_ascii=False, indent=1)

# NOTA: dashboard.json viu darrere el login del panell (túnel), no al GitHub.
# Per tant ja no es fa git add/commit/push del dashboard.json públic.

print('OK cpu=%s%% ram=%s/%sMB disco=%sGB temp=%s°C servicos=%d hist=%d'
      % (DADOS['cpu'], DADOS['ram']['used_mb'], DADOS['ram']['total_mb'],
         DADOS['disk']['free_gb'], DADOS['temp_c'], len(DADOS['servicos']), len(DADOS['hist'])))