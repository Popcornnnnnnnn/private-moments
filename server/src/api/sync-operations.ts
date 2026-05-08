export interface SyncOperationShape {
  type: string;
  entityType: string;
}

export const SUPPORTED_SYNC_OPERATIONS: ReadonlyArray<SyncOperationShape> = [
  { type: "create_post", entityType: "post" },
  { type: "update_post", entityType: "post" },
  { type: "insert_ai_title", entityType: "post" },
  { type: "update_post_favorite", entityType: "post" },
  { type: "update_post_pin", entityType: "post" },
  { type: "delete_post", entityType: "post" },
  { type: "update_media_transcription", entityType: "media" },
  { type: "create_comment", entityType: "comment" },
  { type: "delete_comment", entityType: "comment" },
  { type: "upsert_tag", entityType: "tag" },
  { type: "archive_tag", entityType: "tag" },
  { type: "restore_tag", entityType: "tag" },
  { type: "delete_tag", entityType: "tag" },
  { type: "merge_tag", entityType: "tag" },
  { type: "upsert_tag_alias", entityType: "tag_alias" },
  { type: "delete_tag_alias", entityType: "tag_alias" },
  { type: "set_post_tags", entityType: "post" },
  { type: "upsert_checkin_item", entityType: "checkin_item" },
  { type: "delete_checkin_item", entityType: "checkin_item" },
  { type: "upsert_checkin_entry", entityType: "checkin_entry" },
  { type: "delete_checkin_entry", entityType: "checkin_entry" },
  { type: "delete_checkin_media", entityType: "checkin_media" },
];

export function isSupportedSyncOperation(operation: SyncOperationShape): boolean {
  return SUPPORTED_SYNC_OPERATIONS.some(
    (supported) =>
      supported.type === operation.type && supported.entityType === operation.entityType,
  );
}

export function shouldReplayPreviouslyUnsupportedOperation(
  existing: { rejectionReason: string | null },
  operation: SyncOperationShape,
): boolean {
  return (
    existing.rejectionReason === `Unsupported operation type: ${operation.type}` &&
    isSupportedSyncOperation(operation)
  );
}
