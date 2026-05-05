import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogFields {
  [key: string]: unknown;
}

export class FileLogger {
  constructor(private readonly logsDir: string) {}

  debug(event: string, fields: LogFields = {}): Promise<void> {
    return this.write("debug", event, fields);
  }

  info(event: string, fields: LogFields = {}): Promise<void> {
    return this.write("info", event, fields);
  }

  warn(event: string, fields: LogFields = {}): Promise<void> {
    return this.write("warn", event, fields);
  }

  error(event: string, fields: LogFields = {}): Promise<void> {
    return this.write("error", event, fields);
  }

  private async write(level: LogLevel, event: string, fields: LogFields): Promise<void> {
    const entry = {
      time: new Date().toISOString(),
      level,
      event,
      ...fields,
    };

    await mkdir(this.logsDir, { recursive: true });
    await appendFile(this.logPath(), `${JSON.stringify(entry)}\n`, "utf8");
  }

  private logPath(): string {
    const date = new Date().toISOString().slice(0, 10);
    return path.join(this.logsDir, `app-${date}.jsonl`);
  }
}
