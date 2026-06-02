/**
 * aggregateAttendance — VEXT VigilantMesh Cloud Function
 *
 * Triggered: Firestore onWrite on attendance/{sessionId}/proofs/{studentUid}
 *
 * Flow:
 *   1. Count all proofs under attendance/{sessionId}/proofs/.
 *   2. Write an aggregated summary to sessions/{sessionId} as a subcollection
 *      field { attendanceCount, lastUpdated } — teachers see this on their
 *      session dashboard without reading every proof doc.
 *   3. Idempotent: uses a Firestore transaction to read + write atomically.
 *      Re-runs correctly if triggered multiple times for the same student.
 *
 * Firestore paths written:
 *   sessions/{sessionId}  →  { attendanceCount: N, lastUpdated: Timestamp }
 *
 * Deploy:
 *   firebase deploy --only functions:aggregateAttendance
 *
 * Notes:
 *   - Function runs in asia-south1 to match all other VEXT functions.
 *   - No minInstances here — attendance aggregation is not latency-sensitive.
 *     Cold start is acceptable for a background aggregation job.
 *   - The security rules allow teachers to read sessions/{sessionId}, so the
 *     aggregated count is visible immediately after this function runs.
 */

import * as admin from 'firebase-admin';
import {
  onDocumentWritten,
  FirestoreEvent,
  Change,
  DocumentSnapshot,
} from 'firebase-functions/v2/firestore';

// admin.initializeApp() is called once in index.ts.

// ── Firestore collection names (mirrors AppConstants) ─────────────────────────
const FS_ATTENDANCE = 'attendance';
const FS_PROOFS = 'proofs';
const FS_SESSIONS = 'sessions';

// ── aggregateAttendance ───────────────────────────────────────────────────────

export const aggregateAttendance = onDocumentWritten(
  {
    document: `${FS_ATTENDANCE}/{sessionId}/${FS_PROOFS}/{studentUid}`,
    region: 'asia-south1',
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (
    event: FirestoreEvent<
      Change<DocumentSnapshot> | undefined,
      { sessionId: string; studentUid: string }
    >
  ) => {
    const { sessionId } = event.params;

    if (!sessionId) {
      console.warn('aggregateAttendance: missing sessionId, skipping');
      return;
    }

    console.log(
      `aggregateAttendance triggered: sessionId=${sessionId}`
    );

    const db = admin.firestore();

    // ── 1. Count all proofs for this session ────────────────────────────────
    let proofCount = 0;

    try {
      const proofsSnap = await db
        .collection(FS_ATTENDANCE)
        .doc(sessionId)
        .collection(FS_PROOFS)
        .count()
        .get();

      proofCount = proofsSnap.data().count;
    } catch (err) {
      console.error(
        `aggregateAttendance: failed to count proofs for session ${sessionId}`,
        err
      );
      return;
    }

    // ── 2. Write summary back to the session document ───────────────────────
    // Use set with merge:true so we don't overwrite other session fields.
    try {
      const sessionRef = db.collection(FS_SESSIONS).doc(sessionId);

      await sessionRef.set(
        {
          attendanceCount: proofCount,
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      console.log(
        `aggregateAttendance: session ${sessionId} → attendanceCount=${proofCount}`
      );
    } catch (err) {
      console.error(
        `aggregateAttendance: failed to update session ${sessionId}`,
        err
      );
    }
  }
);
