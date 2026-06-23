# VEXT — Plan vs. Decisions vs. Current State (2026-06-22, last updated 2026-06-23)

Compiled from: `VEXT_VigilantMesh_Technical_Plan.pdf` (original plan), `VEXT_Master_Tasks.md` + Session Handoffs (decisions made along the way), and a live audit of `/Users/shreshtha/Development/vext` (`git log`/`git status`/`git diff`, file structure, `pubspec.yaml`, `google-services.json`).

## Status Summary — read this before starting the next task

### Done
- **Task #2** — `/test` dev route: decision made, keeping it registered for now (debug tool, not part of the demo flow).
- **Task #3** — 3-phone BLE relay test script: `[Mesh]` RX/TX-relay log lines added to `mesh_service.dart`, full procedure written into `VEXT_TESTING_DEMO_GUIDE.md` §10. **Code is in; physical execution is not** — see "Left" below.
- **Task #4** — GPS geofence for attendance: implemented, self-reviewed (found and fixed a real `_inProgressSessionIds` leak bug — see §3), unit-tested (`test/unit/mesh_packet_test.dart`), and now **verified for real**: you ran `flutter analyze` (0 errors, only pre-existing lints elsewhere) and `flutter test` (53/53 passing — the pre-existing 47 plus the 6 new wire-format tests) on 2026-06-23. Two minor lint infos in the new code (`mesh_packet.dart` unbraced single-line `for` loops) were cleaned up after that run. **Physical GPS verification is still open** — see "Left" below.
- **Task #7** — Social DM scope decision: build real 1:1 messaging, not broadcast-only.
- **Task #9 (Social) — 1:1 E2E-encrypted DM implemented and verified 2026-06-23**: `firestore.rules`/`firestore.indexes.json` updated, `public_keys/{uid}` X25519 directory, tap-name-to-DM + search-by-display-name UI, `DirectMessageScreen` + nested `go_router` route. `flutter analyze` clean (2 minor lints found and fixed) and `flutter test` 53/53 passing, both confirmed locally.
- **Task #6/#11 — `rotatePeerKeys.ts` Cloud Function: re-evaluated 2026-06-23, decided unnecessary — will NOT be built.** Reasoning: private keys never leave the device (`CryptoService` generates them once and keeps them in Android Keystore-backed secure storage) — a server-side Cloud Function has no access to a private key and therefore cannot "rotate" it; only the client can. Public-key "rotation" already happens for free: `PublicKeyDirectoryService.uploadOwnPublicKey()` re-uploads the current public key as an idempotent merge-set on every app session, so if a device ever did generate a new keypair (reinstall, cleared app data) the directory self-corrects on the next launch with no function needed. Peers never hold a long-lived session key to invalidate either — `CryptoService._deriveSharedSecret()` re-derives the ECDH shared secret fresh from each side's *current* public key on every send/receive, and `PublicKeyDirectoryService`'s cache is in-memory-only (cleared on restart). Confirmed `rotatePeerKeys.ts` was never actually written (no file in `functions/src/`, not exported from `functions/src/index.ts`) and the `AppConstants.fnRotatePeerKeys` placeholder constant had zero callers — removed it and replaced with a comment explaining why.

### Left (roughly in the order it makes sense to tackle them)
1. **Task #1 — commit + push, resolve `main`/`origin/main` divergence.** This has been "next step" across multiple sessions now and keeps sliding. It's on you (needs your terminal/git credentials) — I can't do this from the sandbox. Nothing is backed up until it's pushed; that's the single biggest standing risk to the whole project.
2. **Physical-device verification for two already-implemented, already-unit-tested features:**
   - 3-phone BLE relay test — `VEXT_TESTING_DEMO_GUIDE.md` §10 (Tests 5A/5B). Needs 3 real Android phones.
   - GPS geofence — `VEXT_TESTING_DEMO_GUIDE.md` §11 (Tests 6A/6B/6C). Needs real GPS fixes, ideally outdoors (indoor fixes are often low-accuracy and get silently discarded).
3. **Task #8 — verify Firestore rules + FCM token delivery in production.** Confirm deployed rules aren't the "EMERGENCY FALLBACK" fully-open ones, and confirm `users/{uid}.fcmToken` actually populates on a real device.

~~Task #5 (Social message encryption), Task #6/#11 (`rotatePeerKeys.ts`), Task #9 (1:1 DM)~~ — all done; see "Done" above. `rotatePeerKeys.ts` specifically was re-evaluated and decided **unnecessary**, not deferred — nothing left to do there.

### Important notes — read before starting any future task
- **The sandbox has no Flutter SDK.** I cannot compile, lint, or run tests myself — every implementation needs you to run `flutter analyze` / `flutter test` and report back, the way you just did for Task #4. My code review is necessary but not sufficient; treat anything I report as "implemented" as unverified until you've run it.
- **The workflow contract stays the same for every future task:** brainstorm the approach first, implement exactly one task, self-review the diff for hidden bugs, get it tested/verified, update this checklist and `VEXT_TESTING_DEMO_GUIDE.md`, then stop and wait for the next instruction. The self-review step is not optional — it's what caught the `_inProgressSessionIds` leak in Task #4, a bug that `flutter test`'s passing suite would not have caught (no existing test exercises a rejection-then-retry sequence).
- **Two different wire-format compatibility strategies are now in play — don't mix them up:**
  - *Additive, no version bump* (used for the GPS geofence): new optional fields appended at the end of the payload, decoder bounds-checks (`if (offset < payload.length)`) before reading them. Safe specifically because old packets and "new but field-absent" packets are byte-identical, and there's only one decoder in the whole codebase to update.
  - *True version bump* (required for Social DM's recipient field, and likely for the encryption work too): needed whenever an old decoder could otherwise misinterpret new bytes, or a new decoder needs to tell "old packet" apart from "new packet with a default value." Do not default to the additive pattern for DM — an old node that doesn't understand "recipient" would still relay/display a message that wasn't meant for it, which is a correctness problem, not just a compatibility one.
- **Proximity/signal gates in this codebase are deliberately fail-open.** RSSI and GPS both: any permission/signal/timeout failure skips that specific check rather than blocking the user. Keep new proximity-style checks consistent with this — a stricter check should only ever activate when there's positive evidence, never by default.
- **Any new early-return inside `_assembleAndSubmitProof()` (or any method guarded by an "in-progress" set) must release that guard before returning.** This is exactly the bug fixed for the RSSI and GPS gates. Audit every `return` path for this if that method is touched again.
- **Reusable test patterns** (don't reinvent these): `FlutterSecureStorage.setMockInitialValues({})` in `setUp()` for anything touching `CryptoService`; inject `FakeFirebaseFirestore()` via constructor for anything touching Firestore; subscribe to a broadcast stream *before* calling `initialize()` if `initialize()` emits synchronously. The "multiple AppDatabase instances" Drift warning during test runs is expected and benign (each test opens its own isolated in-memory DB) — not a bug worth chasing.

---

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
| Attendance proof | RSSI threshold **+** GPS geofence, both must pass (plan §7.2) | RSSI + GPS geofence (50 m default radius), RSSI-only fallback when either side has no GPS fix | Was RSSI-only by deviation; **2026-06-22: decision reversed; implemented 2026-06-23 (Task #10) — see §3 below** |
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
- [x] GPS attendance verification — **implemented and `flutter analyze`/`flutter test`-verified 2026-06-23, Task #10** (was RSSI-only; reversed 2026-06-22). Still needs physical-device verification — see §3 below and `VEXT_TESTING_DEMO_GUIDE.md` §11.
- [ ] Cross-device HMAC verification (local-only)
- [ ] iOS support
- [ ] Student proof history screen (stub — current session only)
- [ ] `/test` dev route still registered in `app_router.dart` — decide whether to strip before final build
- [x] `rotatePeerKeys.ts` Cloud Function — **re-evaluated 2026-06-23, decided unnecessary, will NOT be built** (was "scheduled to implement, Task #11" as of 2026-06-22, reversed once #9's encryption design — long-term X25519 identity keys, fresh ECDH per message, never-leaves-device private keys — made clear there's nothing left for a server-side function to rotate). See the "Done" section above for full reasoning. `AppConstants.fnRotatePeerKeys` (unused placeholder, zero callers) removed.
- [x] Full unit test suite — **ran locally 2026-06-22, found broken across three separate issues, all now fixed.** `attendance_service_test.dart` (47 tests) failed in three successive rounds as each fix exposed the next:
  1. 12 tests: `MissingPluginException` on `flutter_secure_storage`'s MethodChannel — `CryptoService.initialize()` has no platform-channel backing under plain `flutter test`. Fixed by adding `FlutterSecureStorage.setMockInitialValues({})` in a file-level `setUp()` (same pattern already used in `crypto_service_test.dart`).
  2. 8 tests: `[core/no-app] No Firebase App '[DEFAULT]' has been created` — `AttendanceService` falls back to the real `FirebaseFirestore.instance` when no `firestore` is injected, and `Firebase.initializeApp()` never runs under the test runner. Fixed by adding `fake_cloud_firestore: ^3.1.0` as a dev dependency (matches the pinned `cloud_firestore: ^5.4.4`) and passing `firestore: FakeFirebaseFirestore()` at all 3 `AttendanceService(...)` construction sites in the test file.
  3. 1 test ("status starts as idle"): timeout — `attendanceStatusStream` is a broadcast stream and `initialize()` emits the idle status synchronously; the test's shared `_buildService()` helper calls `initialize()` before the test could attach a listener, so the one-and-only idle event was lost. Fixed by building that one test's service manually and subscribing to the stream before calling `initialize()`.
  **Confirmed green locally 2026-06-22: 47/47 passing.** Coverage % still unmeasured.

## 3. Findings from physical-device testing (2026-06-22) — surfaced by hands-on testing, not in the original audit

These came directly from running the app on real phones, not from reading docs. Confirmed against actual source (`mesh_packet.dart`, `social_service.dart`, `mesh_service.dart`, `ble_provider.dart`), not just `VEXT_TESTING_DEMO_GUIDE.md`.

- [ ] **No username search / no direct (1:1) messaging in Social.** Confirmed in code: `MeshPacket` has no recipient field (type/ttl/packet_id/timestamp/sender_uid/payload only), `message_records` (Drift) has no `recipient_uid` column, and the Firestore path is hardcoded to `messages/broadcast/records/{messageId}` — "broadcast" is not a placeholder, it's the only thread. Every Social message currently goes to every device in BLE range plus every device subscribed to that one Firestore collection — it's a single open group channel, not addressed chat. Building real DM would need: a recipient field added to the wire packet (version bump, since old/new packets would otherwise misparse), a recipient column in Drift + Firestore, a user-directory lookup (no username field exists on `users/` either — only email/name/role), and a relay-logic change so a node still forwards packets not addressed to it (otherwise relay breaks for everyone else). This is a real feature to scope, not a small fix.
- [x] **Multi-hop BLE relay test script prepared (2026-06-23).** Added two `debugPrint` lines to `mesh_service.dart` (tag `[Mesh]`: an RX line in `_handleIncomingPacket`, a TX-relay line in `_scheduleRelay`) so a relay hop is directly observable in `adb logcat` instead of being an inference from UI behaviour alone. Wrote the full 3-phone procedure into `VEXT_TESTING_DEMO_GUIDE.md` §10 — covers a pre-check to rule out A/C having a direct link (the main false-positive risk), then two sub-tests: 5A (SOS, hot/0ms-delay path) and 5B (Social message, cold/500ms-duty-cycle path, WiFi off to rule out Firestore masking a broken relay). **Still open: physical execution.** This requires 3 real phones and cannot be run from this sandbox — the gossip/TTL mechanism in `_scheduleRelay` (forwards any non-expired packet regardless of type) is implemented and code-reviewed, but the actual 3-hop path is still unverified until someone runs §10 and fills in the result log.
- [x] **GPS geofence for attendance implemented (2026-06-23, Task #10).** Wire-format extension in `mesh_packet.dart`: `MeshPacket.attendance()` now optionally appends a 1-byte presence flag + 16 bytes (2× float64 LE) carrying the teacher's GPS fix, AFTER the existing sessionId+hmacToken fields — additive, no version bump (old packets, or new packets with no GPS, decode identically; `decodeAttendancePayload()`'s extra-field read is bounds-checked via `if (offset < payload.length)`). `AttendanceService.startSession()` captures the teacher's GPS fix (same Geolocator pattern as `sos_service.dart`: check/request permission, 3 s timeout, discard if accuracy > `AppConstants.gpsMinAccuracyMetres`) and stores it on the broadcast `AttendanceSession`; `_assembleAndSubmitProof()` captures the student's own fix the same way and rejects with a "Outside the classroom geofence" error if `Geolocator.distanceBetween(...) > AppConstants.geofenceRadiusDefault` (50 m). Fail-open by design on both sides — if either the teacher or the student has no usable GPS fix, the geofence check is skipped entirely for that session/student and RSSI remains the sole gate (matches the project's established "GPS never blocks" precedent from the SOS lane). `AttendanceProofs.gpsLat/gpsLng` are now populated with the student's real fix instead of always `null`; `firebase_sync_engine.dart` already passed these through generically, no change needed there. **Self-found-and-fixed bug during the mandated post-implementation review:** the pre-existing RSSI-rejection early-return in `_assembleAndSubmitProof()` never released `_inProgressSessionIds`, so a single weak-signal rejection permanently blocked all future retries for that session (Guard 2 in `_onAttendancePacket()` silently short-circuits forever with no further error shown) — fixed by adding `_inProgressSessionIds.remove(sessionId)` immediately before that `return`, and applied proactively to the new GPS-rejection path as well. Pure-Dart wire-format round-trip tests (geofence round-trip, backward-compat no-geofence decode, negative-coordinate sign bits, non-attendance-packet null return) added in `test/unit/mesh_packet_test.dart` — these run with zero platform-channel dependency. **Verified for real on 2026-06-23:** ran `flutter analyze` (0 errors — 2 minor style infos in the new factory code, since fixed) and `flutter test` (53/53 passing, the pre-existing 47 plus these 6 new tests) outside the sandbox. **Still open: physical-device verification** (cannot capture/compare real GPS fixes from this sandbox) — manual procedure written up in `VEXT_TESTING_DEMO_GUIDE.md` §11 (Tests 6A/6B/6C), not yet run.
- [ ] **Encryption — re-raised, decision may need revisiting.** Still plaintext (`SocialService.sendMessage()`: `contentEncrypted: trimmed, // Plaintext in M6; encrypted in M7`), matching the already-documented M7 deferral. This was previously decided as "ship as documented limitation," but it's worth explicitly re-confirming that decision now that the two gaps above are on the table — encryption, DM, and relay verification may compete for the same remaining time.

**Decision (2026-06-22):** encryption, GPS geofence, and `rotatePeerKeys.ts` are now all moving to **implement**, reversing the earlier "ship as documented limitation" call for these three M7 items. Tracked as Tasks #9 (encryption), #10 (GPS geofence), #11 (`rotatePeerKeys.ts`). DM/addressing (Task #8) is still an open scope question — not yet decided.

**Follow-up decision (2026-06-23):** of those three, `rotatePeerKeys.ts` (#11) is reversed back to **won't build** — re-evaluated after #9 (encryption) and the DM feature shipped, and the settled design leaves it no job to do. See the "Done" section above. Encryption (#9) and GPS geofence (#10) stand as implemented.

## 4. Security/ops housekeeping to verify before final submission

- [ ] Confirm currently-deployed `firestore.rules` are the **real** rules, not the "EMERGENCY FALLBACK" fully-open rules documented in `VEXT_Session10_Handoff.md` (that doc explicitly warns "revert after the demo" — never confirmed reverted in writing).
- [ ] Firestore rules were deployed 2026-06-04 per Session 10 handoff — `VEXT_Master_Tasks.md` (written 2026-06-02) still lists rules-deploy as a pending "immediate action" and names today, 2026-06-22, as an expiry date. That's a stale doc, not a live deadline — but worth a 2-minute Console check to be sure nothing has actually expired since.
- [ ] FCM token delivery on physical devices was still "untested" as of Session 10 (bug B2) — confirm `users/{uid}.fcmToken` populates on a real device before treating SOS push as done.

## 5. Suggested order of operations to "finish the Android version"

1. Resolve the uncommitted diff: fix the `minSdk` regression, verify Dart↔Kotlin platform channel names match post-rename, then commit.
2. Reconcile `main` vs `origin/main` divergence (pull/rebase) before pushing.
3. Run a clean `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test` locally (not possible from this sandbox — no Flutter SDK here) to catch anything the rename broke.
4. Physical-device smoke test all 3 lanes per `VEXT_TESTING_DEMO_GUIDE.md` §6, **plus the 3-phone relay test now written up in §10 of that guide (Tests 5A/5B)** — this should happen before treating DM/encryption as done, since the answer changes the priority (a broken relay is a bug to fix regardless; DM/encryption are scope decisions already made).
5. Decide scope for remaining M7 items (encryption, GPS check, `rotatePeerKeys.ts`, `/test` route removal) **and** the two new findings (DM/addressing, relay verification) — ship as documented limitations or implement, your call given the timeline.
6. Update `VEXT_TESTING_DEMO_GUIDE.md` package-name references once the rename is committed.

## Open questions for you

- Resolved: package rename — finish it properly (`com.example.vext` → `com.vext.vext_app`), not revert.
- Resolved: Flutter SDK — you have it locally; sandbox setup was attempted and is not possible here (official Flutter Linux builds are x64-only, this sandbox is aarch64, no root to emulate). You'll need to run `flutter analyze`/`test`/`build` yourself; I can't self-verify compilation from here.
- Resolved (2026-06-22): M7 deferred items — encryption, GPS geofence, and `rotatePeerKeys.ts` are now all **implement**, not document-as-limitation. See Tasks #9–11.
- New: do you want to scope and build username search + direct messaging for Social, or keep it as a documented limitation (broadcast-only) for this submission? Still open.
- New: after the 3-phone relay test (script ready, `VEXT_TESTING_DEMO_GUIDE.md` §10 — you still need to run it on real phones) — if it fails, fix it before anything else, since it's the core mesh claim.
