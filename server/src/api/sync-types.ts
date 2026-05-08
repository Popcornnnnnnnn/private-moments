export interface SyncRequestBody {
  deviceId: string;
  lastSyncCursor: number;
  localChanges: SyncOperationInput[];
}

export interface SyncOperationInput {
  opId: string;
  type: string;
  entityType: string;
  entityId: string;
  clientCreatedAt: Date;
  payload: Record<string, unknown>;
}

export interface RejectedOperation {
  opId: string;
  reason: string;
}

export interface MediaOrderInput {
  id: string;
  sortOrder: number;
}

export class OperationRejectedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OperationRejectedError";
  }
}
