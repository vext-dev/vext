# VEXT — Step-by-Step Guide: Task #2 (Physical-Device Tests) & Task #8 (Firestore Rules + FCM)

Companion to `VEXT_FINAL_CHECKLIST.md`. Written 2026-06-23. Covers the two
remaining tasks that don't need a git terminal — they need real phones and
the Firebase Console instead. Follow each part top to bottom; don't skip
the pre-checks, they exist because of specific bugs already found in this
project.

---

## Part 1 — Task #2: Physical-Device Verification

Two features are implemented and unit-tested in code, but have never been
run on real hardware. This part proves (or disproves) that they actually
work outside a test file.

### What you need before starting
- 3 Android phones with Bluetooth hardware (no emulators — BLE doesn't work in
  the emulator).
- The VEXT app installed and signed in on all 3 phones.
- A computer with `adb` installed, USB cables (or wireless adb) to all 3
  phones at once.
- For the GPS test specifically: 2 of those phones, with Location services
  ON and location permission granted to the app, ideally outdoors or near a
  window (indoor GPS fixes are often too inaccurate and get silently
  ignored — more on this below).

### Step 1 — Label your phones and open 3 terminal windows
```
adb devices
```
Note the serial number of each phone. Label them on a sticky note or in
your head:
- **Phone A** = originator
- **Phone B** = middle phone / relay
- **Phone C** = target

Open 3 terminal tabs, one per phone, and run this in each (swap in that
phone's serial):
```
adb -s <serial> logcat | grep -E "\[BLE\]|\[Mesh\]|\[SOS\]|\[Social\]|\[Attendance\]|\[SyncEngine\]|\[FGService\]"
```
Leave all 3 running for the whole test — you'll be reading them live.

### Step 2 — Pre-check: prove B is actually needed (do this first, always)
This is the single most important step. If you skip it, you can get a
"pass" that's actually meaningless — A and C might just be talking directly
to each other with B doing nothing.

1. Position Phone A and Phone C far apart, or with a wall between them.
   Position Phone B roughly in the middle, within normal BLE range
   (~5-10 m) of both A and C.
2. Turn Bluetooth **OFF** on Phone B only. Leave A and C's Bluetooth on.
3. On Phone A: open the Social tab, type a message, and send it (this is
   the same send action used in Test 5B below).
4. Watch Phone C for 30 seconds.
   - If the message does **NOT** arrive, and Phone C's logcat shows no
     `[Mesh] RX` line for it — good, move to step 5.
   - If the message **DOES** arrive — A and C have a direct BLE link and
     this whole test is invalid. Move the phones further apart and repeat
     from step 1 until step 4 passes with no direct delivery.
5. Turn Bluetooth back **ON** on Phone B. Wait about 10 seconds for B to
   re-advertise and for A and C to discover it again before running the
   real tests below.

Once step 4 passes, you've confirmed: A↔B and B↔C can talk, A↔C cannot.
Any message that now reaches C *must* have gone through B.

### Step 3 — Test 5A: SOS relay (the urgent path)
SOS is the highest-risk case because a relay phone has to react instantly —
there's a specific known risk that if B doesn't boost its scan rate the
moment it receives an SOS packet, delivery to C could take 30+ seconds.

1. On all 3 phones: turn WiFi **OFF**, Bluetooth **ON**, and open the SOS
   tab (this keeps all three phones in their fast "session" duty cycle
   instead of idle).
2. On **Phone A**: press and hold the SOS button for 3 seconds, then
   release. You should see "SOS ACTIVE — RELAYING ON MESH" on screen.
3. Watch **Phone B's** logcat. Within 1-2 seconds you should see two lines
   with the same packet ID (the 8-character prefix after `id:`):
   ```
   [Mesh] RX  MeshPacket(id: <X>, type: PacketType.sos, ttl: 255, ...
   [Mesh] TX-relay MeshPacket(id: <X>, ..., ttl: 254, ...) (received at ttl 255)
   ```
4. Watch **Phone C's** logcat. Within 1-3 seconds of B's TX-relay line, you
   should see:
   ```
   [Mesh] RX  MeshPacket(id: <X>, type: PacketType.sos, ttl: 254, ...
   ```
5. Check **Phone C's screen**: the SOS tab should show an incoming alert
   card with Phone A's name, within about 5 seconds of A releasing the
   button.

**Pass criteria:** the same packet ID appears in B's RX line, B's TX-relay
line, and C's RX line; the ttl number drops by exactly 1 each hop (255 →
254); and C's screen shows the alert.

**If it fails, use this to figure out where:**
| Symptom | Likely cause |
|---|---|
| ID never appears on B at all | A↔B link issue — redo the pre-check setup |
| ID appears on B's RX but never B's TX-relay | Relay scheduling/broadcast bug on B |
| ID appears on B's TX-relay but never C's RX | B↔C link issue, or C was asleep |

### Step 4 — Test 5B: Social message relay (the harder, "cold" path)
This is the tougher case: unlike SOS, Social messages get no scan-rate
boost, so a relay phone caught mid-sleep when the packet arrives is a real
possible failure.

1. On all 3 phones: WiFi **OFF** (this forces BLE-only delivery — with WiFi
   on, Firestore could quietly deliver the message in the background and
   make a broken BLE relay look like it worked), Bluetooth **ON**, and the
   **Social tab open on all three phones**. Important: don't run this from
   the Profile tab — that drops to a slow 1s/30s idle duty cycle and can
   cause a false failure just because B happened to be "asleep."
2. On **Phone A**: in the Social tab, type a distinctive message (e.g.
   `RELAY-TEST-1`) and send it.
3. Watch **Phone B's** logcat. Within about 1 second:
   ```
   [Mesh] RX  MeshPacket(id: <Y>, type: PacketType.message, ttl: 7, ...
   [Mesh] TX-relay MeshPacket(id: <Y>, ..., ttl: 6, ...) (received at ttl 7)
   ```
   The TX-relay line can land anywhere from 50-500 ms after the RX line —
   that's an intentional random delay (collision avoidance), not a bug.
4. Watch **Phone C's** logcat for:
   ```
   [Mesh] RX  MeshPacket(id: <Y>, type: PacketType.message, ttl: 6, ...
   ```
5. Check **Phone C's screen**: `RELAY-TEST-1` should appear in the Social
   chat within 5-10 seconds of sending.

**Pass criteria:** same ID across B's RX/TX-relay and C's RX, ttl drops
7 → 6, and the message text is visible on Phone C.

**Optional (not required for pass/fail):** repeat the whole test with all
three phones left on the Profile tab instead of Social, just to see how
much extra delay the 30-second sleep cycle adds.

### Step 5 — Write down your results
```
Date:                      Devices (model / Android version):
Test 5A (SOS):     PASS / FAIL    notes:
Test 5B (Social):  PASS / FAIL    notes:
```
Add this to `VEXT_TESTING_DEMO_GUIDE.md` §10's result log when you're done.

---

### B. GPS Geofence Test

**What this checks:** when a teacher starts an attendance session, their
phone captures a GPS location and includes it in the broadcast. When a
student marks attendance, their phone captures its own GPS location and the
app rejects the attempt if the two locations are more than 50 metres apart.

**Important — this is a fail-open system, by design.** GPS never blocks
attendance outright:
- If the teacher's phone can't get a GPS fix at session start (permission
  denied, location off, indoors with no fix within 3 seconds) → no geofence
  is sent at all → every student's geofence check is skipped → RSSI
  (Bluetooth signal strength) is the only gate, same as before this feature
  existed.
- If a student's phone can't get a fix → that student's geofence check is
  skipped individually, even if the teacher's session does have one.
- The geofence only actually applies when **both sides** have a fix that's
  accurate to within 50 metres. A low-accuracy fix is treated the same as
  no fix at all and silently ignored.

This matters during testing: if a test doesn't behave as expected, the
first thing to check is whether both phones actually got a good GPS fix —
go outdoors or near a window if you're not sure.

### Step 1 — Setup
- 2 Android phones: one will play Teacher, one will play Student.
- On both: Location services **ON**, and the app has location permission
  ("while using app" or "always" both work).
- Go outdoors, or stand near a window. Indoor fixes are frequently worse
  than 50 m accuracy and get silently discarded — this isn't a bug, it's
  the fail-open design described above, but it will look like "nothing is
  happening" if you don't know to expect it.

### Step 2 — Test 6A: inside the geofence (should work exactly as before)
1. **Phone 1 (Teacher):** Attendance tab → Teacher Mode → Start Session.
2. **Phone 2 (Student):** stand within about 50 m of Phone 1 → Student
   Mode.
3. **Expected result:** marks "Present" within 5-15 seconds, with no
   visible difference from how attendance worked before this feature
   existed. This confirms the new geofence check doesn't cause false
   rejections for students who are genuinely in range.

### Step 3 — Test 6B: outside the geofence (should be rejected with a message)
This one needs real distance — both phones need to be far enough apart on
GPS (more than 50 m) while still close enough for Bluetooth to reach (BLE
can carry much further than 50 m outdoors with a clear line of sight). Good
options: adjacent rooms, across a large open area, or across a car park.
Don't just leave both phones on the same desk — that will not trigger this
test.

1. **Phone 1 (Teacher):** Start Session, same as Test 6A.
2. **Phone 2 (Student):** Student Mode, but positioned more than 50 m away.
   Confirm the actual distance using Google Maps or similar on a third
   device — don't eyeball it.
3. **Expected result:** instead of "Marked Present ✓", you should see an
   error message like "Outside the classroom geofence (NNN m away, limit
   50 m). Move closer."
4. As a quick extra check: walk the student phone to under 50 m and wait
   for the next 5-second re-broadcast — it should then mark present
   normally.

### Step 4 — Test 6C: retry after rejection (checks a specific bug fix)
This test exists because a real bug was found and fixed during
development: a student who got rejected and then moved into range used to
get stuck forever showing "Listening…" instead of being allowed to retry.

1. Immediately after Test 6B's rejection (don't restart the session or the
   app), walk Phone 2 to within the geofence (under 50 m).
2. **Expected result:** within one re-broadcast cycle (about 5 seconds),
   Phone 2 should mark "Present ✓" normally.
3. **If it fails:** if Phone 2 stays stuck on "Listening…" and never
   retries, that's a regression of the bug mentioned above — flag it
   immediately, don't just write it down as a minor issue.

### Step 5 — Write down your results
```
Date:                                Devices (model / Android version):
Test 6A (in range):              PASS / FAIL   notes (distance, accuracy):
Test 6B (out of range):          PASS / FAIL   notes (measured distance, error shown?):
Test 6C (retry after rejection): PASS / FAIL   notes:
```
Add this to `VEXT_TESTING_DEMO_GUIDE.md` §11's result log when you're done.

---

## Part 2 — Task #8: Verify Firestore Rules + FCM Token Delivery in Production

This task has two halves: (A) make sure the security rules that are
*supposed* to be protecting the database are actually the ones deployed,
and (B) make sure push notifications actually reach a real device.

Firebase project ID for this app: `vext-vigilantmesh-57551` (from
`.firebaserc`).

### Part 2A — Deploy the current Firestore rules (do this first)

**Why this step exists:** the `firestore.rules` file in the repo right now
includes the DM (`isDmParticipant`) and `public_keys/{uid}` rules needed
for the new encrypted-messaging feature — but as of this writing those
changes are still uncommitted. Until they're committed *and* deployed, the
live database is running an older ruleset that has no rule at all for
`public_keys/{uid}`, and since the rules file ends in an explicit
deny-everything fallback, that means direct messages and key uploads are
being **rejected outright** in production right now. This isn't a security
gap — it's a "the feature doesn't work yet" gap.

1. Make sure you've already committed the rules changes (see the git
   steps covered separately — `git status` should show `firestore.rules`
   as committed, not modified, before you continue).
2. Install the Firebase CLI if you don't already have it:
   ```bash
   npm install -g firebase-tools
   ```
3. Log in (opens a browser window):
   ```bash
   firebase login
   ```
4. From the repo root, make sure the CLI is pointed at the right project:
   ```bash
   cd /Users/shreshtha/Development/vext
   firebase use vext-vigilantmesh-57551
   ```
5. Deploy just the Firestore rules and indexes (this does **not** touch
   Cloud Functions or hosting, so it's a low-risk, fast deploy):
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
6. You should see `✔ Deploy complete!` in the terminal output.

### Part 2B — Confirm the deployed rules are the right ones

1. Open the [Firebase Console](https://console.firebase.google.com/), select
   the `vext-vigilantmesh-57551` project.
2. Go to **Firestore Database → Rules** tab.
3. Check the "last updated" timestamp at the top — it should match roughly
   when you ran the deploy command in 2A.
4. Scroll through the displayed ruleset and confirm these specifically are
   present (search the page for these strings):
   - `function isDmParticipant(threadId)`
   - `match /public_keys/{uid}`
   - The deny-all catch-all at the very bottom: `match /{document=**} { allow read, write: if false; }`
5. Confirm it does **NOT** contain the old Firebase default test-mode
   pattern: `allow read, write: if request.time < timestamp.date(...)`. If
   you see that anywhere, the rules were never properly replaced and this
   needs immediate attention — that pattern means "anyone can read/write
   anything" until the date it names.

If everything in step 4 is present and step 5's pattern is absent, the
rules are correctly deployed and Task #8's rules half is done.

### Part 2C — Confirm FCM tokens actually populate on a real device

1. On a real Android phone, sign out of the app if currently signed in,
   then sign back in (this forces a fresh token fetch).
2. In the Firebase Console, go to **Firestore Database → Data**, navigate
   to `users/{the signed-in user's uid}`.
3. Confirm the document has a field called `fcmToken` with a long string
   value (not empty, not missing). If it's missing, check that the phone
   has notification permission granted to the app (Android 13+ requires
   this explicitly) and that Google Play Services is up to date on the
   device.
4. **End-to-end check using the SOS flow** (this is the real proof — a
   token existing in Firestore doesn't guarantee the push actually
   arrives):
   - Make sure at least one test account has `role: "security"` in its
     `users/{uid}` document, and that account is signed in on a phone with
     notifications enabled.
   - On a different phone signed in as a student, trigger an SOS (hold the
     SOS button for 3 seconds).
   - Within about 5 seconds, the security phone should receive a push
     notification, even if the VEXT app is in the background or fully
     closed.
   - To confirm what happened server-side, check the Cloud Function logs:
     ```bash
     firebase functions:log --only handleSOSAlert
     ```
     or view them in the Firebase Console under **Functions → Logs**. Look
     for a line like:
     ```
     handleSOSAlert: sending FCM to 1 security device(s)
     handleSOSAlert: FCM sent — 1 success, 0 failed
     ```
     If instead you see `security users found but none have fcmToken,
     skipping`, that means no security-role user currently has a token
     saved — go back to step 1-3 above for that account.
5. **Sign-out cleanup check (optional but good practice):** sign out of
   the app on the test phone, then check `users/{uid}` in the console
   again — the `fcmToken` field should be gone (the app deletes it on
   sign-out). This isn't required for Task #8 to pass, but if it's wrong
   it means a signed-out device could still receive pushes meant for
   whoever signs in next.

### Step — Write down your results
```
Date:
Rules deployed and confirmed correct (2A/2B):     PASS / FAIL   notes:
fcmToken populates in Firestore on real device:   PASS / FAIL   notes:
SOS → push notification end-to-end (< 5s):        PASS / FAIL   notes:
```

---

## When you're done

Update `VEXT_FINAL_CHECKLIST.md`'s "Done" section with the results from
both parts, and move the corresponding "Left" items to "Done." If anything
fails, write down exactly which step failed and what you saw — that's
enough detail to debug from, whether that debugging happens with me or on
your own.
