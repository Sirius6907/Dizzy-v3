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
    // must be in admins allowlist
    const { data: row } = await sb.from('admins').select('user_id').eq('user_id', data.user.id).maybeSingle();
    if (!row) {
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
}

// ── nav ──
const PAGE_META = {
  overview: ['Overview', 'Live health of the Dizzy fleet'],
  rooms: ['Rooms', 'Watch rooms across the app'],
  moderation: ['Moderation', 'Reported rooms waiting on you'],
  scrapers: ['Scrapers', 'Crowd votes & kill switches'],
  users: ['Installs', 'Installed apps · anonymous IDs only'],
  push: ['Announcements', 'In-app banners the app polls'],
  config: ['Remote config', 'Flags & limits read at app startup'],
  audit: ['Audit log', 'Every admin write, newest first'],
  devicelogs: ['Device logs', 'Enum-only error telemetry'],
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
  if (name === 'moderation') loadRooms(true);
  if (name === 'scrapers') loadScrapers();
  if (name === 'users') { loadUsers(); loadDevices(); }
  if (name === 'push') loadAnn();
  if (name === 'config') loadCfg();
  if (name === 'audit') loadAudit(); else stopAuditLive();
  if (name === 'devicelogs') loadDeviceLogs(); else stopDeviceLogsLive();
}

async function rpc(name, params) {
  const { data, error } = await sb.rpc(name, params || {});
  if (error) throw error;
  return data;
}

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
      <div class="health-foot"><span class="dot dot-grn"></span> Supabase connected · edge functions assumed active · refresh for latest</div>`;
    $('ovUpdated').textContent = 'updated ' + ago(new Date().toISOString());
  } catch (e) {
    $('breakdown').innerHTML = emptyState('⚠️', 'Breakdown unavailable', e.message);
    $('health').innerHTML = emptyState('⚠️', 'Health check failed', e.message);
    toast('Overview failed: ' + e.message, 'err');
  }
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
  grad.addColorStop(0, '#a78bfa');
  grad.addColorStop(1, '#6d28d9');
  const hot = ctx.createLinearGradient(0, padT, 0, H - padB);
  hot.addColorStop(0, '#c4b5fd');
  hot.addColorStop(1, '#8b5cf6');

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

// ── installs ──
async function loadUsers() {
  const tb = document.querySelector('#usersTbl tbody');
  if (tb) tb.innerHTML = skRows(8, 6);
  try {
    const rows = await rpc('admin_installs', { p_limit: 50, p_search: $('uSearch').value || '' });
    if (tb) tb.innerHTML = rows.map((u) =>
      `<tr><td class="mono" title="${esc(u.anon_id)}">${esc(shortId(u.anon_id))}…</td>
       <td>${esc(u.platform)}</td><td>${esc(u.app_version)}</td>
       <td>${esc(u.region_code)}</td>
       <td class="mut" title="${esc(fmtAbs(u.created_at))}">${ago(u.created_at)}</td>
       <td class="mut" title="${esc(fmtAbs(u.last_seen_at))}">${ago(u.last_seen_at)}</td></tr>`).join('')
      || `<tr><td colspan="6">${emptyState('📭', 'No installs found', 'Try another search term.')}</td></tr>`;
  } catch (e) { toast('Installs failed: ' + e.message, 'err'); }
}

// ── devices (Phase C) ──
async function loadDevices() {
  const tb = document.querySelector('#devicesTbl tbody');
  if (tb) tb.innerHTML = skRows(8, 6);
  try {
    const rows = await rpc('admin_devices', { p_limit: 100, p_search: ($('devSearch') || {}).value || '' });
    if (tb) tb.innerHTML = rows.map((d) => {
      const dot = d.online ? '<span class="pill p-live">● online</span>' : '<span class="mut">offline</span>';
      const badges = [
        d.revoked_at ? '<span class="pill p-closed">revoked</span>' : '',
        d.banned ? `<span class="pill p-closed" title="level ${esc(d.ban_level || 'social')}">banned</span>` : '',
        d.hwid_stable === false ? '<span class="pill" title="weak identity anchor">new</span>' : '',
      ].filter(Boolean).join(' ');
      const action = d.revoked_at
        ? `<button class="btn btn-ok btn-sm" onclick="revokeDevice('${d.device_id}',false)">Restore</button>`
        : `<button class="btn btn-danger btn-sm" onclick="revokeDevice('${d.device_id}',true)">Revoke</button>`;
      return `<tr><td class="mono">${esc(d.device_code)}</td>
       <td>${esc(d.platform)}</td><td>${esc(d.app_version)}</td>
       <td>${dot} ${badges}</td>
       <td class="mut" title="${esc(fmtAbs(d.last_seen_at))}">${ago(d.last_seen_at)}</td>
       <td>${action}</td></tr>`;
    }).join('')
      || `<tr><td colspan="6">${emptyState('📭', 'No devices yet', 'Devices register on app boot.')}</td></tr>`;
  } catch (e) { toast('Devices failed: ' + e.message, 'err'); }
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
async function saveAnn() {
  const btn = event && event.target && event.target.closest ? event.target.closest('.btn') : null;
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
async function saveCfg(key, value) {
  try {
    if (key !== 'min_app_version') JSON.parse(value || '{}');
    await rpc('admin_set_config', { p_key: key, p_value: value });
    toast(key + ' saved ⚙️', 'ok');
  } catch (e) { toast('Save failed: ' + e.message, 'err'); }
}

// ── audit ──
// Live mode (15s poll) + action pills for readability.
let _auditTimer = null;
function toggleAuditLive() {
  const on = document.getElementById('auditLive').checked;
  if (_auditTimer) { clearInterval(_auditTimer); _auditTimer = null; }
  if (on) { loadAudit(); _auditTimer = setInterval(loadAudit, 15000); toast('Audit live mode on', 'info'); }
}
function stopAuditLive() {
  if (_auditTimer) { clearInterval(_auditTimer); _auditTimer = null; }
  const box = document.getElementById('auditLive');
  if (box) box.checked = false;
}
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
let _dlTimer = null;
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
function toggleDeviceLogsLive() {
  const on = document.getElementById('dlLive').checked;
  if (_dlTimer) { clearInterval(_dlTimer); _dlTimer = null; }
  if (on) { loadDeviceLogs(); _dlTimer = setInterval(loadDeviceLogs, 10000); toast('Device log live mode on', 'info'); }
}
function stopDeviceLogsLive() {
  if (_dlTimer) { clearInterval(_dlTimer); _dlTimer = null; }
  const box = document.getElementById('dlLive');
  if (box) box.checked = false;
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
        <td class="mut" title="${esc(fmtAbs(r.last_at))}">${ago(r.last_at)}</td>
      </tr>`).join('')
      || `<tr><td colspan="8">${emptyState('🌙', 'Nothing to show', filterDesc ? 'Try a different filter.' : 'No error reports yet.')}</td></tr>`;
  } catch (e) { toast('Device logs failed: ' + e.message, 'err'); }
}

// DCL can fire before this script registers (restored/fast loads) — guard it.
if (document.readyState === 'loading') {
  window.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
