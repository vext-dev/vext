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
adb logcat | grep -E "\[BLE\]|\[Mesh\]|\[SOS\]|\[Social\]|\[Attendance\]|\[SyncEngine\]|\[FGService\]"
```

---

## 10. 3-Phone Mesh Relay Verification (A → B → C)

**Why this test exists:** every test in §6 above uses two phones in direct
BLE range. That proves point-to-point delivery, not relay. The mesh's actual
value proposition — a node forwarding a packet on behalf of two nodes that
can't hear each other — has never been physically confirmed. This test
isolates and proves (or disproves) that specific behaviour.

Two log lines were added to `mesh_service.dart` for this test (tag `[Mesh]`,
filterable with `adb logcat | grep "\[Mesh\]"`):
- `[Mesh] RX  MeshPacket(id: xxxxxxxx…, type: …, ttl: N, sender: ssss …) rssi=R` — logged on receipt of any full (non-advertisement) packet, on every phone that receives it.
- `[Mesh] TX-relay MeshPacket(id: xxxxxxxx…, …, ttl: N-1, …) (received at ttl N)` — logged immediately before a phone re-broadcasts a packet it received, on the relaying phone only.

The same `id` prefix appearing in an RX line on Phone C, after an RX→TX-relay
pair with that same `id` on Phone B, is unambiguous proof of a 3-hop path. If
Phone C's RX line never appears: check Phone B's logs to see whether it
received but never relayed (TTL/backoff/GATT issue) or never received at all
(A↔B link issue, or B was duty-cycle asleep).

### Setup
```
3 Android phones, BLE hardware (no emulators).
Label them:
  A = originator
  B = middle / relay
  C = target
Run `adb devices` and note each phone's serial so you can run
`adb -s <serial> logcat` separately per phone (3 terminal windows/tabs).
```

### Pre-check — confirm B is actually required (do this before trusting any result)
A false pass (A and C exchanging packets via a direct link, with B doing
nothing) is the main risk here — rule it out first.
```
1. Position A and C far apart / behind a wall; position B roughly between
   them, within normal BLE range (~5-10 m) of both A and C.
2. Turn Bluetooth OFF on Phone B only (A and C stay on).
3. Send a Social message from A (procedure in Test 5B below).
4. Confirm it does NOT arrive on C within 30 s, and C's logcat shows no
   `[Mesh] RX` line with that message's id.
   - If it DOES arrive: A and C have a direct link — move them further apart
     and repeat this pre-check until step 4 passes.
5. Turn Bluetooth back ON on Phone B. Wait ~10 s for B to re-advertise and
   for A/C to discover it before running the real tests below.
```
Topology is now confirmed: A↔B and B↔C are live links, A↔C is not.

### Test 5A — SOS relay (hot path, 0 ms relay delay)
SOS is the scenario the code comments explicitly call out as a known risk
(`mesh_service.dart`, `onSosPacketReceived`: a relay node must boost its scan
rate immediately on receipt or multi-hop delivery can take 30+ seconds).
```
On all 3 phones: WiFi OFF, Bluetooth ON, SOS tab open (keeps all three in
"session"-equivalent duty cycle, not idle).

PHONE A: Hold the SOS button 3 s → release. "SOS ACTIVE — RELAYING ON MESH."

PHONE B logcat — expect within ~1-2 s:
  [Mesh] RX  MeshPacket(id: <X>, type: PacketType.sos, ttl: 255, ...
  [Mesh] TX-relay MeshPacket(id: <X>, ..., ttl: 254, ...) (received at ttl 255)

PHONE C logcat — expect within ~1-3 s of B's TX-relay line:
  [Mesh] RX  MeshPacket(id: <X>, type: PacketType.sos, ttl: 254, ...

PHONE C UI: SOS tab shows an incoming alert card from A's name, within ~5 s
of A releasing the button.
```
**Pass:** the same `id` (8-char prefix) appears in B's RX+TX-relay lines and
C's RX line, ttl decremented by exactly 1, and C's SOS tab shows the alert.
**Fail modes to distinguish:** id on B's RX but never B's TX-relay (relay
scheduling/broadcast bug) vs. never appears on B at all (A↔B link issue,
re-check pre-check setup) vs. on B's TX-relay but never C's RX (B↔C link
issue, or C was duty-cycle asleep).

### Test 5B — Social message relay (cold path, idle-adjacent duty cycle)
Harder case: Social messages get no scan-rate boost like SOS does, so a relay
phone caught mid-sleep when the packet arrives is a realistic failure mode.
```
On all 3 phones: WiFi OFF (forces BLE-only — otherwise Firestore could
silently deliver the message and mask a broken relay), Bluetooth ON, Social
tab open on all three (keeps 500 ms/500 ms "session" duty cycle — do NOT run
this from the Profile tab, that drops to idle 1 s/30 s and risks a false
negative purely from B being asleep when the packet arrives).

PHONE A: Social tab → type a distinctive message (e.g. "RELAY-TEST-1") → Send.

PHONE B logcat — expect within ~1 s:
  [Mesh] RX  MeshPacket(id: <Y>, type: PacketType.message, ttl: 7, ...
  [Mesh] TX-relay MeshPacket(id: <Y>, ..., ttl: 6, ...) (received at ttl 7)
  (TX-relay lands 50-500 ms after RX — random backoff, AppConstants.backoffBaseMs/backoffMaxMs)

PHONE C logcat — expect:
  [Mesh] RX  MeshPacket(id: <Y>, type: PacketType.message, ttl: 6, ...

PHONE C UI: "RELAY-TEST-1" appears in the Social chat within ~5-10 s of send.
```
**Pass:** same `id` prefix across B's RX/TX-relay and C's RX, ttl 7→6,
message text visible on C. **Optional stress variant:** repeat with all
three phones left on the Profile tab (idle duty cycle) to see how much
latency the 30 s sleep window adds — informational, not a pass/fail
requirement.

### Result log (fill in after running)
```
Date:                 Devices (model / Android version):
Test 5A (SOS):    PASS / FAIL    notes:
Test 5B (Social): PASS / FAIL    notes:
```

---

## 11. GPS Geofence Verification (Attendance, Milestone 7)

**What changed:** the teacher's device now captures a GPS fix when a session
starts (`AttendanceService.startSession()`) and broadcasts it as part of the
attendance packet (wire-format extension in `mesh_packet.dart` — additive,
no version bump, old packets without GPS still decode correctly). The
student's device captures its own GPS fix when assembling a proof
(`_assembleAndSubmitProof()`) and rejects the proof if the two fixes are more
than `AppConstants.geofenceRadiusDefault` (50 m) apart.

**This cannot be verified from the sandbox** — it requires real device GPS
hardware and an actual physical location, unlike the wire-format encode/decode
logic itself (covered by `test/unit/mesh_packet_test.dart`, pure Dart, no
platform channel).

**Fail-open design — GPS never blocks attendance outright:**
- If the teacher's device has no GPS fix at session start (denied permission,
  location services off, indoors with no fix within 3 s) → the attendance
  packet carries no geofence center → every student's geofence check is
  skipped for that entire session → RSSI is the sole gate (identical to
  pre-Milestone-7 behaviour).
- If a given student's device has no GPS fix when marking attendance → that
  student's own geofence check is skipped → RSSI is the sole gate for that
  student, even if the teacher's packet does carry a geofence center.
- The geofence is an *additional, stricter* check that only applies when
  **both** sides have a usable fix (accuracy ≤ `AppConstants.gpsMinAccuracyMetres`,
  50 m) — this reconciles the plan's "RSSI + GPS, both must pass" requirement
  without regressing the RSSI-only fallback the project already depends on
  for GPS-denied/indoor devices.

### Setup
```
2 Android phones (Teacher + Student), Location services ON on both,
Location permission granted to the app ("while using app" or "always").
Outdoors or near a window recommended — GPS fixes indoors can be slow or
low-accuracy (> 50 m), which causes the fix to be silently discarded (see
"Discard low-quality fixes" comment in startSession()) and the geofence
check to be skipped for that side, same as no fix at all.
```

### Test 6A — Inside the geofence (expected: PASS as normal)
```
PHONE 1 (Teacher): Attendance tab → Teacher Mode → Start Session.
PHONE 2 (Student): within ~50 m of Phone 1 → Student Mode.

Expected: marks "Present" as usual within 5-15 s. No behavioural change
visible — this confirms the geofence gate does not introduce a false
rejection for a student who is actually in range.
```

### Test 6B — Outside the geofence (expected: REJECTED with a geofence error)
```
This needs the student's phone to have a real GPS fix that is genuinely
> 50 m from the teacher's, while still being within BLE range (BLE can reach
further than 50 m outdoors with a clear line of sight) — e.g. teacher and
student in adjacent rooms/across a large open area/across a car park, NOT
just both phones sitting on the same desk.

PHONE 1 (Teacher): Start Session as in 6A.
PHONE 2 (Student): Student Mode, positioned > 50 m away (confirm via Google
Maps or similar on a third device) but still close enough for BLE to connect.

Expected: status shows an error — "Outside the classroom geofence (NNN m
away, limit 50 m). Move closer." — instead of "Marked Present ✓". Walking
the student phone closer (< 50 m) and waiting for the next 5 s re-broadcast
should then allow it to mark present normally.
```

### Test 6C — Retry-after-rejection (regression check for the
`_inProgressSessionIds` leak bug found and fixed during implementation)
```
Immediately after Test 6B's rejection, walk Phone 2 to within the geofence
(< 50 m) WITHOUT restarting the session or the app.

Expected: within one re-broadcast cycle (~5 s), Phone 2 marks "Present ✓"
normally. If it stays stuck on "Listening…" / never retries, that is a
regression of the bug fixed in `_assembleAndSubmitProof()` (the RSSI/GPS
rejection paths must release `_inProgressSessionIds`, not just the
try/finally success/failure paths) — check that fix is still in place.
```

### Result log (fill in after running)
```
Date:                 Devices (model / Android version):
Test 6A (in range):      PASS / FAIL    notes (distance, accuracy):
Test 6B (out of range):  PASS / FAIL    notes (measured distance, error shown?):
Test 6C (retry after rejection): PASS / FAIL    notes:
```

---

## 12. Known Limitations for the Demo

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

7. **GPS geofence requires a real outdoor-ish fix on both sides** — indoor/low-accuracy fixes (> 50 m accuracy) are silently discarded, which falls back to RSSI-only for that session/student rather than failing the demo. See §11 for the manual test procedure (not run from this sandbox — needs real device GPS).
