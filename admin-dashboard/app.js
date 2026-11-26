// Dizzy Control — dashboard logic (static site, Supabase JS v2 via CDN).
// Config comes from ./config.js (window.DIZZY_CONFIG = {url, anonKey}).
// UI kit (toast/skeletons/confirm/palette) lives in ./ui.js.

let sb = null;
let ROOMS_CACHE = [];
let _roomFilter = '';

function $(id) { return document.getElementById(id); }
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function ago(iso) {
  if (!iso) return '—';
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (!isFinite(s)) return '—';
  if (s < 60) return s + 's ago';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  return Math.floor(s / 86400) + 'd ago';
}
function shortId(id) { return id ? String(id).slice(0, 8) : '—'; }

// ── auth ──
async function boot() {
  const cfg = window.DIZZY_CONFIG || {};
  if (!cfg.url || !cfg.anonKey) {
    $('loginErr').textContent = 'config.js missing — copy config.example.js first.';
    return;
  }
  sb = window.supabase.createClient(cfg.url, cfg.anonKey);
  const { data } = await sb.auth.getSession();
  if (data.session) enterApp(data.session.user.email);
  $('pass').addEventListener('keydown', (e) => { if (e.key === 'Enter') doLogin(); });
}

async function doLogin() {
  const btn = $('loginBtn');
  if (btn.disabled) return;              // guard: Enter fires keydown + form submit
  btn.disabled = true;
  btn.classList.add('loading');
  $('loginErr').textContent = '';
  try {
    const { data, error } = await sb.auth.signInWithPassword({
      email: $('email').value.trim(),
      password: $('pass').value,
    });
    if (error) throw error;
    // must be an admin: admin_users (roles) OR legacy admins allowlist.
    // my_admin_role raises for non-admins, returns the role otherwise.
    // supabase-js v2 resolves with {error} instead of throwing, so the
    // gate has to look at the error, not at the promise.
    const { error: roleErr } = await sb.rpc('my_admin_role', {});
    if (roleErr) {
      await sb.auth.signOut();
      throw new Error('This account is not an admin.');
    }
    enterApp(data.user.email);
  } catch (e) {
    $('loginErr').textContent = e.message || 'Login failed';
  }
  btn.disabled = false;
  btn.classList.remove('loading');
}

async function doLogout() {
  await sb.auth.signOut();
  location.reload();
}

function enterApp(email) {
  $('login').style.display = 'none';
  $('app').classList.add('lit');
  $('meEmail').textContent = email || 'admin';
  $('meAvatar').textContent = String(email || 'a').trim().charAt(0).toUpperCase();
  $('cloudDot').textContent = '● live';
  loadOverview();
  startOverviewLive();          // default tab is Overview
  rtStart();                    // live updates for every tab
  loadMyRole();                 // v1.3.3-T2.0: role badge + tab gating
}

// ── v1.3.3-T2.0: per-admin roles ──
// Server is source of truth (require_role); the dashboard only hides
// buttons. Legacy admins fall back to owner via my_admin_role().
let MY_ROLE = 'viewer';
async function loadMyRole() {
  try {
    MY_ROLE = (await rpc('my_admin_role', {})) || 'viewer';
  } catch (_) { MY_ROLE = 'viewer'; }
  const badge = $('meRole');
  if (badge) badge.textContent = 'Administrator · ' + MY_ROLE;
  const nav = $('navAdmins');
  if (nav) nav.hidden = (MY_ROLE !== 'owner');
}

// ── nav ──
const PAGE_META = {
  overview: ['Overview', 'Live health of the Dizzy fleet'],
  rooms: ['Rooms', 'Watch rooms across the app'],
  moderation: ['Moderation', 'Reported rooms waiting on you'],
  scrapers: ['Scrapers', 'Crowd votes & kill switches'],
  users: ['Fleet', 'Live presence · devices · installs — everything tracked in one place'],
  usernames: ['Usernames', 'Who holds each @name and how to repair a stranded one'],
  push: ['Announcements', 'In-app banners the app polls'],
  config: ['Remote config', 'Flags & limits read at app startup'],
  audit: ['Audit log', 'Every admin write, newest first'],
  devicelogs: ['Device logs', 'Enum-only error telemetry'],
  admins: ['Admins', 'Per-admin accounts and roles'],
  support: ['Support', 'AI-escalated tickets waiting on you'],
  curated: ['Curated', 'Playlists and shelves the app shows'],
};

function show(name) {
  document.querySelectorAll('nav .nav-btn').forEach((b) => {
    const on = b.dataset.s === name;
    b.classList.toggle('on', on);
    b.setAttribute('aria-selected', on ? 'true' : 'false');
  });
  document.querySelectorAll('main section').forEach((s) => s.classList.toggle('on', s.id === 's-' + name));
  const meta = PAGE_META[name];
  if (meta) { $('pageTitle').textContent = meta[0]; $('pageSub').textContent = meta[1]; }
  closeNav();
  if (name === 'rooms') loadRooms();
  if (name === 'moderation') { loadRooms(true); loadUserReports(); loadAppeals(); }
  if (name === 'scrapers') loadScrapers();
  if (name === 'overview') startOverviewLive(); else stopOverviewLive();
  if (name === 'users') { loadUsers(); loadDevices(); loadOrphans(); startFleetLive(); } else stopFleetLive();
  if (name === 'usernames') loadUsernames();
  if (name === 'push') { loadAnn(); loadPushLog(); loadPushAudience(); loadPushEvents(); loadCampaign(); }
  if (name === 'config') loadCfg();
  if (name === 'audit') { loadAudit(); loadIdentityTail(); } else stopAuditLive();
  if (name === 'devicelogs') loadDeviceLogs(); else stopDeviceLogsLive();
  if (name === 'admins' && MY_ROLE === 'owner') loadAdmins();
  if (name === 'support') { loadTickets(); loadSupportStats(); loadSupportAnswers(); }
  if (name === 'curated') loadCurated();
}

async function rpc(name, params) {
  const { data, error } = await sb.rpc(name, params || {});
  if (error) throw error;
  return data;
}

// ── realtime ─────────────────────────────────────────────────────────
// One websocket drives every tab: a change lands, the owning loader runs,
// no polling and no manual refresh. A 400 ms debounce collapses bursts
// (a heartbeat flood from 50 devices is one repaint), and loaders only run
// for the tab that is actually on screen. Polling remains as a slow
// safety net in case the socket drops.
const RT_MAP = {
  devices: ['overview', 'users'],
  device_logs: ['devicelogs'],
  user_reports: ['moderation'],
  ban_appeals: ['moderation'],
  room_reports: ['rooms'],
  support_tickets: ['support'],
  announcements: ['push'],
  remote_config: ['config', 'scrapers'],
  admin_audit: ['audit'],
  curated_playlists: ['curated'],
  rooms: ['rooms'],
  push_send_log: ['push'],
  usernames: ['users'],
  identity_history: ['users'],
};
const RT_LOADERS = {
  overview: () => loadUsage(),
  users: () => { loadFleetLive(); loadDevices(); loadOrphans(); loadIdentity(); },
  devicelogs: () => loadDeviceLogs(),
  moderation: () => { loadUserReports(); loadAppeals(); },
  rooms: () => loadRooms(),
  support: () => { loadTickets(); loadSupportStats(); loadSupportAnswers(); },
  push: () => { loadAnn(); loadPushLog(); loadPushAudience(); loadPushEvents(); },
  config: () => loadCfg(),
  scrapers: () => loadScrapers(),
  audit: () => loadAudit(),
  curated: () => loadCurated(),
};

const _rtTimers = new Map();
let _rtChannel = null;

function rtFire(tab) {
  const sec = $('s-' + tab);
  if (!sec || !sec.classList.contains('on')) return;
  // Audit and device logs keep their explicit Live switch.
  if (tab === 'audit' && !($('auditLive') || {}).checked) return;
  if (tab === 'devicelogs' && !($('dlLive') || {}).checked) return;
  const fn = RT_LOADERS[tab];
  if (!fn) return;
  clearTimeout(_rtTimers.get(tab));
  _rtTimers.set(tab, setTimeout(() => {
    _rtTimers.delete(tab);
    try { fn(); } catch (_) { /* keep the socket alive */ }
  }, 400));
}

function rtStart() {
  if (_rtChannel || !sb) return;
  let ch = sb.channel('admin-live');
  Object.entries(RT_MAP).forEach(([table, tabs]) => {
    ch = ch.on('postgres_changes', { event: '*', schema: 'public', table }, () => tabs.forEach(rtFire));
  });
  _rtChannel = ch.subscribe((status) => {
    const dot = $('cloudDot');
    if (dot) dot.textContent = status === 'SUBSCRIBED' ? '● live' : '○ reconnecting';
  });
}

function rtStop() {
  if (!_rtChannel) return;
  sb.removeChannel(_rtChannel);
  _rtChannel = null;
}

// A tab left open for hours may outlive the socket; refresh the visible tab
// when the window comes back rather than waiting for the next event.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') return;
  const sec = document.querySelector('main section.on');
  if (!sec) return;
  const fn = RT_LOADERS[sec.id.replace(/^s-/, '')];
  if (fn) { try { fn(); } catch (_) {} }
});

// ── overview ──
async function loadOverview() {
  const statsEl = $('statCards');
  if (!statsEl.children.length) statsEl.innerHTML = skStats(6);
  $('breakdown').innerHTML = skLines(5);
  $('health').innerHTML = skLines(3);
  try {
    const o = await rpc('admin_overview');
    const cards = [
      ['📱', 'Installs', o.installs, 'total'],
      ['🟢', 'Active 7d', o.installs_7d, 'users'],
      ['🏠', 'Rooms live', o.rooms_live, 'rooms'],
      ['👥', 'In rooms', o.members_live, 'now'],
      ['🚩', 'Reports', o.reports_pending, 'pending'],
      ['🗳️', 'Scraper votes', o.scraper_votes_7d, '7d'],
    ];
    statsEl.innerHTML = cards.map((c) => `
      <div class="stat">
        <div class="stat-top"><span class="stat-ico">${c[0]}</span><span class="stat-l">${c[1]}</span></div>
        <div class="n">${fmtNum(c[2])}<small>${c[3]}</small></div>
      </div>`).join('');

    const badge = $('navReports');
    if (badge) {
      const n = Number(o.reports_pending) || 0;
      badge.hidden = !n;
      badge.textContent = n;
    }

    const daily = await rpc('admin_installs_daily', { p_days: 30 });
    drawBars($('chInstalls'), (daily || []).map((d) => ({
      v: Number(d.n) || 0,
      t: d.day || d.date || d.d || '',
    })));
    const peak = (daily || []).reduce((m, d) => Math.max(m, Number(d.n) || 0), 0);
    $('chInstallsPeak').textContent = peak ? `peak ${peak}/day` : 'no data';

    const b = await rpc('admin_breakdown');
    const maxP = Math.max(1, ...(b.platforms || []).map((p) => p.n));
    $('breakdown').innerHTML =
      `<div class="bd-group"><div class="bd-l"><span>Platforms</span><span>${(b.platforms || []).length}</span></div>` +
      (b.platforms || []).map((p) => `
        <div class="bd-row"><span class="nm">${esc(p.name)}</span><span class="vl">${fmtNum(p.n)}</span></div>
        <div class="bd-bar"><i style="width:${Math.round((p.n / maxP) * 100)}%"></i></div>`).join('') +
      `</div>` +
      `<div class="bd-group"><div class="bd-l"><span>Versions</span><span>${(b.versions || []).length}</span></div>
        <div class="bd-chips">${(b.versions || []).map((p) =>
          `<span class="chip">${esc(p.name)} · <b style="margin-left:4px">${fmtNum(p.n)}</b></span>`).join('')}</div></div>` +
      `<div class="bd-group"><div class="bd-l"><span>Consents</span><span>of ${b.consents.total}</span></div>
        <div class="bd-consent">
          <div><b>${fmtNum(b.consents.telemetry)}</b><span>telemetry</span></div>
          <div><b>${fmtNum(b.consents.genre_prefs)}</b><span>genre prefs</span></div>
          <div><b>${fmtNum(b.consents.crash)}</b><span>crash reports</span></div>
          <div><b>${fmtNum(b.consents.watch_party)}</b><span>watch party</span></div>
        </div></div>`;

    $('health').innerHTML = `
      <div class="health">
        <div class="hbox"><span class="hi">🏠</span><div><b>${fmtNum(o.rooms_live)}</b><span>rooms live</span></div></div>
        <div class="hbox"><span class="hi">👥</span><div><b>${fmtNum(o.members_live)}</b><span>members right now</span></div></div>
        <div class="hbox"><span class="hi">🚩</span><div><b>${fmtNum(o.reports_pending)}</b><span>pending reports</span></div></div>
        <div class="hbox"><span class="hi">📣</span><div><b>${fmtNum(o.announcements)}</b><span>active announcements</span></div></div>
      </div>
      <div class="health-foot"><span class="dot dot-grn"></span> Supabase connected · live updates streamed as they happen</div>`;
    $('ovUpdated').textContent = 'updated ' + ago(new Date().toISOString());
  } catch (e) {
    $('breakdown').innerHTML = emptyState('⚠️', 'Breakdown unavailable', e.message);
    $('health').innerHTML = emptyState('⚠️', 'Health check failed', e.message);
    toast('Overview failed: ' + e.message, 'err');
  }
}

// ── Phase O1/O2: users + downloads (admin_usage_stats + release-latest) ──
// One RPC feeds both the Users stats row and the Downloads card. GitHub
// numbers come from OUR edge fn (5-min DB cache), never GitHub directly —
// unauthenticated GitHub is 60 req/hr per IP.
// Counting semantics: landing ⊂ GitHub total; "GitHub-direct ≈" is derived.
let _ovTimer = null;
let _usage = null;
let _gh = null;   // {total, tag, fetchedAt} | null before the first fetch

function statCard(c) {
  const v = (c[2] === null || c[2] === undefined) ? '—' : fmtNum(c[2]);
  return `<div class="stat">
    <div class="stat-top"><span class="stat-ico">${c[0]}</span><span class="stat-l">${esc(c[1])}</span></div>
    <div class="n">${v}<small>${esc(c[3] || '')}</small></div>
  </div>`;
}

async function fetchReleaseLatest() {
  const cfg = window.DIZZY_CONFIG || {};
  const base = String(cfg.url || '').replace(/\/$/, '');
  if (!base) throw new Error('no supabase url in config.js');
  const res = await fetch(base + '/functions/v1/release-latest',
    { headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error('release-latest ' + res.status);
  const d = await res.json();
  if (!d || !d.tag) throw new Error('release-latest empty');
  return {
    tag: d.tag,
    fetchedAt: d.fetched_at,
    total: (d.assets || []).reduce((n, a) => n + (Number(a.download_count) || 0), 0),
  };
}

function paintDownloads() {
  if (!_usage) return;
  const statsEl = $('dlStats'), barsEl = $('dlBars'), freshEl = $('dlFresh');
  const dl = _usage.downloads || {};
  const landingToday = Number(dl.landing_today) || 0;
  const landingTotal = Number(dl.landing_total) || 0;
  const ghTotal = _gh ? _gh.total : null;
  const ghDirect = (ghTotal !== null) ? Math.max(0, ghTotal - landingTotal) : null;

  if (statsEl) {
    statsEl.innerHTML = [
      ['⬇️', 'Landing today', landingToday, 'tracked'],
      ['📦', 'Landing total', landingTotal, 'all time'],
      ['🐙', 'GitHub total', ghTotal, 'all sources'],
      ['⚡', 'GitHub-direct ≈', ghDirect, 'derived'],
    ].map(statCard).join('');
  }

  const files = dl.landing_by_file || [];
  const maxF = Math.max(1, ...files.map((f) => Number(f.count) || 0));
  if (barsEl) {
    barsEl.innerHTML = files.length
      ? `<div class="bd-group"><div class="bd-l"><span>Landing downloads by file</span><span>${fmtNum(landingTotal)}</span></div>` +
        files.map((f) => `
        <div class="bd-row"><span class="nm mono">${esc(f.file)}</span><span class="vl">${fmtNum(f.count)}</span></div>
        <div class="bd-bar"><i style="width:${Math.round(((Number(f.count) || 0) / maxF) * 100)}%"></i></div>`).join('') +
        `</div>`
      : emptyState('⬇️', 'No landing downloads yet',
          'Counts appear the moment someone downloads from the site.');
  }

  if (freshEl) {
    freshEl.textContent = _gh
      ? `${_gh.tag} · GitHub counts ${ago(_gh.fetchedAt)}`
      : 'GitHub counts —';
    freshEl.title = _gh
      ? `Cached by release-latest · fetched ${fmtAbs(_gh.fetchedAt)}`
      : 'release-latest not reachable yet — landing numbers stay live';
  }
}

async function loadUsage() {
  const uEl = $('userStats'), dEl = $('dlStats');
  if (uEl && !uEl.children.length) uEl.innerHTML = skStats(7);
  if (dEl && !dEl.children.length) dEl.innerHTML = skStats(4);
  try {
    _usage = await rpc('admin_usage_stats');
    if (uEl) {
      uEl.innerHTML = [
        ['📡', 'Devices (Android)', _usage.total_devices, 'total'],
        ['👤', 'Accounts', _usage.accounts, 'registered'],
        ['🟢', 'Active now', _usage.active_now, '<10 min'],
        ['📅', 'DAU', _usage.dau, '24h'],
        ['📆', 'WAU', _usage.wau, '7d'],
        ['🗓️', 'MAU', _usage.mau, '30d'],
        ['✨', 'New today', _usage.new_today, 'first boot'],
      ].map(statCard).join('');
    }
  } catch (e) {
    if (uEl) uEl.innerHTML = emptyState('⚠️', 'Usage stats unavailable', e.message);
    if (dEl) dEl.innerHTML = emptyState('⚠️', 'Usage stats unavailable', e.message);
    toast('Usage stats failed: ' + e.message, 'err');
    return;
  }
  try {
    _gh = await fetchReleaseLatest();
  } catch (_) {
    // Keep the last known numbers (the chip ages naturally via ago()); a
    // flaky edge fn must never blank the card.
  }
  paintDownloads();
}

// Realtime does the instant updates; this slow poll only exists in case the
// websocket drops, and only while the Overview tab is open.
function startOverviewLive() {
  loadUsage();
  if (_ovTimer) clearInterval(_ovTimer);
  _ovTimer = setInterval(loadUsage, 120000);
}
function stopOverviewLive() {
  if (_ovTimer) { clearInterval(_ovTimer); _ovTimer = null; }
}

/* ── installs chart (DPR-aware, gradient bars, hover tooltip) ── */
const _chart = { cv: null, data: [], bars: [], hover: -1, bound: false };

function drawBars(cv, vals) {
  _chart.cv = cv;
  _chart.data = (vals || []).map((x, i) => ({
    v: typeof x === 'object' && x !== null ? (Number(x.v) || 0) : (Number(x) || 0),
    t: (typeof x === 'object' && x !== null && x.t) ? String(x.t) : '',
    i,
  }));
  _chart.hover = -1;
  if (cv && !_chart.bound) {
    _chart.bound = true;
    cv.addEventListener('mousemove', (e) => {
      const r = cv.getBoundingClientRect();
      const x = e.clientX - r.left;
      let hit = -1;
      _chart.bars.forEach((b) => { if (x >= b.x - 2 && x <= b.x + b.w + 2) hit = b.i; });
      if (hit !== _chart.hover) { _chart.hover = hit; renderBars(); }
    });
    cv.addEventListener('mouseleave', () => { _chart.hover = -1; renderBars(); });
    let rt = null;
    window.addEventListener('resize', () => {
      clearTimeout(rt);
      rt = setTimeout(renderBars, 120);
    });
  }
  renderBars();
}

function roundPath(ctx, x, y, w, h, r) {
  const rr = Math.min(r, w / 2, Math.max(0, h));
  if (typeof ctx.roundRect === 'function') {
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, [rr, rr, 0, 0]);
    return;
  }
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.lineTo(x + w - rr, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
  ctx.lineTo(x + w, y + h);
  ctx.lineTo(x, y + h);
  ctx.lineTo(x, y + rr);
  ctx.quadraticCurveTo(x, y, x + rr, y);
  ctx.closePath();
}

function renderBars() {
  const cv = _chart.cv;
  if (!cv || !cv.isConnected) return;
  const box = cv.parentElement;
  const W = Math.max(240, (box && box.clientWidth) || cv.clientWidth || 600);
  const H = Math.max(160, (box && box.clientHeight) || cv.clientHeight || 210);
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  cv.width = Math.round(W * dpr);
  cv.height = Math.round(H * dpr);
  const ctx = cv.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, W, H);

  const data = _chart.data;
  if (!data.length) {
    ctx.fillStyle = '#666e82';
    ctx.font = '12px Inter, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('No install data yet', W / 2, H / 2);
    _chart.bars = [];
    return;
  }

  const padL = 34, padR = 8, padT = 16, padB = 8;
  const plotH = H - padT - padB;
  const max = Math.max(1, ...data.map((d) => d.v));

  // gridlines + y labels
  ctx.font = '10px Inter, sans-serif';
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';
  for (let g = 0; g <= 3; g++) {
    const val = Math.round((max * g) / 3);
    const y = padT + plotH * (1 - g / 3);
    ctx.strokeStyle = g === 0 ? 'rgba(255,255,255,.12)' : 'rgba(255,255,255,.055)';
    ctx.beginPath();
    ctx.moveTo(padL, Math.round(y) + 0.5);
    ctx.lineTo(W - padR, Math.round(y) + 0.5);
    ctx.stroke();
    ctx.fillStyle = '#666e82';
    ctx.fillText(String(val), padL - 7, y);
  }

  const grad = ctx.createLinearGradient(0, padT, 0, H - padB);
  grad.addColorStop(0, '#f9e3b0');
  grad.addColorStop(1, '#e8912a');
  const hot = ctx.createLinearGradient(0, padT, 0, H - padB);
  hot.addColorStop(0, '#d9556e');
  hot.addColorStop(1, '#8e1f35');

  const iw = (W - padL - padR) / data.length;
  const bw = Math.max(3, Math.min(26, iw * 0.62));
  _chart.bars = [];
  data.forEach((d, i) => {
    const h = (d.v / max) * plotH;
    const x = padL + i * iw + (iw - bw) / 2;
    const y = H - padB - h;
    ctx.fillStyle = i === _chart.hover ? hot : grad;
    roundPath(ctx, x, y, bw, Math.max(h, d.v > 0 ? 2 : 0), 3);
    ctx.fill();
    _chart.bars.push({ x, y, w: bw, h, i });
  });

  // hover tooltip
  const hb = _chart.hover >= 0 ? _chart.bars[_chart.hover] : null;
  if (hb) {
    const d = data[hb.i];
    const label = d.v + (d.v === 1 ? ' install' : ' installs') + (d.t ? ' · ' + d.t : ' · day ' + (hb.i + 1));
    ctx.font = '600 11.5px Inter, sans-serif';
    const tw = ctx.measureText(label).width + 18;
    const th = 24;
    let tx = hb.x + hb.w / 2 - tw / 2;
    tx = Math.max(padL, Math.min(W - padR - tw, tx));
    const ty = Math.max(2, hb.y - th - 6);
    ctx.fillStyle = 'rgba(24,27,38,.97)';
    ctx.strokeStyle = 'rgba(255,255,255,.16)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') ctx.roundRect(tx, ty, tw, th, 6);
    else ctx.rect(tx, ty, tw, th);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#f2f4f8';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, tx + tw / 2, ty + th / 2 + 0.5);
  }
}

// ── rooms ──
function roomStatusPill(r) {
  const cls = r.status === 'live' ? 'p-live' : r.status === 'lobby' ? 'p-lobby' : 'p-closed';
  return `<span class="pill ${cls}">${esc(r.status)}</span>`;
}

function roomRow(r) {
  return `<tr data-click onclick="roomDetail('${r.room_id}')" title="Open room detail">
    <td class="mono" title="${esc(r.room_id)}">${esc(shortId(r.room_id))}…</td>
    <td>${esc(r.title || '—')}${r.is_adult ? ' <span class="pill p-adult plain">18+</span>' : ''}${r.locked ? ' <span class="pill p-lock plain">🔒</span>' : ''}</td>
    <td>${roomStatusPill(r)}</td>
    <td><span class="pill ${r.visibility === 'public' ? 'p-pub' : 'p-priv'} plain">${esc(r.visibility)}</span></td>
    <td class="num"><b>${Number(r.members) || 0}</b></td>
    <td class="num">${r.reports > 0 ? '🚩<b>' + r.reports + '</b>' : '<span class="mut">—</span>'}</td>
    <td class="mut"><span title="${esc(fmtAbs(r.created_at))}">${ago(r.created_at)}</span></td>
  </tr>`;
}

function paintRooms() {
  const tb = document.querySelector('#roomsTbl tbody');
  if (!tb) return;
  const q = (($('roomSearch') && $('roomSearch').value) || '').trim().toLowerCase();
  const list = ROOMS_CACHE.filter((r) =>
    (!_roomFilter || r.status === _roomFilter) &&
    (!q || String(r.room_id).toLowerCase().includes(q) || String(r.title || '').toLowerCase().includes(q)));
  tb.innerHTML = list.map(roomRow).join('') ||
    `<tr><td colspan="7">${emptyState('🔍', 'No rooms match', 'Try clearing the search or status filter.')}</td></tr>`;
}

function setRoomFilter(st) {
  _roomFilter = st || '';
  document.querySelectorAll('#roomFilters .chip-btn').forEach((b) =>
    b.classList.toggle('on', (b.dataset.st || '') === _roomFilter));
  paintRooms();
}
function filterRooms() { paintRooms(); }

async function loadRooms() {
  const tb = document.querySelector('#roomsTbl tbody');
  if (tb && !ROOMS_CACHE.length) tb.innerHTML = skRows(6, 7);
  try {
    const rooms = await rpc('admin_rooms', { p_limit: 50 });
    ROOMS_CACHE = rooms || [];
    paintRooms();

    // moderation tab: only reported
    const rep = ROOMS_CACHE.filter((r) => r.reports > 0);
    const badge = $('navReports');
    if (badge) { badge.hidden = !rep.length; badge.textContent = rep.length; }
    if ($('modCount')) $('modCount').textContent = rep.length ? rep.length + ' waiting' : '';
    $('repList').innerHTML = rep.length === 0
      ? emptyState('🎉', 'No reported rooms', 'Everything is clean right now.')
      : rep.map((r) => `
        <div class="rep">
          <div class="rep-top">
            <b class="mono" title="${esc(r.room_id)}">${esc(shortId(r.room_id))}…</b>
            <span class="pill p-adult plain">🚩 ${r.reports}</span>
            <span class="pill p-closed plain">👥 ${r.members}</span>
            ${roomStatusPill(r)}
            ${r.is_adult ? '<span class="pill p-priv plain">18+</span>' : ''}
          </div>
          <div class="rep-meta">${esc(r.title || 'Untitled room')} · created ${ago(r.created_at)}</div>
          <div class="rowbtns">
            <button onclick="roomDetail('${r.room_id}')">🔍 Inspect</button>
            <button class="danger" onclick="roomAct('${r.room_id}','close')">Close room</button>
            <button onclick="roomAct('${r.room_id}','lock')">🔒 Lock</button>
            <button class="ok" onclick="roomAct('${r.room_id}','unlock')">🔓 Unlock</button>
            <button class="ok" onclick="clearRep('${r.room_id}')">✓ Dismiss reports</button>
          </div>
        </div>`).join('');
  } catch (e) { toast('Rooms failed: ' + e.message, 'err'); }
}

async function roomDetail(roomId) {
  try {
    const d = await rpc('admin_room_detail', { p_room_id: roomId });
    const r = d.room || {};
    const members = d.members || [];
    const chat = d.chat || [];
    $('sheet').innerHTML = `
      <button class="icon-btn sheet-close" onclick="closeModal()" title="Close (Esc)" aria-label="Close">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
      </button>
      <h2>🏠 ${esc(r.title || roomId)}</h2>
      <div class="sheet-sub"><span class="mono">${esc(roomId)}</span> · created ${ago(r.created_at)}</div>
      <div class="kv">
        <b>Status</b><span>${roomStatusPill(r)} <span class="pill ${r.visibility === 'public' ? 'p-pub' : 'p-priv'} plain">${esc(r.visibility || '')}</span>${r.locked ? ' <span class="pill p-lock plain">🔒 locked</span>' : ''}${r.is_adult ? ' <span class="pill p-adult plain">🔞 adult</span>' : ''}</span>
        <b>Media</b><span class="mono">${esc(r.media_ref || '—')}</span>
        <b>Members</b><span>${members.length}</span>
        <b>Reports</b><span>${d.reports ? '🚩 ' + d.reports : 'none 🎉'}</span>
        <b>Created</b><span title="${esc(fmtAbs(r.created_at))}">${ago(r.created_at)}</span>
        <b>Notes</b><span>${esc(r.admin_notes || '—')}</span>
      </div>
      <h4>👥 Members <span class="mut" style="font-weight:400">${members.length}</span></h4>
      <div class="tbl-wrap">${members.length ? `<table>
        <thead><tr><th>User</th><th>Role</th><th>Seen</th><th>Joined</th></tr></thead><tbody>
        ${members.map((m) => `<tr><td class="mono">${esc(shortId(m.user_id))}…</td><td>${esc(m.role)}</td>
          <td class="mut" title="${esc(fmtAbs(m.last_seen))}">${ago(m.last_seen)}</td>
          <td class="mut" title="${esc(fmtAbs(m.joined_at))}">${ago(m.joined_at)}</td></tr>`).join('')}
        </tbody></table>` : emptyState('👤', 'No members yet', '')}</div>
      <h4>💬 Recent chat <span class="mut" style="font-weight:400">last 50</span></h4>
      <div class="chatbox">${chat.length ? chat.map((c) =>
        `<div><span class="who">${esc(c.sender_code || shortId(c.sender_id))}</span>${esc(c.body)}
         <span class="mut" style="margin-left:6px">${ago(c.created_at)}</span></div>`).join('')
        : '<span class="mut">No messages.</span>'}</div>
      <div class="sheet-actions">
        <button class="btn btn-ghost btn-sm" onclick="roomAct('${roomId}','close')">⛔ Close room</button>
        <button class="btn btn-ghost btn-sm" onclick="roomAct('${roomId}','lock')">🔒 Lock</button>
        <button class="btn btn-ok btn-sm" onclick="roomAct('${roomId}','unlock')">🔓 Unlock</button>
        <button class="btn btn-warn btn-sm" onclick="roomAct('${roomId}','adult')">🔞 Mark 18+</button>
        <button class="btn btn-ok btn-sm" onclick="roomAct('${roomId}','not_adult')">Clear 18+</button>
        <button class="btn btn-ok btn-sm" onclick="clearRep('${roomId}')">✓ Dismiss reports</button>
      </div>
      <div style="margin-top:14px"><label class="fl" for="modNote">Mod note</label>
        <div class="inline-row">
          <input type="text" id="modNote" value="${esc(r.admin_notes || '')}" maxlength="500" placeholder="Visible to admins only">
          <button class="btn btn-primary btn-sm" onclick="saveNote('${roomId}')">Save</button>
        </div></div>`;
    $('modal').classList.add('open');
  } catch (e) { toast('Detail failed: ' + e.message, 'err'); }
}

async function roomAct(roomId, action) {
  try {
    await rpc('admin_room_action', { p_room_id: roomId, p_action: action, p_note: '' });
    toast('Room ' + shortId(roomId) + '… → ' + action, 'ok');
    loadRooms(); roomDetail(roomId);
  } catch (e) { toast('Action failed: ' + e.message, 'err'); }
}
async function saveNote(roomId) {
  try {
    await rpc('admin_room_action', { p_room_id: roomId, p_action: 'note', p_note: $('modNote').value });
    toast('Note saved', 'ok'); roomDetail(roomId); loadRooms();
  } catch (e) { toast('Note failed: ' + e.message, 'err'); }
}
async function clearRep(roomId) {
  try {
    const n = await rpc('admin_clear_reports', { p_room_id: roomId });
    toast(n + ' reports dismissed', 'ok'); loadRooms();
    if ($('modal').classList.contains('open')) roomDetail(roomId);
  } catch (e) { toast('Dismiss failed: ' + e.message, 'err'); }
}
function closeModal() { $('modal').classList.remove('open'); }
$('modal') && $('modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });

// ── scrapers ──
async function loadScrapers() {
  if (!$('scraperStats').children.length) $('scraperStats').innerHTML = skStats(3);
  $('votes').innerHTML = skLines(5);
  try {
    const d = await rpc('admin_scraper_votes');
    const votes = d.votes || [];
    let kill = {};
    try { kill = JSON.parse(d.kill || '{}'); } catch (_) {}
    const dead = votes.filter((v) => v.reporters >= 5).length;
    $('scraperStats').innerHTML = [
      ['🗳️', 'With votes', votes.length, '7d'],
      ['🔴', 'Likely dead', dead, '5+ reporters'],
      ['⛔', 'Currently killed', Object.keys(kill).length, 'in kill map'],
    ].map((c) => `<div class="stat">
        <div class="stat-top"><span class="stat-ico">${c[0]}</span><span class="stat-l">${c[1]}</span></div>
        <div class="n">${fmtNum(c[2])}<small>${c[3]}</small></div></div>`).join('');

    $('votes').innerHTML = votes.length === 0
      ? emptyState('🎉', 'No votes in the last 7 days', 'All sources look healthy.')
      : votes.map((v) => {
        const sev = v.reporters >= 5 ? 'sev-hi' : v.reporters >= 3 ? 'sev-md' : 'sev-lo';
        const flag = v.reporters >= 5 ? '🔴' : v.reporters >= 3 ? '🟡' : '🟢';
        return `<div class="vote ${sev}">
          <div class="v-main">
            <div class="mono" style="font-size:12.5px">${flag} ${esc(v.scraper)}</div>
            <div class="v-meta">${v.reporters} user${v.reporters === 1 ? '' : 's'} · last seen ${ago(v.last_seen)}</div>
          </div>
          <div class="v-n">${v.n} votes</div>
          <button class="btn btn-ghost btn-sm" onclick="killOne('${esc(v.scraper)}')" title="Add this source to the kill map">⛔ Kill</button>
        </div>`;
      }).join('');

    $('killJson').value = JSON.stringify(kill, null, 2);
    const cd = await sb.from('remote_config').select('value').eq('key', 'scraper_cooldown_days').single();
    if (cd.data) $('cooldownDays').value = cd.data.value;
  } catch (e) { toast('Scrapers failed: ' + e.message, 'err'); }
}
function killOne(name) {
  let kill = {};
  try { kill = JSON.parse($('killJson').value || '{}'); } catch (_) {}
  kill[name] = 'killed from dashboard';
  $('killJson').value = JSON.stringify(kill, null, 2);
  saveKill();
}
async function saveKill() {
  try {
    JSON.parse($('killJson').value || '{}'); // validate
    await rpc('admin_set_config', { p_key: 'scraper_kill', p_value: $('killJson').value });
    toast('Kill map live ⛔', 'ok'); loadScrapers();
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}
async function saveCooldown() {
  try {
    await rpc('admin_set_config', { p_key: 'scraper_cooldown_days', p_value: $('cooldownDays').value.trim() || '7' });
    toast('Cooldown saved', 'ok');
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}

// ── install history (devices ledger: one row per install) ──
async function loadUsers() {
  const tb = document.querySelector('#usersTbl tbody');
  if (tb) tb.innerHTML = skRows(8, 6);
  try {
    const rows = await rpc('admin_installs', { p_limit: 50, p_search: ($('uSearch') || {}).value || '' });
    if (tb) tb.innerHTML = (rows || []).map((u) =>
      `<tr><td class="mono">DIZ-${esc(u.anon_id)}</td>
       <td>${u.username ? `<strong>@${esc(u.username)}</strong>` : '<span class="mut">no name</span>'}</td>
       <td>${esc(u.platform)}</td><td>${esc(u.app_version)}</td>
       <td class="mut" title="${esc(fmtAbs(u.created_at))}">${ago(u.created_at)}</td>
       <td class="mut" title="${esc(fmtAbs(u.last_seen_at))}">${ago(u.last_seen_at)}</td></tr>`).join('')
      || `<tr><td colspan="6">${emptyState('📭', 'No installs found', 'Try another search term.')}</td></tr>`;
  } catch (e) { toast('Install history failed: ' + e.message, 'err'); }
  loadIdentity();
}

// ── v1.3.3-T1.1: identity lookup + history ──
// Shows current @username, profile display names + avatars, and the full
// old → new trail (auto-generated default first) per user.
function kindPill(kind) {
  const k = String(kind || '');
  if (k === 'username') return '<span class="pill p-live plain">@name</span>';
  if (k === 'display_name') return '<span class="pill p-lobby plain">profile</span>';
  if (k === 'avatar') return '<span class="pill p-pub plain">avatar</span>';
  return '<span class="pill p-closed plain">' + esc(k) + '</span>';
}
function historyRows(hist) {
  if (!hist || !hist.length) return '<span class="mut">no changes yet</span>';
  return hist.map((h) =>
    `<div class="hist-row">${kindPill(h.kind)}
     <span class="mono">${esc(h.old_value || '—')}</span>
     <span class="mut">→</span>
     <span class="mono"><b>${esc(h.new_value || '—')}</b></span>
     <span class="mut" title="${esc(fmtAbs(h.at))}">${ago(h.at)}</span></div>`).join('');
}
async function loadIdentity() {
  const box = $('identityList');
  if (box && !box.children.length) box.innerHTML = skLines(4);
  try {
    const rows = await rpc('admin_user_identity', { p_search: $('idSearch') ? $('idSearch').value : '' });
    if (box) box.innerHTML = (rows || []).length
      ? rows.map((u) => {
        const prof = (u.profiles || []).map((p) =>
          `<span class="chip">${esc(p.avatar || '')} ${esc(p.name || 'Profile')}</span>`).join(' ');
        return `<div class="rep-card">
          <div class="rep-top">
            <span class="mono">@${esc(u.username || '—')}</span>
            <span class="mut mono" title="${esc(u.user_id)}">${esc(shortId(u.user_id))}…</span>
            <span class="mut" title="${esc(fmtAbs(u.last_change_at))}">changed ${ago(u.last_change_at)}</span>
          </div>
          <div class="rep-meta">profiles: ${prof || '<span class="mut">none synced</span>'}</div>
          <div class="hist">${historyRows(u.history)}</div>
        </div>`;
      }).join('')
      : emptyState('👤', 'No users with usernames yet', 'Usernames appear after the first claim.');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Identity lookup failed', e.message); }
}

// ── v1.3.3-T2.4: support inbox ──
// Tickets carry the enum trail + error codes from T2.3 — never the user's
// own words, which stay on the device. Replies go out via announcements.
async function loadSupportStats() {
  const box = $('supportStats');
  if (box) box.innerHTML = skRows(1, 4);
  try {
    const s = await rpc('admin_support_stats', {}) || {};
    const solved = (Number(s.ai_solved) || 0);
    const human = (Number(s.human) || 0);
    const closedLike = solved + human;
    const rate = closedLike > 0 ? Math.round((solved / closedLike) * 100) : 0;
    const badge = $('navTickets');
    const openN = (Number(s.open) || 0) + (Number(s.assigned) || 0);
    if (badge) { badge.textContent = String(openN); badge.hidden = openN === 0; }
    if (box) box.innerHTML = [
      ['Open', s.open || 0], ['Assigned', s.assigned || 0],
      ['Closed', s.closed || 0], ['Last 30d', s.total_30d || 0],
      ['AI solved', solved], ['Deflection', rate + '%'],
    ].map(([l, v]) => `<div class="stat"><div class="stat-v">${esc(String(v))}</div><div class="stat-l">${esc(l)}</div></div>`).join('');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Stats failed', e.message); }
}
async function loadSupportAnswers() {
  const box = $('supportAnswers');
  if (box) box.innerHTML = skLines(4);
  try {
    const rows = await rpc('admin_support_answers', { p_limit: 100 }) || [];
    if (!box) return;
    box.innerHTML = rows.length
      ? rows.map((r) => `<div class="rep-card">
          <div class="rep-top">
            <span class="pill ${r.tier === 'llm' ? 'p-live' : r.tier === 'kb' ? 'p-lobby' : 'p-closed'}">${esc(r.tier || 'none')}</span>
            <span class="mut mono">@${esc(r.username || '—')}</span>
            <span class="mut mono">${esc(r.lang || 'en')}</span>
            <span class="mut mono">${Number(r.latency_ms) || 0} ms</span>
            <span class="mut" title="${esc(fmtAbs(r.created_at))}">${ago(r.created_at)}</span>
          </div>
          <div class="rep-meta"><b>Q:</b> ${esc(r.question || '—')}</div>
          <div class="rep-meta"><b>A:</b> ${esc((r.answer || '—').slice(0, 400))}</div>
        </div>`).join('')
      : emptyState('💬', 'No assistant answers yet', 'Rows appear when telemetry is on.');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Answers failed', e.message); }
}
async function loadTickets() {
  const box = $('ticketList');
  if (box) box.innerHTML = skLines(5);
  try {
    const status = ($('tkStatus') || {}).value || '';
    const rows = await rpc('admin_support_tickets', { p_status: status, p_limit: 50 });
    if (!box) return;
    box.innerHTML = (rows || []).length
      ? rows.map((t) => {
        const codes = (t.codes || []).map((c) => `<span class="chip mono">${esc(String(c))}</span>`).join(' ');
        return `<div class="rep-card">
          <div class="rep-top">
            <span class="pill ${t.status === 'open' ? 'p-adult' : t.status === 'assigned' ? 'p-lobby' : 'p-closed'}">${esc(t.status)}</span>
            <span class="mono">${esc(t.topic)}</span>
            <span class="mut mono">@${esc(t.username || '—')}</span>
            <span class="mut mono">DIZ-${esc(t.device_code)}</span>
            <span class="mut">${esc(t.platform)} ${esc(t.app_version || '')}</span>
            <span class="mut" title="${esc(fmtAbs(t.created_at))}">${ago(t.created_at)}</span>
            ${t.ai_answered ? '<span class="pill p-live plain">AI answered</span>' : ''}
          </div>
          <div class="rep-meta">codes: ${codes || '<span class="mut">none</span>'}</div>
          <div class="rep-meta">trail: ${trailCell(t.trail)}</div>
          <div class="rowbtns">
            <button class="btn btn-ghost btn-sm" onclick="ticketAct('${esc(t.id)}','assign')">Assign</button>
            <button class="btn btn-ok btn-sm" onclick="ticketAct('${esc(t.id)}','close','fixed')">Close · fixed</button>
            <button class="btn btn-ghost btn-sm" onclick="ticketAct('${esc(t.id)}','close','duplicate')">Duplicate</button>
            <button class="btn btn-ghost btn-sm" onclick="ticketAct('${esc(t.id)}','reopen')">Reopen</button>
          </div>
        </div>`;
      }).join('')
      : emptyState('💬', 'Inbox zero', 'No tickets in this filter.');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Tickets failed', e.message); }
}
async function ticketAct(id, action, resolution) {
  try {
    await rpc('admin_ticket_action', { p_id: id, p_action: action, p_resolution: resolution || '' });
    toast('Ticket ' + action + ' ✓', 'ok');
    loadTickets(); loadSupportStats();
  } catch (e) { toast('Ticket action failed: ' + e.message, 'err'); }
}

// ── v1.3.3-T2.4/T3.4: curated playlists ──
async function loadCurated() {
  const box = $('curatedList');
  if (box) box.innerHTML = skLines(4);
  try {
    const rows = await rpc('admin_curated_list', {});
    if (!box) return;
    box.innerHTML = (rows || []).length
      ? rows.map((p) => `<div class="rep-card">
          <div class="rep-top">
            <span class="mono">${esc(p.slug)}</span>
            <span>${esc(p.title || '(untitled)')}</span>
            <span class="pill ${p.active ? 'p-live' : 'p-closed'}">${p.active ? 'live' : 'hidden'}</span>
            <span class="mut">${esc(p.rail)} · pos ${Number(p.position) || 0} · ${Number(p.track_count) || 0} tracks</span>
            <span class="mut" title="${esc(fmtAbs(p.updated_at))}">${ago(p.updated_at)}</span>
          </div>
          <div class="rowbtns">
            <button class="btn btn-ghost btn-sm" onclick="editCurated('${esc(p.id)}')">Edit</button>
            <button class="btn btn-ghost btn-sm" onclick="delCurated('${esc(p.id)}')">Delete</button>
          </div>
        </div>`).join('')
      : emptyState('🎧', 'No curated playlists yet', 'Publish one below — it shows up in the app rail.');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Curated list failed', e.message); }
}
let CURATED_CACHE = [];
async function editCurated(id) {
  try {
    CURATED_CACHE = await rpc('admin_curated_list', {}) || [];
    const p = CURATED_CACHE.find((x) => String(x.id) === String(id));
    if (!p) return;
    $('curId').value = p.id;
    $('curSlug').value = p.slug || '';
    $('curTitleIn').value = p.title || '';
    $('curSub').value = p.subtitle || '';
    $('curRail').value = p.rail || 'dizzy_pick';
    $('curPos').value = p.position || 100;
    $('curActive').value = p.active ? 'true' : 'false';
    if ($('curTitle')) $('curTitle').textContent = 'Edit: ' + (p.title || p.slug);
    toast('Loaded — tracks stay as-is unless you paste them', 'info');
  } catch (e) { toast('Load failed: ' + e.message, 'err'); }
}

function toSlug(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64);
}

function resetCurated() {
  ['curId', 'curSlug', 'curTitleIn', 'curSub', 'curCover', 'curTracks'].forEach((k) => { if ($(k)) $(k).value = ''; });
  if ($('curSlug')) delete $('curSlug').dataset.touched;
  if ($('curPos')) $('curPos').value = '100';
  if ($('curActive')) $('curActive').value = 'true';
  if ($('curTitle')) $('curTitle').textContent = 'New playlist';
}

async function saveCurated() {
  const saveBtn = document.querySelector('#s-curated button.btn-primary');
  if (saveBtn) { saveBtn.disabled = true; saveBtn.textContent = 'Saving...'; }
  try {
    const title = ($('curTitleIn') || {}).value?.trim() || '';
    let slug = ($('curSlug') || {}).value?.trim() || '';
    if (!slug && title) {
      slug = toSlug(title);
      if ($('curSlug')) $('curSlug').value = slug;
    }
    if (!slug) slug = 'curated-' + Math.random().toString(36).slice(2, 7);

    let tracks = [];
    const tracksRaw = (($('curTracks') || {}).value || '').trim();
    if (tracksRaw) {
      try {
        const parsed = JSON.parse(tracksRaw);
        tracks = Array.isArray(parsed) ? parsed : [parsed];
      } catch (err) {
        toast('Tracks JSON invalid: ' + err.message, 'err');
        if (saveBtn) { saveBtn.disabled = false; saveBtn.textContent = '💾 Save playlist'; }
        return;
      }
    }

    await rpc('admin_curated_upsert', {
      p_id: ($('curId') || {}).value || '',
      p_slug: slug,
      p_title: title || 'Curated Playlist',
      p_subtitle: ($('curSub') || {}).value?.trim() || '',
      p_cover: ($('curCover') || {}).value?.trim() || '',
      p_rail: ($('curRail') || {}).value || 'dizzy_pick',
      p_position: Number(($('curPos') || {}).value || 100),
      p_tracks: tracks,
      p_active: (($('curActive') || {}).value || 'true') === 'true',
    });
    toast('Playlist saved 🎧', 'ok');
    resetCurated();
    loadCurated();
  } catch (e) {
    toast('Save failed: ' + (e.message || e.details || 'unknown error'), 'err');
  } finally {
    if (saveBtn) { saveBtn.disabled = false; saveBtn.textContent = '💾 Save playlist'; }
  }
}
async function delCurated(id) {
  if (!confirm('Delete this playlist?')) return;
  try {
    await rpc('admin_curated_delete', { p_id: id });
    toast('Deleted ✓', 'ok');
    loadCurated();
  } catch (e) { toast('Delete failed: ' + e.message, 'err'); }
}
// Phase 6: one paste, one device card.
// A support ticket says "DIZ-1234567". Answering it used to mean three tabs —
// Fleet for the code, Device logs for the errors, Privacy for consent — and if
// the user had reinstalled, the code in the ticket was the RETIRED one, so
// Fleet showed nothing at all. admin_device_card() resolves current and
// retired codes alike and returns the whole answer as one object.
function devConsentPill(label, on) {
  return `<span class="pill plain ${on ? 'p-live' : 'p-closed'}"
    title="${label} consent: ${on ? 'allowed' : 'denied'}">${label} ${on ? 'on' : 'off'}</span>`;
}

function deviceCardHtml(d) {
  const code = String(d.device_code || '');
  const days = d.days_since_seen == null ? null : Number(d.days_since_seen);
  const stale = d.stale
    ? `<span class="pill p-lock" title="no boot from this device for ${days == null ? 'over 30 days' : days + ' day(s)'}">stale${days == null ? '' : ' ' + days + 'd'}</span>`
    : '';
  const online = d.online ? '<span class="pill p-live">online</span>' : '';
  const revoked = d.revoked_at ? '<span class="pill p-closed">revoked</span>' : '';
  const banned = d.banned
    ? `<span class="pill p-closed" title="ban level ${esc(d.ban_level || 'social')}">banned</span>` : '';
  const adult = d.adult_allowed ? '<span class="pill p-adult" title="18+ content allowed">🔞 18+</span>' : '';
  const weak = d.hwid_stable === false
    ? '<span class="pill" title="weak identity anchor — hwid did not stay stable on this install">new</span>' : '';

  // null consent means the user never made a choice. That is NOT "no", and the
  // card says so rather than quietly implying the user refused.
  const c = d.consent;
  const consent = c
    ? [devConsentPill('telemetry', c.telemetry),
       devConsentPill('crash', c.crash),
       devConsentPill('genres', c.genre_prefs)].join(' ')
    : '<span class="pill p-closed plain" title="this user never opened the consent sheet">no choice recorded</span>';

  const codes = Array.isArray(d.codes) ? d.codes : [];
  const codeChips = codes.map((x) => `<span class="chip mono"
      title="${esc(x.source || 'boot')} · first seen ${x.first_seen_at ? esc(fmtAbs(x.first_seen_at)) : '—'}">
      DIZ-${esc(x.code)}${x.current ? ' · current' : ''}
      <span class="mut">${fmtNum(Number(x.hits) || 0)} hits</span>
      <button class="btn btn-ghost btn-sm" onclick="openDevLogs('${esc(x.code)}')">logs</button>
    </span>`).join('');

  const hist = (d.username_history || []).length
    ? `<div class="hist">${d.username_history.map((h) => `<div class="hist-row">
         <span class="mut">${ago(h.at)}</span>
         <span class="mono">@${esc(h.old_value || '—')}</span>
         <span class="mut">→</span>
         <span class="mono"><b>@${esc(h.new_value || '—')}</b></span></div>`).join('')}</div>`
    : '<div class="mut">No username changes.</div>';

  const rows = Number(d.log_rows) || 0;
  const hits = Number(d.log_hits) || 0;
  const screens = Number(d.log_screens) || 0;
  const telemetry = rows
    ? `${rows} kind${rows === 1 ? '' : 's'} · <b>${fmtNum(hits)}</b> hit${hits === 1 ? '' : 's'}
       · ${screens} screen${screens === 1 ? '' : 's'}
       · last ${d.log_last_at ? ago(d.log_last_at) : '—'}`
    : 'No error reports from this device.';

  const owner = d.username
    ? `<strong>@${esc(d.username)}</strong>`
    : '<span class="mut">no username claimed</span>';
  const wasName = d.previous_username && d.previous_username !== d.username
    ? `<span class="pill plain" title="username left behind by the previous owner of this device">was @${esc(d.previous_username)}</span>`
    : '';

  return `<div class="dev-card${d.stale ? ' is-stale' : ''}">
    <div class="rep-top">
      <span class="mono dev-code">DIZ-${esc(code || '—')}</span>
      ${online} ${stale} ${revoked} ${banned} ${adult} ${weak}
    </div>
    <div class="rep-meta">${owner} ${wasName} ·
      <span class="mono" title="${esc(d.user_id)}">${esc(shortId(d.user_id))}…</span></div>
    <div class="kv">
      <b>Build</b><span>${esc(d.platform || '—')} · v${esc(d.app_version || '—')}</span>
      <b>First seen</b><span>${d.first_seen_at ? `${esc(fmtAbs(d.first_seen_at))} <span class="mut">(${ago(d.first_seen_at)})</span>` : '—'}</span>
      <b>Last seen</b><span>${d.last_seen_at ? `${esc(fmtAbs(d.last_seen_at))} <span class="mut">(${ago(d.last_seen_at)})</span>` : '—'}</span>
      <b>Consent</b><span>${consent}</span>
      <b>Telemetry</b><span>${telemetry}</span>
      <b>Codes (${codes.length})</b><span>${codeChips || '<span class="mut">none</span>'}</span>
      <b>Username log</b><span>${hist}</span>
    </div>
    <div class="rowbtns">
      <button class="btn btn-ghost btn-sm" onclick="openDevLogs('${esc(code)}')">Open device logs</button>
      <button class="btn btn-ghost btn-sm" onclick="findUserFor('${esc(d.user_id)}')">Look up owner</button>
    </div>
  </div>`;
}

// Device card -> owner's user card, without retyping the id.
function findUserFor(uid) {
  const box = $('fuSearch');
  if (box) box.value = uid;
  loadFindUser();
}

async function loadFindUser() {
  const box = $('findUserList');
  if (box) box.innerHTML = skLines(4);
  try {
    const q = (($('fuSearch') || {}).value || '').trim();
    if (!q) {
      if (box) box.innerHTML = emptyState('🔎', 'Search a user or device',
        'Try @username, a user id, or a DIZ- device code — retired codes work too.');
      return;
    }
    // Both lookups run: a code answers with a device card, a username answers
    // with a user card, and one query can legitimately answer with both.
    const [devices, users] = await Promise.all([
      rpc('admin_device_card', { p_search: q }).catch(() => []),
      rpc('admin_find_user', { p_search: q }).catch(() => []),
    ]);
    if (!box) return;
    const devCards = (devices || []).map(deviceCardHtml);
    const userCards = (users || []).map((u) => {
      const dev = (u.installs || []).map((d) =>
        `<span class="chip mono">DIZ-${esc(d.device_code || '?')} · ${esc(d.platform || '?')}</span>`).join(' ');
      const prof = (u.profiles || []).map((p) =>
        `<span class="chip">${esc(p.avatar || '')} ${esc(p.name || 'Profile')}</span>`).join(' ');
      return `<div class="rep-card">
        <div class="rep-top">
          <span class="mono">@${esc(u.username || '—')}</span>
          <span class="mut mono" title="${esc(u.user_id)}">${esc(shortId(u.user_id))}…</span>
          <span class="mut">${Number(u.sessions) || 0} sessions</span>
          <span class="mut">seen ${ago(u.last_seen)}</span>
        </div>
        <div class="rep-meta">devices: ${dev || '<span class="mut">none</span>'}</div>
        <div class="rep-meta">profiles: ${prof || '<span class="mut">none</span>'}</div>
        <div class="hist">${historyRows(u.history)}</div>
        <div class="rowbtns">
          <button class="btn btn-ghost btn-sm" onclick="banUser('${esc(u.user_id)}','social')">🟠 Social ban</button>
          <button class="btn btn-ghost btn-sm" onclick="banUser('${esc(u.user_id)}','full')">⛔ Full ban</button>
          <button class="btn btn-ghost btn-sm" onclick="unbanUser('${esc(u.user_id)}')">🔓 Unban</button>
          <button class="btn btn-ghost btn-sm" onclick="resetUser('${esc(u.user_id)}','progress')">Reset progress</button>
          <button class="btn btn-ghost btn-sm" onclick="resetUser('${esc(u.user_id)}','profile')">Reset profile</button>
        </div>
      </div>`;
    });
    const cards = [...devCards, ...userCards];
    box.innerHTML = cards.length
      ? `<div class="mut" style="margin:0 0 10px">
           ${devCards.length} device${devCards.length === 1 ? '' : 's'} ·
           ${userCards.length} user${userCards.length === 1 ? '' : 's'}
           matching “${esc(q)}”</div>` + cards.join('')
      : emptyState('🔎', 'No match',
        'Check the spelling, or paste the full DIZ- code from the ticket.');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Lookup failed', e.message); }
}
async function resetUser(uid, scope) {
  const label = scope === 'profile' ? 'profiles + usernames + progress' : 'watch progress';
  if (!confirm(`Reset ${label} for this user? This cannot be undone.`)) return;
  try {
    const r = await rpc('admin_reset_user', { p_user_id: uid, p_scope: scope });
    toast(`Reset done · ${(r && r.sessions) || 0} sessions cleared`, 'ok');
    loadFindUser();
  } catch (e) { toast('Reset failed: ' + e.message, 'err'); }
}
async function loadIdentityTail() {
  const tb = document.querySelector('#idTailTbl tbody');
  if (tb && !tb.children.length) tb.innerHTML = skRows(6, 5);
  try {
    const rows = await rpc('admin_identity_tail', { p_limit: 50 });
    if (tb) tb.innerHTML = (rows || []).map((h) =>
      `<tr><td class="mut" title="${esc(fmtAbs(h.at))}">${ago(h.at)}</td>
       <td>${kindPill(h.kind)}</td>
       <td class="mono">@${esc(h.username || shortId(h.user_id) + '…')}</td>
       <td><span class="mono">${esc(h.old_value || '—')}</span> <span class="mut">→</span> <span class="mono"><b>${esc(h.new_value || '—')}</b></span></td>
       <td class="mut mono">${esc(h.profile_id || '—')}</td></tr>`).join('')
      || `<tr><td colspan="5">${emptyState('🧾', 'No identity changes yet', 'Renames and avatar changes will show up here.')}</td></tr>`;
  } catch (e) { toast('Identity feed failed: ' + e.message, 'err'); }
}

// ── Phase L3: live fleet pulse ──
// Must mirror the server's devices_activity_check values exactly.
const ACTIVITY_META = {
  idle: ['💤', 'idle'],
  watching: ['🎬', 'watching'],
  listening: ['🎧', 'listening'],
  reading: ['📖', 'reading'],
  downloading: ['⬇️', 'downloading'],
  in_room: ['🏠', 'in a room'],
  in_voice: ['🎤', 'in voice'],
};
function prettyActivity(k) {
  const m = ACTIVITY_META[k];
  return m ? `${m[0]} ${m[1]}` : (k || 'idle');
}

let _fleetTimer = null;

async function loadFleetLive() {
  const statsEl = $('fleetStats');
  const actEl = $('fleetActivity');
  const verEl = $('fleetVersions');
  const feedEl = $('feedList');
  if (statsEl && !statsEl.children.length) statsEl.innerHTML = skStats(4);
  if (actEl) actEl.innerHTML = skLines(4);
  if (verEl) verEl.innerHTML = skLines(4);
  if (feedEl && !feedEl.children.length) feedEl.innerHTML = skLines(5);
  try {
    const f = await rpc('admin_fleet_live');
    if (statsEl) {
      const cards = [
        ['🟢', 'Online now', f.online, 'devices'],
        ['📦', 'Devices', f.total, 'total'],
        ['🚩', 'Banned', f.banned, 'users'],
        ['🔒', 'Revoked', f.revoked, 'devices'],
      ];
      statsEl.innerHTML = cards.map((c) => `
        <div class="stat">
          <div class="stat-top"><span class="stat-ico">${c[0]}</span><span class="stat-l">${c[1]}</span></div>
          <div class="n">${fmtNum(c[2])}<small>${c[3]}</small></div>
        </div>`).join('');
    }

    const acts = f.activity || [];
    const maxA = Math.max(1, ...acts.map((a) => a.cnt));
    if (actEl) {
      actEl.innerHTML = acts.length
        ? `<div class="bd-group"><div class="bd-l"><span>Online devices</span><span>${fmtNum(f.online || 0)}</span></div>` +
          acts.map((a) => `
            <div class="bd-row"><span class="nm">${esc(prettyActivity(a.key))}</span><span class="vl">${fmtNum(a.cnt)}</span></div>
            <div class="bd-bar"><i style="width:${Math.round((a.cnt / maxA) * 100)}%"></i></div>`).join('') +
          `</div>` +
          ((f.with_activity || 0) < (f.online || 0)
            ? `<div class="bd-group"><div class="bd-l"><span>Idle online</span><span>${fmtNum((f.online || 0) - (f.with_activity || 0))}</span></div>
               <div class="bd-chips"><span class="chip">💤 idle · ${fmtNum(Math.max(0, (f.online || 0) - (f.with_activity || 0)))}</span></div></div>`
            : '')
        : emptyState('🌙', 'Nobody online', 'Open the app to show up here.');
    }

    const vers = f.versions || [];
    const maxV = Math.max(1, ...vers.map((v) => v.cnt));
    if (verEl) {
      verEl.innerHTML = vers.length
        ? `<div class="bd-group"><div class="bd-l"><span>Devices</span><span>${fmtNum(f.total || 0)}</span></div>` +
          vers.map((v) => `
            <div class="bd-row"><span class="nm">${esc(v.key || 'unknown')}</span><span class="vl">${fmtNum(v.cnt)}</span></div>
            <div class="bd-bar"><i style="width:${Math.round((v.cnt / maxV) * 100)}%"></i></div>`).join('') +
          `</div>`
        : emptyState('📭', 'No devices yet', 'Devices register on app boot.');
    }

    if ($('fleetStamp')) $('fleetStamp').textContent = 'updated ' + ago(new Date().toISOString());

    // Phase O3: last 50 transitions — 7-char device code + enum + time only
    // (no hwid, no user id, no titles — the privacy floor). Failures are
    // isolated so a feed hiccup never blanks the live cards above.
    try {
      const feed = await rpc('admin_activity_feed', { p_limit: 50 });
      if (feedEl) {
        feedEl.innerHTML = (feed || []).length
          ? `<div class="chatbox">${feed.map((f) =>
              `<div><span class="who">DIZ-${esc(f.device_code)}</span>${esc(prettyActivity(f.activity))}` +
              `<span class="mut" style="margin-left:8px">${ago(f.at)}</span></div>`).join('')}</div>`
          : emptyState('🕒', 'No transitions yet',
              'Open the app and start playing — changes appear here instantly.');
      }
    } catch (fe) {
      if (feedEl) feedEl.innerHTML = emptyState('⚠️', 'Activity feed unavailable', fe.message);
    }
  } catch (e) {
    if (actEl) actEl.innerHTML = emptyState('⚠️', 'Live fleet unavailable', e.message);
    if (verEl) verEl.innerHTML = emptyState('⚠️', 'Versions unavailable', e.message);
    toast('Fleet live failed: ' + e.message, 'err');
  }
}

// Realtime pushes device changes instantly; this is only the drop-socket
// safety net.
function startFleetLive() {
  loadFleetLive();
  if (_fleetTimer) clearInterval(_fleetTimer);
  _fleetTimer = setInterval(loadFleetLive, 120000);
}
function stopFleetLive() {
  if (_fleetTimer) { clearInterval(_fleetTimer); _fleetTimer = null; }
}

// ── devices (Phase C) ──
// v1.4.3: each device row now carries its owner's @username and an expandable
// username log (identity_history kind='username') plus the name a reinstall
// left behind on previous_user_id. device_id is shown in full inside the
// expansion so support can quote it; hwid_hash is never returned by the RPC.
function devNameLog(d) {
  const hist = Array.isArray(d.username_history) ? d.username_history : [];
  if (!hist.length) {
    return '<li class="mut">No username changes recorded for this device yet.</li>';
  }
  return hist.map((h) => {
    const from = h.old_value === 'auto-generated' ? 'auto' : (h.old_value || '—');
    const to = h.new_value === 'released-by-admin'
      ? 'released by admin' : (h.new_value || '—');
    return `<li><span class="mono">${esc(from)} → ${esc(to)}</span>
      <span class="mut" title="${esc(fmtAbs(h.at))}">· ${ago(h.at)}</span></li>`;
  }).join('');
}

function toggleDevDetail(deviceId) {
  const row = $('devdet-' + deviceId);
  if (!row) return;
  row.style.display = row.style.display === 'none' ? '' : 'none';
}

// Jump straight from a device row into the Device logs tab, already filtered
// to that code. Support used to copy the code across two tabs by hand.
function openDevLogs(code) {
  const box = $('dlDevice');
  if (box) box.value = 'DIZ-' + code;
  _dlCodePrefix = '';
  show('devicelogs');
}

async function loadDevices() {
  const tb = document.querySelector('#devicesTbl tbody');
  if (tb) tb.innerHTML = skRows(8, 7);
  try {
    const rows = await rpc('admin_devices', { p_limit: 500, p_search: ($('devSearch') || {}).value || '' });
    if (tb) tb.innerHTML = rows.map((d) => {
      const dot = d.online ? '<span class="pill p-live">● online</span>' : '<span class="mut">offline</span>';
      const activity = d.online && d.activity && d.activity !== 'idle'
        ? `<span class="pill" title="what this device is doing right now">${prettyActivity(d.activity)}</span>` : '';
      const badges = [
        d.revoked_at ? '<span class="pill p-closed">revoked</span>' : '',
        d.banned ? `<span class="pill p-closed" title="level ${esc(d.ban_level || 'social')}">banned</span>` : '',
        d.adult_allowed ? '<span class="pill p-adult" title="18+ Heaven allowed">🔞 18+</span>' : '',
        d.hwid_stable === false ? '<span class="pill" title="weak identity anchor">new</span>' : '',
        activity,
      ].filter(Boolean).join(' ');
      const adultBtn = d.adult_allowed
        ? `<button class="btn btn-ok btn-sm" onclick="setAdultAllow('${d.device_id}',false)">Block 18+</button>`
        : `<button class="btn btn-sm" onclick="setAdultAllow('${d.device_id}',true)">Allow 18+</button>`;
      const action = d.revoked_at
        ? `<button class="btn btn-ok btn-sm" onclick="revokeDevice('${d.device_id}',false)">Restore</button>`
        : `<button class="btn btn-danger btn-sm" onclick="revokeDevice('${d.device_id}',true)">Revoke</button>`;
      const who = d.username
        ? `<strong>@${esc(d.username)}</strong>`
        : '<span class="mut" title="this device has not claimed a username">no name</span>';
      const leftBehind = d.previous_username && d.previous_username !== d.username
        ? `<span class="pill" title="username left behind by the previous owner of this device">was @${esc(d.previous_username)}</span>`
        : '';
      const nameLog = Number(d.username_change_count) || 0;
      const logBtn = nameLog
        ? `<button class="btn btn-ghost btn-sm" onclick="toggleDevDetail('${esc(d.device_id)}')"
        title="Show this device's username log">log ${nameLog}</button>`
        : '';
      const codeCell = `<span class="mono" style="cursor:pointer"
        onclick="toggleDevDetail('${esc(d.device_id)}')"
        title="Show full device ID and username log">${esc(d.device_code)}</span>`;
      const prevOwner = d.previous_user_id && d.previous_user_id !== d.user_id
        ? `<div class="mut">Previous owner <span class="mono" title="${esc(d.previous_user_id)}">${esc(shortId(d.previous_user_id))}…</span>
             ${d.previous_username ? `(@${esc(d.previous_username)})` : ''}</div>`
        : '';
      const hits = Number(d.log_hits) || 0;
      const logRows = Number(d.log_rows) || 0;
      const errorLine = logRows
        ? `<div class="mut">Errors <span class="mono">${logRows} kind${logRows === 1 ? '' : 's'} · ${hits} hit${hits === 1 ? '' : 's'}</span>
             · last ${d.log_last_at ? ago(d.log_last_at) : '—'}</div>`
        : '<div class="mut">No error reports from this device.</div>';
      // Every code this device has worn. A reinstall mints a new code, and
      // before the registry existed that silently stranded the old code's
      // telemetry. Now both are listed and both open their own logs.
      const codes = Array.isArray(d.codes) ? d.codes : [];
      const codesBlock = codes.length ? `
        <div class="mut" style="margin:6px 0 4px">Device codes (${codes.length})</div>
        <ul class="ann-list" style="margin:0 0 6px;padding-left:18px">${codes.map((c) => `
          <li><span class="mono">DIZ-${esc(c.code)}</span>
            ${c.current ? '<span class="pill p-live">current</span>'
                        : '<span class="pill" title="retired code; telemetry still attributable">retired</span>'}
            <span class="mut">· ${Number(c.hits) || 0} hits · ${Number(c.rows) || 0} kinds
              · last ${c.last_seen_at ? ago(c.last_seen_at) : '—'}</span>
            <button class="btn btn-ghost btn-sm" onclick="openDevLogs('${esc(c.code)}')">logs</button>
          </li>`).join('')}</ul>` : '';
      const detail = `<tr id="devdet-${esc(d.device_id)}" style="display:none">
        <td colspan="7">
          <div class="mut" style="margin-bottom:6px">
            Device ID <span class="mono">${esc(d.device_id)}</span> ·
            Owner <span class="mono" title="${esc(d.user_id)}">${esc(shortId(d.user_id))}…</span>
            ${d.username ? `(@${esc(d.username)})` : ''}
            · registered ${ago(d.created_at)}
          </div>
          ${prevOwner}
          <div style="margin:6px 0">${errorLine}
            <button class="btn btn-ghost btn-sm" onclick="openDevLogs('${esc(d.device_code)}')"
              title="Open Device logs filtered to this device">Open logs</button></div>
          ${codesBlock}
          <div class="mut" style="margin:6px 0 4px">Username log</div>
          <ul class="ann-list" style="margin:0;padding-left:18px">${devNameLog(d)}</ul>
        </td></tr>`;
      return `<tr><td>${codeCell}</td>
       <td>${who} ${leftBehind} ${logBtn}</td>
       <td>${esc(d.platform)}</td><td>${esc(d.app_version)}</td>
       <td>${dot} ${badges}</td>
       <td class="mut" title="${esc(fmtAbs(d.last_seen_at))}">${ago(d.last_seen_at)}</td>
       <td>${action} ${adultBtn}</td></tr>${detail}`;
    }).join('')
      || `<tr><td colspan="7">${emptyState('📭', 'No devices yet', 'Devices register on app boot.')}</td></tr>`;
  } catch (e) { toast('Devices failed: ' + e.message, 'err'); }
}

// Phase 3: codes no device can be proven to own. Grouped, never dropped.
// A pre-registry install left no legacy hash behind, so "unlinked" is the
// honest answer rather than a hidden bucket. The moment a device boots
// presenting one of these codes it attaches and the row leaves this list.
async function loadOrphans() {
  const tb = $('orphanBody');
  const sum = $('orphanSummary');
  if (tb) tb.innerHTML = skRows(5, 8);
  if (sum) sum.textContent = 'Loading…';
  try {
    const data = await rpc('admin_orphan_logs', { p_limit: 200 });
    const totals = (data && data.totals) || {};
    const codes = Array.isArray(data && data.codes) ? data.codes : [];
    // Reuse the device search box: pasting an old code here narrows both lists.
    const q = String(($('devSearch') || {}).value || '').trim().toLowerCase();
    const shown = q ? codes.filter((c) => String(c.code).toLowerCase().includes(q)) : codes;
    if (sum) {
      const hits = Number(totals.hits) || 0;
      const rows = Number(totals.rows) || 0;
      sum.innerHTML = codes.length
        ? `${Number(totals.codes) || 0} unlinked code${(Number(totals.codes) || 0) === 1 ? '' : 's'}
           · ${rows} kind${rows === 1 ? '' : 's'} · <b>${hits}</b> hit${hits === 1 ? '' : 's'}
           · first ${totals.first_at ? esc(fmtAbs(totals.first_at)) : '—'}
           · last ${totals.last_at ? ago(totals.last_at) : '—'}
           ${q ? `· ${shown.length} matching “${esc(q)}”` : ''}`
        : 'No unlinked telemetry — every code has a provable owner.';
    }
    if (tb) tb.innerHTML = shown.map((c) => {
      const top = Array.isArray(c.top) && c.top.length ? c.top[0] : null;
      const worst = top
        ? `<span class="pill">${esc(top.code)}</span>
           <span class="mut">${esc(top.screen)} · ${Number(top.hits) || 0} hits</span>`
        : '<span class="mut">—</span>';
      const meta = [c.platform, c.app_version].filter(Boolean).map(esc).join(' · ');
      return `<tr>
        <td><span class="mono">DIZ-${esc(c.code)}</span>${meta ? `<div class="mut">${meta}</div>` : ''}</td>
        <td class="num"><b>${Number(c.hits) || 0}</b></td>
        <td class="num">${Number(c.rows) || 0}</td>
        <td class="num">${Number(c.screens) || 0}</td>
        <td>${worst}</td>
        <td class="mut" title="${esc(fmtAbs(c.first_at))}">${ago(c.first_at)}</td>
        <td class="mut" title="${esc(fmtAbs(c.last_at))}">${ago(c.last_at)}</td>
        <td><button class="btn btn-ghost btn-sm" onclick="openDevLogs('${esc(c.code)}')"
          title="Open Device logs filtered to this code">logs</button></td>
      </tr>`;
    }).join('') || `<tr><td colspan="8">${emptyState('✔', q ? 'No unlinked code matches' : 'Nothing unlinked', q ? 'Clear the search to see all codes.' : 'Every telemetry code has a device.')}</td></tr>`;
  } catch (e) {
    if (sum) sum.textContent = 'Unlinked telemetry unavailable.';
    toast('Unlinked telemetry failed: ' + e.message, 'err');
  }
}

// ── v1.3.5: username ownership ──
// A guest session that no longer owns a device row leaves its @name behind;
// the person then cannot claim their own name. This panel shows the owner,
// whether the name is stranded, and lets an admin release or move it.
async function loadUsernames() {
  const tb = document.querySelector('#unamesTbl tbody');
  if (tb) tb.innerHTML = skRows(8, 6);
  try {
    const rows = await rpc('admin_usernames', {
      p_search: ($('unSearch') || {}).value || '',
      p_limit: 100,
    });
    if (tb) tb.innerHTML = (rows || []).map((u) => {
      const stranded = (u.device_count || 0) === 0;
      const devices = (u.devices || []).map((d) =>
        `<span class="chip">${esc(d.device_code || '')}</span>`).join(' ')
        || '<span class="mut">none</span>';
      const session = u.is_anonymous
        ? '<span class="pill">guest</span>'
        : '<span class="pill p-live">verified</span>';
      const flag = stranded
        ? ' <span class="pill p-closed" title="no device row — the name was left behind">stranded</span>'
        : '';
      return `<tr><td class="mono">@${esc(u.username)}</td>
       <td class="mut mono" title="${esc(u.user_id)}">${esc(shortId(u.user_id))}…</td>
       <td>${session}${flag}</td>
       <td>${devices}</td>
       <td class="mut" title="${esc(fmtAbs(u.last_seen))}">${ago(u.last_seen)}</td>
       <td><button class="btn btn-sm" onclick="reassignUsername('${esc(u.username)}')">Reassign</button>
           <button class="btn btn-danger btn-sm" onclick="releaseUsername('${esc(u.username)}')">Release</button></td></tr>`;
    }).join('')
      || `<tr><td colspan="6">${emptyState('🔤', 'No usernames yet', 'Names appear after the first claim.')}</td></tr>`;
  } catch (e) { toast('Usernames failed: ' + e.message, 'err'); }
}

async function releaseUsername(name) {
  if (!confirm(`Release @${name}? The name becomes claimable by anyone.`)) return;
  try {
    await rpc('admin_release_username', { p_username: name });
    toast('@' + name + ' released', 'ok');
    loadUsernames();
  } catch (e) { toast('Release failed: ' + e.message, 'err'); }
}

async function reassignUsername(name) {
  const uid = (prompt(`Move @${name} to which user id? (paste the uid)`, '')) || '';
  if (!uid.trim()) return;
  try {
    await rpc('admin_reassign_username', { p_username: name, p_target_uid: uid.trim() });
    toast('@' + name + ' reassigned', 'ok');
    loadUsernames();
  } catch (e) { toast('Reassign failed: ' + e.message, 'err'); }
}

async function revokeDevice(deviceId, revoke) {
  const verb = revoke ? 'Revoke' : 'Restore';
  if (revoke && !confirm('Revoke this device? It will see a "removed" screen until restored.')) return;
  try {
    await rpc('admin_device_revoke', { p_device_id: deviceId, p_revoke: revoke });
    toast(revoke ? 'Device revoked 🔒' : 'Device restored 🔓', 'ok');
    loadDevices();
  } catch (e) { toast(verb + ' failed: ' + e.message, 'err'); }
}

// ── 18+ Heaven per-device allow ──
async function setAdultAllow(deviceId, allow) {
  const verb = allow ? 'Allow 18+' : 'Block 18+';
  if (!allow && !confirm('Block 18+ Heaven on this device? Its adult section vanishes on next boot.')) return;
  try {
    await rpc('admin_device_adult', { p_device_id: deviceId, p_allow: allow });
    toast(allow ? '18+ Heaven allowed 🔞' : '18+ Heaven blocked 🔒', 'ok');
    loadDevices();
  } catch (e) { toast(verb + ' failed: ' + e.message, 'err'); }
}

// ── Phase D: reported users + escalating bans ──
async function loadUserReports() {
  $('userRepList').innerHTML = skLines(4);
  try {
    const rows = await rpc('admin_user_reports', { p_limit: 100, p_search: ($('repSearch') || {}).value || '' });
    $('userRepList').innerHTML = rows.map((u) => {
      const lvl = u.level === 'full' ? '<span class="pill p-closed">full</span>'
        : u.level === 'social' ? '<span class="pill p-adult">social</span>'
        : '<span class="pill p-live">clean</span>';
      const open = Number(u.reports_open) || 0;
      return `<div class="ann">
        <div class="ann-top"><span class="ann-title mono">${esc(u.user_id)}</span>
          <span>${open > 0 ? `<span class="pill p-closed">🚩 ${open} open</span>` : '<span class="mut">all dismissed</span>'} ${lvl}
          ${u.offence_count > 0 ? `<span class="chip" title="offences">⛓ ${u.offence_count}</span>` : ''}</span></div>
        <div class="ann-body">Last: ${esc(u.last_reason || '—')}</div>
        <div class="ann-meta"><span class="chip" title="${esc(fmtAbs(u.last_at))}">${ago(u.last_at)}</span>
          ${u.banned_until ? `<span class="chip">until ${esc(fmtAbs(u.banned_until))}</span>` : ''}</div>
        <div class="rowbtns">
          <button onclick="banUser('${u.user_id}','social')">🟠 Social ban</button>
          <button class="danger" onclick="banUser('${u.user_id}','full')">⛔ Full ban</button>
          <button onclick="dismissReports('${u.user_id}')">✓ Dismiss reports</button>
          <button class="ok" onclick="unbanUser('${u.user_id}')">🔓 Unban</button>
        </div></div>`;
    }).join('') || emptyState('🎉', 'No reported users', 'Nobody has been reported.');
  } catch (e) { toast('Reports failed: ' + e.message, 'err'); }
}

async function banUser(userId, level) {
  const daysStr = prompt(
    `${level === 'full' ? 'FULL' : 'SOCIAL'} ban — days (0 = permanent, blank = 3):`,
    '3');
  if (daysStr === null) return;
  const days = daysStr.trim() === '' ? 3 : parseInt(daysStr, 10);
  if (!Number.isFinite(days) || days < 0 || days > 3650) { toast('Days must be 0–3650', 'err'); return; }
  const reason = prompt('Reason (shown to the user in Easy English):', '') || '';
  if (!confirm(`Apply ${level} ban for ${days === 0 ? 'PERMANENTLY' : days + ' day(s)'}? offence_count will increase.`)) return;
  try {
    await rpc('admin_ban_user', { p_user_id: userId, p_level: level, p_days: days, p_reason: reason });
    toast(`Banned (${level}) ⛔`, 'ok'); refreshUserViews();
  } catch (e) { toast('Ban failed: ' + e.message, 'err'); }
}

async function unbanUser(userId) {
  if (!confirm('Lift this ban + restore their revoked devices?')) return;
  try {
    await rpc('admin_unban_user', { p_user_id: userId });
    toast('Unbanned 🔓', 'ok'); refreshUserViews();
  } catch (e) { toast('Unban failed: ' + e.message, 'err'); }
}

// Ban/unban is reachable from two places — the reported-users list and a
// plain Fleet search — so refresh whichever lists actually have a query.
function refreshUserViews() {
  if ($('userRepList')) loadUserReports();
  if (($('fuSearch') || {}).value && String($('fuSearch').value).trim()) loadFindUser();
}

async function dismissReports(userId) {
  try {
    await rpc('admin_dismiss_user_reports', { p_target_id: userId });
    toast('Reports dismissed ✓', 'ok'); loadUserReports();
  } catch (e) { toast('Dismiss failed: ' + e.message, 'err'); }
}

// ── Phase D: appeals ──
async function loadAppeals() {
  $('appealList').innerHTML = skLines(4);
  try {
    const rows = await rpc('ban_appeals_pending');
    $('appealList').innerHTML = rows.map((a) => {
      const st = a.status === 'pending' ? '<span class="pill p-live">pending</span>'
        : a.status === 'approved' ? '<span class="pill p-closed">approved</span>'
        : '<span class="pill p-closed">rejected</span>';
      const actions = a.status === 'pending' ? `<div class="rowbtns">
          <button class="ok" onclick="decideAppeal('${a.id}',true)">✓ Approve (lift ban)</button>
          <button class="danger" onclick="decideAppeal('${a.id}',false)">✗ Reject</button>
        </div>` : '';
      return `<div class="ann">
        <div class="ann-top"><span class="ann-title mono">${esc(a.user_id)}</span>
          <span>${st} ${a.level ? `<span class="pill ${a.level === 'full' ? 'p-closed' : 'p-adult'}">${esc(a.level)}</span>` : ''}
          ${a.offence_count > 0 ? `<span class="chip">⛓ ${a.offence_count}</span>` : ''}</span></div>
        <div class="ann-body">${esc(a.text)}</div>
        <div class="ann-meta"><span class="chip" title="${esc(fmtAbs(a.created_at))}">${ago(a.created_at)}</span></div>
        ${actions}</div>`;
    }).join('') || emptyState('📭', 'No appeals', 'Appeals show up here when users send them.');
  } catch (e) { toast('Appeals failed: ' + e.message, 'err'); }
}

async function decideAppeal(id, approve) {
  if (approve && !confirm('Approve? Ban is lifted and their devices are restored.')) return;
  const note = approve ? (prompt('Note (optional):', '') || '') : (prompt('Rejection reason:', '') || '');
  try {
    await rpc('ban_appeal_decide', { p_appeal_id: id, p_approve: approve, p_note: note });
    toast(approve ? 'Appeal approved ✅' : 'Appeal rejected ✗', 'ok');
    loadAppeals();
  } catch (e) { toast('Decision failed: ' + e.message, 'err'); }
}

// ── announcements ──
async function loadAnn() {
  $('annList').innerHTML = skLines(4);
  try {
    const { data, error } = await sb.from('announcements').select('*').order('created_at', { ascending: false }).limit(30);
    if (error) throw error;
    $('annList').innerHTML = (data || []).map((a) =>
      `<div class="ann ${a.active ? '' : 'off'}">
        <div class="ann-top"><span class="ann-title">${esc(a.title)}</span>
          ${a.active ? '<span class="pill p-live">active</span>' : '<span class="pill p-closed">paused</span>'}</div>
        <div class="ann-body">${esc(a.body)}</div>
        <div class="ann-meta">
          <span class="chip">versions ${esc(a.min_version || 'any')} → ${esc(a.max_version || 'any')}</span>
          <span class="chip" title="${esc(fmtAbs(a.created_at))}">${ago(a.created_at)}</span>
        </div>
        <div class="rowbtns">
          <button onclick='editAnn(${JSON.stringify(a.id)})'>✏️ Edit</button>
          <button class="danger" onclick="delAnn('${a.id}')">🗑 Delete</button>
        </div></div>`).join('')
      || emptyState('📭', 'No announcements yet', 'Create one with the form on the right.');
    window._annCache = Object.fromEntries((data || []).map((a) => [a.id, a]));
  } catch (e) { toast('Announcements failed: ' + e.message, 'err'); }
}
function editAnn(id) {
  const a = (window._annCache || {})[id];
  if (!a) return;
  $('annId').value = a.id; $('annTitle').value = a.title; $('annBody').value = a.body;
  $('annUrl').value = a.url || ''; $('annMin').value = a.min_version || '';
  $('annMax').value = a.max_version || ''; $('annActive').value = String(a.active);
  $('annFormTitle').textContent = 'Edit announcement';
  window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });
  $('annTitle').focus();
}
function resetAnn() {
  $('annId').value = ''; $('annTitle').value = ''; $('annBody').value = '';
  $('annUrl').value = ''; $('annMin').value = ''; $('annMax').value = '';
  $('annActive').value = 'true'; $('annFormTitle').textContent = 'New announcement';
}
async function saveAnn(ev) {
  const btn = ev && ev.target && ev.target.closest ? ev.target.closest('.btn') : null;
  try {
    await withLoading(btn, () => rpc('admin_announce_upsert', {
      p_id: $('annId').value || '', p_title: $('annTitle').value.trim(),
      p_body: $('annBody').value.trim(), p_url: $('annUrl').value.trim(),
      p_min_version: $('annMin').value.trim(), p_max_version: $('annMax').value.trim(),
      p_active: $('annActive').value === 'true',
    }));
    toast('Announcement saved 📣', 'ok'); resetAnn(); loadAnn();
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}
async function delAnn(id) {
  const ok = await confirmDialog({
    title: 'Delete this announcement?',
    message: 'It will disappear from the app right away. This cannot be undone.',
    okText: 'Delete',
  });
  if (!ok) return;
  try {
    await rpc('admin_announce_delete', { p_id: id });
    toast('Deleted', 'ok'); loadAnn();
  } catch (e) { toast('Delete failed: ' + e.message, 'err'); }
}

// ── config ──
const KNOWN_FEATURE_FLAGS = [
  { key: 'watch_party', label: 'Watch Together Cinema' },
  { key: 'voice', label: 'Voice Audio Chat' },
  { key: 'lossless_audio', label: 'Lossless FLAC Studio' },
  { key: 'offline_downloads', label: 'Smart Offline Hub' },
  { key: 'discover_daily', label: 'Discover Daily Rails' },
  { key: 'scraper_quarantine', label: 'Auto Quarantine Scrapers' },
  { key: 'new_episode_alerts', label: 'New Episode Alerts' },
  { key: 'yearly_wrap', label: 'Yearly Wrapped' },
];

function renderFeatureToggles(featuresObj) {
  const container = $('featureToggles');
  if (!container) return;
  const flags = { ...(featuresObj || {}) };
  const allKeys = Array.from(new Set([...KNOWN_FEATURE_FLAGS.map((f) => f.key), ...Object.keys(flags)]));
  container.innerHTML = allKeys.map((k) => {
    const known = KNOWN_FEATURE_FLAGS.find((f) => f.key === k);
    const label = known ? known.label : k;
    const active = Boolean(flags[k]);
    return `<button type="button" class="flag ${active ? 'on' : ''}" onclick="toggleFeatureFlag('${esc(k)}')"
      title="${active ? 'ON — click to turn off' : 'OFF — click to turn on'} · ${esc(k)}">
      <span class="sw-dot"></span>${esc(label)} <span class="key">${esc(k)}</span>
    </button>`;
  }).join('');
}

function onFeaturesJsonEdited() {
  try {
    const parsed = JSON.parse($('cfgFeatures').value || '{}');
    renderFeatureToggles(parsed);
  } catch (_) {}
}

async function toggleFeatureFlag(key) {
  try {
    let current = {};
    try { current = JSON.parse($('cfgFeatures').value || '{}'); } catch (_) {}
    current[key] = !Boolean(current[key]);
    $('cfgFeatures').value = JSON.stringify(current, null, 2);
    renderFeatureToggles(current);
    await saveCfg('features', JSON.stringify(current));
  } catch (e) { toast('Toggle failed: ' + e.message, 'err'); }
}

async function loadCfg() {
  try {
    const { data } = await sb.from('remote_config').select('key,value');
    const m = Object.fromEntries((data || []).map((r) => [r.key, r.value]));
    $('cfgMinVer').value = m.min_app_version || '';
    $('cfgForceAfter').value = m.force_after || '';
    $('cfgRollout').value = m.rollout_percent || '100';
    $('cfgChannel').value = (m.update_channel === 'beta') ? 'beta' : 'stable';
    $('cfgFeatures').value = pretty(m.features);
    $('cfgNotice').value = pretty(m.notice);
    let feat = {};
    try { feat = JSON.parse(m.features || '{}'); } catch (_) {}
    renderFeatureToggles(feat);
  } catch (e) { toast('Config failed: ' + e.message, 'err'); }
}
function pretty(v) {
  try { return JSON.stringify(JSON.parse(v || '{}'), null, 2); } catch (_) { return v || ''; }
}
// Only these config values are JSON blobs. Everything else (min_app_version,
// force_after, update_channel, rollout_percent) is plain text, and parsing it
// threw, which left the force_after and update_channel Save buttons dead.
const JSON_CFG_KEYS = ['features', 'notice'];
async function saveCfg(key, value) {
  try {
    if (JSON_CFG_KEYS.indexOf(key) >= 0) JSON.parse(value || '{}');
    await rpc('admin_set_config', { p_key: key, p_value: value });
    toast(key + ' saved ⚙️', 'ok');
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}

// ── v1.3.3-T5: hot-fix key editor (curators + owners; server gates keys) ──
const HOTFIX_KEYS = [
  ['min_supported_build', 'Min supported build (below → force update)', false],
  ['support_faq_bundle_version', 'FAQ bundle version', false],
  ['music_shelves_layout', 'Music shelves layout (JSON)', true],
  ['music_endpoints.jiosaavn', 'Music endpoint: JioSaavn (Edge URL)', false],
  ['music_endpoints.ytmusic', 'Music endpoint: YT-Music (Edge URL)', false],
  ['music_endpoints.spotify', 'Music endpoint: Spotify (Edge URL)', false],
  ['scraper_urls', 'Scraper URL overrides (JSON)', true],
  ['scraper_regex', 'Scraper regex overrides (JSON)', true],
  ['ranking_weights', 'Ranking weights (JSON)', true],
  ['feature_flags', 'Feature flags (JSON)', true],
  ['announcements_feed', 'Announcements feed (JSON)', true],
];
async function loadHotfix() {
  const box = $('hotfixList');
  try {
    const { data } = await sb.from('remote_config').select('key,value');
    const m = Object.fromEntries((data || []).map((r) => [r.key, r.value]));
    if (box) box.innerHTML = HOTFIX_KEYS.map(([k, label, isJson]) =>
      `<div class="cfg-row col"><div class="cfg-l"><label class="fl" for="hf-${k}">${esc(label)}</label><p class="hint mono">${esc(k)}</p></div>
       <textarea id="hf-${k}" rows="${isJson ? 3 : 1}" class="mono" spellcheck="false">${esc(m[k] || '')}</textarea>
       <div class="rowbtns"><button class="btn btn-ok btn-sm" onclick="saveHotfix('${esc(k)}',${isJson})">💾 Save</button></div></div>`
    ).join('');
  } catch (e) { if (box) box.innerHTML = emptyState('⚠️', 'Hot-fix load failed', e.message); }
}
async function saveHotfix(key, isJson) {
  try {
    const v = ($( 'hf-' + key) || {}).value || '';
    if (isJson && v.trim()) JSON.parse(v);
    await rpc('admin_set_config', { p_key: key, p_value: v });
    toast(key + ' saved ⚙️', 'ok');
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}

// ── audit ──
// Live is a realtime switch now (see rtFire); it persists across tabs.
function toggleAuditLive() {
  const on = document.getElementById('auditLive').checked;
  if (on) { loadAudit(); toast('Audit live mode on', 'info'); }
}
function stopAuditLive() { /* nothing to tear down — the socket is shared */ }
function auditPill(action) {
  const a = String(action || '').toLowerCase();
  if (a.includes('delete') || a.includes('kill') || a.includes('ban')) return 'p-adult';
  if (a.includes('save') || a.includes('create') || a.includes('add') || a.includes('upsert')) return 'p-live';
  if (a.includes('update') || a.includes('edit')) return 'p-lobby';
  return 'p-closed';
}
async function loadAudit() {
  const tb = document.querySelector('#auditTbl tbody');
  if (tb && !tb.children.length) tb.innerHTML = skRows(8, 4);
  try {
    const rows = await rpc('admin_audit_tail', { p_limit: 50 });
    if (tb) tb.innerHTML = rows.map((a) =>
      `<tr><td class="mut" title="${esc(fmtAbs(a.created_at))}">${ago(a.created_at)}</td>
       <td><span class="pill ${auditPill(a.action)}">${esc(a.action)}</span></td>
       <td class="mono">${esc(a.target)}</td>
       <td class="mut">${esc(JSON.stringify(a.detail))}</td></tr>`).join('')
      || `<tr><td colspan="4">${emptyState('🧾', 'No audit entries yet', 'Admin writes will show up here.')}</td></tr>`;
  } catch (e) { toast('Audit failed: ' + e.message, 'err'); }
}

// ── device logs ──
// Error telemetry from the app. Enum codes only: the client and the
// report-error edge both reject free text, so nothing here is user data.
// RLS allows SELECT for is_admin() only, so this table is simply not
// readable by the anon key used by sb.
const DEVICE_LOG_LIMIT = 100;
let _dlCodePrefix = '';

function deviceCodeFilter() {
  const raw = String(document.getElementById('dlDevice')?.value || '').trim();
  return raw.replace(/^DIZ-/i, '');
}
function clearDeviceLogFilter() {
  const box = document.getElementById('dlDevice');
  if (box) box.value = '';
  _dlCodePrefix = '';
  document.querySelectorAll('#dlChips .chip-btn').forEach((b) => b.classList.toggle('on', b.dataset.pre === ''));
  loadDeviceLogs();
}
function setDeviceErrorCodeFilter(prefix) {
  _dlCodePrefix = prefix || '';
  document.querySelectorAll('#dlChips .chip-btn').forEach((b) =>
    b.classList.toggle('on', (b.dataset.pre || '') === _dlCodePrefix));
  loadDeviceLogs();
}
// Live is a realtime switch now (see rtFire); it persists across tabs.
function toggleDeviceLogsLive() {
  const on = document.getElementById('dlLive').checked;
  if (on) { loadDeviceLogs(); toast('Device log live mode on', 'info'); }
}
function stopDeviceLogsLive() { /* nothing to tear down — the socket is shared */ }
// v1.3.3-T2.3: render the enum session trail as a compact timeline.
// The trail is already enum-only (validated client + edge + RPC), so this
// is display sugar — but it still escapes, because "validated" is not a
// licence to skip escaping.
function trailCell(trail) {
  const t = String(trail || '').trim();
  if (!t) return '<span class="mut">—</span>';
  return t.split('>').map((x) => `<span class="tstep">${esc(x)}</span>`).join('<span class="tarrow">›</span>');
}
async function loadDeviceLogs() {
  try {
    const filter = deviceCodeFilter();
    let q = sb.from('device_logs').select('*')
      .order('last_at', { ascending: false })
      .limit(DEVICE_LOG_LIMIT);
    if (filter) q = q.eq('device_code', filter);
    if (_dlCodePrefix) q = q.like('code', `${_dlCodePrefix}%`);
    const { data, error } = await q;
    if (error) throw error;
    const rows = data || [];
    const filterDesc = [
      filter ? `device DIZ-${filter}` : '',
      _dlCodePrefix ? `code ${_dlCodePrefix}*` : '',
    ].filter(Boolean).join(', ');
    $('dlSummary').textContent = rows.length
      ? `${rows.length} of the last ${DEVICE_LOG_LIMIT} · ${rows.reduce((n, r) => n + (r.count || 0), 0)} hits${filterDesc ? ` (${filterDesc})` : ''}`
      : (filterDesc ? `No logs matching ${filterDesc}.` : 'No error reports yet.');
    document.querySelector('#dlTbl tbody').innerHTML = rows.map((r) =>
      `<tr>
        <td class="mono">${r.device_code === 'unknown' ? 'unknown' : 'DIZ-' + esc(r.device_code)}</td>
        <td><span class="pill ${r.count > 10 ? 'p-adult' : r.count > 2 ? 'p-priv' : 'p-lobby'}">${esc(r.code)}</span></td>
        <td>${esc(r.screen)}</td>
        <td class="mut">${esc(r.detail || '—')}</td>
        <td class="num"><b>${Number(r.count) || 0}</b></td>
        <td>${esc(r.platform)}</td>
        <td class="mut">${esc(r.app_version || '—')}</td>
        <td class="trail">${trailCell(r.trail)}</td>
        <td class="mut" title="${esc(fmtAbs(r.last_at))}">${ago(r.last_at)}</td>
      </tr>`).join('')
      || `<tr><td colspan="9">${emptyState('🌙', 'Nothing to show', filterDesc ? 'Try a different filter.' : 'No error reports yet.')}</td></tr>`;
  } catch (e) { toast('Device logs failed: ' + e.message, 'err'); }
}

// DCL can fire before this script registers (restored/fast loads) — guard it.
if (document.readyState === 'loading') {
  window.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}

// ── v1.3.3-T2.0: admin account management (owner only) ──
async function loadAdmins() {
  const tb = document.querySelector('#admTbl tbody');
  if (tb && !tb.children.length) tb.innerHTML = skRows(4, 4);
  try {
    const rows = await rpc('admin_user_list', {});
    if (tb) tb.innerHTML = (rows || []).map((a) =>
      `<tr><td>${esc(a.email || shortId(a.user_id) + '…')}</td>
       <td><span class="pill ${a.role === 'owner' ? 'p-adult' : a.role === 'viewer' ? 'p-closed' : 'p-lobby'}">${esc(a.role)}</span></td>
       <td class="mut" title="${esc(fmtAbs(a.created_at))}">${ago(a.created_at)}</td>
       <td><button class="btn btn-ghost btn-sm" onclick="removeAdmin('${esc(a.user_id)}')">Remove</button></td></tr>`).join('')
      || `<tr><td colspan="4">${emptyState('👑', 'No admins yet', 'Add the first owner above.')}</td></tr>`;
  } catch (e) { toast('Admins failed: ' + e.message, 'err'); }
}
async function saveAdmin() {
  const email = ($('admEmail') || {}).value || '';
  const role = ($('admRole') || {}).value || 'viewer';
  if (!email.trim()) { toast('Email needed', 'err'); return; }
  try {
    await rpc('admin_user_upsert', { p_email: email.trim(), p_role: role });
    toast(email + ' → ' + role + ' ✓', 'ok');
    if ($('admEmail')) $('admEmail').value = '';
    loadAdmins();
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}
async function removeAdmin(uid) {
  if (!confirm('Remove this admin?')) return;
  try {
    await rpc('admin_user_remove', { p_user_id: uid });
    toast('Removed ✓', 'ok');
    loadAdmins();
  } catch (e) { toast('Remove failed: ' + e.message, 'err'); }
}

// ── device push (v1.3.3 Phase 4, v1.4 operator controls) ──
// Thin wrappers over the two edge functions. The dashboard sends its own
// admin JWT; push-send and push-brain both accept a real admin, so nothing
// secret ever ships in this static bundle.
//
// v1.4 adds the three things an operator actually needs at 2 a.m.: how big
// the audience is, one tap to stop the world, and one tap to aim a single
// notification at the device named in a support ticket.
let pushAudience = null;
let pushTarget = null;
let pushTargets = [];

async function pushFn(name, payload) {
  const cfg = window.DIZZY_CONFIG || {};
  const { data } = await sb.auth.getSession();
  const token = (data && data.session && data.session.access_token) || '';
  const res = await fetch(cfg.url + '/functions/v1/' + name, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + token,
    },
    body: JSON.stringify(payload || {}),
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(out.error || ('HTTP ' + res.status));
  return out;
}
function pushOut(obj) {
  const el = $('rpOut');
  if (!el) return;
  el.style.display = 'block';
  el.textContent = JSON.stringify(obj, null, 2);
}

// Audience + kill switch. One RPC, so the number and the switch can never
// disagree: if the header says "12.4k phones" the switch beside it is the one
// that reaches them.
async function loadPushAudience() {
  const line = $('rpAudience');
  const btn = $('rpSwitch');
  try {
    const a = (await rpc('admin_push_audience')) || {};
    pushAudience = a;
    const on = a.sending_enabled !== false;
    if (line) {
      line.innerHTML = on
        ? `<b>${fmtNum(a.phones)}</b> phones · <b>${fmtNum(a.people)}</b> people · ` +
          `${fmtNum(a.android)} Android / ${fmtNum(a.ios)} iOS · ` +
          `${fmtNum(a.sent_24h)} sent in 24 h` +
          (a.failed_24h ? ` · <span style="color:var(--red)">${fmtNum(a.failed_24h)} failed</span>` : '')
        : `⏸ <b style="color:var(--red)">Push is paused</b> — ${esc(a.paused_reason || 'no reason given')} · ` +
          `${fmtNum(a.phones)} phones waiting`;
    }
    if (btn) {
      btn.textContent = on ? '⏸ Pause all' : '▶ Resume push';
      btn.style.color = on ? '' : 'var(--acc)';
    }
  } catch (e) {
    if (line) line.innerHTML = 'Audience unavailable: ' + esc(e.message);
  }
}

async function togglePushSwitch() {
  const currentlyOn = !(pushAudience && pushAudience.sending_enabled === false);
  try {
    if (currentlyOn) {
      const ok = await confirmDialog({
        title: 'Pause every notification?',
        message: 'The brain and every manual send stop until you resume. Nobody is unsubscribed.',
        okText: 'Pause all',
      });
      if (!ok) return;
      const reason = prompt('Reason (kept in the admin log):', '') || '';
      pushAudience = await rpc('admin_push_set_enabled', {
        p_enabled: false,
        p_reason: reason,
      });
      toast('Push paused', 'warn');
    } else {
      pushAudience = await rpc('admin_push_set_enabled', {
        p_enabled: true,
        p_reason: '',
      });
      toast('Push resumed', 'ok');
    }
  } catch (e) {
    toast('Switch failed: ' + e.message, 'err');
  }
  await loadPushAudience();
  loadPushEvents();
}

// Paste a ticket code -> the user id push-send needs. The resolver lives in
// the database (admin_push_resolve), so retired DIZ-codes and @usernames work
// here exactly like they do on the device card.
async function findPushTarget() {
  const box = $('rpTargetOut');
  const btn = $('rpSendTarget');
  const q = (($('rpTarget') || {}).value || '').trim();
  pushTarget = null;
  pushTargets = [];
  if (btn) btn.disabled = true;
  if (!q) {
    if (box) box.textContent = 'Paste a DIZ-code, @username or user id.';
    return;
  }
  if (box) box.textContent = 'Looking…';
  try {
    const rows = await rpc('admin_push_resolve', { p_search: q });
    pushTargets = Array.isArray(rows) ? rows : [];
    if (!pushTargets.length) {
      if (box) {
        box.innerHTML =
          '<span style="color:var(--acc)">No device matches that. ' +
          'If they reinstalled, try the retired code printed in the ticket.</span>';
      }
      return;
    }
    pushTarget = pushTargets[0];
    if (btn) btn.disabled = false;
    if (box) {
      box.innerHTML = pushTargets.slice(0, 4).map((r, i) => `
        <div style="display:flex;gap:8px;align-items:center;margin-top:5px;flex-wrap:wrap">
          <span class="chip">${esc(r.device_code || '—')}</span>
          <span>${esc(r.username ? '@' + r.username : shortId(r.user_id))}</span>
          <span class="chip">${fmtNum(r.tokens)} phone${(Number(r.tokens) === 1) ? '' : 's'}</span>
          <button class="btn btn-ghost btn-sm" onclick="pickPushTarget(${i})">Use</button>
        </div>`).join('');
    }
  } catch (e) {
    if (box) box.textContent = 'Lookup failed: ' + e.message;
  }
}

function pickPushTarget(i) {
  const row = pushTargets[i];
  if (!row) return;
  pushTarget = row;
  const btn = $('rpSendTarget');
  if (btn) btn.disabled = false;
  toast('Aiming at ' + (row.device_code || shortId(row.user_id)), 'info');
}

async function logAdminPush({ mode, target, kind, title, body, out, dry }) {
  try {
    await rpc('admin_push_log', {
      p_mode: mode,
      p_target: target || '',
      p_kind: kind,
      p_title: title,
      p_body: body,
      p_tokens: out.tokens || 0,
      p_sent: out.sent || 0,
      p_failed: out.failed || 0,
      p_dry_run: !!dry,
      p_error: out.error || '',
    });
  } catch (e) {
    // A send that already happened must never be hidden by a log failure.
    console.warn('push log failed', e);
  }
}

async function sendPush(mode) {
  const title = ($('rpTitle') || {}).value || '';
  const body = ($('rpBody') || {}).value || '';
  const dry = !!($('rpDry') || {}).checked;
  const kind = ($('rpKind') || {}).value || 'releases';
  if (!title.trim() && !body.trim()) {
    toast('Title or body required', 'warn');
    return;
  }

  const payload = {
    mode: mode === 'target' ? 'users' : mode,
    kind,
    title: title.trim(),
    body: body.trim(),
    dry_run: dry,
  };
  let target = '';

  if (mode === 'target') {
    if (!pushTarget || !pushTarget.user_id) {
      toast('Find a device first', 'warn');
      return;
    }
    payload.user_ids = [pushTarget.user_id];
    target = pushTarget.device_code || pushTarget.username || pushTarget.user_id;
    if (!dry) {
      const ok = await confirmDialog({
        title: 'Send to ' + target + '?',
        message: 'One notification, to that account only' +
          (pushTarget.tokens ? ' (' + pushTarget.tokens + ' phone' + (Number(pushTarget.tokens) === 1 ? '' : 's') + ').' : '.'),
        okText: 'Send',
      });
      if (!ok) return;
    }
  }

  if (mode === 'broadcast' && !dry) {
    const n = pushAudience && pushAudience.phones ? pushAudience.phones : 0;
    const ok = await confirmDialog({
      title: 'Broadcast to every phone?',
      message: (n ? fmtNum(n) + ' phones get this right now. ' : '') +
        'Every device with notifications enabled gets this.',
      okText: 'Broadcast',
    });
    if (!ok) return;
  }

  try {
    const out = await pushFn('push-send', payload);
    pushOut(out);
    const label = out.dry_run ? 'previewed' : 'sent';
    toast('Push ' + label + ' · ' + (out.sent || 0) + '/' + (out.tokens || 0), 'ok');
    await logAdminPush({ mode, target, kind, title, body, out, dry });
    loadPushLog();
    loadPushEvents();
  } catch (e) {
    toast('Push failed: ' + e.message, 'err');
    // A refused send is still worth a line: kill switch, quota, bad token.
    await logAdminPush({
      mode, target, kind, title, body,
      out: { error: e.message }, dry,
    });
    loadPushEvents();
  }
}
async function runBrain() {
  try {
    const out = await pushFn('push-brain', { dry_run: true, max_users: 5 });
    pushOut(out);
    toast('Brain preview · ' + (out.users || 0) + ' user(s)', 'info');
  } catch (e) {
    toast('Brain failed: ' + e.message, 'err');
  }
}

// ── v1.3.7 update campaign ──
// One card that sees all four surfaces at once: the GitHub release the site
// links to, the app's min_app_version, the version the fleet actually reports
// and the exact text each phone will receive. Preview calls push-send with
// `preview:true`, which returns messages[] and sends nothing.
const campaignState = { release: {}, min: '' };

function campaignDefaults() {
  const c = $('rpCampaign');
  if (c && !c.value) c.value = new Date().toISOString().slice(0, 10);
}

async function loadCampaign() {
  campaignDefaults();
  const line = $('rpSurfaces');
  const cfg = window.DIZZY_CONFIG || {};
  let tag = '';
  let cfgRows = [];
  try {
    const [rel, rows] = await Promise.all([
      fetch(cfg.url + '/functions/v1/release-latest', { headers: { Accept: 'application/json' } })
        .then(function (r) { return r.json(); })
        .catch(function () { return {}; }),
      sb.from('remote_config').select('key,value'),
    ]);
    campaignState.release = rel || {};
    tag = String((rel || {}).tag || '').replace(/^v/, '');
    cfgRows = (rows && rows.data) || [];
  } catch (_) {}
  const m = Object.fromEntries(cfgRows.map(function (r) { return [r.key, r.value]; }));
  const min = m.min_app_version || '';
  campaignState.min = min;
  const latestInput = $('rpLatest');
  if (latestInput && !latestInput.value && tag) latestInput.value = tag;
  const phones = pushAudience && pushAudience.phones;
  loadCampaignLedger();
  if (!line) return;
  if (!tag && !latestInput.value) {
    line.innerHTML = '⚠️ GitHub release list unreachable — type the target version yourself.';
    return;
  }
  const drift = min && tag && min !== tag
    ? ' · <span style="color:var(--acc)">min_app_version (' + esc(min) +
      ') is not the release (' + esc(tag) + ')</span>'
    : '';
  line.innerHTML =
    'release <b>v' + esc(tag || latestInput.value) + '</b> · ' +
    'min_app_version <b>' + esc(min || '—') + '</b> · ' +
    '<b>' + fmtNum(phones || 0) + '</b> phones with push' + drift;
}

function campaignPayload() {
  const latest = (($('rpLatest') || {}).value || '').trim().replace(/^v/, '');
  const campaign = (($('rpCampaign') || {}).value || '').trim();
  const fromVer = (($('rpFromVer') || {}).value || '').trim();
  if (!latest) { toast('latest_version required', 'warn'); return null; }
  if (!campaign) { toast('campaign id required (single-shot key)', 'warn'); return null; }
  const payload = {
    mode: 'update',
    campaign: campaign,
    latest_version: latest,
    android_only: !!($('rpAndroidOnly') || {}).checked,
  };
  if (fromVer) payload.from_version = fromVer;
  // Canary knobs. A cap with no ids means "the oldest N builds", which is the
  // trial most likely to surface a broken payload before the fleet sees it.
  const limit = parseInt((($('rpLimit') || {}).value || '0'), 10) || 0;
  const ids = (($('rpDeviceIds') || {}).value || '')
    .split(/[\s,]+/)
    .map(function (s) { return s.trim(); })
    .filter(Boolean);
  if (limit > 0) payload.limit = limit;
  if (ids.length) payload.device_ids = ids;
  return payload;
}

async function previewCampaign() {
  const payload = campaignPayload();
  if (!payload) return;
  const box = $('rpMessages');
  if (box) box.textContent = 'Rendering…';
  try {
    const out = await pushFn('push-send', Object.assign({ preview: true }, payload));
    const list = out.messages || [];
    const head = '<div class="hint">' + fmtNum(out.tokens) + ' phone(s) · ' +
      fmtNum(out.considered) + ' token(s) considered' +
      (out.limit ? ' · canary capped at ' + fmtNum(out.limit) + ' of ' + fmtNum(out.eligible || out.tokens) : '') +
      (out.truncated ? ' · <span style="color:var(--acc)">TRUNCATED at the cap</span>' : '') +
      (list.some(function (m) { return !m.name; }) ? ' · some have no username' : '') +
      '</div>';
        const body = list.map(function (m, i) {
      return '<div style="border-top:1px solid rgba(255,255,255,.08);padding:8px 0">' +
        '<div class="hint">#' + (i + 1) + ' · pattern ' + esc(m.pattern || '?') +
        ' · ' + (m.from ? 'v' + esc(m.from) : 'no version reported') +
        ' · ' + esc(m.name || 'no username') +
        (m.device_id ? ' · device ' + esc(String(m.device_id).slice(0, 8)) : '') +
        '</div>' +
        '<div><b>' + esc(m.title) + '</b></div>' +
        '<div>' + esc(m.body) + '</div></div>';
    }).join('');
    if (box) box.innerHTML = head + (body || '<div class="hint">No phones are below this version.</div>');
    toast('Preview · ' + fmtNum(list.length) + ' message(s), nothing sent', 'ok');
  } catch (e) {
    if (box) box.textContent = 'Preview failed: ' + e.message;
    toast('Preview failed: ' + e.message, 'err');
  }
}

async function sendCampaign(dry, canary) {
  const payload = campaignPayload();
  if (!payload) return;
  // A canary claims `<campaign>#canary` on the ledger, so this trial does not
  // burn the whole-fleet send's 20-hour single-shot key.
  if (canary) payload.canary = true;
  try {
    if (!dry) {
      // Count first so the confirmation names a real number.
      const pre = await pushFn('push-send', Object.assign({ preview: true }, payload));
      const n = (pre.messages || []).length;
      if (!n) { toast('Nobody is below v' + payload.latest_version, 'warn'); return; }
      const ok = await confirmDialog({
        title: canary
          ? 'Send a canary to ' + n + ' phone(s)?'
          : 'Send the ' + payload.latest_version + ' campaign?',
        message: n + ' phone(s) get one notification now. ' + (canary
          ? 'Key ' + payload.campaign + '#canary — the full send stays available.'
          : 'Campaign ' + payload.campaign + ' is single-shot for 20 h.') +
          ' A push cannot be recalled.',
        okText: (canary ? 'Canary ' : 'Send to ') + n,
      });
      if (!ok) return;
    }
    const out = await pushFn('push-send', Object.assign({ dry_run: !!dry }, payload));
    const pre = $('rpOut2');
    if (pre) { pre.style.display = 'block'; pre.textContent = JSON.stringify(out, null, 2); }
    if (dry) {
      toast('Dry run · ' + fmtNum(out.tokens) + ' target(s), nothing sent', 'ok');
    } else {
      toast((canary ? 'Canary sent · ' : 'Campaign sent · ') + fmtNum(out.sent) + '/' + fmtNum(out.tokens) +
        (out.failed ? ' · ' + fmtNum(out.failed) + ' failed' : ''), 'ok');
    }
    loadPushAudience();
    loadPushEvents();
    loadPushLog();
    loadCampaignLedger();
  } catch (e) {
    // 409 campaign_already_sent / push_disabled arrive as thrown errors.
    toast('Campaign refused: ' + e.message, 'err');
  }
}

// Every update send the server ever recorded, newest first. The server claims a
// row before the first FCM call and closes it after the loop, so a row whose
// sent+failed is short of `tokens` is a send that was interrupted — the one
// thing an operator has to see after a canary.
async function loadCampaignLedger() {
  const box = $('rpLedger');
  if (!box) return;
  box.innerHTML = skLines(2);
  try {
    const { data, error } = await sb
      .from('admin_push_events')
      .select('id, target, title, body, tokens, sent, failed, error, created_at')
      .eq('event', 'send')
      .eq('mode', 'update')
      .order('created_at', { ascending: false })
      .limit(12);
    if (error) throw error;
    box.innerHTML = (data || []).map(function (r) {
      const isCanary = String(r.target || '').slice(-7) === '#canary';
      const interrupted = Number(r.tokens) > 0 &&
        Number(r.sent) + Number(r.failed) < Number(r.tokens);
      const pill = interrupted ? 'p-closed' : Number(r.sent) > 0 ? 'p-live' : 'p-lobby';
      return '<div class="ann">' +
        '<div class="ann-top"><span class="ann-title">' + esc(r.target || '(no campaign id)') +
          (isCanary ? ' <span class="chip">canary</span>' : '') + '</span>' +
          '<span class="pill ' + pill + '">' +
            (interrupted ? 'interrupted' : Number(r.sent) > 0 ? 'sent' : 'no sends') + '</span></div>' +
        '<div class="ann-meta">' +
          '<span class="chip">' + fmtNum(r.sent) + '/' + fmtNum(r.tokens) + ' sent</span>' +
          (Number(r.failed) ? '<span class="chip" style="color:var(--red)">' + fmtNum(r.failed) + ' failed</span>' : '') +
          (r.body ? '<span class="chip">' + esc(r.body) + '</span>' : '') +
          '<span class="chip" title="' + esc(fmtAbs(r.created_at)) + '">' + ago(r.created_at) + '</span>' +
        '</div>' +
        (r.error ? '<div class="ann-body" style="opacity:.6">' + esc(String(r.error).slice(0, 140)) + '</div>' : '') +
        '</div>';
    }).join('') || emptyState('🐤', 'No campaign sent yet', 'Preview, canary, then the full send — each one lands here.');
  } catch (e) {
    box.innerHTML = '<p class="hint">Ledger failed: ' + esc(e.message) + '</p>';
  }
}

async function loadPushEvents() {
  const box = $('rpEvents');
  if (!box) return;
  box.innerHTML = skLines(3);
  try {
    const { data, error } = await sb
      .from('admin_push_events')
      .select('id, event, mode, target, title, tokens, sent, failed, dry_run, error, created_at')
      .order('created_at', { ascending: false })
      .limit(20);
    if (error) throw error;
    box.innerHTML = (data || []).map((r) => {
      const isSwitch = r.event === 'pause' || r.event === 'resume';
      const pill = r.event === 'pause' ? 'p-closed'
        : r.event === 'resume' ? 'p-live'
        : r.dry_run ? 'p-lobby' : 'p-live';
      const what = isSwitch
        ? (r.event === 'pause' ? 'Push paused' : 'Push resumed')
        : (r.title || '—');
      const counts = isSwitch ? '' :
        `<span class="chip">${fmtNum(r.sent)}/${fmtNum(r.tokens)} sent</span>` +
        (r.failed ? `<span class="chip" style="color:var(--red)">${fmtNum(r.failed)} failed</span>` : '');
      return `<div class="ann">
        <div class="ann-top"><span class="ann-title">${esc(what)}</span>
          <span class="pill ${pill}">${esc(r.event)}${r.dry_run ? ' · dry' : ''}</span></div>
        <div class="ann-meta">
          <span class="chip">${esc(r.mode || '—')}</span>
          ${r.target ? `<span class="chip">${esc(r.target)}</span>` : ''}
          ${counts}
          <span class="chip" title="${esc(fmtAbs(r.created_at))}">${ago(r.created_at)}</span>
        </div>
        ${r.error ? `<div class="ann-body" style="opacity:.6">${esc(String(r.error).slice(0, 140))}</div>` : ''}
      </div>`;
    }).join('') || emptyState('🧾', 'No admin sends yet', 'Send, pause or resume and it lands here.');
  } catch (e) {
    box.innerHTML = '<p class="hint">Actions failed: ' + esc(e.message) + '</p>';
  }
}

async function loadPushLog() {
  const box = $('rpLog');
  if (!box) return;
  box.innerHTML = skLines(4);
  try {
    const { data, error } = await sb
      .from('push_send_log')
      .select('id, user_id, kind, title, status, error, created_at')
      .order('created_at', { ascending: false })
      .limit(40);
    if (error) throw error;
    box.innerHTML = (data || []).map((r) => {
      const pill =
        r.status === 'sent' ? 'p-live'
          : r.status === 'failed' ? 'p-closed'
          : r.status === 'queued' ? 'p-lobby' : '';
      return `<div class="ann">
        <div class="ann-top"><span class="ann-title">${esc(r.title || '—')}</span>
          <span class="pill ${pill}">${esc(r.status)}</span></div>
        <div class="ann-meta">
          <span class="chip">${esc(r.kind)}</span>
          <span class="chip">${shortId(r.user_id)}</span>
          <span class="chip" title="${esc(fmtAbs(r.created_at))}">${ago(r.created_at)}</span>
        </div>
        ${r.error ? `<div class="ann-body" style="opacity:.6">${esc(String(r.error).slice(0, 140))}</div>` : ''}
      </div>`;
    }).join('') || emptyState('📭', 'No sends yet', 'The brain writes here when it ships a title.');
  } catch (e) {
    box.innerHTML = '<p class="hint">Log failed: ' + esc(e.message) + '</p>';
  }
}
