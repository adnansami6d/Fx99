/* ===================== Config ===================== */
const PROJECT = "tournament-2d6d4";
const API_KEY = "AIzaSyCNvnJsIn4-oKHLVv7-oNHCTskjE8";   // put your working Firebase API key here
const COL     = "secureChats";
const PBKDF2_ITER = 250000;

const DOC_ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `https://firestore.googleapis.com/v1/${DOC_ROOT}`;
const KQ = `key=${API_KEY}`;
const TR = [{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }];

/* ===================== Icons ===================== */
const ICONS = {
  msg:'<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.6 8.6 0 0 1-3.6-.8L3 21l1.9-5.4A8.4 8.4 0 1 1 21 11.5z"/>',
  lock:'<rect x="4" y="11" width="16" height="10" rx="2.5"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11"/>',
  shuffle:'<path d="M16 3h5v5"/><path d="M4 20 21 3"/><path d="M21 16v5h-5"/><path d="M15 15l6 6"/><path d="M4 4l5 5"/>',
  backspace:'<path d="M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z"/><path d="m18 9-6 6"/><path d="m12 9 6 6"/>',
  key:'<circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3 21 2"/><path d="m16 7 3 3"/><path d="m14 9 2 2"/>',
  send:'<path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7z"/>',
  trash:'<path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/>',
  copy:'<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  x:'<path d="M18 6 6 18M6 6l12 12"/>',
  logout:'<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
  ban:'<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
  clock:'<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  check:'<path d="M4 12.5l5 5L20 6.5"/>',
  checks:'<path d="M1.5 12.5l5 5L17 6.5"/><path d="M11 16.5l1 1L23 6.5"/>'
};
const ic = (n) => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[n]}</svg>`;
document.querySelectorAll('i[data-ic]').forEach(el => { el.outerHTML = ic(el.dataset.ic); });

/* ===================== Helpers ===================== */
const $ = (id) => document.getElementById(id);
const enc = new TextEncoder(), dec = new TextDecoder();
const esc = (s) => s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const b64 = (buf) => { let s=''; new Uint8Array(buf).forEach(b => s += String.fromCharCode(b)); return btoa(s); };
const unb64 = (s) => Uint8Array.from(atob(s), c => c.charCodeAt(0));
const hex = (u8) => Array.from(u8).map(b => b.toString(16).padStart(2,'0')).join('');
const randId = (n=12) => hex(crypto.getRandomValues(new Uint8Array(n)));
const FS = (v) => ({ stringValue: v });
const FB = (v) => ({ booleanValue: v });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const fmtTime = new Intl.DateTimeFormat('en-US', { hour:'numeric', minute:'2-digit', hour12:true });
const fmtDate = new Intl.DateTimeFormat('en-US', { day:'numeric', month:'short', year:'numeric' });
const dayKey = (ts) => { const d = new Date(ts); return d.getFullYear()+'-'+d.getMonth()+'-'+d.getDate(); };
function dayLabel(ts){
  const now = Date.now();
  if (dayKey(ts) === dayKey(now)) return 'Today';
  if (dayKey(ts) === dayKey(now - 86400000)) return 'Yesterday';
  return fmtDate.format(new Date(ts));
}

let toastTimer;
function toast(msg){
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
}

/* 'a' = owner (7-digit code ending in 1), 'b' = guest (6-digit code). Set when entering the chat. */
let ME = '';

/* ===================== Crypto ===================== */
async function deriveKeys(pin, secret){
  const base = await crypto.subtle.importKey('raw', enc.encode(JSON.stringify(['sc1', pin, secret || ''])), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name:'PBKDF2', hash:'SHA-256', salt: enc.encode('secret-chat-salt-v1'), iterations: PBKDF2_ITER }, base, 512);
  const bytes = new Uint8Array(bits);
  const key = await crypto.subtle.importKey('raw', bytes.slice(0,32), 'AES-GCM', false, ['encrypt','decrypt']);
  const roomId = hex(bytes.slice(32));
  return { key, roomId };
}
async function encryptText(key, text, aad){
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name:'AES-GCM', iv, additionalData: enc.encode(aad) }, key, enc.encode(text));
  return { ct: b64(ct), iv: b64(iv) };
}
async function decryptText(key, ct, iv, aad){
  try {
    const pt = await crypto.subtle.decrypt({ name:'AES-GCM', iv: unb64(iv), additionalData: enc.encode(aad) }, key, unb64(ct));
    return dec.decode(pt);
  } catch { return null; }
}

/* ===================== Firestore REST ===================== */
async function api(url, opts){
  const r = await fetch(url, opts);
  if (!r.ok) {
    const e = new Error('HTTP ' + r.status); e.status = r.status;
    try { e.body = await r.json(); } catch {}
    throw e;
  }
  return r.json();
}
const jpost = (url, body) => api(url, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body) });
const commit = (writes) => jpost(`${BASE}:commit?${KQ}`, { writes });
const msgName = (roomId, id) => `${DOC_ROOT}/${COL}/${roomId}/messages/${id}`;

async function getRoom(roomId){
  try { return await api(`${BASE}/${COL}/${roomId}?${KQ}`); }
  catch (e) { if (e.status === 404) return null; throw e; }
}
async function createRoomDoc(roomId, key){
  const { ct, iv } = await encryptText(key, 'ok-v1', 'check');
  return jpost(`${BASE}/${COL}?documentId=${roomId}&${KQ}`, {
    fields: { ct: FS(ct), iv: FS(iv), createdAt: { timestampValue: new Date().toISOString() } }
  });
}

/* ===================== State ===================== */
let S = null;
const list = $('list'), input = $('msgInput');

function showScreen(id){ document.querySelectorAll('.screen').forEach(s => s.classList.toggle('active', s.id === id)); }
function setBusy(btn, busy, text){ btn.disabled = busy; btn.textContent = busy ? 'Please wait…' : text; }
function errMsg(e){
  if (e === 'notfound' || e === 'wrong') return 'Invalid PIN.';
  if (e === 'exists') return 'This PIN is already in use. Try another.';
  if (e && e.status === 403) return 'Permission denied. Check Firestore rules.';
  return 'Connection error. Please try again.';
}
/* ===================== Lock screen ===================== */
const L = { mode:'join', busy:false };
const pinEl = $('pin');
const maxLen = () => (L.mode === 'join' ? 7 : 6);

function renderLock(){
  const join = L.mode === 'join';
  $('lockLbl').textContent = join ? 'Enter PIN' : 'Choose a PIN';
  pinEl.placeholder = join ? '••••••' : 'Auto-generate';
  pinEl.maxLength = maxLen();
  $('goBtn').textContent = L.busy ? 'Please wait…' : (join ? 'Continue' : 'Create');
  $('goBtn').disabled = L.busy;
  $('swapBtn').textContent = join ? 'Create a new chat' : 'I already have a PIN';
}
function lockError(text){
  $('lockErr').textContent = text;
  pinEl.classList.remove('shake'); void pinEl.offsetWidth; pinEl.classList.add('shake');
  if (navigator.vibrate) navigator.vibrate([30, 40, 30]);
}
function resetLock(){
  L.mode = 'join'; L.busy = false;
  pinEl.value = ''; $('lockErr').textContent = '';
  renderLock();
}
function setLockBusy(v){ L.busy = v; renderLock(); }

pinEl.addEventListener('input', () => { pinEl.value = pinEl.value.replace(/\D/g, '').slice(0, maxLen()); $('lockErr').textContent = ''; });
$('swapBtn').addEventListener('click', () => {
  if (L.busy) return;
  L.mode = L.mode === 'join' ? 'new' : 'join';
  pinEl.value = ''; $('lockErr').textContent = '';
  renderLock(); pinEl.focus();
});
$('lockForm').addEventListener('submit', (e) => { e.preventDefault(); if (!L.busy) (L.mode === 'join' ? doJoin() : doCreate()); });

/* ----- Join ----- */
async function doJoin(){
  const raw = pinEl.value, secret = '';
  if (raw.length !== 6 && raw.length !== 7) return lockError('PIN must be 6 digits.');
  if (raw.length === 7 && raw[6] !== '1') return lockError(errMsg('wrong'));
  const pin = raw.slice(0, 6), role = raw.length === 7 ? 'a' : 'b';
  setLockBusy(true); await sleep(30);
  try {
    const { key, roomId } = await deriveKeys(pin, secret);
    const doc = await getRoom(roomId);
    if (!doc) throw 'notfound';
    const ok = await decryptText(key, doc.fields.ct.stringValue, doc.fields.iv.stringValue, 'check');
    if (ok !== 'ok-v1') throw 'wrong';
    openChat(key, roomId, pin, false, false, role);
  } catch (err) { setLockBusy(false); lockError(errMsg(err)); }
}

/* ----- Create ----- */
async function doCreate(){
  const custom = pinEl.value, secret = '';
  if (custom && custom.length !== 6) return lockError('PIN must be 6 digits.');
  setLockBusy(true); await sleep(30);
  try {
    let pin = custom, keys = null;
    for (let i = 0; i < 6; i++) {
      if (!custom) pin = String(100000 + (crypto.getRandomValues(new Uint32Array(1))[0] % 900000));
      keys = await deriveKeys(pin, secret);
      if (!(await getRoom(keys.roomId))) break;
      if (custom) throw 'exists';
      keys = null;
    }
    if (!keys) throw new Error('retry');
    await createRoomDoc(keys.roomId, keys.key);
    openChat(keys.key, keys.roomId, pin, false, true, 'a');
  } catch (err) {
    if (err && err.status === 409) err = 'exists';
    setLockBusy(false); lockError(errMsg(err));
  }
}

/* ===================== Chat ===================== */
function openChat(key, roomId, pin, hasSecret, justCreated, role){
  ME = role;   // 'a' = মালিক (৭ ডিজিট, শেষে 1), 'b' = অতিথি (৬ ডিজিট)
  S = { key, roomId, pin, hasSecret, msgs:new Map(), lastSync:'1970-01-01T00:00:00Z',
        timer:null, selected:new Set(), seenSent:new Set(), lastActivity:Date.now(), unread:0 };
  resetLock();
  showScreen('chat'); render(true); tick();
  if (justCreated) showPin();
}
function leaveChat(){
  if (S) clearTimeout(S.timer);
  S = null;
  list.innerHTML = ''; input.value = ''; autosize();
  $('app').classList.remove('selmode');
  closeModals();
  resetLock();
  showScreen('lock');
}
function myCode(){ return ME === 'a' ? S.pin + '1' : S.pin; }
function showPin(){
  $('bigPin').textContent = myCode();
  $('pinNote').textContent = ME === 'a'
    ? 'This is your code. Give your friend only the first 6 digits: ' + S.pin
    : 'Use this code to enter again.';
  $('pinModal').classList.add('open');
}
function closeModals(){ document.querySelectorAll('.modal').forEach(m => m.classList.remove('open')); }

/* ----- Sync ----- */
async function applyDoc(s, d){
  const id = d.name.split('/').pop(), f = d.fields || {};
  const ts = parseInt(f.ts?.integerValue || '0', 10);
  const sender = f.snd?.stringValue || '';
  const old = s.msgs.get(id);
  const isNew = !old;
  if (f.deleted?.booleanValue) {
    s.msgs.set(id, { id, ts, sender, deleted:true, delBy: f.delBy?.stringValue || '' });
  } else {
    let text;
    if (old && !old.deleted && old.ct === f.ct.stringValue && old.text !== undefined) text = old.text;
    else text = await decryptText(s.key, f.ct.stringValue, f.iv.stringValue, id);
    s.msgs.set(id, { id, ts, sender, text: text === null ? 'Unable to decrypt' : text, bad: text === null,
                     ct: f.ct.stringValue, seen: !!f.seen?.booleanValue, deleted:false });
  }
  return isNew && sender !== ME;
}
async function pollOnce(s){
  let changed = false, incoming = 0, more = true;
  while (more && S === s) {
    const res = await jpost(`${BASE}/${COL}/${s.roomId}:runQuery?${KQ}`, { structuredQuery: {
      from: [{ collectionId: 'messages' }],
      where: { fieldFilter: { field:{ fieldPath:'updatedAt' }, op:'GREATER_THAN', value:{ timestampValue: s.lastSync } } },
      orderBy: [{ field:{ fieldPath:'updatedAt' }, direction:'ASCENDING' }],
      limit: 200 } });
    const docs = res.filter(r => r.document).map(r => r.document);
    for (const d of docs) { if (await applyDoc(s, d)) incoming++; }
    if (docs.length) { s.lastSync = docs[docs.length - 1].fields.updatedAt.timestampValue; changed = true; s.lastActivity = Date.now(); }
    more = docs.length >= 200;
  }
  return { changed, incoming };
}
function setConn(ok){
  const el = $('subline');
  el.textContent = (ok ? 'Connected' : 'Offline, retrying…') + (ME === 'a' ? ' · Owner' : '');
  el.classList.toggle('off', !ok);
}
async function tick(){
  const s = S; if (!s) return;
  clearTimeout(s.timer);
  try {
    const { changed, incoming } = await pollOnce(s);
    if (S !== s) return;
    setConn(true);
    if (changed) {
      if (!isAtBottom()) s.unread += incoming;
      render(false);
      maybeSeen();
    }
  } catch (e) { if (S !== s) return; setConn(false); }
  schedule();
}
function schedule(){
  const s = S; if (!s) return;
  clearTimeout(s.timer);
  if (document.hidden) return;
  const idle = Date.now() - s.lastActivity;
  s.timer = setTimeout(tick, idle < 60000 ? 1500 : idle < 300000 ? 4000 : 8000);
}
document.addEventListener('visibilitychange', () => { if (S && !document.hidden) { S.lastActivity = Date.now(); tick(); } });
window.addEventListener('online', () => { if (S) tick(); });
const bump = () => { if (S) S.lastActivity = Date.now(); };
['pointerdown','keydown','touchstart'].forEach(ev => document.addEventListener(ev, bump, { passive:true }));

/* ----- Seen ----- */
function maybeSeen(){
  const s = S; if (!s || document.hidden) return;
  const ids = [];
  for (const m of s.msgs.values()) if (m.sender !== ME && !m.deleted && !m.seen && !s.seenSent.has(m.id)) ids.push(m.id);
  if (!ids.length) return;
  ids.forEach(id => s.seenSent.add(id));
  commit(ids.map(id => ({
    update: { name: msgName(s.roomId, id), fields: { seen: FB(true) } },
    updateMask: { fieldPaths: ['seen'] }, updateTransforms: TR, currentDocument: { exists: true }
  }))).catch(() => ids.forEach(id => s.seenSent.delete(id)));
}

/* ----- Render ----- */
function isAtBottom(){ return list.scrollHeight - list.scrollTop - list.clientHeight < 140; }
function updateToBottom(){
  const at = isAtBottom();
  if (at && S) S.unread = 0;
  const show = !at && S && S.unread > 0;
  $('toBottom').classList.toggle('hidden', !show);
  $('newCnt').textContent = show ? String(S.unread) : '';
}
list.addEventListener('scroll', updateToBottom, { passive:true });
$('toBottom').addEventListener('click', () => { list.scrollTo({ top: list.scrollHeight, behavior:'smooth' }); });

function tickHtml(m){
  if (m.failed) return `<button class="retry" data-retry="${m.id}">Retry</button>`;
  if (m.pending) return `<span class="tick pend">${ic('clock')}</span>`;
  return `<span class="tick ${m.seen ? 'seen' : ''}">${ic(m.seen ? 'checks' : 'check')}</span>`;
}
function rowHtml(m){
  const mine = m.sender === ME;
  const sel = S.selected.has(m.id) ? ' sel' : '';
  const time = fmtTime.format(new Date(m.ts));
  let inner;
  if (m.deleted) {
    const who = m.delBy === ME ? 'You deleted this message' : 'This message was deleted';
    inner = `<div class="bubble deleted"><span>${ic('ban')}${who}</span></div>`;
  } else {
    inner = `<div class="bubble"><span class="txt-m">${esc(m.text)}</span><span class="meta">${time}${mine ? tickHtml(m) : ''}</span></div>`;
  }
  return `<div class="row ${mine ? 'mine' : 'theirs'}${sel}" data-id="${m.id}">${inner}</div>`;
}
function render(forceBottom){
  if (!S) return;
  const wasBottom = isAtBottom(), prevTop = list.scrollTop;
  const arr = [...S.msgs.values()].sort((a, b) => a.ts - b.ts || (a.id < b.id ? -1 : 1));
  let html = '';
  if (!arr.length) html += `<div class="empty"><div class="tile">${ic('lock')}</div><b>No messages yet</b><span>Messages are end-to-end encrypted.</span></div>`;
  let last = '';
  for (const m of arr) {
    const k = dayKey(m.ts);
    if (k !== last) { html += `<div class="day"><span>${dayLabel(m.ts)}</span></div>`; last = k; }
    html += rowHtml(m);
  }
  list.innerHTML = html;
  list.scrollTop = (forceBottom || wasBottom) ? list.scrollHeight : prevTop;
  updateToBottom();
}

/* ----- Send ----- */
function autosize(){ input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 120) + 'px'; }
input.addEventListener('input', autosize);
input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey && matchMedia('(pointer:fine)').matches) { e.preventDefault(); send(); }
});
$('sendBtn').addEventListener('mousedown', e => e.preventDefault());
$('sendBtn').addEventListener('click', send);

function send(){
  if (!S) return;
  const text = input.value.trim(); if (!text) return;
  input.value = ''; autosize(); input.focus();
  const id = randId(10), ts = Date.now();
  S.msgs.set(id, { id, ts, sender: ME, text, seen:false, deleted:false, pending:true });
  S.lastActivity = Date.now();
  render(true);
  pushMsg(id);
}
async function pushMsg(id){
  const s = S; if (!s) return;
  const m = s.msgs.get(id); if (!m) return;
  m.pending = true; m.failed = false;
  try {
    const { ct, iv } = await encryptText(s.key, m.text, id);
    await commit([{
      update: { name: msgName(s.roomId, id), fields: {
        ct: FS(ct), iv: FS(iv), snd: FS(ME), ts: { integerValue: String(m.ts) }, seen: FB(false), deleted: FB(false) } },
      updateTransforms: TR, currentDocument: { exists: false }
    }]);
    m.pending = false;
    if (S === s) setTimeout(tick, 150);
  } catch (e) { m.pending = false; m.failed = true; }
  if (S === s) render(false);
}

/* ----- Select & delete ----- */
let lp = null, lpFired = false, sx = 0, sy = 0;
const rowOf = (t) => t.closest('.row[data-id]');
list.addEventListener('pointerdown', (e) => {
  const row = rowOf(e.target); if (!row) return;
  lpFired = false; sx = e.clientX; sy = e.clientY; clearTimeout(lp);
  lp = setTimeout(() => { lpFired = true; toggleSel(row.dataset.id); if (navigator.vibrate) navigator.vibrate(15); }, 420);
});
list.addEventListener('pointermove', (e) => { if (Math.abs(e.clientX - sx) > 8 || Math.abs(e.clientY - sy) > 8) clearTimeout(lp); });
['pointerup','pointercancel','pointerleave'].forEach(ev => list.addEventListener(ev, () => clearTimeout(lp)));
list.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  if (e.pointerType === 'mouse') { const row = rowOf(e.target); if (row) toggleSel(row.dataset.id); }
});
list.addEventListener('click', (e) => {
  if (lpFired) { lpFired = false; return; }
  const rt = e.target.closest('[data-retry]');
  if (rt) { pushMsg(rt.dataset.retry); render(false); return; }
  if (S && S.selected.size) { const row = rowOf(e.target); if (row) toggleSel(row.dataset.id); }
});
function toggleSel(id){
  if (!S) return;
  const m = S.msgs.get(id); if (!m || m.deleted || m.pending) return;
  if (S.selected.has(id)) S.selected.delete(id); else S.selected.add(id);
  const row = list.querySelector(`.row[data-id="${id}"]`);
  if (row) row.classList.toggle('sel', S.selected.has(id));
  updateSelBar();
}
function updateSelBar(){
  const n = S ? S.selected.size : 0;
  $('app').classList.toggle('selmode', n > 0);
  $('selCount').textContent = n + ' selected';
}
function clearSel(){
  if (!S) return;
  S.selected.clear();
  list.querySelectorAll('.row.sel').forEach(r => r.classList.remove('sel'));
  updateSelBar();
}
$('selCancel').addEventListener('click', clearSel);
$('selCopy').addEventListener('click', async () => {
  if (!S) return;
  const txt = [...S.selected].map(id => S.msgs.get(id)).filter(Boolean).sort((a, b) => a.ts - b.ts).map(m => m.text).join('\n');
  try { await navigator.clipboard.writeText(txt); toast('Copied'); } catch { toast('Copy failed'); }
  clearSel();
});
$('selDel').addEventListener('click', () => {
  if (!S || !S.selected.size) return;
  const n = S.selected.size;
  $('delText').textContent = `${n} message${n > 1 ? 's' : ''} will be deleted for everyone.`;
  $('delModal').classList.add('open');
});
$('delNo').addEventListener('click', closeModals);
$('delYes').addEventListener('click', async () => {
  const s = S; closeModals(); if (!s) return;
  const ids = [...s.selected].filter(id => { const m = s.msgs.get(id); return m && !m.deleted; });
  clearSel(); if (!ids.length) return;
  const backup = ids.map(id => ({ ...s.msgs.get(id) }));
  ids.forEach(id => { const m = s.msgs.get(id); s.msgs.set(id, { id, ts:m.ts, sender:m.sender, deleted:true, delBy:ME }); });
  render(false);
  try {
    await commit(ids.map(id => ({
      update: { name: msgName(s.roomId, id), fields: { deleted: FB(true), ct: FS(''), iv: FS(''), delBy: FS(ME) } },
      updateMask: { fieldPaths: ['deleted','ct','iv','delBy'] }, updateTransforms: TR, currentDocument: { exists: true }
    })));
    if (S === s) setTimeout(tick, 150);
  } catch (e) {
    backup.forEach(m => s.msgs.set(m.id, m));
    if (S === s) { render(false); toast('Delete failed. Try again.'); }
  }
});

/* ----- Misc ----- */
$('exitBtn').addEventListener('click', leaveChat);
$('pinBtn').addEventListener('click', () => S && showPin());
$('pinClose').addEventListener('click', closeModals);
$('pinCopy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(myCode()); toast('Copied'); } catch { toast('Copy failed'); }
});
document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', (e) => { if (e.target === m) closeModals(); }));

/* Keep layout correct when the mobile keyboard opens */
const appEl = $('app');
function fitHeight(){
  const vv = window.visualViewport;
  appEl.style.height = (vv ? vv.height : window.innerHeight) + 'px';
  if (S && document.activeElement === input) list.scrollTop = list.scrollHeight;
}
if (window.visualViewport) {
  visualViewport.addEventListener('resize', fitHeight);
  visualViewport.addEventListener('scroll', () => window.scrollTo(0, 0));
}
window.addEventListener('resize', fitHeight);
fitHeight();

/* Glass bars float over the list: keep list padding in sync with their heights */
function measure(){
  const c = $('chat');
  c.style.setProperty('--hdr-h', $('hdrMain').offsetHeight + 'px');
  c.style.setProperty('--comp-h', $('composer').offsetHeight + 'px');
}
if (window.ResizeObserver) { const ro = new ResizeObserver(measure); ro.observe($('hdrMain')); ro.observe($('composer')); }
window.addEventListener('resize', measure);

resetLock();

