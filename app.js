/* Barcelos Hoje — app.js (sem dependências, sem chaves de API) */
(function () {
  'use strict';

  // ---------- Coordenadas ----------
  var BARCELOS = { lat: 41.538, lon: -8.616 };   // cidade
  var OFIR = { lat: 41.53, lon: -8.78 };          // Praia de Ofir

  // ---------- WMO -> emoji/descrição ----------
  var WMO = {
    0: ['☀️', 'Céu limpo'], 1: ['🌤️', 'Maioritariamente limpo'], 2: ['⛅', 'Parcialmente nublado'], 3: ['☁️', 'Nublado'],
    45: ['🌫️', 'Nevoeiro'], 48: ['🌫️', 'Neblina com gelo'],
    51: ['🌦️', 'Chuvisco fraco'], 53: ['🌦️', 'Chuvisco'], 55: ['🌧️', 'Chuvisco intenso'],
    56: ['🌧️', 'Chuvisco gelado'], 57: ['🌧️', 'Chuvisco gelado intenso'],
    61: ['🌦️', 'Chuva fraca'], 63: ['🌧️', 'Chuva'], 65: ['🌧️', 'Chuva forte'],
    66: ['🌧️', 'Chuva gelada'], 67: ['🌧️', 'Chuva gelada forte'],
    71: ['🌨️', 'Neve fraca'], 73: ['🌨️', 'Neve'], 75: ['❄️', 'Neve forte'],
    77: ['🌨️', 'Grão de neve'],
    80: ['🌦️', 'Aguaceiros fracos'], 81: ['🌧️', 'Aguaceiros'], 82: ['⛈️', 'Aguaceiros fortes'],
    85: ['🌨️', 'Aguaceiros de neve'], 86: ['❄️', 'Aguaceiros de neve fortes'],
    95: ['⛈️', 'Trovoada'], 96: ['⛈️', 'Trovoada com granizo'], 99: ['⛈️', 'Trovoada forte com granizo']
  };
  function wmo(code) { var e = WMO[code]; return e ? e : ['🌡️', '—']; }

  // ---------- Helpers ----------
  function $(id) { return document.getElementById(id); }
  function fmtH(h) { var d = new Date(h); return d.getHours() + 'h' + String(d.getMinutes()).padStart(2, '0'); }
  var days = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
  var months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  function diaSemana(d) { var dt = new Date(d + 'T12:00:00'); return days[dt.getDay()]; }

  // ---------- Estado ----------
  function setLive(txt) { var l = $('live-label'); if (l) l.textContent = txt; }
  function setStamp(id, txt) { var el = $(id); if (el) el.textContent = txt; }

  // ---------- 1. TEMPO (Open-Meteo) ----------
  function carregarTempo() {
    var url = 'https://api.open-meteo.com/v1/forecast' +
      '?latitude=' + BARCELOS.lat + '&longitude=' + BARCELOS.lon +
      '&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m' +
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum' +
      '&timezone=Europe%2FLisbon&forecast_days=5';
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var c = d.current;
        var emo = wmo(c.weather_code);
        $('t-emoji').textContent = emo.e;
        $('t-temp').textContent = Math.round(c.temperature_2m) + '°';
        $('t-desc').textContent = emo.d + ' · sensação ' + Math.round(c.apparent_temperature) + '°';
        $('t-meta').innerHTML =
          '<div><b>' + Math.round(c.relative_humidity_2m) + '%</b>Humidade</div>' +
          '<div><b>' + (c.precipitation || 0) + ' mm</b>Chuva agora</div>' +
          '<div><b>' + Math.round(c.wind_speed_10m) + ' km/h</b>Vento</div>';
        // dias
        var dias = d.daily;
        var html = '';
        for (var i = 0; i < dias.time.length; i++) {
          var e = wmo(dias.weather_code[i]);
          html += '<div class="day"><div class="d">' + (i === 0 ? 'Hoje' : diaSemana(dias.time[i])) + '</div>' +
            '<div class="e">' + e.e + '</div>' +
            '<div class="t"><b>' + Math.round(dias.temperature_2m_max[i]) + '°</b> / ' + Math.round(dias.temperature_2m_min[i]) + '°</div>' +
            '<div class="rain">💧 ' + (dias.precipitation_sum[i] || 0) + ' mm</div></div>';
        }
        $('t-days').innerHTML = html;
        setStamp('tempo-stamp', 'atualizado ' + fmtH(c.time));
      })
      .catch(function () {
        $('tempo-now').innerHTML = '<div class="err">Tempo indisponível de momento. Tenta recarregar a página.</div>';
      });
  }

  // ---------- 2. Mar Ofir (Open-Meteo Marine) ----------
  function bandeiraOndas(h) {
    if (h <= 0.5) return { c: '🟢', t: 'Mar calmo — bandeira verde', k: '#3ec9a7' };
    if (h <= 1.0) return { c: '🟡', t: 'Ondas moderadas — bandeira amarela', k: '#ffd166' };
    if (h <= 1.5) return { c: '🟠', t: 'Mar agitado — cuidado redobrado', k: '#ff9f43' };
    return { c: '🔴', t: 'Mar perigoso — bandeira vermelha provável', k: '#ff7a6b' };
  }
  function bandeiraVento(v) {
    if (v < 15) return '💨 vento fraco';
    if (v < 30) return '🌬️ vento moderado';
    return '🌪️ vento forte';
  }
  function carregarMar() {
    var url = 'https://marine-api.open-meteo.com/v1/marine' +
      '?latitude=' + OFIR.lat + '&longitude=' + OFIR.lon +
      '&hourly=wave_height,wave_period,wave_direction,sea_surface_temperature' +
      '&forecast_days=1&timezone=Europe%2FLisbon';
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        var h = d.hourly;
        var now = new Date();
        // procurar o índice da hora atual
        var idx = -1;
        for (var i = 0; i < h.time.length; i++) {
          var t = new Date(h.time[i]);
          if (t.getHours() === now.getHours()) { idx = i; break; }
        }
        if (idx < 0) idx = 0;
        var alt = h.wave_height[idx], per = h.wave_period[idx], dir = h.wave_direction[idx], st = h.sea_surface_temperature[idx];
        var fl = bandeiraOndas(alt);
        $('mar-stats').innerHTML = '' +
          '<div class="sea-box"><b>' + alt.toFixed(1) + ' m</b><span>Altura de onda</span></div>' +
          '<div class="sea-box"><b>' + (per ? per.toFixed(1) : '—') + ' s</b><span>Período</span></div>' +
          '<div class="sea-box"><b>' + (dir != null ? Math.round(dir) + '°' : '—') + '</b><span>Direção</span></div>' +
          '<div class="sea-box"><b>' + (st != null ? Math.round(st) + '°' : '—') + '</b><span>Água</span></div>';
        var info = $('praia-info');
        info.innerHTML = '<div class="flag" style="border:1px solid ' + fl.k + '"><span class="col" style="background:' + fl.k + '"></span>' + fl.t + '</div>' +
          '<div class="mut" style="margin-top:8px">Estimativa das ' + fmtH(h.time[idx]) + ' · ' + bandeiraVento(0) + ' em alto mar. Confirma bandeiras no local.</div>';
        setStamp('praia-stamp', 'agora');
      })
      .catch(function () {
        $('mar-stats').innerHTML = '<div class="err">Dados do mar indisponíveis de momento.</div>';
      });
  }

  // ---------- 3. Notícias (Google News via rss2json + fallback allorigins) ----------
  function carregarNoticias() {
    var url = 'https://api.rss2json.com/v1/api.json?rss_url=' +
      encodeURIComponent('https://news.google.com/rss/search?q=Barcelos+OR+Ofir+OR+Esposende&hl=pt-PT&gl=PT&ceid=PT:pt');
    fetch(url).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) {
        if (d && d.items && d.items.length) { desenharNoticias(d.items); }
        else { throw new Error('sem items'); }
      })
      .catch(function () { noticiasFallback(); });
  }
  function noticiasFallback() {
    var rss = 'https://news.google.com/rss/search?q=Barcelos+OR+Ofir+OR+Esposende&hl=pt-PT&gl=PT&ceid=PT:pt';
    var prox = 'https://api.allorigins.win/raw?url=' + encodeURIComponent(rss);
    fetch(prox).then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (xml) {
        var doc = new DOMParser().parseFromString(xml, 'text/xml');
        var its = Array.prototype.slice.call(doc.querySelectorAll('item')).slice(0, 8);
        if (!its.length) throw new Error('vazio');
        var items = its.map(function (it) {
          var t = (it.querySelector('title') || {}).textContent || '';
          var m = t.match(/^(.*?)\s+-\s+([^-]+)$/);
          return {
            titulo: m ? m[1] : t,
            fonte: m ? m[2] : '',
            link: (it.querySelector('link') || {}).textContent || '#',
            pub: (it.querySelector('pubDate') || {}).textContent || ''
          };
        });
        desenharNoticias({ items: items });
      })
      .catch(function () {
        $('news-card').innerHTML = '<div class="err">Sem ligação às notícias agora. Tenta mais tarde.</div>';
      });
  }
  function desenharNoticias(d) {
    var card = $('news-card');
    var items = (d.items || []).slice(0, 8);
    if (!items.length) { card.innerHTML = '<div class="err">Sem notícias de momento.</div>'; return; }
    var html = '';
    items.forEach(function (it) {
      var titulo = it.titulo || it.title || '';
      var fonte = it.fonte || it.author || '';
      var pub = it.pub || it.pubDate || '';
      var quando = '';
      if (pub) {
        var dt = new Date(pub);
        if (!isNaN(dt)) quando = dt.toLocaleDateString('pt-PT', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
      }
      html += '<div class="news-item"><div class="nx"><h4><a href="' + (it.link || '#') + '" target="_blank" rel="noopener nofollow">' + titulo + '</a></h4>' +
        '<div class="src">' + (fonte ? '📰 ' + fonte + ' · ' : '') + quando + '</div></div>' +
        '<span class="tag">região</span></div>';
    });
    card.innerHTML = html;
  }

  // ---------- Início ----------
  setLive('A carregar…');
  carregarTempo();
  carregarMar();
  carregarNoticias();
  setLive('Dados ao vivo · ' + new Date().toLocaleDateString('pt-PT'));
})();