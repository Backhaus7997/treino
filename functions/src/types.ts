/**
 * Shared TypeScript types for the deleteAccount Cloud Function.
 */

/** Request payload passed by the Flutter client callable. */
export interface DeleteAccountRequest {
  uid: string;
}

/** Response returned on full or partial success. */
export interface DeleteAccountResponse {
  status: "success" | "partial";
  deletedCollections: string[];
  errors: string[];
}

/**
 * Shape of the audit_log/{uid} Firestore document.
 * Admin-only readable/writable — no client rules grant access.
 */
export interface AuditLogEntry {
  uid: string;
  status: "started" | "success" | "partial" | "failed";
  provider: string;
  startedAt?: FirebaseFirestore.Timestamp;
  completedAt?: FirebaseFirestore.Timestamp;
  deletedCollections?: string[];
  errors?: string[];
}

/** Result of a single cascade module. */
export interface CascadeResult {
  collection: string;
  success: boolean;
  error?: string;
}
