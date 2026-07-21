# VEXT — VigilantMesh

**Campus BLE Mesh Intelligence Platform.** An offline-first Flutter app that keeps attendance, campus messaging, and emergency SOS alerts working over a Bluetooth mesh network when Wi-Fi and cellular data aren't available — with automatic sync to Firebase when connectivity returns.

## Why

Campus networks aren't always reliable, and emergencies don't wait for a signal. VEXT builds a peer-to-peer Bluetooth Low Energy mesh between nearby phones so critical events — an SOS alert, a class check-in, a message — can hop device to device until they reach someone with internet access, at which point they sync to the cloud automatically. Verified across a 3-phone multi-hop relay test in the field.

## Features

- **Attendance** — BLE proximity-based check-in with server-side aggregation (Cloud Functions), falls back to Firestore when online.
- **Social messaging** — 1:1 direct messages with end-to-end encryption (X25519 key exchange + AES-256-GCM), relayed across the mesh by non-recipient nodes.
- **SOS alerts** — one-tap emergency broadcast to all users on campus, delivered over BLE mesh with Firestore/FCM as the online fallback.
- **Offline-first sync** — local SQLite (Drift) as the source of truth, with a sync engine that reconciles with Firestore once a connection is available.
- **On-device mesh diagnostics** — live BLE advertising/scanning error surfacing, so connectivity failures are visible in the UI instead of failing silently.

## Architecture

```
lib/
├── core/          # shared models, protobuf-defined wire format
├── lanes/         # feature verticals: attendance, social, sos
├── services/       # BLE transport, mesh relay, crypto, Drift DB, Firebase sync
├── providers/       # Riverpod state management
└── screens/        # UI

functions/          # Firebase Cloud Functions (TypeScript)
├── handleSOSAlert.ts       # broadcasts SOS to all users
└── aggregateAttendance.ts  # server-side attendance rollups
```

**Mesh transport:** custom protobuf packet format over `flutter_blue_plus`, with a Kotlin-native BLE advertiser/GATT server on Android for background operation via a foreground service.

**Security:** end-to-end encrypted messaging (X25519 + AES-256-GCM), Firestore security rules scoped per-collection, credentials in secure storage.

## Tech Stack

| Layer | Technology |
|---|---|
| App | Flutter (Dart), Riverpod state management, go_router |
| Mesh networking | BLE (flutter_blue_plus + native Kotlin advertiser/GATT server), Protobuf |
| Local storage | Drift (SQLite), offline-first with background sync |
| Backend | Firebase (Auth, Firestore, Cloud Functions, FCM) |
| Cryptography | X25519 key exchange, AES-256-GCM (`cryptography` package) |
| CI/CD | GitHub Actions (auto-deploy Firestore rules on push to `main`) |

## Getting Started

```bash
flutter pub get
flutter run
```

Requires a configured Firebase project (`firebase_options.dart`) and, for BLE features, a physical device — mesh networking is not available on simulators/emulators.

### Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

## Testing

```bash
flutter test
```

Unit tests cover attendance, crypto, and mesh service logic, including an in-memory Firestore fake so business logic is tested without a live backend.

## Status

Actively developed. Core mesh relay, attendance, encrypted messaging, and SOS broadcast are built and field-tested; student-teacher messaging restrictions and GPS geofencing are in progress.
