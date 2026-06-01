/**
 * VEXT VigilantMesh — Firebase Cloud Functions entry point
 *
 * All functions are exported from their own modules and re-exported here.
 * firebase deploy --only functions
 */

import * as admin from 'firebase-admin';

// Initialize the Admin SDK once here — all modules share this instance.
admin.initializeApp();

// ── Lane C — SOS ──────────────────────────────────────────────────────────────
export { handleSOSAlert } from './handleSOSAlert';
