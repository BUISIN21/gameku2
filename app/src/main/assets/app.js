'use strict';

// Semua ID di server PeerJS publik diberi prefix supaya tidak bentrok dengan aplikasi lain.
const ID_PREFIX = 'gameku-vc-';
const CALL_TIMEOUT_MS = 45000;
const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
  // Tambahkan server TURN di sini jika panggilan sering gagal di jaringan seluler/kantor:
  // { urls: 'turn:turn.contoh.com:3478', username: 'user', credential: 'pass' },
];

// Kosongkan untuk memakai server PeerJS publik gratis (0.peerjs.com).
// Isi jika punya server sendiri, mis. { host: 'peer.contoh.com', port: 443, path: '/', secure: true }.
const PEER_SERVER = window.PEER_SERVER || {};

const $ = (id) => document.getElementById(id);
const el = {
  status: $('status'),
  preview: $('preview'),
  previewPlaceholder: $('preview-placeholder'),
  myCode: $('my-code'),
  copyBtn: $('copy-btn'),
  remoteCode: $('remote-code'),
  callBtn: $('call-btn'),
  incoming: $('incoming'),
  incomingCode: $('incoming-code'),
  acceptBtn: $('accept-btn'),
  rejectBtn: $('reject-btn'),
  home: $('home'),
  inCall: $('in-call'),
  remoteVideo: $('remote-video'),
  localVideo: $('local-video'),
  callPeer: $('call-peer'),
  callState: $('call-state'),
  muteBtn: $('mute-btn'),
  camBtn: $('cam-btn'),
  switchBtn: $('switch-btn'),
  hangupBtn: $('hangup-btn'),
  toast: $('toast'),
};

const state = {
  peer: null,
  myCode: null,
  localStream: null,
  facingMode: 'user',
  call: null,        // MediaConnection aktif
  control: null,     // DataConnection untuk sinyal tutup/tolak
  pendingCall: null, // panggilan masuk yang belum dijawab
  callTimer: null,
  micOn: true,
  camOn: true,
};

// ---------- Util ----------

let toastTimer;
function toast(msg) {
  el.toast.textContent = msg;
  el.toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.toast.classList.remove('show'), 2500);
}

function storageGet(key) {
  try { return localStorage.getItem(key); } catch (_) { return null; }
}
function storageSet(key, value) {
  try { localStorage.setItem(key, value); } catch (_) { /* abaikan */ }
}

function randomCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function setStatus(text, cls) {
  el.status.textContent = text;
  el.status.className = 'status ' + cls;
}

function showScreen(name) {
  el.home.classList.toggle('active', name === 'home');
  el.inCall.classList.toggle('active', name === 'call');
  const v = name === 'home' ? el.preview : el.localVideo;
  if (v.srcObject) v.play().catch(() => {});
}

// ---------- Nada dering ----------

const ringer = {
  ctx: null,
  timer: null,
  start(outgoing) {
    this.stop();
    try {
      this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
      this.ctx.resume();
    } catch (_) { return; }
    const beep = () => {
      const t = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.frequency.value = outgoing ? 425 : 660;
      gain.gain.setValueAtTime(0.0001, t);
      gain.gain.exponentialRampToValueAtTime(0.25, t + 0.05);
      gain.gain.setValueAtTime(0.25, t + 0.9);
      gain.gain.exponentialRampToValueAtTime(0.0001, t + 1.0);
      osc.connect(gain).connect(this.ctx.destination);
      osc.start(t);
      osc.stop(t + 1.0);
      if (!outgoing && navigator.vibrate) navigator.vibrate([400, 200, 400]);
    };
    beep();
    this.timer = setInterval(beep, outgoing ? 3000 : 2000);
  },
  stop() {
    clearInterval(this.timer);
    this.timer = null;
    if (navigator.vibrate) navigator.vibrate(0);
  },
};

// ---------- Media ----------

async function getLocalStream() {
  if (state.localStream && state.localStream.active) return state.localStream;
  try {
    state.localStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: state.facingMode, width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    });
  } catch (err) {
    console.error(err);
    toast('Tidak bisa membuka kamera/mikrofon');
    throw err;
  }
  applyTrackToggles();
  el.preview.srcObject = state.localStream;
  el.localVideo.srcObject = state.localStream;
  el.previewPlaceholder.style.display = 'none';
  return state.localStream;
}

function applyTrackToggles() {
  if (!state.localStream) return;
  state.localStream.getAudioTracks().forEach((t) => { t.enabled = state.micOn; });
  state.localStream.getVideoTracks().forEach((t) => { t.enabled = state.camOn; });
  el.muteBtn.classList.toggle('off', !state.micOn);
  el.camBtn.classList.toggle('off', !state.camOn);
}

async function switchCamera() {
  if (!state.localStream) return;
  const next = state.facingMode === 'user' ? 'environment' : 'user';
  let newTrack;
  try {
    const s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { exact: next } } });
    newTrack = s.getVideoTracks()[0];
  } catch (_) {
    toast('Kamera lain tidak tersedia');
    return;
  }
  const oldTrack = state.localStream.getVideoTracks()[0];
  newTrack.enabled = state.camOn;
  if (state.call && state.call.peerConnection) {
    const sender = state.call.peerConnection.getSenders().find((s) => s.track && s.track.kind === 'video');
    if (sender) await sender.replaceTrack(newTrack);
  }
  if (oldTrack) {
    state.localStream.removeTrack(oldTrack);
    oldTrack.stop();
  }
  state.localStream.addTrack(newTrack);
  state.facingMode = next;
  el.localVideo.classList.toggle('rear', next === 'environment');
  // Paksa elemen video memuat ulang track baru.
  el.localVideo.srcObject = state.localStream;
  el.preview.srcObject = state.localStream;
}

// ---------- PeerJS ----------

function initPeer(code) {
  state.myCode = code;
  el.myCode.textContent = code;
  setStatus('Menghubungkan…', 'connecting');

  const peer = new Peer(ID_PREFIX + code, { ...PEER_SERVER, config: { iceServers: ICE_SERVERS } });
  state.peer = peer;

  peer.on('open', () => {
    storageSet('myCode', code);
    setStatus('Online', 'online');
  });

  peer.on('disconnected', () => {
    setStatus('Terputus', 'offline');
    setTimeout(() => { if (!peer.destroyed && peer.disconnected) peer.reconnect(); }, 2000);
  });

  peer.on('error', (err) => {
    console.error('peer error', err.type, err);
    switch (err.type) {
      case 'unavailable-id':
        // Kode sudah dipakai orang lain: buat kode baru.
        peer.destroy();
        initPeer(randomCode());
        break;
      case 'peer-unavailable':
        toast('Kode teman tidak ditemukan / sedang offline');
        endCall(false);
        break;
      case 'network':
      case 'server-error':
      case 'socket-error':
      case 'socket-closed':
        setStatus('Offline', 'offline');
        setTimeout(() => { if (!peer.destroyed && peer.disconnected) peer.reconnect(); }, 3000);
        break;
      default:
        toast('Error: ' + err.type);
    }
  });

  peer.on('connection', (conn) => {
    conn.on('data', (msg) => handleControl(conn, msg));
    // Simpan kanal kontrol dari penelepon yang sedang/akan kita layani.
    const from = conn.peer;
    if ((state.pendingCall && state.pendingCall.peer === from) || (state.call && state.call.peer === from)) {
      state.control = conn;
    } else {
      conn.on('open', () => {
        if (!state.control && !state.call && (!state.pendingCall || state.pendingCall.peer === from)) {
          state.control = conn;
        }
      });
    }
  });

  peer.on('call', (call) => {
    if (state.call || state.pendingCall) {
      // Sedang sibuk.
      const busyConn = peer.connect(call.peer);
      busyConn.on('open', () => { busyConn.send({ type: 'busy' }); setTimeout(() => busyConn.close(), 1000); });
      setTimeout(() => call.close(), 500);
      return;
    }
    state.pendingCall = call;
    el.incomingCode.textContent = call.peer.replace(ID_PREFIX, '');
    el.incoming.classList.add('active');
    ringer.start(false);
    // Jika penelepon membatalkan sebelum dijawab.
    call.on('close', () => { if (state.pendingCall === call) dismissIncoming(); });
  });
}

function handleControl(conn, msg) {
  if (!msg || typeof msg !== 'object') return;
  const fromActive = (state.call && state.call.peer === conn.peer) ||
    (state.pendingCall && state.pendingCall.peer === conn.peer);
  if (!fromActive) return;
  switch (msg.type) {
    case 'hangup':
      if (state.pendingCall) { dismissIncoming(); toast('Panggilan dibatalkan'); }
      else { toast('Panggilan diakhiri'); endCall(false); }
      break;
    case 'reject':
      toast('Panggilan ditolak');
      endCall(false);
      break;
    case 'busy':
      toast('Teman sedang dalam panggilan lain');
      endCall(false);
      break;
  }
}

function sendControl(type) {
  const c = state.control;
  if (c && c.open) {
    try { c.send({ type }); } catch (_) { /* abaikan */ }
  }
}

function watchConnection(call) {
  const pc = call.peerConnection;
  if (!pc) return;
  let disconnectTimer;
  pc.addEventListener('iceconnectionstatechange', () => {
    const s = pc.iceConnectionState;
    if (state.call !== call) return;
    if (s === 'connected' || s === 'completed') {
      clearTimeout(disconnectTimer);
      el.callState.textContent = 'Terhubung';
    } else if (s === 'disconnected') {
      el.callState.textContent = 'Koneksi tidak stabil…';
      disconnectTimer = setTimeout(() => {
        if (state.call === call && pc.iceConnectionState !== 'connected') {
          toast('Koneksi terputus');
          endCall(false);
        }
      }, 10000);
    } else if (s === 'failed') {
      toast('Gagal terhubung (jaringan memblokir koneksi)');
      endCall(false);
    }
  });
}

function attachCall(call) {
  state.call = call;
  call.on('stream', (remote) => {
    ringer.stop();
    clearTimeout(state.callTimer);
    el.remoteVideo.srcObject = remote;
    el.callState.textContent = 'Terhubung';
    startDurationClock();
  });
  call.on('close', () => { if (state.call === call) endCall(false); });
  call.on('error', (e) => { console.error(e); if (state.call === call) endCall(false); });
  // peerConnection baru tersedia setelah negosiasi dimulai.
  setTimeout(() => watchConnection(call), 0);
}

let durationTimer;
function startDurationClock() {
  clearInterval(durationTimer);
  const start = Date.now();
  durationTimer = setInterval(() => {
    const s = Math.floor((Date.now() - start) / 1000);
    el.callState.textContent = `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  }, 1000);
}

// ---------- Alur panggilan ----------

async function startCall() {
  const code = el.remoteCode.value.replace(/\D/g, '');
  if (code.length !== 6) { toast('Masukkan 6 digit kode teman'); return; }
  if (code === state.myCode) { toast('Itu kode kamu sendiri 🙂'); return; }
  if (!state.peer || !state.peer.open) { toast('Belum terhubung ke server, coba lagi'); return; }
  if (state.call) return;

  let stream;
  try { stream = await getLocalStream(); } catch (_) { return; }
  storageSet('lastRemote', code);

  const remoteId = ID_PREFIX + code;
  state.control = state.peer.connect(remoteId, { reliable: true });
  state.control.on('data', (msg) => handleControl(state.control, msg));

  const call = state.peer.call(remoteId, stream);
  if (!call) { toast('Gagal memanggil'); state.control.close(); state.control = null; return; }
  attachCall(call);

  el.callPeer.textContent = code;
  el.callState.textContent = 'Memanggil…';
  showScreen('call');
  ringer.start(true);
  state.callTimer = setTimeout(() => {
    if (state.call === call && !el.remoteVideo.srcObject) {
      toast('Tidak dijawab');
      endCall(true);
    }
  }, CALL_TIMEOUT_MS);
}

async function acceptCall() {
  const call = state.pendingCall;
  if (!call) return;
  ringer.stop();
  el.incoming.classList.remove('active');
  let stream;
  try { stream = await getLocalStream(); } catch (_) { rejectCall(); return; }
  state.pendingCall = null;
  attachCall(call);
  call.answer(stream);
  el.callPeer.textContent = call.peer.replace(ID_PREFIX, '');
  el.callState.textContent = 'Menyambungkan…';
  showScreen('call');
}

function rejectCall() {
  const call = state.pendingCall;
  if (!call) return;
  sendControl('reject');
  dismissIncoming();
  setTimeout(() => call.close(), 300);
}

function dismissIncoming() {
  ringer.stop();
  el.incoming.classList.remove('active');
  state.pendingCall = null;
  closeControlSoon();
}

function closeControlSoon() {
  const c = state.control;
  state.control = null;
  if (c) setTimeout(() => { try { c.close(); } catch (_) {} }, 500);
}

function endCall(notifyRemote) {
  ringer.stop();
  clearTimeout(state.callTimer);
  clearInterval(durationTimer);
  if (notifyRemote) sendControl('hangup');
  const call = state.call;
  state.call = null;
  if (call) setTimeout(() => { try { call.close(); } catch (_) {} }, 300);
  closeControlSoon();
  el.remoteVideo.srcObject = null;
  showScreen('home');
}

// Dipanggil oleh MainActivity saat tombol Back ditekan. true = sudah ditangani.
window.onAndroidBack = function () {
  if (state.pendingCall) { rejectCall(); return true; }
  if (state.call) { endCall(true); return true; }
  return false;
};

// ---------- Event UI ----------

el.callBtn.addEventListener('click', startCall);
el.remoteCode.addEventListener('keydown', (e) => { if (e.key === 'Enter') startCall(); });
el.acceptBtn.addEventListener('click', acceptCall);
el.rejectBtn.addEventListener('click', rejectCall);
el.hangupBtn.addEventListener('click', () => endCall(true));
el.muteBtn.addEventListener('click', () => {
  state.micOn = !state.micOn;
  applyTrackToggles();
  toast(state.micOn ? 'Mikrofon aktif' : 'Mikrofon dimatikan');
});
el.camBtn.addEventListener('click', () => {
  state.camOn = !state.camOn;
  applyTrackToggles();
  toast(state.camOn ? 'Kamera aktif' : 'Kamera dimatikan');
});
el.switchBtn.addEventListener('click', switchCamera);
el.copyBtn.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(state.myCode);
    toast('Kode disalin');
  } catch (_) {
    toast('Kode kamu: ' + state.myCode);
  }
});

// ---------- Mulai ----------

el.remoteCode.value = storageGet('lastRemote') || '';
initPeer(storageGet('myCode') || randomCode());
getLocalStream().catch(() => { /* user bisa memberi izin nanti saat menelepon */ });
