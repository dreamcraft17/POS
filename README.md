# e+e POS (`ee_pos`)

Aplikasi **Point of Sale (POS)** berbasis Flutter untuk operasional kasir kafe/restoran (mis. **e+e Coffee**). Terhubung ke backend POS API, bisa dipakai saat jaringan tidak stabil, dan mendukung cetak struk serta tiket dapur/bar ke printer thermal (Bluetooth/USB).

## Tentang aplikasi

| Aspek | Keterangan |
|--------|------------|
| **Tujuan** | Transaksi penjualan di lokasi: pilih menu, keranjang, diskon, pajak, bayar, cetak. |
| **Pengguna** | Kasir / staff outlet yang login ke sistem POS. |
| **Platform** | Utama Android (tablet/HP kasir); build Flutter juga memungkinkan target desktop lain jika dikonfigurasi. |
| **Backend** | REST API (Laravel-style public path), URL dikonfigurasi lewat `API_URL`. |
| **Mode offline** | Order dan beberapa request bisa diantrikan lokal; `SyncManager` menyinkronkan saat online (`offline_queue` + `outbox`). |
| **Cetak** | Struk customer, tiket antrian (customer printer), kitchen, dan bar — profil printer di Settings. |

### Fitur utama

- **Layar POS** — grid menu, pencarian produk (debounce), keranjang, subtotal/diskon/pajak, tipe order.
- **Pembayaran** — metode bayar dari API, konfirmasi & cetak, dialog sukses + cetak ulang.
- **Open Bills** — simpan bill lokal (draft), lanjutkan pesanan, tambah item (delta).
- **Split bill** — bagi total ke beberapa orang + cetak per bagian.
- **Pengaturan** — pajak, diskon, tipe order, template struk, printer (customer/kitchen/bar), shift, dll.
- **Autentikasi** — login kasir; sesi API via cookie (`ApiService`).

### Alur singkat

```
Splash → init DB & SyncManager → Login (jika perlu) → POS Home
                                              ↓
                         Menu → Cart → Pay / Save Bill / Split → Cetak
                                              ↓
                         Offline? → antrian lokal → sync otomatis saat online
```

## Prerequisites

- Flutter SDK (Dart 3.3+)
- Android SDK + Android Studio (untuk build Android)

## Setup

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Jalankan debug:
   ```bash
   flutter run
   ```

## API Configuration

`lib/config.dart` membaca URL API dari `--dart-define`:

| | |
|---|---|
| **Key** | `API_URL` |
| **Default** | `https://cafepos2.epluseglobal.com/pos-api/public` |

Contoh:

```bash
flutter run --dart-define=API_URL=https://your-api-host/pos-api/public
```

Build release dengan API custom:

```bash
flutter build apk --release --dart-define=API_URL=https://your-api-host/pos-api/public
```

## Android Release Signing

Nilai signing release bisa dari:

- `android/gradle.properties`, atau
- environment variables: `RELEASE_STORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD`

Setup lokal (disarankan):

1. Salin `android/gradle.properties.local.example` → `android/gradle.properties.local`
2. Isi path keystore dan password di file lokal itu
3. Jangan commit password atau file `.jks` ke repository

## Useful Commands

| Perintah | Fungsi |
|----------|--------|
| `flutter analyze` | Cek masalah statis |
| `flutter test` | Unit/widget tests |
| `flutter build apk --release` | APK production |

## Performance & arsitektur ringkas

- **Satu klien API:** `ApiService.shared()` — cookie/sesi dipakai ulang.
- **Satu runner sync:** `SyncManager.instance.init()` di bootstrap (interval 30s, debounce konektivitas 2s, gap minimal 5s). Pemicu manual: `requestBackgroundSync()` / `SyncManager.instance.syncNow()`.
- **POS tidak saling rebuild:** panel menu (`_PosCatalogPane`) terpisah dari `CartPanel`; filter menu di `filteredMenusProvider`.
- **Cart:** `ListView.builder`, persist SQLite di background (`unawaited`), tombol aksi hanya rebuild saat cart kosong ↔ berisi.
- **Pajak:** `cartTotalsProvider` — total terpisah dari list item.
- **Pencarian menu:** debounce 220 ms + `TextEditingController` (tanpa rebuild tiap ketik).
- **Navigasi:** `IndexedStack` menjaga state halaman saat pindah tab.

## Struktur proyek (`lib/`)

| Area | Path |
|------|------|
| Entry & bootstrap | `main.dart`, `bootstrap/splash_bootstrap.dart` |
| Layar POS | `pages/pos_home.dart`, `widgets/menu_grid.dart`, `widgets/product_grid.dart` |
| Keranjang & bayar | `widgets/cart_panel.dart`, `widgets/cart/cart_dialogs.dart`, `cart_helpers.dart`, `cart_ui_shared.dart` |
| API & config | `services/api_service.dart`, `config.dart` |
| Offline sync | `services/sync_manager.dart`, `offline/outbox_repo.dart`, `repositories/offline_queue_repo.dart` |
| Database lokal | `db/local_db.dart`, `repositories/*` |
| Settings | `pages/settings_page.dart`, `widgets/settings/` |
| Cetak | `widgets/bill_receipt.dart`, `services/printer_prefs.dart` |
| State (Riverpod) | `providers/` |

## Tech stack

- **Flutter** + **Riverpod** (state)
- **Dio** (HTTP + cookies)
- **sqflite** (SQLite lokal)
- **connectivity_plus** (deteksi jaringan untuk sync)
- **blue_thermal_printer** / **flutter_usb_thermal_plugin** + ESC/POS utils (thermal print)

## Versi

Lihat `pubspec.yaml` — saat ini `version: 1.0.1+2`.
