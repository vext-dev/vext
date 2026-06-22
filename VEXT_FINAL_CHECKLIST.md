# VEXT — Plan vs. Decisions vs. Current State (2026-06-22)

Compiled from: `VEXT_VigilantMesh_Technical_Plan.pdf` (original plan), `VEXT_Master_Tasks.md` + Session Handoffs (decisions made along the way), and a live audit of `/Users/shreshtha/Development/vext` (`git log`/`git status`/`git diff`, file structure, `pubspec.yaml`, `google-services.json`).

## 0. Most urgent — uncommitted work sitting in your working tree

Your last commit is still `6b95cc2` (2026-06-07). **Status as of end of 2026-06-22 session: every fix below is done and verified on disk, but NONE of it is committed yet.**

- [x] **Android package rename**: `com.example.vext` → `com.vext.vext_app`. Old Kotlin folder deleted, new one created (`android/app/src/main/kotlin/com/vext/`), `build.gradle.kts` and `AndroidManifest.xml` updated.
- [x] **`minSdk` regression — fixed.** Hardcoded back to `21` in `android/app/build.gradle.kts`.
- [x] **Dart↔Kotlin platform channel names verified consistent** post-rename (`com.vext.vext_app/...` on both sides).
- [x] **`VEXT_TESTING_DEMO_GUIDE.md` package-name references updated** to the new package name.
- [x] **Full unit test suite verified green — 47/47 passing locally** (see §2 below for the three fixes that got it there).
- [ ] **`.git/index.lock` — no longer present** (confirmed gone as of this session), but **nothing has been committed**. `main` is still 2 commits ahead / 2 behind `origin/main` (unmerged) — needs a pull/rebase decision before pushing. The working tree now has even more uncommitted changes than before (the `pubspec.yaml`/`pubspec.lock` test-dependency addition and `attendance_service_test.dart` fixes from this session are on top of the original 32-file diff).
- [ ] **Nothing is safely backed up.** If this machine's working tree were lost, all of the above — rename, minSdk fix, test fixes — disappears. This is the single biggest remaining risk.

**Next step: resolve the `main`/`origin/main` divergence and commit + push everything above (Task #6).**

## 1. Plan vs. what actually shipped — deviations (with reasons, where known)

| Area | Plan said | Actual state | Verdict |
|---|---|---|---|
| Local DB | Isar | Drift (SQLite) | Justified — Isar 3.x incompatible with AGP 8.0+, unfixed upstream since 2023 (documented in `pubspec.yaml` comments) |
| Team | 4–6 people, layer-owned roles | Solo developer, AI-assisted | Major deviation — explains deferred items below (encryption, full test suite, Track 2, iOS) |
| Message encryption (Lane B) | Curve25519 + XSalsa20-Poly1305, "relay nodes carry bytes they cannot read" — core, non-negotiable | Plaintext. Field is literally named `contentEncrypted` but stores plain text | Was deferred to M7; **2026-06-22: decision reversed, now scheduled to implement (Task #9)** |
| Attendance proof | RSSI threshold **+** GPS geofence, both must pass (plan §7.2) | RSSI-only; `gpsLat/gpsLng` stored as null | Was RSSI-only by deviation; **2026-06-22: decision reversed, GPS geofence now scheduled to implement (Task #10)** |
| Cross-device HMAC verify | Implied server/cross-device verification | Local-only; token passed unchanged, real verify deferred to M7 | Matches plan's "M7" framing — not done yet |
| iOS | Phase 2 | Not implemented (no BLE background entitlements) | Matches plan intent, not a deviation |
| SOS unencrypted by design | Explicit, intentional ("CRITICAL DESIGN DECISION") | Matches | No deviation |
| GATT concurrency cap, MTU negotiation, retry/dedup/stream-resub fixes, foreground-service WakeLock/Doze hardening | Not specified at this level of detail | Added during real device testing (Samsung GATT_ERROR 133, OEM background kill lists) | Expected evolution, not a deviation |
| Offline session/proof sync race | Assumed to "just sync" | Race condition found between session-doc sync and proof sync; one-line `.ignore()` fix shipped (Track 1), proper architectural fix (Track 2) explicitly deferred — needs its own session, schema-migration risk | Documented, deliberate scope cut — fine for submission per `VEXT_PROJECT_REPORT.md`'s own recommendation |
| Router | Not specified | `go_router ^17.x` added | Reasonable addition |

## 2. Lane-by-lane: working vs. not (per repo's own `VEXT_TESTING_DEMO_GUIDE.md`, cross-checked against `git diff` — re-verify after a clean build)

**Working:**
- [x] Firebase Auth (domain-locked `@bmsce.ac.in`, role persists)
- [x] BLE scan/advertise across tested Android versions
- [x] Duty-cycle lock system (idle/session/SOS), centrally managed in `home_shell.dart`
- [x] Attendance auto-marking, online and offline (BLE-ACK fallback)
- [x] SOS trigger + relay, RSSI-sorted peer selection, FCM push to Security role
- [x] Social chat via BLE gossip + Firestore fallback for out-of-range peers — **caveat:** this is a single global broadcast channel, not 1:1 messaging, and the multi-hop relay path has never been physically verified. See §3.
- [x] Foreground service + Doze survival (AlarmManager + WakeLock)
- [x] Offline-first writes (Drift first, Firebase best-effort sync)

**Not working / not done:**
- [ ] Message encryption (plaintext, M7) — **now scheduled to implement, Task #9** (was "ship as documented limitation," reversed 2026-06-22)
- [ ] GPS attendance verification (RSSI-only currently) — **now scheduled to implement, Task #10** (reversed 2026-06-22)
- [ ] Cross-device HMAC verification (local-only)
- [ ] iOS support
- [ ] Student proof history screen (stub — current session only)
- [ ] `/test` dev route still registered in `app_router.dart` — decide whether to strip before final build
- [ ] `rotatePeerKeys.ts` Cloud Function — **now scheduled to implement, Task #11** (reversed 2026-06-22); depends on the encryption task's key-exchange design being settled first
- [x] Full unit test suite — **ran locally 2026-06-22, found broken across three separate issues, all now fixed.** `attendance_service_test.dart` (47 tests) failed in three successive rounds as each fix exposed the next:
  1. 12 tests: `MissingPluginException` on `flutter_secure_storage`'s MethodChannel — `CryptoService.initialize()` has no platform-channel backing under plain `flutter test`. Fixed by adding `FlutterSecureStorage.setMockInitialValues({})` in a file-level `setUp()` (same pattern already used in `crypto_service_test.dart`).
  2. 8 tests: `[core/no-app] No Firebase App '[DEFAULT]' has been created` — `AttendanceService` falls back to the real `FirebaseFirestore.instance` when no `firestore` is injected, and `Firebase.initializeApp()` never runs under the test runner. Fixed by adding `fake_cloud_firestore: ^3.1.0` as a dev dependency (matches the pinned `cloud_firestore: ^5.4.4`) and passing `firestore: FakeFirebaseFirestore()` at all 3 `AttendanceService(...)` construction sites in the test file.
  3. 1 test ("status starts as idle"): timeout — `attendanceStatusStream` is a broadcast stream and `initialize()` emits the idle status synchronously; the test's shared `_buildService()` helper calls `initialize()` before the test could attach a listener, so the one-and-only idle event was lost. Fixed by building that one test's service manually and subscribing to the stream before calling `initialize()`.
  **Confirmed green locally 2026-06-22: 47/47 passing.** Coverage % still unmeasured.

## 3. Findings from physical-device testing (2026-06-22) — surfaced by hands-on testing, not in the original audit

These came directly from running the app on real phones, not from reading docs. Confirmed against actual source (`mesh_packet.dart`, `social_service.dart`, `mesh_service.dart`, `ble_provider.dart`), not just `VEXT_TESTING_DEMO_GUIDE.md`.

- [ ] **No username search / no direct (1:1) messaging in Social.** Confirmed in code: `MeshPacket` has no recipient field (type/ttl/packet_id/timestamp/sender_uid/payload only), `message_records` (Drift) has no `recipient_uid` column, and the Firestore path is hardcoded to `messages/broadcast/records/{messageId}` — "broadcast" is not a placeholder, it's the only thread. Every Social message currently goes to every device in BLE range plus every device subscribed to that one Firestore collection — it's a single open group channel, not addressed chat. Building real DM would need: a recipient field added to the wire packet (version bump, since old/new packets would otherwise misparse), a recipient column in Drift + Firestore, a user-directory lookup (no username field exists on `users/` either — only email/name/role), and a relay-logic change so a node still forwards packets not addressed to it (otherwise relay breaks for everyone else). This is a real feature to scope, not a small fix.
- [ ] **Multi-hop BLE relay is unverified.** The gossip/TTL relay mechanism does exist generically in `mesh_service.dart` (`_scheduleRelay` forwards any non-expired packet regardless of type; Social messages get `ttl: 7`, same SeenPackets dedup as SOS). But every documented test (`VEXT_TESTING_DEMO_GUIDE.md` §6, Test 3) is two phones in direct BLE range — there is no record of a 3-phone test where a middle phone is the *only* bridge between the other two. This is the core "VigilantMesh" value proposition and is currently an architectural claim, not a verified one. **Recommended test:** 3 phones, B in range of A and C but A and C never in range of each other; WiFi off on A and C so Firestore can't quietly carry the message instead of BLE; keep all three phones on Attendance/Social/SOS (not Profile) so none of them drop to idle duty cycle (1s scan / 30s sleep) and produce a false negative. Send from A, confirm receipt on C.
- [ ] **Encryption — re-raised, decision may need revisiting.** Still plaintext (`SocialService.sendMessage()`: `contentEncrypted: trimmed, // Plaintext in M6; encrypted in M7`), matching the already-documented M7 deferral. This was previously decided as "ship as documented limitation," but it's worth explicitly re-confirming that decision now that the two gaps above are on the table — encryption, DM, and relay verification may compete for the same remaining time.

**Decision (2026-06-22):** encryption, GPS geofence, and `rotatePeerKeys.ts` are now all moving to **implement**, reversing the earlier "ship as documented limitation" call for these three M7 items. Tracked as Tasks #9 (encryption), #10 (GPS geofence), #11 (`rotatePeerKeys.ts`). DM/addressing (Task #8) is still an open scope question — not yet decided.

## 4. Security/ops housekeeping to verify before final submission

- [ ] Confirm currently-deployed `firestore.rules` are the **real** rules, not the "EMERGENCY FALLBACK" fully-open rules documented in `VEXT_Session10_Handoff.md` (that doc explicitly warns "revert after the demo" — never confirmed reverted in writing).
- [ ] Firestore rules were deployed 2026-06-04 per Session 10 handoff — `VEXT_Master_Tasks.md` (written 2026-06-02) still lists rules-deploy as a pending "immediate action" and names today, 2026-06-22, as an expiry date. That's a stale doc, not a live deadline — but worth a 2-minute Console check to be sure nothing has actually expired since.
- [ ] FCM token delivery on physical devices was still "untested" as of Session 10 (bug B2) — confirm `users/{uid}.fcmToken` populates on a real device before treating SOS push as done.

## 5. Suggested order of operations to "finish the Android version"

1. Resolve the uncommitted diff: fix the `minSdk` regression, verify Dart↔Kotlin platform channel names match post-rename, then commit.
2. Reconcile `main` vs `origin/main` divergence (pull/rebase) before pushing.
3. Run a clean `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test` locally (not possible from this sandbox — no Flutter SDK here) to catch anything the rename broke.
4. Physical-device smoke test all 3 lanes per `VEXT_TESTING_DEMO_GUIDE.md` §6, **plus the 3-phone relay test in §3 above** — this should happen before deciding scope on DM/encryption, since the answer changes the priority (a broken relay is a bug to fix regardless; DM/encryption are scope decisions).
5. Decide scope for remaining M7 items (encryption, GPS check, `rotatePeerKeys.ts`, `/test` route removal) **and** the two new findings (DM/addressing, relay verification) — ship as documented limitations or implement, your call given the timeline.
6. Update `VEXT_TESTING_DEMO_GUIDE.md` package-name references once the rename is committed.

## Open questions for you

- Resolved: package rename — finish it properly (`com.example.vext` → `com.vext.vext_app`), not revert.
- Resolved: Flutter SDK — you have it locally; sandbox setup was attempted and is not possible here (official Flutter Linux builds are x64-only, this sandbox is aarch64, no root to emulate). You'll need to run `flutter analyze`/`test`/`build` yourself; I can't self-verify compilation from here.
- Resolved (2026-06-22): M7 deferred items — encryption, GPS geofence, and `rotatePeerKeys.ts` are now all **implement**, not document-as-limitation. See Tasks #9–11.
- New: do you want to scope and build username search + direct messaging for Social, or keep it as a documented limitation (broadcast-only) for this submission? Still open.
- New: after the 3-phone relay test — if it fails, do you want to debug/fix it before anything else (this is the core mesh claim), regardless of what gets decided on DM/encryption?
