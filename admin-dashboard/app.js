// Dizzy Control — dashboard logic (static site, Supabase JS v2 via CDN).
// Config comes from ./config.js (window.DIZZY_CONFIG = {url, anonKey}).

let sb = null;
let ROOMS_CACHE = [];

function $(id) { return document.getElementById(id); }
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.style.display = 'block';
  clearTimeout(t._h);
  t._h = setTimeout(() => (t.style.display = 'none'), 3200);
}
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function ago(iso) {
  if (!iso) return '—';
  const s = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return s + 's ago';
  if (s < 3600) return Math.floor(s / 60) + 'm ago';
  if (s < 86400) return Math.floor(s / 3600) + 'h ago';
  return Math.floor(s / 86400) + 'd ago';
}
function shortId(id) { return id ? String(id).slice(0, 8) + '…' : '—'; }

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
  btn.disabled = true;
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
}

async function doLogout() {
  await sb.auth.signOut();
  location.reload();
}

function enterApp(email) {
  $('login').style.display = 'none';
  $('app').style.display = 'block';
  $('meEmail').textContent = email;
  $('cloudDot').textContent = '● live';
  $('cloudDot').style.color = 'var(--grn)';
  loadOverview();
}

// ── nav ──
function show(name) {
  document.querySelectorAll('nav button').forEach((b) => b.classList.toggle('on', b.dataset.s === name));
  document.querySelectorAll('main section').forEach((s) => s.classList.toggle('on', s.id === 's-' + name));
  if (name === 'rooms') loadRooms();
  if (name === 'moderation') loadRooms(true);
  if (name === 'scrapers') loadScrapers();
  if (name === 'users') loadUsers();
  if (name === 'push') loadAnn();
  if (name === 'config') loadCfg();
  if (name === 'audit') loadAudit();
}

async function rpc(name, params) {
  const { data, error } = await sb.rpc(name, params || {});
  if (error) throw error;
  return data;
}

// ── overview ──
async function loadOverview() {
  try {
    const o = await rpc('admin_overview');
    const cards = [
      ['📱', o.installs, 'total installs'],
      ['🟢', o.installs_7d, 'active 7d'],
      ['🏠', o.rooms_live, 'rooms live'],
      ['👥', o.members_live, 'in rooms now'],
      ['🚩', o.reports_pending, 'reports'],
      ['🗳️', o.scraper_votes_7d, 'scraper votes 7d'],
    ];
    $('statCards').innerHTML = cards.map((c) =>
      `<div class="stat"><div class="n">${c[1]}</div><div class="l">${c[0]} ${c[2]}</div></div>`).join('');

    const daily = await rpc('admin_installs_daily', { p_days: 30 });
    drawBars($('chInstalls'), daily.map((d) => d.n));

    const b = await rpc('admin_breakdown');
    $('breakdown').innerHTML =
      `<div class="mut">PLATFORMS</div>` + b.platforms.map((p) =>
        `<div style="display:flex;justify-content:space-between;padding:4px 0;font-size:13px"><span>${esc(p.name)}</span><b>${p.n}</b></div>`).join('') +
      `<div class="mut" style="margin-top:10px">VERSIONS</div>` + b.versions.map((p) =>
        `<div style="display:flex;justify-content:space-between;padding:4px 0;font-size:13px"><span>${esc(p.name)}</span><b>${p.n}</b></div>`).join('') +
      `<div class="mut" style="margin-top:10px">CONSENTS (of ${b.consents.total})</div>
       <div style="font-size:13px;padding:4px 0">telemetry ${b.consents.telemetry} · genre ${b.consents.genre_prefs} · crash ${b.consents.crash} · party ${b.consents.watch_party}</div>`;

    $('health').innerHTML =
      `<div style="font-size:14px">Rooms live <b>${o.rooms_live}</b> · members <b>${o.members_live}</b> · pending reports <b>${o.reports_pending}</b> · active announcements <b>${o.announcements}</b></div>
       <div class="mut" style="margin-top:6px">Supabase connected · edge functions assumed ACTIVE · refresh for latest</div>
       <div class="rowbtns"><button onclick="loadOverview()">↻ Refresh now</button></div>`;
  } catch (e) { toast('Overview failed: ' + e.message); }
}

function drawBars(cv, vals) {
  const ctx = cv.getContext('2d');
  const W = cv.width, H = cv.height;
  ctx.clearRect(0, 0, W, H);
  const max = Math.max(1, ...vals);
  const bw = W / vals.length;
  vals.forEach((v, i) => {
    const h = (v / max) * (H - 30);
    ctx.fillStyle = '#8b5cf6';
    ctx.fillRect(i * bw + 2, H - 15 - h, bw - 4, h);
  });
  ctx.fillStyle = '#9aa0ae';
  ctx.font = '11px sans-serif';
  ctx.fillText('max ' + max + ' / day', 8, 14);
}

// ── rooms ──
async function loadRooms(modOnly) {
  try {
    const rooms = await rpc('admin_rooms', { p_limit: 50 });
    ROOMS_CACHE = rooms;
    const tb = document.querySelector('#roomsTbl tbody');
    tb.innerHTML = rooms.map((r) => `<tr onclick="roomDetail('${r.room_id}')" style="cursor:pointer">
      <td class="mono">${esc(r.room_id)}</td>
      <td>${esc(r.title)}${r.is_adult ? ' <span class="pill p-adult">18+</span>' : ''}${r.locked ? ' <span class="pill p-lock">🔒</span>' : ''}</td>
      <td><span class="pill ${r.status === 'live' ? 'p-live' : r.status === 'lobby' ? 'p-lobby' : 'p-closed'}">${esc(r.status)}</span>
        <span class="pill ${r.visibility === 'public' ? 'p-pub' : 'p-priv'}">${esc(r.visibility)}</span></td>
      <td><b>${r.members}</b></td><td>${r.reports > 0 ? '🚩<b>' + r.reports + '</b>' : '—'}</td>
      <td class="mut">${ago(r.created_at)}</td></tr>`).join('') || '<tr><td colspan="6" class="mut">No rooms yet.</td></tr>';

    // moderation tab: only reported
    const rep = rooms.filter((r) => r.reports > 0);
    $('repList').innerHTML = rep.length === 0 ? '<div class="mut">No reported rooms. 🎉</div>' : rep.map((r) =>
      `<div style="border:1px solid var(--line);border-radius:12px;padding:12px;margin-bottom:10px">
        <b class="mono">${esc(r.room_id)}</b> · ${esc(r.title)} · 🚩 ${r.reports} reports · 👥 ${r.members} · ${esc(r.status)}
        <div class="rowbtns">
          <button onclick="roomDetail('${r.room_id}')">Inspect</button>
          <button onclick="roomAct('${r.room_id}','close')">Close room</button>
          <button onclick="roomAct('${r.room_id}','lock')">Lock</button>
          <button class="ok" onclick="roomAct('${r.room_id}','unlock')">Unlock</button>
          <button class="ok" onclick="clearRep('${r.room_id}')">Dismiss reports</button>
        </div></div>`).join('');
  } catch (e) { toast('Rooms failed: ' + e.message); }
}

async function roomDetail(roomId) {
  try {
    const d = await rpc('admin_room_detail', { p_room_id: roomId });
    const r = d.room || {};
    $('sheet').innerHTML = `
      <h2>🏠 ${esc(r.title || roomId)} <span class="mono">${esc(roomId)}</span></h2>
      <div class="kv">
        <b>Status</b><span>${esc(r.status)} · ${esc(r.visibility)}${r.locked ? ' · 🔒 locked' : ''}${r.is_adult ? ' · 🔞 adult' : ''}</span>
        <b>Media</b><span class="mono">${esc(r.media_ref || '—')}</span>
        <b>Members</b><span>${(d.members || []).length}</span>
        <b>Reports</b><span>🚩 ${d.reports || 0}</span>
        <b>Created</b><span>${ago(r.created_at)}</span>
        <b>Notes</b><span>${esc(r.admin_notes || '—')}</span>
      </div>
      <h3 style="font-size:14px;margin-bottom:8px">👥 Members</h3>
      <div style="overflow-x:auto;margin-bottom:12px"><table>
        <thead><tr><th>User</th><th>Role</th><th>Seen</th><th>Joined</th></tr></thead><tbody>
        ${(d.members || []).map((m) => `<tr><td class="mono">${shortId(m.user_id)}</td><td>${esc(m.role)}</td><td class="mut">${ago(m.last_seen)}</td><td class="mut">${ago(m.joined_at)}</td></tr>`).join('')}
        </tbody></table></div>
      <h3 style="font-size:14px;margin-bottom:8px">💬 Recent chat (last 50)</h3>
      <div class="chatbox">${(d.chat || []).map((c) => `<div><span class="who">${esc(c.sender_code || shortId(c.sender_id))}</span> ${esc(c.body)}<br><span class="mut">${ago(c.created_at)}</span></div>`).join('') || '<span class="mut">No messages.</span>'}</div>
      <div class="rowbtns">
        <button onclick="roomAct('${roomId}','close')">Close</button>
        <button onclick="roomAct('${roomId}','lock')">Lock</button>
        <button class="ok" onclick="roomAct('${roomId}','unlock')">Unlock</button>
        <button onclick="roomAct('${roomId}','adult')">Mark 18+</button>
        <button class="ok" onclick="roomAct('${roomId}','not_adult')">Clear 18+</button>
        <button class="ok" onclick="clearRep('${roomId}')">Dismiss reports</button>
      </div>
      <div style="margin-top:12px"><label class="fl">Mod note</label>
        <div style="display:flex;gap:8px"><input type="text" id="modNote" value="${esc(r.admin_notes || '')}" maxlength="500">
        <button class="btn btn-sm" style="width:auto" onclick="saveNote('${roomId}')">Save</button></div></div>
      <div class="rowbtns" style="margin-top:14px"><button class="danger" onclick="closeModal()">Close ✕</button></div>`;
    $('modal').classList.add('open');
  } catch (e) { toast('Detail failed: ' + e.message); }
}

async function roomAct(roomId, action) {
  try {
    await rpc('admin_room_action', { p_room_id: roomId, p_action: action, p_note: '' });
    toast('Room ' + roomId + ' → ' + action);
    loadRooms(); roomDetail(roomId);
  } catch (e) { toast('Action failed: ' + e.message); }
}
async function saveNote(roomId) {
  try {
    await rpc('admin_room_action', { p_room_id: roomId, p_action: 'note', p_note: $('modNote').value });
    toast('Note saved'); roomDetail(roomId); loadRooms();
  } catch (e) { toast('Note failed: ' + e.message); }
}
async function clearRep(roomId) {
  try {
    const n = await rpc('admin_clear_reports', { p_room_id: roomId });
    toast(n + ' reports dismissed'); loadRooms();
    if ($('modal').classList.contains('open')) roomDetail(roomId);
  } catch (e) { toast('Dismiss failed: ' + e.message); }
}
function closeModal() { $('modal').classList.remove('open'); }
$('modal') && $('modal').addEventListener('click', (e) => { if (e.target.id === 'modal') closeModal(); });

// ── scrapers ──
async function loadScrapers() {
  try {
    const d = await rpc('admin_scraper_votes');
    const votes = d.votes || [];
    let kill = {};
    try { kill = JSON.parse(d.kill || '{}'); } catch (_) {}
    const dead = votes.filter((v) => v.reporters >= 5).length;
    $('scraperStats').innerHTML =
      `<div class="stat"><div class="n">${votes.length}</div><div class="l">🗳️ scrapers with votes</div></div>
       <div class="stat"><div class="n">${dead}</div><div class="l">🔴 likely dead (5+)</div></div>
       <div class="stat"><div class="n">${Object.keys(kill).length}</div><div class="l">⛔ currently killed</div></div>`;
    $('votes').innerHTML = votes.length === 0 ? '<div class="mut">No votes in last 7 days. 🎉</div>' :
      votes.map((v) => `<div style="display:flex;justify-content:space-between;gap:8px;padding:7px 0;border-bottom:1px solid #ffffff08;font-size:13px">
        <span><b class="mono">${esc(v.scraper)}</b> ${v.reporters >= 5 ? '🔴' : v.reporters >= 3 ? '🟡' : '🟢'}</span>
        <span class="mut">${v.n} votes · ${v.reporters} users · ${ago(v.last_seen)}</span></div>
        <div class="rowbtns" style="margin:0 0 6px"><button onclick="killOne('${esc(v.scraper)}')">⛔ Kill</button></div>`).join('');
    if (!($('killJson').value)) $('killJson').value = JSON.stringify(kill, null, 2);
    const cd = await sb.from('remote_config').select('value').eq('key', 'scraper_cooldown_days').single();
    if (cd.data) $('cooldownDays').value = cd.data.value;
  } catch (e) { toast('Scrapers failed: ' + e.message); }
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
    toast('Kill map live ⛔'); loadScrapers();
  } catch (e) { toast('Save failed: ' + e.message); }
}
async function saveCooldown() {
  try {
    await rpc('admin_set_config', { p_key: 'scraper_cooldown_days', p_value: $('cooldownDays').value.trim() || '7' });
    toast('Cooldown saved');
  } catch (e) { toast('Save failed: ' + e.message); }
}

// ── installs ──
async function loadUsers() {
  try {
    const rows = await rpc('admin_installs', { p_limit: 50, p_search: $('uSearch').value || '' });
    document.querySelector('#usersTbl tbody').innerHTML = rows.map((u) =>
      `<tr><td class="mono">${shortId(u.anon_id)}</td><td>${esc(u.platform)}</td><td>${esc(u.app_version)}</td>
       <td>${esc(u.region_code)}</td><td class="mut">${ago(u.created_at)}</td><td class="mut">${ago(u.last_seen_at)}</td></tr>`).join('')
      || '<tr><td colspan="6" class="mut">No installs found.</td></tr>';
  } catch (e) { toast('Installs failed: ' + e.message); }
}

// ── announcements ──
async function loadAnn() {
  try {
    const { data, error } = await sb.from('announcements').select('*').order('created_at', { ascending: false }).limit(30);
    if (error) throw error;
    $('annList').innerHTML = (data || []).map((a) =>
      `<div style="border:1px solid var(--line);border-radius:12px;padding:12px;margin-bottom:10px;${a.active ? '' : 'opacity:.55'}">
        <b>${esc(a.title)}</b> ${a.active ? '<span class="pill p-live">active</span>' : '<span class="pill p-closed">paused</span>'}
        <div style="font-size:13px;color:var(--mut);margin-top:4px">${esc(a.body)}</div>
        <div class="mut" style="margin-top:4px">${a.min_version || 'any'} → ${a.max_version || 'any'} · ${ago(a.created_at)}</div>
        <div class="rowbtns"><button onclick='editAnn(${JSON.stringify(a.id)})'>Edit</button>
        <button class="danger" onclick="delAnn('${a.id}')">Delete</button></div></div>`).join('')
      || '<div class="mut">No announcements yet.</div>';
    window._annCache = Object.fromEntries((data || []).map((a) => [a.id, a]));
  } catch (e) { toast('Announcements failed: ' + e.message); }
}
function editAnn(id) {
  const a = (window._annCache || {})[id];
  if (!a) return;
  $('annId').value = a.id; $('annTitle').value = a.title; $('annBody').value = a.body;
  $('annUrl').value = a.url || ''; $('annMin').value = a.min_version || '';
  $('annMax').value = a.max_version || ''; $('annActive').value = String(a.active);
  $('annFormTitle').textContent = '✏️ Edit announcement';
  window.scrollTo(0, document.body.scrollHeight);
}
function resetAnn() {
  $('annId').value = ''; $('annTitle').value = ''; $('annBody').value = '';
  $('annUrl').value = ''; $('annMin').value = ''; $('annMax').value = '';
  $('annActive').value = 'true'; $('annFormTitle').textContent = '➕ New announcement';
}
async function saveAnn() {
  try {
    await rpc('admin_announce_upsert', {
      p_id: $('annId').value || '', p_title: $('annTitle').value.trim(),
      p_body: $('annBody').value.trim(), p_url: $('annUrl').value.trim(),
      p_min_version: $('annMin').value.trim(), p_max_version: $('annMax').value.trim(),
      p_active: $('annActive').value === 'true',
    });
    toast('Announcement saved 📣'); resetAnn(); loadAnn();
  } catch (e) { toast('Save failed: ' + e.message); }
}
async function delAnn(id) {
  if (!confirm('Delete this announcement?')) return;
  try {
    await rpc('admin_announce_delete', { p_id: id });
    toast('Deleted'); loadAnn();
  } catch (e) { toast('Delete failed: ' + e.message); }
}

// ── config ──
async function loadCfg() {
  try {
    const { data } = await sb.from('remote_config').select('key,value');
    const m = Object.fromEntries((data || []).map((r) => [r.key, r.value]));
    $('cfgMinVer').value = m.min_app_version || '';
    $('cfgFeatures').value = pretty(m.features);
    $('cfgNotice').value = pretty(m.notice);
  } catch (e) { toast('Config failed: ' + e.message); }
}
function pretty(v) {
  try { return JSON.stringify(JSON.parse(v || '{}'), null, 2); } catch (_) { return v || ''; }
}
async function saveCfg(key, value) {
  try {
    if (key !== 'min_app_version') JSON.parse(value || '{}');
    await rpc('admin_set_config', { p_key: key, p_value: value });
    toast(key + ' saved ⚙️');
  } catch (e) { toast('Save failed: ' + e.message); }
}

// ── audit ──
async function loadAudit() {
  try {
    const rows = await rpc('admin_audit_tail', { p_limit: 50 });
    document.querySelector('#auditTbl tbody').innerHTML = rows.map((a) =>
      `<tr><td class="mut">${ago(a.created_at)}</td><td><b>${esc(a.action)}</b></td>
       <td class="mono">${esc(a.target)}</td><td class="mut">${esc(JSON.stringify(a.detail))}</td></tr>`).join('')
      || '<tr><td colspan="4" class="mut">No audit entries yet.</td></tr>';
  } catch (e) { toast('Audit failed: ' + e.message); }
}

window.addEventListener('DOMContentLoaded', boot);
