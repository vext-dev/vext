"use strict";
/**
 * VEXT VigilantMesh — Firebase Cloud Functions entry point
 *
 * All functions are exported from their own modules and re-exported here.
 * firebase deploy --only functions
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
exports.aggregateAttendance = exports.handleSOSAlert = void 0;
const admin = __importStar(require("firebase-admin"));
// Initialize the Admin SDK once here — all modules share this instance.
admin.initializeApp();
// ── Lane C — SOS ──────────────────────────────────────────────────────────────
var handleSOSAlert_1 = require("./handleSOSAlert");
Object.defineProperty(exports, "handleSOSAlert", { enumerable: true, get: function () { return handleSOSAlert_1.handleSOSAlert; } });
// ── Lane A — Attendance aggregation ───────────────────────────────────────────
var aggregateAttendance_1 = require("./aggregateAttendance");
Object.defineProperty(exports, "aggregateAttendance", { enumerable: true, get: function () { return aggregateAttendance_1.aggregateAttendance; } });
//# sourceMappingURL=index.js.map