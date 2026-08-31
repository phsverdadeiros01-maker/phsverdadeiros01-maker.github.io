#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extrai a previsão marítima horária da praia de Ofir (IPMA) e imprime JSON.
Local 247 = Ofir. Fonte: https://www.ipma.pt/pt/maritima/costeira/index.jsp?selLocal=247&idLocal=247
"""
import re, sys, json, urllib.request, datetime

URL = 'https://www.ipma.pt/pt/maritima/costeira/index.jsp?selLocal=247&idLocal=247'

def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', errors='ignore')

DIRS = {'n':'N','s':'S','e':'E','w':'W','no':'NW','ne':'NE','so':'SW','se':'SE',
        'nno':'NNW','nne':'NNE','ono':'WNW','ene':'ENE','sso':'SSW','sse':'SSE',
        'oso':'WSW','ese':'ESE','nw':'NW','sw':'SW','c':'—'}

def dir_icono(img):
    m = re.search(r'mar_([a-z_]+)\.gif', img or '')
    if not m: return ''
    key = m.group(1).replace('_','').lower()
    if key.startswith('ond'): key = key[3:]  # "ond_no" -> "no"
    return DIRS.get(key, key.upper())

def parse(html):
    tabs = re.findall(r'<table[^>]*>.*?</table>', html, re.S)
    # datas: extrair "31 Ago", "1 Set"... das ocorrências getShortDayOfWeekFromArray
    dias_txt = re.findall(r'(\d{1,2})\s*([A-Za-zç]+)', html)
    # melhor: procurar padrão "31 Ago, document.write" — construir lista de datas
    meses = {'jan':1,'fev':2,'mar':3,'abr':4,'mai':5,'jun':6,'jul':7,'ago':8,'set':9,'out':10,'nov':11,'dez':12}
    datas = []
    for mnum, mnome in re.findall(r'(\d{1,2})\s+(Jan|Fev|Mar|Abr|Mai|Jun|Jul|Ago|Set|Out|Nov|Dez)', html):
        d = (int(mnum), meses[mnome.lower()])
        if d not in datas:
            datas.append(d)
    res = []
    for i, t in enumerate(tabs):
        linhas = re.findall(r'<tr[^>]*>.*?</tr>', t, re.S)
        horas = []
        for tr in linhas:
            cels = re.findall(r'<td[^>]*>(.*?)</td>', tr, re.S)
            if len(cels) < 5: continue
            hora = re.sub(r'<[^>]+>','',cels[0]).strip()
            if not re.match(r'^\d{2}h$', hora): continue
            imgs = re.findall(r'<img[^>]*src="([^"]*)"', tr)
            vals = [re.sub(r'<[^>]+>','',c).strip() for c in cels]
            def num(x):
                try: return float(x)
                except: return None
            horas.append({
                'hora': hora,
                'mar_total': num(vals[1]),
                'ondulacao': num(vals[2]),
                'dir_onda': dir_icono(imgs[0]) if len(imgs)>0 else '',
                'periodo_onda': num(vals[4]),
                'periodo_pico': num(vals[5]),
                'vento_nos': num(vals[6]),
                'dir_vento': dir_icono(imgs[1]) if len(imgs)>1 else '',
                'beaufort': num(vals[8]),
                'temp_agua': num(vals[9]),
                'potencia': num(vals[10]),
            })
        # data da tabela
        data = None
        if i < len(datas):
            dd, mm = datas[i]
            data = f'2026-{mm:02d}-{dd:02d}'
        res.append({'data': data, 'horas': horas})
    return res

if __name__ == '__main__':
    html = fetch(URL)
    dias = parse(html)
    out = {'fonte': 'IPMA · Praia de Ofir (local 247)', 'atualizado_em': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'dias': dias}
    print(json.dumps(out, ensure_ascii=False, indent=1))