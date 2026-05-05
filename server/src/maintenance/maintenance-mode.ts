import type { FastifyReply } from "fastify";

import { sendServiceUnavailable } from "../api/http-errors.js";

export interface MaintenanceModeState {
  active: boolean;
  jobId: string | null;
  reason: string | null;
  startedAt: string | null;
}

export class MaintenanceModeService {
  private state: {
    jobId: string;
    reason: string;
    startedAt: Date;
  } | null = null;

  enter(jobId: string, reason: string): void {
    this.state = {
      jobId,
      reason,
      startedAt: new Date(),
    };
  }

  exit(jobId: string): void {
    if (this.state?.jobId === jobId) {
      this.state = null;
    }
  }

  isActive(): boolean {
    return this.state !== null;
  }

  snapshot(): MaintenanceModeState {
    return {
      active: this.state !== null,
      jobId: this.state?.jobId ?? null,
      reason: this.state?.reason ?? null,
      startedAt: this.state?.startedAt.toISOString() ?? null,
    };
  }
}

export function blockWritesDuringMaintenance(
  reply: FastifyReply,
  maintenanceMode: MaintenanceModeService,
): FastifyReply | null {
  const state = maintenanceMode.snapshot();
  if (!state.active) {
    return null;
  }

  return sendServiceUnavailable(
    reply,
    "Server is in maintenance mode. Try again after the current archive operation finishes.",
    {
      maintenance: state,
    },
  );
}
