// Dizzy Control — UI kit (loaded before app.js).
// Toasts, skeletons, empty states, confirm dialog, command palette,
// mobile drawer, password toggle. No business logic lives here.

/* ── tiny DOM helper ── */
function el(tag, cls, html) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (html != null) n.innerHTML = html;
  return n;
}

/* ── formatting ── */
function fmtAbs(iso) {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleString(undefined, {
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    });
  } catch (_) { return String(iso); }
}
function fmtNum(n) {
  const v = Number(n) || 0;
  return v >= 10000 ? (v / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(v);
}

/* ══════════ TOASTS ══════════ */
function toast(msg, type) {
  const box = document.getElementById('toasts');
  if (!box) return;
  const text = String(msg ?? '');
  const t = type || (/fail|error|denied|invalid|cannot|not an/i.test(text) ? 'err'
    : /saved|dismissed|live|deleted|✓|added/i.test(text) ? 'ok' : 'info');
  const ico = t === 'err' ? '⛔' : t === 'ok' ? '✅' : t === 'warn' ? '⚠️' : 'ℹ️';
  const node = el('div', 'toast t-' + t,
    `<span class="t-ico">${ico}</span><span class="t-txt">${esc(text)}</span>`);
  box.appendChild(node);
  while (box.children.length > 4) box.removeChild(box.firstChild);
  setTimeout(() => {
    node.classList.add('out');
    setTimeout(() => node.remove(), 260);
  }, 3400);
}

/* ══════════ SKELETONS ══════════ */
function skStats(n) {
  let h = '';
  for (let i = 0; i < (n || 6); i++) h += '<div class="sk sk-stat"></div>';
  return h;
}
function skLines(n, widths) {
  const w = widths || ['w80', 'w60', 'w40', 'w60', 'w80'];
  let h = '';
  for (let i = 0; i < (n || 4); i++) h += `<div class="sk sk-line ${w[i % w.length]}"></div>`;
  return h;
}
function skRows(n, cols) {
  const c = cols || 5;
  let h = '';
  for (let i = 0; i < (n || 6); i++) {
    h += '<tr>';
    for (let j = 0; j < c; j++) h += `<td><div class="sk sk-line ${j % 2 ? 'w60' : 'w80'}" style="margin:0;height:11px"></div></td>`;
    h += '</tr>';
  }
  return h;
}

/* ══════════ EMPTY STATES ══════════ */
function emptyState(icon, title, hint) {
  return `<div class="empty"><span class="ei">${icon || '🌙'}</span>
    <div class="et">${esc(title || 'Nothing here yet')}</div>
    ${hint ? `<div class="eh">${esc(hint)}</div>` : ''}</div>`;
}

/* ══════════ BUTTON LOADING ══════════ */
function withLoading(btn, fn) {
  if (!btn) return fn();
  btn.classList.add('loading');
  return Promise.resolve(fn()).finally(() => btn.classList.remove('loading'));
}

/* ══════════ CONFIRM DIALOG ══════════ */
function confirmDialog(opts) {
  const o = opts || {};
  return new Promise((resolve) => {
    const prev = document.activeElement;
    const ov = el('div', 'overlay');
    ov.innerHTML = `<div class="confirm-box" role="alertdialog" aria-modal="true">
      <h3>${esc(o.title || 'Are you sure?')}</h3>
      <p>${esc(o.message || 'This action cannot be undone.')}</p>
      <div class="confirm-acts">
        <button class="btn btn-ghost btn-sm" data-a="0">Cancel</button>
        <button class="btn ${o.danger === false ? 'btn-primary' : 'btn-danger'} btn-sm" data-a="1">${esc(o.okText || 'Yes, continue')}</button>
      </div></div>`;
    const done = (v) => {
      document.removeEventListener('keydown', onKey, true);
      ov.remove();
      if (prev && prev.focus) prev.focus();
      resolve(v);
    };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.stopPropagation(); done(false); }
      if (e.key === 'Enter') { e.stopPropagation(); done(true); }
    };
    ov.addEventListener('click', (e) => { if (e.target === ov) done(false); });
    ov.querySelectorAll('[data-a]').forEach((b) =>
      b.addEventListener('click', () => done(b.dataset.a === '1')));
    document.addEventListener('keydown', onKey, true);
    document.body.appendChild(ov);
    ov.querySelector('[data-a="1"]').focus();
  });
}

/* ══════════ COMMAND PALETTE ══════════ */
const SECTIONS = [
  { s: 'overview',    i: '📊', t: 'Overview',     d: 'Live health of the fleet' },
  { s: 'rooms',       i: '🏠', t: 'Rooms',        d: 'Watch rooms across the app' },
  { s: 'moderation',  i: '🚩', t: 'Moderation',   d: 'Reported rooms' },
  { s: 'scrapers',    i: '🎬', t: 'Scrapers',     d: 'Votes & kill map' },
  { s: 'users',       i: '📱', t: 'Installs',     d: 'Installed apps' },
  { s: 'push',        i: '📣', t: 'Announcements', d: 'In-app banners' },
  { s: 'config',      i: '⚙️', t: 'Config',       d: 'Remote config & flags' },
  { s: 'audit',       i: '🧾', t: 'Audit',        d: 'Admin write log' },
  { s: 'devicelogs',  i: '🐞', t: 'Device logs',  d: 'Error telemetry' },
];
let _palSel = 0, _palItems = [];

function openPalette() {
  if (document.querySelector('.overlay')) return;
  const ov = el('div', 'overlay');
  ov.innerHTML = `<div class="palette" role="dialog" aria-modal="true" aria-label="Quick switch">
    <input type="text" id="palInput" placeholder="Jump to a section…" autocomplete="off" spellcheck="false">
    <div class="palette-list" id="palList"></div></div>`;
  ov.addEventListener('click', (e) => { if (e.target === ov) closePalette(); });
  document.body.appendChild(ov);

  const input = ov.querySelector('#palInput');
  const render = () => {
    const q = input.value.trim().toLowerCase();
    _palItems = SECTIONS.filter((x) => !q || x.t.toLowerCase().includes(q) || x.d.toLowerCase().includes(q) || x.s.includes(q));
    _palSel = 0;
    ov.querySelector('#palList').innerHTML = _palItems.length
      ? _palItems.map((x, i) => `<div class="pal-item ${i === 0 ? 'sel' : ''}" data-i="${i}" data-s="${x.s}">
          <span class="pi">${x.i}</span><span>${x.t}</span><span class="pd">${x.d}</span></div>`).join('')
      : `<div class="pal-empty">No section matches “${esc(input.value)}”</div>`;
    ov.querySelectorAll('.pal-item').forEach((n) => n.addEventListener('click', () => {
      show(n.dataset.s); closePalette();
    }));
  };
  const move = (dir) => {
    if (!_palItems.length) return;
    _palSel = (_palSel + dir + _palItems.length) % _palItems.length;
    ov.querySelectorAll('.pal-item').forEach((n, i) => n.classList.toggle('sel', i === _palSel));
    const sel = ov.querySelector('.pal-item.sel');
    if (sel) sel.scrollIntoView({ block: 'nearest' });
  };
  input.addEventListener('input', render);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      if (_palItems[_palSel]) { show(_palItems[_palSel].s); closePalette(); }
    } else if (e.key === 'Escape') { e.preventDefault(); closePalette(); }
  });
  render();
  input.focus();
}
function closePalette() {
  const ov = document.querySelector('.overlay');
  if (ov) ov.remove();
}

/* ══════════ MOBILE DRAWER ══════════ */
function toggleNav() { document.body.classList.toggle('nav-open'); }
function closeNav() { document.body.classList.remove('nav-open'); }

/* ══════════ PASSWORD TOGGLE ══════════ */
function togglePw() {
  const inp = document.getElementById('pass');
  const btn = document.getElementById('pwEye');
  if (!inp || !btn) return;
  const show = inp.type === 'password';
  inp.type = show ? 'text' : 'password';
  btn.textContent = show ? 'Hide' : 'Show';
  btn.setAttribute('aria-label', show ? 'Hide password' : 'Show password');
  inp.focus();
}

/* ══════════ GLOBAL KEYS ══════════ */
document.addEventListener('keydown', (e) => {
  const k = e.key.toLowerCase();
  if ((e.ctrlKey || e.metaKey) && k === 'k') {
    if (document.getElementById('app').classList.contains('lit')) {
      e.preventDefault();
      document.querySelector('.overlay') ? closePalette() : openPalette();
    }
    return;
  }
  if (e.key === 'Escape') {
    if (document.querySelector('.overlay')) { closePalette(); return; }
    if (typeof closeModal === 'function' && document.getElementById('modal').classList.contains('open')) closeModal();
  }
});
