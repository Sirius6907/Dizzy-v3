/* Dizzy landing logic: release loading, smart OS/ABI picker, reveals.
   No cookies, no analytics. Every download button goes through the tracked
   `dl` edge function (302 to GitHub, counted). File names are deterministic
   per tag, so buttons stay clickable even when the release fetch fails. */
(function () {
  'use strict';

  var SUPABASE = 'https://tiasihuropxrbcxmxorj.supabase.co';
  var DL = SUPABASE + '/functions/v1/dl?src=landing';

  // Exact asset names CI produces (build.yml). Legacy debug-key mirrors are
  // deliberately NOT listed here — they must never be offered.
  var FILES = {
    android: [
      { file: 'Dizzy-v3-arm64-v8a.apk', abi: 'arm64-v8a', label: 'arm64 (most phones)', rec: true },
      { file: 'Dizzy-v3-armeabi-v7a.apk', abi: 'armeabi-v7a', label: 'armeabi (older phones)' },
      { file: 'Dizzy-v3-x86_64.apk', abi: 'x86_64', label: 'x86_64 (tablets, emulators)' },
      { file: 'Dizzy-v3-Universal.apk', abi: 'universal', label: 'Universal (big, works everywhere)' },
    ],
    windows: [
      { file: 'Dizzy-Windows-Setup.exe', label: 'Setup (recommended)', rec: true },
      { file: 'Dizzy-Windows-x64-Portable.zip', label: 'Portable ZIP (no install)' },
    ],
    linux: [
      { file: 'Dizzy-Linux-x86_64.AppImage', label: 'AppImage (recommended)', rec: true },
      { file: 'Dizzy-Linux-x86_64.tar.gz', label: 'tar.gz archive' },
    ],
  };

  var state = { os: 'android', abi: 'arm64-v8a', release: null };
  try {
    var saved = JSON.parse(localStorage.getItem('dizzy-dl') || '{}');
    if (saved.os && FILES[saved.os]) state.os = saved.os;
    if (saved.abi) state.abi = saved.abi;
  } catch (_) { /* private mode — defaults stand */ }

  function $(s, r) { return (r || document).querySelector(s); }
  function $all(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }

  function fmtSize(b) {
    b = Number(b) || 0;
    if (!b) return '';
    return b >= 1048576 ? (b / 1048576).toFixed(1).replace(/\.0$/, '') + ' MB'
      : Math.max(1, Math.round(b / 1024)) + ' KB';
  }
  function fmtCount(n) {
    n = Number(n) || 0;
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return String(n);
  }
  function ago(iso) {
    var s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
    if (!isFinite(s) || s < 0) return '';
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    var d = Math.floor(s / 86400);
    return d === 1 ? 'yesterday' : d + 'd ago';
  }

  function assetByName(name) {
    var a = (state.release && state.release.assets) || [];
    for (var i = 0; i < a.length; i++) if (a[i].name === name) return a[i];
    return null;
  }
  function dlUrl(os, file) {
    return DL + '&os=' + encodeURIComponent(os) + '&file=' + encodeURIComponent(file);
  }
  function persist() {
    try { localStorage.setItem('dizzy-dl', JSON.stringify({ os: state.os, abi: state.abi })); } catch (_) {}
  }

  /* ── release loading: edge fn first, bundled fallback second ── */
  function paintRelease() {
    var r = state.release;
    if (!r) return;
    $all('[data-ver]').forEach(function (el) { el.textContent = r.tag || 'latest'; });
    var total = (r.assets || []).reduce(function (n, a) { return n + (Number(a.download_count) || 0); }, 0);
    $all('[data-total-dl]').forEach(function (el) {
      el.textContent = total > 0 ? fmtCount(total) : 'fresh release';
    });
    var rd = $('[data-rel-date]');
    if (rd && r.published_at) { var a = ago(r.published_at); if (a) rd.textContent = a; }
    renderPanel();
  }

  function loadRelease() {
    fetch(SUPABASE + '/functions/v1/release-latest', { headers: { Accept: 'application/json' } })
      .then(function (res) { if (!res.ok) throw new Error('http ' + res.status); return res.json(); })
      .then(function (d) {
        if (!d || !d.tag) throw new Error('empty');
        state.release = d;
        paintRelease();
      })
      .catch(function () {
        // Offline/dev path: deterministic file names per fallback tag.
        fetch('./releases.json', { headers: { Accept: 'application/json' } })
          .then(function (res) { return res.json(); })
          .then(function (d) { state.release = d; paintRelease(); })
          .catch(function () { renderPanel(); });
      });
  }

  /* ── download panel ── */
  function renderPanel() {
    var os = state.os;
    $all('.tab').forEach(function (t) {
      var on = t.dataset.os === os;
      t.classList.toggle('on', on);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
    });

    var abiRow = $('#abiRow'), abiBtns = $('#abiBtns'), list = $('#fileList');
    var files = FILES[os];

    // ABI picker only for Android; the primary button follows the selection.
    if (os === 'android') {
      abiRow.hidden = false;
      abiBtns.innerHTML = '';
      files.forEach(function (f) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'abi' + (f.abi === state.abi ? ' on' : '');
        b.setAttribute('aria-pressed', f.abi === state.abi ? 'true' : 'false');
        var a = assetByName(f.file);
        b.innerHTML = '<span>' + f.abi + '</span><small>' + (a && a.size ? fmtSize(a.size) : f.label) + '</small>';
        b.addEventListener('click', function () { state.abi = f.abi; persist(); renderPanel(); });
        abiBtns.appendChild(b);
      });
    } else {
      abiRow.hidden = true;
    }

    list.innerHTML = '';
    files.forEach(function (f) {
      var a = assetByName(f.file);
      var row = document.createElement('a');
      row.className = 'file';
      row.href = dlUrl(os, f.file);
      row.rel = 'noopener';
      var sub = a && a.size ? fmtSize(a.size) : (f.label || '');
      row.innerHTML = '<span class="fn">' + f.file + '</span>' +
        (f.rec ? '<span class="tag">recommended</span>' : '') +
        (sub ? '<span class="fs">' + sub + '</span>' : '');
      list.appendChild(row);
    });

    // Primary CTA = recommended file for this OS (ABI selection on Android).
    var primary = $('#dlPrimary');
    var pick = os === 'android'
      ? (files.filter(function (f) { return f.abi === state.abi; })[0] || files[0])
      : files[0];
    primary.href = dlUrl(os, pick.file);
    var pa = assetByName(pick.file);
    primary.textContent = 'Download' + (pa && pa.size ? ' · ' + fmtSize(pa.size) : '');
  }

  $all('.tab').forEach(function (t) {
    t.addEventListener('click', function () {
      state.os = t.dataset.os;
      // Android default: the ABI 99% of modern phones use.
      if (state.os === 'android' && !FILES.android.some(function (f) { return f.abi === state.abi; })) {
        state.abi = 'arm64-v8a';
      }
      persist();
      renderPanel();
    });
  });

  /* ── smart default: detect the visitor's OS once (stored choice wins) ── */
  function detectOS() {
    try {
      var saved = JSON.parse(localStorage.getItem('dizzy-dl') || 'null');
      if (saved && saved.os) return; // explicit choice outranks detection
    } catch (_) {}
    var ua = navigator.userAgent || '';
    var plat = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '';
    if (/android/i.test(ua)) { state.os = 'android'; state.abi = 'arm64-v8a'; }
    else if (/win/i.test(plat)) { state.os = 'windows'; }
    else if (/linux/i.test(plat) && !/android/i.test(ua)) { state.os = 'linux'; }
  }

  /* ── hero CTA label matches the visitor's OS ── */
  function paintHeroCta() {
    var l = $('[data-dl-label]');
    if (l) {
      l.textContent = state.os === 'windows' ? 'Download for Windows'
        : state.os === 'linux' ? 'Download for Linux' : 'Download for Android';
    }
  }

  /* ── reveals + magnetic CTA + sticky nav shadow ── */
  function initMotion() {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.12 });
    $all('.reveal').forEach(function (el) { io.observe(el); });

    if (window.matchMedia('(pointer: fine)').matches) {
      $all('.magnetic').forEach(function (btn) {
        btn.addEventListener('mousemove', function (e) {
          var r = btn.getBoundingClientRect();
          var x = (e.clientX - r.left - r.width / 2) / (r.width / 2);
          var y = (e.clientY - r.top - r.height / 2) / (r.height / 2);
          btn.style.transform = 'translate(' + (x * 8).toFixed(1) + 'px,' + (y * 8).toFixed(1) + 'px)';
        });
        btn.addEventListener('mouseleave', function () { btn.style.transform = ''; });
      });
    }
  }

  detectOS();
  paintHeroCta();
  renderPanel(); // clickable immediately, sizes fill in when release loads
  loadRelease();
  initMotion();

  // Hero CTA label follows tab switches too.
  $all('.tab').forEach(function (t) {
    t.addEventListener('click', paintHeroCta);
  });
})();
