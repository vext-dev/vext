"use strict";
/**
 * handleSOSAlert — VEXT VigilantMesh Cloud Function
 *
 * Triggered: Firestore onCreate on sos_events/{sosId}
 *
 * Flow:
 *   1. Read the new SOS document (senderUid, latitude, longitude, timestamp).
 *   2. Query the `users` collection for all documents where role == 'security'.
 *   3. Collect every non-empty fcmToken field from those documents.
 *   4. Send an FCM multicast push notification to all security tokens.
 *   5. Log success / failure counts; do NOT throw on partial FCM failure
 *      (some tokens may be stale — this is expected and should not block).
 *
 * M5 exit criterion: FCM push arrives on a security device in < 5 seconds
 * from the moment the student triggers SOS. End-to-end path:
 *   Student device → Drift → FirebaseSyncEngine → Firestore → this function
 *   → FCM → Security device notification
 *
 * Deploy:
 *   cd functions && npm install && firebase deploy --only functions:handleSOSAlert
 *
 * Firestore rules reminder:
 *   sos_events/{sosId} must be writable by authenticated users
 *   (rules expire 2026-06-22 — write permanent rules before Milestone 7)
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.handleSOSAlert = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
// admin.initializeApp() is called once in index.ts — not here.
// ── Firestore collection names (mirrors AppConstants) ─────────────────────────
const FS_USERS = 'users';
const FS_SOS_EVENTS = 'sos_events';
const ROLE_SECURITY = 'security';
// ── Notification copy ─────────────────────────────────────────────────────────
const NOTIF_TITLE = '🚨 SOS Emergency Alert';
// ── handleSOSAlert ────────────────────────────────────────────────────────────
// Keep one warm instance to eliminate the 10-12s cold start observed in M5 testing.
// Cost: ~$1.44/month (1 instance × 256 MB × 730 hr). Acceptable for safety-critical path.
const _sosHandlerOptions = {
    region: 'asia-south1',
    minInstances: 1,
    memory: '256MiB',
    timeoutSeconds: 30,
};
exports.handleSOSAlert = (0, firestore_1.onDocumentCreated)({ document: `${FS_SOS_EVENTS}/{sosId}`, ..._sosHandlerOptions }, async (event) => {
    const snap = event.data;
    if (!snap) {
        console.warn('handleSOSAlert: empty snapshot, skipping');
        return;
    }
    const sosId = event.params.sosId;
    const data = snap.data();
    const senderUid = data.senderUid ?? 'unknown';
    const latitude = data.latitude ?? 0;
    const longitude = data.longitude ?? 0;
    const hasLocation = latitude !== 0 || longitude !== 0;
    const locationText = hasLocation
        ? `Location: ${latitude.toFixed(5)}, ${longitude.toFixed(5)}`
        : 'Location unavailable';
    console.log(`handleSOSAlert triggered: sosId=${sosId} sender=${senderUid} ` +
        `lat=${latitude} lng=${longitude}`);
    // ── 1. Fetch all security-role users ────────────────────────────────────
    const db = admin.firestore();
    let securityUsersSnap;
    try {
        securityUsersSnap = await db
            .collection(FS_USERS)
            .where('role', '==', ROLE_SECURITY)
            .get();
    }
    catch (err) {
        console.error('handleSOSAlert: failed to query security users', err);
        return;
    }
    if (securityUsersSnap.empty) {
        console.log('handleSOSAlert: no security users found, nothing to notify');
        return;
    }
    // ── 2. Collect FCM tokens ────────────────────────────────────────────────
    const tokens = [];
    securityUsersSnap.forEach((doc) => {
        const userData = doc.data();
        const token = userData.fcmToken;
        if (token && token.trim().length > 0) {
            tokens.push(token.trim());
        }
    });
    if (tokens.length === 0) {
        console.log('handleSOSAlert: security users found but none have fcmToken, skipping');
        return;
    }
    console.log(`handleSOSAlert: sending FCM to ${tokens.length} security device(s)`);
    // ── 3. Send multicast FCM push ───────────────────────────────────────────
    const message = {
        tokens,
        notification: {
            title: NOTIF_TITLE,
            body: `Emergency from ${senderUid.substring(0, 8)}… — ${locationText}`,
        },
        data: {
            // Raw string data for the app to deep-link or handle programmatically.
            type: 'sos',
            sosId,
            senderUid,
            latitude: String(latitude),
            longitude: String(longitude),
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'vext_sos_channel',
                priority: 'max',
                defaultSound: true,
                defaultVibrateTimings: true,
                // Red color to match the SOS UI (#EF4444)
                color: '#EF4444',
                icon: 'ic_sos_notification',
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: 'default',
                    badge: 1,
                    contentAvailable: true,
                },
            },
            headers: {
                'apns-priority': '10',
            },
        },
    };
    try {
        const response = await admin.messaging().sendEachForMulticast(message);
        const successCount = response.responses.filter((r) => r.success).length;
        const failCount = response.responses.length - successCount;
        console.log(`handleSOSAlert: FCM sent — ${successCount} success, ${failCount} failed`);
        // Log individual failures for token cleanup (stale tokens are common).
        if (failCount > 0) {
            response.responses.forEach((r, idx) => {
                if (!r.success) {
                    console.warn(`handleSOSAlert: token[${idx}] failed — ` +
                        `${r.error?.code}: ${r.error?.message}`);
                }
            });
        }
    }
    catch (err) {
        // Catch-all — do not rethrow; a partial FCM failure should not cause
        // the Firestore trigger to retry (which would re-send to ALL tokens).
        console.error('handleSOSAlert: FCM sendEachForMulticast threw', err);
    }
});
//# sourceMappingURL=handleSOSAlert.js.map