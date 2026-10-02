/* Dizzy landing logic: release loading, smart OS/ABI picker, motion system.
   No cookies, no analytics. Every download button goes through the tracked
   `dl` edge function (302 to GitHub, counted). File names are deterministic
   per tag, so buttons stay clickable even when the release fetch fails.

   Motion contract: everything degrades — no IntersectionObserver, no
   matchMedia or prefers-reduced-motion means content shows instantly. */
(function () {
  'use strict';

  var SUPABASE = 'https://tiasihuropxrbcxmxorj.supabase.co';
  var DL = SUPABASE + '/functions/v1/dl?src=landing';
  var GH = 'https://api.github.com/repos/Sirius6907/Dizzy-v3';

  var reduced = false;
  try { reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (_) {}
  var finePointer = false;
  try { finePointer = window.matchMedia('(pointer: fine)').matches; } catch (_) {}

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

  /* ══ release loading: edge fn first, bundled fallback second ══ */
  function paintRelease() {
    var r = state.release;
    if (!r) return;
    $all('[data-ver]').forEach(function (el) { el.textContent = r.tag || 'latest'; });
    var total = (r.assets || []).reduce(function (n, a) { return n + (Number(a.download_count) || 0); }, 0);
    $all('[data-total-dl]').forEach(function (el) {
      // a day-old release shows "3 downloads" — say "fresh release" instead
      el.textContent = total >= 25 ? fmtCount(total) : 'fresh release';
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

  /* ══ download panel ══ */
  function renderPanel() {
    var os = state.os;
    $all('.tab').forEach(function (t) {
      var on = t.dataset.os === os;
      t.classList.toggle('on', on);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    moveGlider();

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
      row.innerHTML = '<span class="fi" aria-hidden="true">' +
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/></svg></span>' +
        '<span class="fn">' + f.file + '</span>' +
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
    var lab = $('#dlPrimaryLabel');
    if (lab) lab.textContent = 'Download' + (pa && pa.size ? ' · ' + fmtSize(pa.size) : '');
    else primary.textContent = 'Download';
  }

  function moveGlider() {
    var g = $('#tabGlider'), on = $('.tab.on');
    if (!g || !on) return;
    g.style.left = on.offsetLeft + 'px';
    g.style.width = on.offsetWidth + 'px';
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
      paintHeroCta();
    });
  });

  /* ══ smart default: detect the visitor's OS once (stored choice wins) ══ */
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

  /* ══ hero CTA labels match the visitor's OS ══ */
  function paintHeroCta() {
    var label = state.os === 'windows' ? 'Download for Windows'
      : state.os === 'linux' ? 'Download for Linux' : 'Download for Android';
    $all('[data-dl-label]').forEach(function (el) { el.textContent = label; });
  }

  /* ══ scroll progress + sticky nav + active link ══ */
  function initNav() {
    var nav = $('#nav'), bar = $('#progressBar'), last = 0, ticking = false;
    function frame() {
      ticking = false;
      var y = window.pageYOffset || document.documentElement.scrollTop;
      if (bar) {
        var max = (document.documentElement.scrollHeight - window.innerHeight) || 1;
        bar.style.width = Math.min(100, (y / max) * 100) + '%';
      }
      if (nav) {
        nav.classList.toggle('stuck', y > 8);
        var down = y > last && y > 320;
        if (!document.body.classList.contains('menu-open')) nav.classList.toggle('up', down);
      }
      last = y;
      parallax(y);
      sweepReveals();
    }
    window.addEventListener('scroll', function () {
      if (!ticking) { ticking = true; requestAnimationFrame(frame); }
    }, { passive: true });
    frame();

    // active section highlight
    var links = $all('[data-nav]');
    if (links.length && 'IntersectionObserver' in window) {
      var byId = {};
      links.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
      var so = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            links.forEach(function (a) { a.classList.remove('on'); });
            var l = byId[e.target.id];
            if (l) l.classList.add('on');
          }
        });
      }, { rootMargin: '-45% 0px -50% 0px' });
      Object.keys(byId).forEach(function (id) {
        var s = document.getElementById(id);
        if (s) so.observe(s);
      });
    }
  }

  /* ══ hero parallax (scroll-linked, rAF-throttled) ══ */
  var heroParEls = [];
  function parallax(y) {
    if (reduced || !heroParEls.length) return;
    for (var i = 0; i < heroParEls.length; i++) {
      var el = heroParEls[i];
      var f = parseFloat(el.getAttribute('data-par')) || 0;
      el.style.setProperty('--py', (y * f).toFixed(1) + 'px');
    }
  }

  /* ══ reveals with stagger ══ */
  var pendingReveals = [];   // elements waiting to fade in
  var pendingFx = [];        // {el, run} one-shot effects (count-ups, step line)
  // Safety net: IntersectionObserver samples once per frame, so a fast
  // flick-scroll can skip elements — they would stay invisible forever.
  // Sweep anything whose top has entered the viewport on every scroll frame.
  function sweepReveals() {
    var vh = window.innerHeight;
    if (pendingReveals.length) {
      pendingReveals = pendingReveals.filter(function (el) {
        var r = el.getBoundingClientRect();
        if (r.bottom <= -80) { el.classList.add('in'); return false; } // scrolled clean past
        if (r.top < vh * 0.94) { el.classList.add('in'); return false; }
        return true;
      });
    }
    // same safety net for one-shot effects: a flick-scroll must not leave
    // the stats band reading "0 platforms" forever
    if (pendingFx.length) {
      pendingFx = pendingFx.filter(function (fx) {
        var r = fx.el.getBoundingClientRect();
        if (r.bottom <= 0 || r.top < vh * 0.94) { fx.run(fx.el); return false; }
        return true;
      });
    }
  }

  function initReveals() {
    var els = $all('.reveal');
    if (reduced || !('IntersectionObserver' in window)) {
      els.forEach(function (el) { el.classList.add('in'); });
      $all('[data-steps]').forEach(function (s) { s.classList.add('in'); });
      $all('[data-count]').forEach(function (n) { paintCount(n, Number(n.getAttribute('data-count')) || 0); });
      return;
    }
    // stagger siblings inside a shared parent
    var groups = {};
    els.forEach(function (el) {
      var p = el.parentNode;
      var key = p && p.className ? String(p.className) + (p.id || '') : 'x';
      groups[key] = (groups[key] || 0);
      if (!el.style.transitionDelay) el.style.transitionDelay = Math.min(groups[key] * 70, 350) + 'ms';
      groups[key]++;
    });

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    els.forEach(function (el) { io.observe(el); });
    pendingReveals = els.slice();
    sweepReveals();

    // steps progress line + count-up numbers: IO for the pretty trigger,
    // sweepReveals as the guaranteed one
    var steps = $('[data-steps]');
    if (steps) {
      pendingFx.push({ el: steps, run: function (e) { e.classList.add('in'); } });
      var sio = new IntersectionObserver(function (en) {
        en.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); sio.unobserve(e.target); } });
      }, { threshold: 0.3 });
      sio.observe(steps);
    }
    $all('[data-count]').forEach(function (n) { pendingFx.push({ el: n, run: countUp }); });
  }

  function paintCount(el, v) {
    el.textContent = (el.getAttribute('data-prefix') || '') + v + (el.getAttribute('data-suffix') || '');
  }
  function countUp(el) {
    if (el.dataset.counted) return;
    el.dataset.counted = '1';
    var target = Number(el.getAttribute('data-count')) || 0;
    if (target === 0) { paintCount(el, 0); return; }
    var start = performance.now(), dur = 1100;
    (function tick(now) {
      var p = Math.min(1, (now - start) / dur);
      var eased = 1 - Math.pow(1 - p, 3);
      paintCount(el, Math.round(target * eased));
      if (p < 1) requestAnimationFrame(tick);
    })(start);
  }

  /* ══ magnetic buttons + card spotlight ══ */
  function initPointerFX() {
    if (!finePointer || reduced) return;
    $all('.magnetic').forEach(function (btn) {
      btn.addEventListener('mousemove', function (e) {
        var r = btn.getBoundingClientRect();
        var x = (e.clientX - r.left - r.width / 2) / (r.width / 2);
        var y = (e.clientY - r.top - r.height / 2) / (r.height / 2);
        btn.style.transform = 'translate(' + (x * 9).toFixed(1) + 'px,' + (y * 7).toFixed(1) + 'px)';
      });
      btn.addEventListener('mouseleave', function () { btn.style.transform = ''; });
    });
    $all('.card').forEach(function (c) {
      c.addEventListener('mousemove', function (e) {
        var r = c.getBoundingClientRect();
        c.style.setProperty('--mx', ((e.clientX - r.left) / r.width * 100).toFixed(1) + '%');
        c.style.setProperty('--my', ((e.clientY - r.top) / r.height * 100).toFixed(1) + '%');
      });
    });
  }

  /* ══ screenshot rail: buttons, drag, lightbox ══ */
  function initRail() {
    var rail = $('#rail');
    if (!rail) return;
    var step = 340;
    var prev = $('#railPrev'), next = $('#railNext');
    // Own rAF tween instead of smooth scrolling: some engines silently
    // no-op programmatic smooth scrolls, and scroll-snap then fights them.
    function glide(to) {
      to = Math.max(0, Math.min(rail.scrollWidth - rail.clientWidth, to));
      if (reduced) { rail.scrollLeft = to; return; }
      // suspend CSS smooth-scroll + snap for the duration of our own tween,
      // otherwise the engine animates each assignment and snap fights it
      var prevSnap = rail.style.scrollSnapType, prevBeh = rail.style.scrollBehavior;
      rail.style.scrollSnapType = 'none';
      rail.style.scrollBehavior = 'auto';
      var from = rail.scrollLeft, t0 = performance.now(), dur = 480;
      (function step2(t) {
        var p = Math.min(1, (t - t0) / dur);
        rail.scrollLeft = from + (to - from) * (1 - Math.pow(1 - p, 3));
        if (p < 1) { requestAnimationFrame(step2); return; }
        rail.style.scrollSnapType = prevSnap;
        rail.style.scrollBehavior = prevBeh;
      })(t0);
    }
    function glideBy(dir) {
      // snap-aware: aim for the next shot edge, not a raw pixel amount
      var shots = $all('.shot', rail), w = shots.length ? shots[0].offsetWidth + 18 : step;
      var target = rail.scrollLeft + dir * w * Math.max(1, Math.round(step / w));
      glide(target);
    }
    if (prev) prev.addEventListener('click', function () { glideBy(-1); });
    if (next) next.addEventListener('click', function () { glideBy(1); });

    // pointer drag-to-scroll
    var down = false, startX = 0, startL = 0, moved = 0;
    rail.addEventListener('pointerdown', function (e) {
      if (e.pointerType === 'touch') return; // native touch scrolling wins
      down = true; moved = 0;
      startX = e.clientX; startL = rail.scrollLeft;
      rail.classList.add('drag');
    });
    rail.addEventListener('pointermove', function (e) {
      if (!down) return;
      var dx = e.clientX - startX;
      moved = Math.max(moved, Math.abs(dx));
      rail.scrollLeft = startL - dx;
    });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach(function (ev) {
      rail.addEventListener(ev, function () { down = false; rail.classList.remove('drag'); });
    });

    // lightbox
    var lb = $('#lightbox'), lbImg = $('#lbImg'), lbCap = $('#lbCap'), lbClose = $('#lbClose');
    function closeLb() { if (lb) { lb.classList.remove('open'); document.body.style.overflow = ''; } }
    $all('.shot img', rail).forEach(function (img) {
      img.addEventListener('click', function () {
        if (moved > 6) { moved = 0; return; } // it was a drag, not a click
        if (!lb) return;
        lbImg.src = img.currentSrc || img.src;
        lbImg.alt = img.alt;
        lbCap.textContent = img.alt;
        lb.classList.add('open');
        document.body.style.overflow = 'hidden';
      });
    });
    if (lbClose) lbClose.addEventListener('click', closeLb);
    if (lb) lb.addEventListener('click', function (e) { if (e.target === lb) closeLb(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeLb(); });
  }

  /* ══ FAQ accordion (details + animated open/close) ══ */
  function initFaq() {
    var items = $all('.qa');
    items.forEach(function (d) {
      if (d.open) d.classList.add('open');
      var s = d.querySelector('summary');
      if (!s) return;
      s.addEventListener('click', function (e) {
        if (reduced) return; // native behaviour is fine
        e.preventDefault();
        if (d.open) {
          d.classList.remove('open');
          var done = function () { d.open = false; d.removeEventListener('transitionend', done); };
          d.addEventListener('transitionend', done);
          setTimeout(function () { if (d.open && !d.classList.contains('open')) d.open = false; }, 450);
        } else {
          items.forEach(function (o) {
            if (o !== d && o.open) {
              o.classList.remove('open');
              setTimeout(function () { if (!o.classList.contains('open')) o.open = false; }, 350);
            }
          });
          d.open = true;
          requestAnimationFrame(function () { d.classList.add('open'); });
        }
      });
    });
  }

  /* ══ mobile menu ══ */
  function initMenu() {
    var btn = $('#menuBtn'), menu = $('#mobileMenu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function () {
      var open = btn.getAttribute('aria-expanded') === 'true';
      btn.setAttribute('aria-expanded', open ? 'false' : 'true');
      menu.classList.toggle('open', !open);
      document.body.classList.toggle('menu-open', !open);
      $('#nav').classList.remove('up');
    });
    $all('a', menu).forEach(function (a) {
      a.addEventListener('click', function () {
        btn.setAttribute('aria-expanded', 'false');
        menu.classList.remove('open');
        document.body.classList.remove('menu-open');
      });
    });
  }

  /* ══ GitHub stars (real data, degrades to hidden) ══ */
  function loadStars() {
    fetch(GH, { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) { if (!r.ok) throw 0; return r.json(); })
      .then(function (d) {
        if (typeof d.stargazers_count !== 'number' || d.stargazers_count <= 0) return; // never show "0 stars"
        $all('[data-gh-stars]').forEach(function (el) {
          el.textContent = d.stargazers_count >= 1000 ? (d.stargazers_count / 1000).toFixed(1) + 'k' : String(d.stargazers_count);
          el.hidden = false;
        });
        $all('[data-gh-fact]').forEach(function (el) { el.hidden = false; });
      })
      .catch(function () { /* offline or rate-limited — stars stay hidden */ });
  }

  /* ══ boot ══ */
  detectOS();
  paintHeroCta();
  renderPanel(); // clickable immediately, sizes fill in when release loads
  loadRelease();
  initNav();
  initReveals();
  initPointerFX();
  initRail();
  initFaq();
  initMenu();
  loadStars();
  heroParEls = $all('[data-par]');
  window.addEventListener('resize', moveGlider);
  window.addEventListener('load', moveGlider);
  moveGlider();
})();
