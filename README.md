# Video Call (Android)

Aplikasi video call 1-lawan-1 sederhana untuk Android. Tiap HP mendapat **kode 6 digit**;
masukkan kode teman lalu tekan **Panggil**.

## Fitur
- Video + suara real-time (WebRTC, peer-to-peer)
- Kode 6 digit tetap tersimpan di HP
- Panggilan masuk dengan nada dering & getar, terima / tolak
- Matikan mikrofon, matikan kamera, ganti kamera depan/belakang, tutup panggilan
- Tombol Back = tolak / akhiri panggilan
- Deteksi "tidak dijawab", "sedang sibuk", "kode tidak ditemukan", koneksi terputus

## Cara dapat APK
APK dibangun otomatis oleh GitHub Actions (`.github/workflows/build-apk.yml`):

1. Buka tab **Actions** di repo → workflow **Build APK** → run terbaru.
2. Unduh artifact **VideoCall-apk**, ekstrak, install `VideoCall.apk` di HP
   (izinkan "Install dari sumber tidak dikenal").

Untuk rilis: buat tag `v1.0` → APK otomatis dilampirkan di halaman **Releases**.

Build lokal (butuh Android SDK + JDK 17): `./gradlew assembleRelease`

## Cara kerja
- `MainActivity.kt` — WebView yang memuat `app/src/main/assets/` lewat
  `https://appassets.androidplatform.net` (secure context untuk kamera) dan meneruskan izin kamera/mikrofon.
- `assets/app.js` — logika panggilan memakai [PeerJS](https://peerjs.com) (dibundel lokal).
  Sinyal memakai server PeerJS publik gratis; video/suara mengalir langsung antar HP.

## Batasan & pengembangan
- **Jaringan ketat** (beberapa operator seluler / Wi-Fi kantor) bisa gagal tersambung karena hanya
  memakai STUN. Tambahkan server TURN di `ICE_SERVERS` pada `app.js`.
- Server PeerJS publik tidak dijamin selalu aktif. Untuk produksi, jalankan
  [peerjs-server](https://github.com/peers/peerjs-server) sendiri dan isi `PEER_SERVER` di `app.js`.
- Panggilan hanya bisa diterima saat aplikasi terbuka (belum ada push notification).
- APK release ditandatangani dengan debug key; ganti dengan keystore sendiri sebelum upload ke Play Store.
