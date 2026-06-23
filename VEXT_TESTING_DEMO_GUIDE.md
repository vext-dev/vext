# VEXT VigilantMesh — Testing & Demo Guide
**Prepared for:** Review session  
**Project:** `vext-vigilantmesh-57551` (Firebase) · Flutter/Android · BLE Mesh  
**Domain restriction:** Only `@bmsce.ac.in` emails can sign up or log in.

---

## 1. Quick Setup Checklist (Do This First)

```
Before you demo, confirm on EVERY phone:
  ✅ Bluetooth ON
  ✅ Location ON (required for BLE scanning on Android)
  ✅ All permissions granted (see §6)
  ✅ Screen stays ON (developer options → Stay Awake)
  ✅ App open and on a main tab (Attendance / Social / SOS)
  ✅ Signed in with @bmsce.ac.in email
  ✅ Role selected (Student / Teacher / Security)
```

One mandatory step after the schema change (run once on dev machine):
```bash
cd /Users/shreshtha/Development/vext
dart run build_runner build --delete-conflicting-outputs
flutter run
```

---

## 2. Firebase Database — Where To Find Everything

### Firebase Console
- **Project:** `vext-vigilantmesh-57551`
- **URL:** https://console.firebase.google.com/project/vext-vigilantmesh-57551
- **Services used:** Firestore · Auth · Cloud Messaging (FCM)

### Firestore Collections (Firestore → Data tab)

```
users/
  └── {uid}/                         ← one doc per user
        email, name, role, institution_id,
        publicKeyFingerprint, fcmToken, created_at

sessions/
  └── {sessionId}/                   ← created by teacher on startSession()
        id, courseId, teacherUid,
        startTime, isActive, createdAt

attendance/
  └── {sessionId}/
        └── proofs/
              └── {studentUid}/      ← one doc per student per session
                    id, sessionId, studentUid, hmacToken,
                    rssi, timestamp, gpsLat, gpsLng, syncedAt

messages/
  └── broadcast/
        └── records/
              └── {messageId}/       ← all social messages go here
                    id, senderUid, contentEncrypted,
                    ttl, timestamp, lane, syncedAt

sos_events/
  └── {sosId}/                       ← written when any node receives SOS
        id, senderUid, latitude, longitude,
        ttl, timestamp, createdAt
```

### How to watch live during demo
1. Open Firestore → `attendance/{sessionId}/proofs`
2. Students appear here within seconds of marking attendance (online)
3. Or watch `sos_events/` when SOS is triggered

---

## 3. Local Database — Where To Find It

### File Location on Device
```
/data/data/com.vext.vext_app/app_flutter/vext_mesh.db
```
(Inside app sandbox — accessible via Android Studio Device Explorer or `adb`)

### Pull it from device (adb):
```bash
adb shell "run-as com.vext.vext_app cp /data/data/com.vext.vext_app/app_flutter/vext_mesh.db /sdcard/vext_mesh.db"
adb pull /sdcard/vext_mesh.db
# Open with: DB Browser for SQLite (https://sqlitebrowser.org/)
```

### Local DB Tables (Drift / SQLite) — Schema v2

| Table | Purpose | Key Columns |
|---|---|---|
| `attendance_proofs` | Student proof records (offline-first) | `id`, `session_id`, `student_uid`, `hmac_token`, `rssi`, `synced` |
| `message_records` | Social messages sent/received | `id`, `sender_uid`, `content_encrypted`, `synced`, `is_read` |
| `sos_records` | SOS events this node processed | `id`, `sender_uid`, `latitude`, `longitude`, `synced` |
| `seen_packets` | Deduplication table (60-min TTL) | `packet_id`, `first_seen` |
| `peers` | Known BLE nodes nearby (7-day retention) | `peer_uid`, `last_seen`, `rssi` |

### What `synced = false` means
Rows with `synced = false` are queued for Firebase upload.  
`FirebaseSyncEngine` uploads them when WiFi is available, in priority order: SOS → Attendance → Messages.

---

## 4. Important Files & Their Locations

### Core Architecture
```
lib/
├── main.dart                          Entry point, Firebase init, FCM setup
├── core/
│   ├── app_constants.dart             ALL magic numbers (BLE UUIDs, RSSI thresholds, TTLs)
│   ├── app_router.dart                GoRouter + auth-aware redirect logic
│   ├── app_theme.dart                 Dark theme tokens
│   ├── models/tables.dart             Drift table schema (5 tables, schema v2)
│   └── proto/mesh_packet.dart         BLE packet binary encoding/decoding
│
├── services/
│   ├── ble_transport_layer.dart       BLE scan, advertise, GATT client/server
│   ├── mesh_service.dart              Gossip relay, dedup, lane dispatch
│   ├── drift_service.dart             Local SQLite DB + all DAOs
│   ├── firebase_sync_engine.dart      Offline→Firestore sync (SOS→Attendance→Messages)
│   ├── auth_service.dart              Firebase Auth + Firestore user profile
│   ├── crypto_service.dart            X25519, Ed25519, AES-GCM, HMAC, HKDF
│   └── mesh_foreground_service.dart   Android foreground service (keeps BLE alive)
│
├── lanes/
│   ├── attendance/
│   │   ├── attendance_service.dart    Teacher session + student auto-marking
│   │   └── screens/
│   │       ├── teacher_session_screen.dart   Live attendance list (Firestore + BLE fallback)
│   │       └── student_attendance_screen.dart Auto-detection status
│   ├── sos/
│   │   ├── sos_service.dart           SOS trigger, relay, re-broadcast
│   │   └── screens/sos_screen.dart    Hold button + incoming alert list
│   └── social/
│       ├── social_service.dart        Message send/receive + Firestore receive path
│       └── screens/social_screen.dart Chat UI
│
├── providers/
│   ├── ble_provider.dart              BLE mode lock system (NEW - key file for Issue 4)
│   ├── mesh_service_provider.dart     Mesh init + relay SOS boost (NEW)
│   ├── attendance_service_provider.dart Session lock wiring (NEW)
│   ├── sos_service_provider.dart      SOS lock callbacks (NEW)
│   └── auth_service_provider.dart     authStateProvider + firebaseUidProvider
│
└── screens/
    ├── home/home_shell.dart           Bottom nav + BLE UI preference (UPDATED)
    └── profile/profile_screen.dart    Logout + role display
```

### Android Native (Kotlin)
```
android/app/src/main/kotlin/com/vext/vext_app/
├── MainActivity.kt          Registers all 6 platform channels
├── BleAdvertiser.kt         BLE peripheral advertising
├── VextGattServer.kt        GATT server (receives incoming packets)
└── VextAlarmReceiver.kt     Doze-safe AlarmManager receiver (keeps BLE alive in Doze)
```

### Platform Channels (Dart ↔ Kotlin bridge)
```
com.vext.vext_app/ble_advertiser   → Start/stop BLE advertising
com.vext.vext_app/gatt_server      → Start/stop GATT server
com.vext.vext_app/gatt_packets     → EventChannel: incoming packets from peers
com.vext.vext_app/wake_lock        → CPU WakeLock (keeps timer alive when screen off)
com.vext.vext_app/alarm_manager    → Doze-safe alarm scheduling
com.vext.vext_app/alarm_events     → EventChannel: Doze alarm fired events
```

---

## 5. What Is Working ✅ vs Not Working ❌

### ✅ Working
| Feature | Notes |
|---|---|
| Firebase Auth (login/signup/logout) | @bmsce.ac.in only. Role selection persists. |
| BLE scanning & advertising | All Android versions tested. Samsung One UI filter bug worked around. |
| BLE duty cycle (idle/session/SOS) | Lock system: service locks override UI preference — Profile tab can't drop active session |
| Attendance auto-marking (online) | Teacher starts session → student auto-marks → appears in Firestore |
| Attendance auto-marking (offline / BLE only) | Student proof → ACK packet → teacher's Drift DB → dashboard shows student even without WiFi |
| SOS trigger & relay | Boost before send; relay nodes boost on SOS receive; RSSI-sorted peer selection |
| Social mesh chat (BLE) | Messages in retry queue; delivered via GATT to nearby peers |
| Social (Firestore fallback) | Messages from non-BLE-range devices arrive via Firestore subscription |
| Foreground service | Keeps BLE scanning alive when screen is off (Android) |
| Doze-mode survival | AlarmManager wakes device during deep Doze to restart BLE |
| Offline-first | All data goes to Drift first; Firebase sync is best-effort |
| Connectivity-aware dashboard | Teacher dashboard auto-switches between Firestore (online) and BLE-ACK (offline) sources |
| FCM push for SOS | Security devices receive push notification when SOS hits Firestore |

### ❌ Not Working / Not Yet Implemented
| Feature | Status | Notes |
|---|---|---|
| Message encryption | Plaintext (Milestone 7) | Field is named `contentEncrypted` but stores plain text in M6 |
| GPS attendance verification | Not active | `gpsLat/gpsLng` stored as null; RSSI is the proximity proof |
| Cross-device HMAC verification | Local only | Student passes token unchanged; real verify is milestone 7 |
| iOS support | Not implemented | iOS config exists but no BLE background mode entitlements |
| Student proof history screen | Stub | Shows current session only; full history is milestone 7 |
| `/test` route | Dev only | `TestScreen` is still in router — remove before final demo if needed |

---

## 6. Physical Device Testing — Step by Step

### Prerequisites (Both Phones)
```
Android 10+ (API 29+) recommended
Bluetooth hardware (not emulator — BLE requires real radio)
Location services: ON
Bluetooth: ON
```

### First Launch — Grant All Permissions
When the app first opens, accept ALL dialogs in this order:
1. **Nearby devices** (BLUETOOTH_SCAN + BLUETOOTH_CONNECT + BLUETOOTH_ADVERTISE) → Allow
2. **Location** → Allow while using app
3. **Notifications** (Android 13+) → Allow
4. These are requested automatically by the app on startup.

### Sign Up / Login
```
Email: anything@bmsce.ac.in   (domain-locked)
Password: min 6 chars
After signup → Role Selection screen appears
Select: Teacher (Phone 1) | Student (Phone 2) | Security (optional Phone 3)
```

### Test 1 — Attendance (the main demo)
```
PHONE 1 (Teacher):
  → Attendance tab → "Teacher Mode" button
  → Enter course ID (e.g. CS101) → "Start Session"
  → Status shows "Broadcasting — CS101"
  → Keep screen on

PHONE 2 (Student):
  → Attendance tab → "Student Mode" button  
  → Status shows "Listening…"
  → Within 30 seconds: status changes to "Marked Present ✓"
  → RSSI shown in dBm (or "GATT" if via direct connection)

TEACHER DASHBOARD shows student appearing:
  → Online (WiFi): appears under "Live — cloud + BLE" badge via Firestore
  → Offline (no WiFi): appears under "BLE-only" badge via ACK packet
```

**Expected time to mark attendance:** 5–15 seconds (BLE GATT path)

### Test 2 — SOS
```
ANY PHONE:
  → SOS tab
  → Hold the red SOS button for 3 seconds
  → Release — "SOS ACTIVE — RELAYING ON MESH" appears
  → GPS coordinates shown (or "GPS unavailable")

OTHER PHONES:
  → SOS tab shows incoming alert card with sender name + timestamp
  → Security role: FCM push notification appears even if app is backgrounded

To cancel: tap CANCEL on the originating phone
```

**Expected time for SOS to reach next phone:** 1–5 seconds (with fixes applied)

### Test 3 — Social Messaging
```
PHONE 1:
  → Social tab → type message → Send

PHONE 2:
  → Social tab → message appears within 5–30 seconds
  → If phones are in BLE range: arrives via GATT relay (~5s)
  → If phones are on same WiFi (not BLE range): arrives via Firestore (~10s)
```

### Test 4 — Offline Attendance (No WiFi)
```
Turn off WiFi on BOTH phones (keep Bluetooth ON)

PHONE 1 (Teacher):
  → Start session as normal
  → Dashboard shows "No network — showing BLE-only results"

PHONE 2 (Student):
  → Is marked present automatically via BLE

PHONE 1 (Teacher):
  → Student appears in dashboard via BLE ACK path (bluetooth icon instead of cloud icon)
  → When WiFi restored: automatically switches back to cloud view
```

---

## 7. BLE Signal Thresholds (For Context During Demo)

```
rssiThresholdAttendance = -85 dBm    ← attendance gate (~15-20m)
rssiMeshMinimum         = -90 dBm    ← mesh relay minimum
rssiThresholdDefault    = -75 dBm    ← general proximity (~8-10m)

Practical meaning:
  -40 to -60 dBm = Excellent (phones side by side)
  -60 to -75 dBm = Good (same room, ~5m)
  -75 to -85 dBm = Acceptable for attendance (same room, ~10-15m)
  Below -90 dBm  = Too weak — mesh will not relay
```

---

## 8. BLE Duty Cycles (How Aggressively BLE Scans)

| Mode | Scan | Sleep | When Active |
|---|---|---|---|
| **SOS** | 100ms | 100ms | SOS triggered (originator + relay nodes) |
| **Session** | 500ms | 500ms | Attendance session running, or any active lane tab |
| **Idle** | 1s | 30s | Profile tab, no active services |

**NEW BEHAVIOUR (post-fix):** The BLE mode is now service-driven, not tab-driven. If a teacher starts an attendance session, BLE stays in session mode even if they navigate to the Profile tab. Visiting Profile no longer silences the mesh.

---

## 9. Debugging Tips During Demo

### BLE indicator in AppBar
- **MESH ON (green):** BLE scanning and advertising is active
- **MESH OFF (grey):** BLE not started (shouldn't happen after login)

### If attendance doesn't mark:
1. Check both phones show MESH ON
2. Check distance (< 10m recommended)
3. Check teacher screen shows "Broadcasting"
4. On student phone: Status should show "Session Detected" → "Marked Present"
5. If stuck on "Listening…" — navigate away and back to Attendance tab

### If SOS doesn't arrive:
1. Check receiving phone's SOS tab is open (or was open recently)
2. Verify BLE is active on receiver (MESH ON)
3. SOS now boosts to 100ms/100ms on ALL phones that receive it
4. If still failing: check logcat for `[BLE]` and `[SOS]` tags

### If social messages don't appear:
1. Messages retry for 30 seconds via BLE (retry queue)
2. After that, falls back to Firestore (needs WiFi)
3. Check `[Social]` logs for "Firestore message from…" to see cloud path

### Logcat filter for demo:
```
adb logcat | grep -E "\[BLE\]|\[SOS\]|\[Social\]|\[Attendance\]|\[SyncEngine\]|\[FGService\]"
```

---

## 10. Known Limitations for the Demo

1. **Encryption is off** — Social messages are plaintext. The field is called `contentEncrypted` in the DB but stores plain text. This is Milestone 7 scope.

2. **Only Android** — iOS config exists but BLE background mode requires different entitlements. Demo on Android phones only.

3. **`/test` route exists** — `TestScreen` is accessible at `/test` path. It's a Milestone 3 debug tool. Not part of the demo flow but still in the router.

4. **First attendance can take ~10s** — First BLE scan cycle after login discovers peers. Subsequent markings are faster (peers already known).

5. **Drift codegen needed** — After the schema change to v2 (unique constraint), you must run:
   ```
   dart run build_runner build --delete-conflicting-outputs
   ```
   Without this, the app compiles but the unique constraint is not enforced. The in-memory `_inProgressSessionIds` guard still prevents duplicates at runtime.

6. **Firestore rules required** — The app assumes Firestore security rules are deployed. If they aren't, proof syncing will fail silently (Drift keeps data safe, sync retries every 10s).
