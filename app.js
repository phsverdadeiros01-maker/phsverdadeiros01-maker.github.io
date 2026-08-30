/* Barcelos Hoje — app.js (sem dependências, sem chaves) */
(function () {
  'use strict';

  // Coordenadas
  var BARCELOS = { lat: 41.538, lon: -8.616 };
  var OFIR = { lat: 41.53, lon: -8.78 };

  // Beacon de visitas -> admin (lê o túnel atual de admin/link.json, nunca fica desatualizado)
  var BEACON_BASE = null;

  // WMO -> [emoji, descrição]
  var WMO = {
    0: ['☀️', 'Céu limpo'], 1: ['🌤️', 'Maioritariamente limpo'], 2: ['⛅', 'Parcialmente nublado'], 3: ['☁️', 'Nublado'],
    45: ['🌫️', 'Nevoeiro'], 48: ['🌫️', 'Neblina com gelo'],
    51: ['🌦️', 'Chuvisco fraco'], 53: ['🌦️', 'Chuvisco'], 55: ['🌧️', 'Chuvisco intenso'],
    56: ['🌧️', 'Chuvisco gelado'], 57: ['🌧️', 'Chuvisco gelado intenso'],
    61: ['🌦️', 'Chuva fraca'], 63: ['🌧️', 'Chuva'], 65: ['🌧️', 'Chuva forte'],
    66: ['🌧️', 'Chuva gelada'], 67: ['🌧️', 'Chuva gelada forte'],
    71: ['🌨️', 'Neve fraca'], 73: ['🌨️', 'Neve'], 75: ['❄️', 'Neve forte'], 77: ['🌨️', 'Grão de neve'],
    80: ['🌦️', 'Aguaceiros fracos'], 81: ['🌧️', 'Aguaceiros'], 82: ['⛈️', 'Aguaceiros fortes'],
    85: ['🌨️', 'Aguaceiros de neve'], 86: ['❄️', 'Aguaceiros de neve fortes'],
    95: ['⛈️', 'Trovoada'], 96: ['⛈️', 'Trovoada com granizo'], 99: ['⛈️', 'Trovoada forte com granizo']
  };
  function wmo(c) { return WMO[c] || ['🌡️', '—']; }

  function $(id) { return document.getElementById(id); }
  function fmtH(h) { var d = new Date(h); return d.getHours() + 'h' + String(d.getMinutes()).padStart(2, '0'); }
  var days = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
  function diaSemana(d) { return days[new Date(d + 'T12:00:00').getDay()]; }
  function setLive(t) { var l = $('live-label'); if (l) l.textContent = t; }
  function stamp(id, t) { var e = $(id); if (e) e.textContent = t; }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }

  /* ---- beacon de visitas (dinâmico: usa o túnel atual publicado no link.json) ---- */
  function beacon() {
    try {
      fetch('admin/link.json?t=' + Date.now()).then(function (r) { return r.json(); })
        .then(function (d) {
          var u = d && d.tunnel;
          if (!u) return;
          BEACON_BASE = u;
          var hit = u + '/hit';
          if (navigator.sendBeacon) { navigator.sendBeacon(hit); }
          else { fetch(hit, { method: 'POST', mode: 'no-cors' }).catch(function () {}); }
        }).catch(function () {});
    } catch (e) {}
  }

  /* ---- 1. Tempo Barcelos ---- */
  function carregarTempo() {
    var url = 'https://api.open-meteo.com/v1/forecast?latitude=' + BARCELOS.lat + '&longitude=' + BARCELOS.lon +
      '&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,uv_index' +
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset&timezone=Europe%2FLisbon&forecast_days=3';
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var c = d.current, e = wmo(c.weather_code);
        $('t-emoji').textContent = e[0];
        $('t-temp').textContent = Math.round(c.temperature_2m) + '°';
        $('t-desc').textContent = e[1] + ' · sensação ' + Math.round(c.apparent_temperature) + '°';
        $('t-meta').innerHTML =
          '<div><b>' + Math.round(c.relative_humidity_2m) + '%</b><span>Humidade</span></div>' +
          '<div><b>' + (c.precipitation || 0) + ' mm</b><span>Chuva agora</span></div>' +
          '<div><b>' + Math.round(c.wind_speed_10m) + ' km/h</b><span>Vento</span></div>' +
          '<div><b>' + (c.uv_index != null ? Math.round(c.uv_index) : '—') + '</b><span>Índice UV</span></div>';
        // hero
        $('h-temp').textContent = Math.round(c.temperature_2m) + '°C';
        $('h-desc').textContent = e[1];
        var dias = d.daily, html = '';
        for (var i = 0; i < dias.time.length; i++) {
          var de = wmo(dias.weather_code[i]);
          var chuva = dias.precipitation_probability_max ? (dias.precipitation_probability_max[i] != null ? dias.precipitation_probability_max[i] + '%' : '—') : ((dias.precipitation_sum[i] || 0) + ' mm');
          html += '<div class="day"><div class="d">' + (i === 0 ? 'Hoje' : diaSemana(dias.time[i])) + '</div>' +
            '<div class="e">' + de[0] + '</div>' +
            '<div class="t">' + Math.round(dias.temperature_2m_max[i]) + '° / ' + Math.round(dias.temperature_2m_min[i]) + '°</div>' +
            '<div class="rain">💧 ' + chuva + '</div></div>';
        }
        $('t-days').innerHTML = html;
        var sun = $('t-sun');
        if (sun) {
          var nascer = dias.sunrise && dias.sunrise[0] ? fmtH(dias.sunrise[0]) : '';
          var por = dias.sunset && dias.sunset[0] ? fmtH(dias.sunset[0]) : '';
          if (nascer || por) sun.textContent = '🌅 Nascer do sol ' + nascer + '  ·  🌇 Pôr do sol ' + por;
        }
        stamp('tempo-stamp', 'atualizado ' + fmtH(c.time));
      })
      .catch(function () { $('t-desc').textContent = 'Tempo indisponível de momento.'; });
  }

  /* ---- 2. Mar Ofir ---- */
  function bandeira(h) {
    if (h <= 0.5) return { c: '#3ec9a7', t: '🟢 Mar calmo — bandeira verde provável' };
    if (h <= 1.0) return { c: '#ffd166', t: '🟡 Ondas moderadas — bandeira amarela provável' };
    if (h <= 1.5) return { c: '#ff9f43', t: '🟠 Mar agitado — cuidado redobrado' };
    return { c: '#ff7a6b', t: '🔴 Mar perigoso — bandeira vermelha provável' };
  }
  function carregarMar() {
    var url = 'https://marine-api.open-meteo.com/v1/marine?latitude=' + OFIR.lat + '&longitude=' + OFIR.lon +
      '&hourly=wave_height,wave_period,wave_direction,sea_surface_temperature&forecast_days=1&timezone=auto';
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var h = d.hourly, now = new Date(), idx = -1;
        for (var i = 0; i < h.time.length; i++) { if (new Date(h.time[i]).getHours() === now.getHours()) { idx = i; break; } }
        if (idx < 0) idx = 0;
        var alt = h.wave_height[idx], per = h.wave_period[idx], dir = h.wave_direction[idx], st = h.sea_surface_temperature[idx];
        var fl = bandeira(alt);
        var ac = $('flag-col'); if (ac) ac.style.background = fl.c;
        var ft = $('flag-txt'); if (ft) ft.textContent = fl.t;
        $('mar-stats').innerHTML =
          '<div class="sea-b"><b>' + alt.toFixed(1) + ' m</b><span>Altura de onda</span></div>' +
          '<div class="sea-b"><b>' + (per ? per.toFixed(1) : '—') + ' s</b><span>Período</span></div>' +
          '<div class="sea-b"><b>' + (dir != null ? Math.round(dir) + '°' : '—') + '</b><span>Direção</span></div>' +
          '<div class="sea-b"><b>' + (st != null ? Math.round(st) + '°' : '—') + '</b><span>Água</span></div>';
        $('mar-info').textContent = 'Estimativa das ' + fmtH(h.time[idx]) + ' — confirma as bandeiras no local com os nadadores-salvadores.';
        // hero
        $('h-wave').textContent = alt.toFixed(1) + ' m';
        $('h-wave-d').textContent = per ? 'período ' + per.toFixed(1) + 's' : '—';
        if (st != null) { $('h-sea').textContent = Math.round(st) + '°C'; $('h-sea-d').textContent = 'água do mar'; }
        stamp('praia-stamp', 'agora');
      })
      .catch(function () { $('mar-info').textContent = 'Dados do mar indisponíveis de momento.'; });
  }

  /* ---- 3. Notícias (rss2json + fallback allorigins) ---- */
  function carregarNoticias() {
    var q = 'Barcelos+OR+Ofir+OR+Esposende';
    var url = 'https://api.rss2json.com/v1/api.json?rss_url=' + encodeURIComponent('https://news.google.com/rss/search?q=' + q + '&hl=pt-PT&gl=PT&ceid=PT:pt');
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) { if (d && d.items && d.items.length) desenharNoticias(d.items); else throw new Error('vazio'); })
      .catch(noticiasFallback);
  }
  function noticiasFallback() {
    var prox = 'https://api.allorigins.win/raw?url=' + encodeURIComponent('https://news.google.com/rss/search?q=Barcelos+OR+Ofir+OR+Esposende&hl=pt-PT&gl=PT&ceid=PT:pt');
    fetch(prox).then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (xml) {
        var doc = new DOMParser().parseFromString(xml, 'text/xml');
        var its = Array.prototype.slice.call(doc.querySelectorAll('item')).slice(0, 8);
        if (!its.length) throw new Error('vazio');
        var items = its.map(function (it) {
          var t = (it.querySelector('title') || {}).textContent || '';
          var m = t.match(/^(.*?)\s+-\s+([^-]+)$/);
          return { titulo: m ? m[1] : t, fonte: m ? m[2] : '', link: (it.querySelector('link') || {}).textContent || '#', pub: (it.querySelector('pubDate') || {}).textContent || '' };
        });
        desenharNoticias(items);
      })
      .catch(function () { $('news-card').innerHTML = '<div class="err">Sem ligação às notícias agora.</div>'; });
  }
  function quandoRel(pub) {
    if (!pub) return '';
    var dt = new Date(pub);
    if (isNaN(dt.getTime())) return '';
    var dif = (Date.now() - dt.getTime()) / 1000;
    if (dif < 60) return 'agora';
    if (dif < 3600) return 'há ' + Math.round(dif / 60) + ' min';
    if (dif < 86400) return 'há ' + Math.round(dif / 3600) + ' h';
    return dt.toLocaleDateString('pt-PT', { day: 'numeric', month: 'short' });
  }
  function desenharNoticias(items) {
    var card = $('news-card'), html = '';
    (items || []).slice(0, 6).forEach(function (it) {
      var titulo = it.titulo || it.title || '';
      var fonte = it.fonte || it.author || '';
      var pub = it.pub || it.pubDate || '';
      html += '<div class="news-item"><div class="nx"><h4><a href="' + esc(it.link || '#') + '" target="_blank" rel="noopener nofollow">' + esc(titulo) + '</a></h4>' +
        '<div class="src">' + (fonte ? '<span class="pill-src">' + esc(fonte) + '</span>' : '') +
        (pub ? '<span class="qnd">🕐 ' + quandoRel(pub) + '</span>' : '') + '</div></div></div>';
    });
    card.innerHTML = html || '<div class="err">Sem notícias de momento.</div>';
  }

  /* ---- início ---- */
  setLive('a carregar…');
  beacon();
  carregarTempo();
  carregarMar();
  carregarNoticias();
  setLive('dados ao vivo · ' + new Date().toLocaleDateString('pt-PT', { day: 'numeric', month: 'short' }));
})();