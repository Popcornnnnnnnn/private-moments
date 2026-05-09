import { spawn } from "node:child_process";
import { cp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { PrismaClient, type Prisma } from "@prisma/client";

import { SCHEMA_VERSION, SERVER_VERSION, type AppConfig } from "../config/app-config.js";
import type { FileLogger } from "../logging/file-logger.js";
import { createPrismaClient } from "../db/prisma.js";
import { ensureDataDir, type DataPaths } from "../storage/data-dir.js";
import { isPathInsideOrEqual } from "../storage/path-safety.js";
import { normalizeTagName, serializePostTag, serializeTag, serializeTagAlias } from "../tags/tagging.js";

interface ExportDateRange {
  from?: Date;
  to?: Date;
}

interface ExportPackageManifest {
  packageType: "private-moments-export";
  packageVersion: 1;
  createdAt: string;
  serverVersion: string;
  schemaVersion: number;
  mode: "all" | "date_range";
  dateRange: {
    from: string | null;
    to: string | null;
  };
  counts: {
    posts: number;
    media: number;
    comments: number;
    tags: number;
    tagAliases: number;
    postTags: number;
    aiSummaries: number;
    checkInItems: number;
    checkInEntries: number;
    checkInMedia: number;
  };
}

type ExportPost = Prisma.PostGetPayload<{
  include: {
    media: true;
    comments: true;
    aiSummaries: true;
    tags: true;
  };
}>;

type ExportTag = Prisma.TagGetPayload<{
  include: {
    aliases: true;
  };
}>;

type ExportCheckInItem = Prisma.CheckInItemGetPayload<{
  include: {
    entries: {
      include: {
        media: true;
      };
    };
  };
}>;

export class ExportImportService {
  constructor(
    private readonly config: AppConfig,
    private readonly paths: DataPaths,
    private readonly prisma: PrismaClient,
    private readonly fileLogger: FileLogger,
  ) {}

  async createExport(input: { from?: string; to?: string }): Promise<Record<string, unknown>> {
    const dateRange = parseDateRange(input);
    const exportId = new Date().toISOString().replace(/[:.]/g, "-");
    const exportDir = path.join(this.paths.exportsDir, `private-moments-export-${exportId}`);
    const mediaDir = path.join(exportDir, "media");
    await mkdir(mediaDir, { recursive: true });

    const posts = await this.loadExportPosts(dateRange);
    const postIds = posts.map((post) => post.id);
    const tags = await this.loadExportTags(postIds);
    const tagAliases = tags.flatMap((tag) => tag.aliases);
    const postTags = posts.flatMap((post) => post.tags);
    const media = posts.flatMap((post) => post.media);
    const comments = posts.flatMap((post) => post.comments);
    const aiSummaries = posts.flatMap((post) => post.aiSummaries);
    const checkInItems = await this.loadExportCheckInItems(dateRange);
    const checkInEntries = checkInItems.flatMap((item) => item.entries);
    const checkInMedia = checkInEntries.flatMap((entry) => entry.media);

    const copiedMediaFiles =
      (await this.copyExportMedia(media, mediaDir)) +
      (await this.copyExportCheckInMedia(checkInMedia, mediaDir));
    const manifest: ExportPackageManifest = {
      packageType: "private-moments-export",
      packageVersion: 1,
      createdAt: new Date().toISOString(),
      serverVersion: SERVER_VERSION,
      schemaVersion: SCHEMA_VERSION,
      mode: dateRange.from || dateRange.to ? "date_range" : "all",
      dateRange: {
        from: dateRange.from?.toISOString() ?? null,
        to: dateRange.to?.toISOString() ?? null,
      },
      counts: {
        posts: posts.length,
        media: media.length,
        comments: comments.length,
        tags: tags.length,
        tagAliases: tagAliases.length,
        postTags: postTags.length,
        aiSummaries: aiSummaries.length,
        checkInItems: checkInItems.length,
        checkInEntries: checkInEntries.length,
        checkInMedia: checkInMedia.length,
      },
    };

    await writeFile(
      path.join(exportDir, "manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
      "utf8",
    );
    await writeFile(
      path.join(exportDir, "archive.json"),
      `${JSON.stringify({
        manifest,
        tags: tags.map((tag) => serializeTagRecord(tag)),
        tagAliases: tagAliases.map((alias) => serializeTagAlias(alias)),
        posts: posts.map((post) => serializePostRecord(post)),
        checkInItems: checkInItems.map((item) => serializeCheckInItemRecord(item)),
      }, null, 2)}\n`,
      "utf8",
    );
    await writeFile(path.join(exportDir, "preview.md"), renderPreview(posts, checkInItems), "utf8");

    const tarballPath = `${exportDir}.tar.gz`;
    await runCommand("tar", ["-czf", tarballPath, "-C", path.dirname(exportDir), path.basename(exportDir)]);
    await this.fileLogger.info("archive.export_completed", {
      posts: posts.length,
      media: media.length,
      checkInEntries: checkInEntries.length,
      tarballPath,
    });

    return {
      exportDir,
      packagePath: tarballPath,
      manifest,
      copiedMediaFiles,
    };
  }

  async importPackage(input: { packagePath: string; importName?: string }): Promise<Record<string, unknown>> {
    const packagePath = path.resolve(input.packagePath);
    if (!(await exists(packagePath))) {
      throw new Error("Export package does not exist");
    }

    const importRoot = await this.importRootPath(input.importName);
    const extractRoot = path.join(importRoot, "extracted");
    await mkdir(extractRoot, { recursive: true });
    await runCommand("tar", ["-xzf", packagePath, "-C", extractRoot]);

    const exportDir = await findExportDirectory(extractRoot);
    const archive = await readArchiveFile(path.join(exportDir, "archive.json"));
    const importedDataDir = path.join(importRoot, "data");
    const importedPaths = await ensureDataDir(importedDataDir);

    await migrateImportedDatabase(importedPaths.databasePath);
    await this.writeImportedArchive(archive, exportDir, importedPaths);
    const verification = await verifyImportedData(importedPaths);

    await this.fileLogger.info("archive.import_completed", {
      importPath: importedDataDir,
      ok: verification.ok,
      posts: archive.posts.length,
      media: archive.posts.reduce((count, post) => count + post.media.length, 0),
    });

    return {
      importPath: importedDataDir,
      verification,
      sourcePackagePath: packagePath,
      counts: archive.manifest.counts,
    };
  }

  private async loadExportPosts(dateRange: ExportDateRange): Promise<ExportPost[]> {
    return this.prisma.post.findMany({
      where: {
        ...(dateRange.from || dateRange.to
          ? {
              occurredAt: {
                ...(dateRange.from ? { gte: dateRange.from } : {}),
                ...(dateRange.to ? { lt: dateRange.to } : {}),
              },
            }
          : {}),
      },
      include: {
        media: {
          orderBy: {
            sortOrder: "asc",
          },
        },
        comments: {
          orderBy: {
            createdAt: "asc",
          },
        },
        aiSummaries: true,
        tags: true,
      },
      orderBy: {
        occurredAt: "asc",
      },
    });
  }

  private async loadExportTags(postIds: string[]): Promise<ExportTag[]> {
    const assignedTagIds = postIds.length
      ? await this.prisma.postTag.findMany({
          where: {
            postId: {
              in: postIds,
            },
          },
          select: {
            tagId: true,
          },
          distinct: ["tagId"],
        })
      : [];

    return this.prisma.tag.findMany({
      where: {
        OR: [
          {
            id: {
              in: assignedTagIds.map((row) => row.tagId),
            },
          },
          {
            isDefault: true,
          },
          {
            isArchived: true,
          },
        ],
      },
      include: {
        aliases: true,
      },
      orderBy: {
        createdAt: "asc",
      },
    });
  }

  private async loadExportCheckInItems(dateRange: ExportDateRange): Promise<ExportCheckInItem[]> {
    return this.prisma.checkInItem.findMany({
      where: dateRange.from || dateRange.to
        ? {
            entries: {
              some: {
                occurredAt: {
                  ...(dateRange.from ? { gte: dateRange.from } : {}),
                  ...(dateRange.to ? { lt: dateRange.to } : {}),
                },
              },
            },
          }
        : {},
      include: {
        entries: {
          where: dateRange.from || dateRange.to
            ? {
                occurredAt: {
                  ...(dateRange.from ? { gte: dateRange.from } : {}),
                  ...(dateRange.to ? { lt: dateRange.to } : {}),
                },
              }
            : {},
          include: {
            media: {
              orderBy: {
                sortOrder: "asc",
              },
            },
          },
          orderBy: {
            occurredAt: "asc",
          },
        },
      },
      orderBy: {
        sortOrder: "asc",
      },
    });
  }

  private async copyExportMedia(
    media: Array<{ id: string; compressedPath: string | null; originalPath: string | null; thumbnailPath: string | null }>,
    mediaDir: string,
  ): Promise<number> {
    const seen = new Set<string>();
    let copied = 0;
    for (const item of media) {
      for (const relativePath of [item.compressedPath, item.originalPath, item.thumbnailPath]) {
        if (!relativePath || seen.has(relativePath)) {
          continue;
        }

        const source = path.join(this.paths.dataDir, relativePath);
        if (!isPathInsideOrEqual(this.paths.dataDir, source) || !(await exists(source))) {
          continue;
        }

        const target = path.join(mediaDir, relativePath);
        if (!isPathInsideOrEqual(mediaDir, target)) {
          continue;
        }

        await mkdir(path.dirname(target), { recursive: true });
        await cp(source, target);
        seen.add(relativePath);
        copied += 1;
      }
    }

    return copied;
  }

  private async copyExportCheckInMedia(
    media: Array<{ compressedPath: string | null }>,
    mediaDir: string,
  ): Promise<number> {
    const seen = new Set<string>();
    let copied = 0;
    for (const item of media) {
      if (!item.compressedPath || seen.has(item.compressedPath)) {
        continue;
      }

      const source = path.join(this.paths.dataDir, item.compressedPath);
      if (!isPathInsideOrEqual(this.paths.dataDir, source) || !(await exists(source))) {
        continue;
      }

      const target = path.join(mediaDir, item.compressedPath);
      if (!isPathInsideOrEqual(mediaDir, target)) {
        continue;
      }

      await mkdir(path.dirname(target), { recursive: true });
      await cp(source, target);
      seen.add(item.compressedPath);
      copied += 1;
    }

    return copied;
  }

  private async importRootPath(importName?: string): Promise<string> {
    const label = sanitizeToken(importName ?? "");
    const base = `${new Date().toISOString().replace(/[:.]/g, "-")}${label ? `-${label}` : ""}`;
    const resolved = path.resolve(path.join(this.paths.archiveImportsDir, base));
    if (!isPathInsideOrEqual(this.paths.archiveImportsDir, resolved)) {
      throw new Error("Import target path is invalid");
    }
    if (await exists(resolved)) {
      throw new Error("Import target already exists");
    }
    return resolved;
  }

  private async writeImportedArchive(
    archive: ExportArchiveFile,
    exportDir: string,
    importedPaths: DataPaths,
  ): Promise<void> {
    const importedConfig: AppConfig = {
      ...this.config,
      dataDir: importedPaths.dataDir,
      databaseUrl: `file:${importedPaths.databasePath}`,
    };
    const importedPrisma = createPrismaClient(importedConfig);
    try {
      await importedPrisma.$connect();
      await importedPrisma.$transaction(async (tx) => {
        await clearImportedRuntime(tx);
        await importTags(tx, archive);
        await importCheckIns(tx, archive);
        await importPosts(tx, archive);
        await rebuildServerChanges(tx, archive);
      }, {
        timeout: 120_000,
      });
    } finally {
      await importedPrisma.$disconnect();
    }

    await copyImportedMedia(exportDir, importedPaths);
    await writeFile(
      importedPaths.manifestPath,
      `${JSON.stringify({
        app: "PrivateMoments",
        dataVersion: 1,
        schemaVersion: SCHEMA_VERSION,
        createdAt: new Date().toISOString(),
        mediaLayoutVersion: 1,
        importedFrom: archive.manifest.createdAt,
      }, null, 2)}\n`,
      "utf8",
    );
  }
}

interface ExportArchiveFile {
  manifest: ExportPackageManifest;
  tags: Array<Record<string, unknown>>;
  tagAliases: Array<Record<string, unknown>>;
  posts: Array<ExportedPostRecord>;
  checkInItems: Array<ExportedCheckInItemRecord>;
}

interface ExportedPostRecord {
  id: string;
  text: string;
  isFavorite: boolean;
  isPinned: boolean;
  pinnedAt: string | null;
  aiTagProcessedAt: string | null;
  tagsUserEditedAt: string | null;
  occurredAt: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  clientCreatedAt: string | null;
  clientUpdatedAt: string | null;
  media: Array<Record<string, unknown>>;
  comments: Array<Record<string, unknown>>;
  aiSummaries: Array<Record<string, unknown>>;
  postTags: Array<Record<string, unknown>>;
}

interface ExportedCheckInItemRecord {
  id: string;
  name: string;
  symbolName: string;
  colorHex: string;
  recordMode: string;
  timeVisualization: string;
  activeWeekdays: Array<unknown>;
  sortOrder: number;
  defaultShowInTimeline: boolean;
  tagId: string | null;
  createdAt: string;
  updatedAt: string;
  archivedAt: string | null;
  deletedAt: string | null;
  entries: Array<Record<string, unknown>>;
}

function parseDateRange(input: { from?: string; to?: string }): ExportDateRange {
  const from = parseOptionalDate(input.from, "from");
  const to = parseOptionalDate(input.to, "to");
  if (from && to && from >= to) {
    throw new Error("Export from must be before to");
  }
  return { from, to };
}

function parseOptionalDate(value: string | undefined, field: string): Date | undefined {
  if (!value) {
    return undefined;
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Export ${field} must be a valid date`);
  }
  return date;
}

function serializeTagRecord(tag: ExportTag): Record<string, unknown> {
  return serializeTag(tag);
}

function serializePostRecord(post: ExportPost): ExportedPostRecord {
  return {
    id: post.id,
    text: post.text,
    isFavorite: post.isFavorite,
    isPinned: post.isPinned,
    pinnedAt: post.pinnedAt?.toISOString() ?? null,
    aiTagProcessedAt: post.aiTagProcessedAt?.toISOString() ?? null,
    tagsUserEditedAt: post.tagsUserEditedAt?.toISOString() ?? null,
    occurredAt: post.occurredAt.toISOString(),
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
    deletedAt: post.deletedAt?.toISOString() ?? null,
    clientCreatedAt: post.clientCreatedAt?.toISOString() ?? null,
    clientUpdatedAt: post.clientUpdatedAt?.toISOString() ?? null,
    media: post.media.map(serializeMediaRecord),
    comments: post.comments.map(serializeCommentRecord),
    aiSummaries: post.aiSummaries.map(serializeSummaryRecord),
    postTags: post.tags.map(serializePostTag),
  };
}

function serializeCheckInItemRecord(item: ExportCheckInItem): ExportedCheckInItemRecord {
  return {
    id: item.id,
    name: item.name,
    symbolName: item.symbolName,
    colorHex: item.colorHex,
    recordMode: item.recordMode,
    timeVisualization: item.timeVisualization,
    activeWeekdays: parseJsonArray(item.activeWeekdaysJson),
    sortOrder: item.sortOrder,
    defaultShowInTimeline: item.defaultShowInTimeline,
    tagId: item.tagId,
    createdAt: item.createdAt.toISOString(),
    updatedAt: item.updatedAt.toISOString(),
    archivedAt: item.archivedAt?.toISOString() ?? null,
    deletedAt: item.deletedAt?.toISOString() ?? null,
    entries: item.entries.map(serializeCheckInEntryRecord),
  };
}

function serializeCheckInEntryRecord(entry: ExportCheckInItem["entries"][number]): Record<string, unknown> {
  return {
    id: entry.id,
    itemId: entry.itemId,
    occurredAt: entry.occurredAt.toISOString(),
    note: entry.note,
    showInTimeline: entry.showInTimeline,
    clientCreatedAt: entry.clientCreatedAt?.toISOString() ?? null,
    clientUpdatedAt: entry.clientUpdatedAt?.toISOString() ?? null,
    createdAt: entry.createdAt.toISOString(),
    updatedAt: entry.updatedAt.toISOString(),
    deletedAt: entry.deletedAt?.toISOString() ?? null,
    media: entry.media.map(serializeCheckInMediaRecord),
  };
}

function serializeCheckInMediaRecord(media: ExportCheckInItem["entries"][number]["media"][number]): Record<string, unknown> {
  return {
    id: media.id,
    entryId: media.entryId,
    kind: media.kind,
    status: media.status,
    compressedPath: media.compressedPath,
    mimeType: media.mimeType,
    compressedSizeBytes: media.compressedSizeBytes,
    checksum: media.checksum,
    sortOrder: media.sortOrder,
    createdAt: media.createdAt.toISOString(),
    updatedAt: media.updatedAt.toISOString(),
    deletedAt: media.deletedAt?.toISOString() ?? null,
  };
}

function serializeMediaRecord(media: ExportPost["media"][number]): Record<string, unknown> {
  return {
    id: media.id,
    postId: media.postId,
    kind: media.kind,
    status: media.status,
    compressedPath: media.compressedPath,
    originalPath: media.originalPath,
    thumbnailPath: media.thumbnailPath,
    mimeType: media.mimeType,
    durationSeconds: media.durationSeconds,
    transcriptionText: media.transcriptionText,
    originalPreserved: media.originalPreserved,
    width: media.width,
    height: media.height,
    compressedSizeBytes: media.compressedSizeBytes,
    originalSizeBytes: media.originalSizeBytes,
    checksum: media.checksum,
    sortOrder: media.sortOrder,
    createdAt: media.createdAt.toISOString(),
    updatedAt: media.updatedAt.toISOString(),
    deletedAt: media.deletedAt?.toISOString() ?? null,
  };
}

function serializeCommentRecord(comment: ExportPost["comments"][number]): Record<string, unknown> {
  return {
    id: comment.id,
    postId: comment.postId,
    text: comment.text,
    createdAt: comment.createdAt.toISOString(),
    updatedAt: comment.updatedAt.toISOString(),
    deletedAt: comment.deletedAt?.toISOString() ?? null,
    clientCreatedAt: comment.clientCreatedAt?.toISOString() ?? null,
    clientUpdatedAt: comment.clientUpdatedAt?.toISOString() ?? null,
  };
}

function serializeSummaryRecord(summary: ExportPost["aiSummaries"][number]): Record<string, unknown> {
  return {
    id: summary.id,
    postId: summary.postId,
    mediaId: summary.mediaId,
    status: summary.status,
    format: summary.format,
    language: summary.language,
    overview: summary.overview,
    keyPointsJson: summary.keyPointsJson,
    sectionsJson: summary.sectionsJson,
    summaryText: summary.summaryText,
    documentTitle: summary.documentTitle,
    oneLiner: summary.oneLiner,
    documentBlocksJson: summary.documentBlocksJson,
    inputTranscriptHash: summary.inputTranscriptHash,
    inputTranscriptLength: summary.inputTranscriptLength,
    inputDurationSeconds: summary.inputDurationSeconds,
    promptVersion: summary.promptVersion,
    provider: summary.provider,
    model: summary.model,
    errorCode: summary.errorCode,
    errorMessage: summary.errorMessage,
    createdAt: summary.createdAt.toISOString(),
    updatedAt: summary.updatedAt.toISOString(),
    deletedAt: summary.deletedAt?.toISOString() ?? null,
  };
}

function renderPreview(posts: ExportPost[], checkInItems: ExportCheckInItem[]): string {
  const lines = [
    "# Private Moments Export Preview",
    "",
    `Generated at ${new Date().toISOString()}.`,
    "",
    `Moments: ${posts.length}`,
    `Check-ins: ${checkInItems.reduce((count, item) => count + item.entries.length, 0)}`,
    "",
  ];
  for (const post of posts) {
    lines.push(`## ${post.occurredAt.toISOString()}`);
    if (post.deletedAt) {
      lines.push("_Soft deleted_");
      lines.push("");
    }
    lines.push(post.text.trim() || "_Media-only moment_");
    lines.push("");
    if (post.media.length > 0) {
      lines.push(`Media: ${post.media.map((media) => media.kind).join(", ")}`);
      lines.push("");
    }
    if (post.comments.length > 0) {
      lines.push("Comments:");
      for (const comment of post.comments) {
        lines.push(`- ${comment.text}`);
      }
      lines.push("");
    }
  }
  return `${lines.join("\n")}\n`;
}

async function readArchiveFile(filePath: string): Promise<ExportArchiveFile> {
  const parsed = JSON.parse(await readFile(filePath, "utf8")) as unknown;
  if (!isRecord(parsed) || !isRecord(parsed.manifest) || !Array.isArray(parsed.posts)) {
    throw new Error("Invalid export package archive.json");
  }
  if (parsed.manifest.packageType !== "private-moments-export") {
    throw new Error("Unsupported export package type");
  }
  if (!Array.isArray(parsed.tags) || !Array.isArray(parsed.tagAliases)) {
    throw new Error("Invalid export package metadata");
  }
  if (!Array.isArray(parsed.checkInItems)) {
    parsed.checkInItems = [];
  }
  return parsed as unknown as ExportArchiveFile;
}

async function clearImportedRuntime(tx: Prisma.TransactionClient): Promise<void> {
  await tx.maintenanceJob.deleteMany();
  await tx.syncOperation.deleteMany();
  await tx.serverChange.deleteMany();
  await tx.aiSummary.deleteMany();
  await tx.postTag.deleteMany();
  await tx.checkInMedia.deleteMany();
  await tx.checkInEntry.deleteMany();
  await tx.checkInItem.deleteMany();
  await tx.tagAlias.deleteMany();
  await tx.tag.deleteMany();
  await tx.comment.deleteMany();
  await tx.media.deleteMany();
  await tx.post.deleteMany();
  await tx.device.deleteMany();
  await tx.user.deleteMany();
}

async function importTags(tx: Prisma.TransactionClient, archive: ExportArchiveFile): Promise<void> {
  for (const raw of archive.tags) {
    const id = getString(raw, "id");
    const type = getString(raw, "type");
    const name = getString(raw, "name");
    if (!id || !type || !name) {
      continue;
    }
    await tx.tag.create({
      data: {
        id,
        type,
        name,
        normalizedName: getString(raw, "normalizedName") ?? normalizeTagName(name),
        colorHex: getNullableString(raw, "colorHex"),
        isDefault: getBoolean(raw, "isDefault") ?? false,
        isArchived: getBoolean(raw, "isArchived") ?? false,
        aiUsableAsPrimary: getBoolean(raw, "aiUsableAsPrimary") ?? false,
        createdAt: getDate(raw, "createdAt") ?? new Date(),
        updatedAt: getDate(raw, "updatedAt") ?? new Date(),
        archivedAt: getNullableDate(raw, "archivedAt"),
      },
    });
  }

  for (const raw of archive.tagAliases) {
    const id = getString(raw, "id");
    const tagId = getString(raw, "tagId");
    const alias = getString(raw, "alias");
    if (!id || !tagId || !alias) {
      continue;
    }
    await tx.tagAlias.create({
      data: {
        id,
        tagId,
        alias,
        normalizedAlias: getString(raw, "normalizedAlias") ?? normalizeTagName(alias),
        createdAt: getDate(raw, "createdAt") ?? new Date(),
        deletedAt: getNullableDate(raw, "deletedAt"),
      },
    });
  }
}

async function importCheckIns(tx: Prisma.TransactionClient, archive: ExportArchiveFile): Promise<void> {
  for (const item of archive.checkInItems) {
    const activeWeekdays = Array.isArray(item.activeWeekdays)
      ? item.activeWeekdays.filter((value): value is number => Number.isInteger(value))
      : [];

    await tx.checkInItem.create({
      data: {
        id: item.id,
        name: item.name,
        symbolName: item.symbolName,
        colorHex: item.colorHex,
        recordMode: item.recordMode,
        timeVisualization: validCheckInTimeVisualization(item.timeVisualization),
        activeWeekdaysJson: JSON.stringify(activeWeekdays.length ? activeWeekdays : [1, 2, 3, 4, 5, 6, 7]),
        sortOrder: item.sortOrder,
        defaultShowInTimeline: item.defaultShowInTimeline,
        tagId: item.tagId,
        createdAt: parseDate(item.createdAt),
        updatedAt: parseDate(item.updatedAt),
        archivedAt: parseNullableDate(item.archivedAt),
        deletedAt: parseNullableDate(item.deletedAt),
        serverVersion: 0,
      },
    });

    for (const raw of item.entries) {
      const id = getString(raw, "id");
      if (!id) {
        continue;
      }

      await tx.checkInEntry.create({
        data: {
          id,
          itemId: item.id,
          occurredAt: getDate(raw, "occurredAt") ?? new Date(),
          note: getString(raw, "note") ?? "",
          showInTimeline: getBoolean(raw, "showInTimeline") ?? false,
          clientCreatedAt: getNullableDate(raw, "clientCreatedAt"),
          clientUpdatedAt: getNullableDate(raw, "clientUpdatedAt"),
          createdAt: getDate(raw, "createdAt") ?? new Date(),
          updatedAt: getDate(raw, "updatedAt") ?? new Date(),
          deletedAt: getNullableDate(raw, "deletedAt"),
          serverVersion: 0,
        },
      });

      const rawMedia = raw["media"];
      const media = Array.isArray(rawMedia) ? rawMedia.filter(isRecord) : [];
      for (const mediaRecord of media) {
        const mediaId = getString(mediaRecord, "id");
        if (!mediaId) {
          continue;
        }
        await tx.checkInMedia.create({
          data: {
            id: mediaId,
            entryId: id,
            kind: getString(mediaRecord, "kind") ?? "image",
            status: getString(mediaRecord, "status") ?? "uploaded",
            compressedPath: getNullableString(mediaRecord, "compressedPath"),
            mimeType: getNullableString(mediaRecord, "mimeType"),
            compressedSizeBytes: getNullableInteger(mediaRecord, "compressedSizeBytes"),
            checksum: getNullableString(mediaRecord, "checksum"),
            sortOrder: getInteger(mediaRecord, "sortOrder") ?? 0,
            createdAt: getDate(mediaRecord, "createdAt") ?? new Date(),
            updatedAt: getDate(mediaRecord, "updatedAt") ?? new Date(),
            deletedAt: getNullableDate(mediaRecord, "deletedAt"),
          },
        });
      }
    }
  }
}

async function importPosts(tx: Prisma.TransactionClient, archive: ExportArchiveFile): Promise<void> {
  for (const post of archive.posts) {
    await tx.post.create({
      data: {
        id: post.id,
        text: post.text,
        isFavorite: post.isFavorite,
        isPinned: post.isPinned ?? false,
        pinnedAt: parseNullableDate(post.pinnedAt),
        aiTagProcessedAt: parseNullableDate(post.aiTagProcessedAt),
        tagsUserEditedAt: parseNullableDate(post.tagsUserEditedAt),
        occurredAt: parseDate(post.occurredAt),
        createdAt: parseDate(post.createdAt),
        updatedAt: parseDate(post.updatedAt),
        deletedAt: parseNullableDate(post.deletedAt),
        clientCreatedAt: parseNullableDate(post.clientCreatedAt),
        clientUpdatedAt: parseNullableDate(post.clientUpdatedAt),
        serverVersion: 0,
      },
    });

    for (const raw of post.media) {
      const id = getString(raw, "id");
      if (!id) {
        continue;
      }
      await tx.media.create({
        data: {
          id,
          postId: post.id,
          kind: getString(raw, "kind") ?? "image",
          status: getString(raw, "status") ?? "uploaded",
          compressedPath: getNullableString(raw, "compressedPath"),
          originalPath: getNullableString(raw, "originalPath"),
          thumbnailPath: getNullableString(raw, "thumbnailPath"),
          mimeType: getNullableString(raw, "mimeType"),
          durationSeconds: getNullableNumber(raw, "durationSeconds"),
          transcriptionText: getNullableString(raw, "transcriptionText"),
          originalPreserved: getBoolean(raw, "originalPreserved") ?? false,
          width: getNullableInteger(raw, "width"),
          height: getNullableInteger(raw, "height"),
          compressedSizeBytes: getNullableInteger(raw, "compressedSizeBytes"),
          originalSizeBytes: getNullableInteger(raw, "originalSizeBytes"),
          checksum: getNullableString(raw, "checksum"),
          sortOrder: getInteger(raw, "sortOrder") ?? 0,
          createdAt: getDate(raw, "createdAt") ?? new Date(),
          updatedAt: getDate(raw, "updatedAt") ?? new Date(),
          deletedAt: getNullableDate(raw, "deletedAt"),
        },
      });
    }

    for (const raw of post.comments) {
      const id = getString(raw, "id");
      if (!id) {
        continue;
      }
      await tx.comment.create({
        data: {
          id,
          postId: post.id,
          text: getString(raw, "text") ?? "",
          createdAt: getDate(raw, "createdAt") ?? new Date(),
          updatedAt: getDate(raw, "updatedAt") ?? new Date(),
          deletedAt: getNullableDate(raw, "deletedAt"),
          clientCreatedAt: getNullableDate(raw, "clientCreatedAt"),
          clientUpdatedAt: getNullableDate(raw, "clientUpdatedAt"),
          serverVersion: 0,
        },
      });
    }

    for (const raw of post.aiSummaries) {
      const id = getString(raw, "id");
      const mediaId = getString(raw, "mediaId");
      if (!id || !mediaId) {
        continue;
      }
      await tx.aiSummary.create({
        data: {
          id,
          postId: post.id,
          mediaId,
          status: getString(raw, "status") ?? "ready",
          format: getNullableString(raw, "format"),
          language: getNullableString(raw, "language"),
          overview: getNullableString(raw, "overview"),
          keyPointsJson: getString(raw, "keyPointsJson") ?? "[]",
          sectionsJson: getString(raw, "sectionsJson") ?? "[]",
          summaryText: getNullableString(raw, "summaryText"),
          documentTitle: getNullableString(raw, "documentTitle"),
          oneLiner: getNullableString(raw, "oneLiner"),
          documentBlocksJson: getString(raw, "documentBlocksJson") ?? "[]",
          inputTranscriptHash: getNullableString(raw, "inputTranscriptHash"),
          inputTranscriptLength: getNullableInteger(raw, "inputTranscriptLength"),
          inputDurationSeconds: getNullableNumber(raw, "inputDurationSeconds"),
          promptVersion: getString(raw, "promptVersion") ?? "imported",
          provider: getNullableString(raw, "provider"),
          model: getNullableString(raw, "model"),
          errorCode: getNullableString(raw, "errorCode"),
          errorMessage: getNullableString(raw, "errorMessage"),
          createdAt: getDate(raw, "createdAt") ?? new Date(),
          updatedAt: getDate(raw, "updatedAt") ?? new Date(),
          deletedAt: getNullableDate(raw, "deletedAt"),
        },
      });
    }

    for (const raw of post.postTags) {
      const id = getString(raw, "id");
      const tagId = getString(raw, "tagId");
      if (!id || !tagId) {
        continue;
      }
      await tx.postTag.create({
        data: {
          id,
          postId: post.id,
          tagId,
          role: getString(raw, "role") ?? "topic",
          source: getString(raw, "source") ?? "manual",
          confidence: getNullableNumber(raw, "confidence"),
          aiSummaryId: getNullableString(raw, "aiSummaryId"),
          createdAt: getDate(raw, "createdAt") ?? new Date(),
          updatedAt: getDate(raw, "updatedAt") ?? new Date(),
          deletedAt: getNullableDate(raw, "deletedAt"),
        },
      });
    }
  }
}

async function rebuildServerChanges(tx: Prisma.TransactionClient, archive: ExportArchiveFile): Promise<void> {
  const postVersion = new Map<string, number>();
  const checkInItemVersion = new Map<string, number>();

  for (const raw of archive.tags) {
    const id = getString(raw, "id");
    if (!id) {
      continue;
    }
    await tx.serverChange.create({
      data: {
        entityType: "tag",
        entityId: id,
        changeType: "tag_updated",
        payloadJson: JSON.stringify(raw),
      },
    });
  }

  for (const raw of archive.tagAliases) {
    const id = getString(raw, "id");
    if (!id) {
      continue;
    }
    await tx.serverChange.create({
      data: {
        entityType: "tag_alias",
        entityId: id,
        changeType: getNullableString(raw, "deletedAt") ? "tag_alias_deleted" : "tag_alias_updated",
        payloadJson: JSON.stringify(raw),
      },
    });
  }

  for (const item of archive.checkInItems) {
    const itemChange = await tx.serverChange.create({
      data: {
        entityType: "checkin_item",
        entityId: item.id,
        changeType: item.deletedAt ? "checkin_item_deleted" : "checkin_item_updated",
        payloadJson: JSON.stringify(item.deletedAt
          ? {
              id: item.id,
              deletedAt: item.deletedAt,
            }
          : {
              id: item.id,
              name: item.name,
              symbolName: item.symbolName,
              colorHex: item.colorHex,
              recordMode: item.recordMode,
              timeVisualization: validCheckInTimeVisualization(item.timeVisualization),
              activeWeekdays: item.activeWeekdays,
              sortOrder: item.sortOrder,
              defaultShowInTimeline: item.defaultShowInTimeline,
              tagId: item.tagId,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
              archivedAt: item.archivedAt,
              deletedAt: item.deletedAt,
            }),
      },
    });
    checkInItemVersion.set(item.id, itemChange.version);

    for (const entry of item.entries) {
      const id = getString(entry, "id");
      if (!id) {
        continue;
      }
      const change = await tx.serverChange.create({
        data: {
          entityType: "checkin_entry",
          entityId: id,
          changeType: getNullableString(entry, "deletedAt") ? "checkin_entry_deleted" : "checkin_entry_updated",
          payloadJson: JSON.stringify(entry),
        },
      });
      await tx.checkInEntry.update({
        where: {
          id,
        },
        data: {
          serverVersion: change.version,
        },
      });
      checkInItemVersion.set(item.id, change.version);

      const rawMedia = entry["media"];
      const mediaRecords = Array.isArray(rawMedia) ? rawMedia.filter(isRecord) : [];
      for (const media of mediaRecords) {
        const mediaId = getString(media, "id");
        if (!mediaId) {
          continue;
        }
        const mediaChange = await tx.serverChange.create({
          data: {
            entityType: "checkin_media",
            entityId: mediaId,
            changeType: getNullableString(media, "deletedAt") ? "checkin_media_deleted" : "checkin_media_uploaded",
            payloadJson: JSON.stringify({
              id: mediaId,
              entryId: id,
              kind: getString(media, "kind") ?? "image",
              status: getString(media, "status") ?? "uploaded",
              variant: "compressed",
              path: getNullableString(media, "compressedPath"),
              mimeType: getNullableString(media, "mimeType"),
              sortOrder: getInteger(media, "sortOrder") ?? 0,
              checksum: getNullableString(media, "checksum"),
              compressedSizeBytes: getNullableInteger(media, "compressedSizeBytes"),
              deletedAt: getNullableString(media, "deletedAt"),
            }),
          },
        });
        checkInItemVersion.set(item.id, mediaChange.version);
      }
    }
  }

  for (const post of archive.posts) {
    const postChange = await tx.serverChange.create({
      data: {
        entityType: "post",
        entityId: post.id,
        changeType: post.deletedAt ? "post_deleted" : "post_created",
        payloadJson: JSON.stringify(post.deletedAt
          ? {
              id: post.id,
              deletedAt: post.deletedAt,
            }
          : {
              id: post.id,
              text: post.text,
              isFavorite: post.isFavorite,
              isPinned: post.isPinned ?? false,
              pinnedAt: post.pinnedAt ?? null,
              occurredAt: post.occurredAt,
              deletedAt: null,
            }),
      },
    });
    postVersion.set(post.id, postChange.version);

    for (const media of post.media) {
      const id = getString(media, "id");
      if (!id) {
        continue;
      }
      for (const variant of ["compressed", "original", "thumbnail"] as const) {
        const relativePath = getString(media, `${variant}Path`);
        if (!relativePath) {
          continue;
        }
        const change = await tx.serverChange.create({
          data: {
            entityType: "media",
            entityId: id,
            changeType: "media_uploaded",
            payloadJson: JSON.stringify({
              id,
              postId: post.id,
              kind: getString(media, "kind"),
              status: getString(media, "status"),
              variant,
              path: relativePath,
              mimeType: getNullableString(media, "mimeType"),
              durationSeconds: getNullableNumber(media, "durationSeconds"),
              transcriptionText: getNullableString(media, "transcriptionText"),
              width: getNullableInteger(media, "width"),
              height: getNullableInteger(media, "height"),
              originalPreserved: getBoolean(media, "originalPreserved") ?? false,
              sortOrder: getInteger(media, "sortOrder") ?? 0,
              checksum: getNullableString(media, "checksum"),
              compressedSizeBytes: getNullableInteger(media, "compressedSizeBytes"),
              originalSizeBytes: getNullableInteger(media, "originalSizeBytes"),
            }),
          },
        });
        postVersion.set(post.id, change.version);
      }
    }

    for (const comment of post.comments) {
      const id = getString(comment, "id");
      if (!id) {
        continue;
      }
      const change = await tx.serverChange.create({
        data: {
          entityType: "comment",
          entityId: id,
          changeType: getNullableString(comment, "deletedAt") ? "comment_deleted" : "comment_created",
          payloadJson: JSON.stringify(comment),
        },
      });
      await tx.comment.update({
        where: {
          id,
        },
        data: {
          serverVersion: change.version,
        },
      });
      postVersion.set(post.id, change.version);
    }

    for (const summary of post.aiSummaries) {
      const id = getString(summary, "id");
      if (!id) {
        continue;
      }
      const change = await tx.serverChange.create({
        data: {
          entityType: "ai_summary",
          entityId: id,
          changeType: getNullableString(summary, "deletedAt") ? "ai_summary_deleted" : "ai_summary_updated",
          payloadJson: JSON.stringify(summary),
        },
      });
      postVersion.set(post.id, change.version);
    }

    for (const postTag of post.postTags) {
      const id = getString(postTag, "id");
      if (!id) {
        continue;
      }
      const change = await tx.serverChange.create({
        data: {
          entityType: "post_tag",
          entityId: id,
          changeType: getNullableString(postTag, "deletedAt") ? "post_tag_deleted" : "post_tag_updated",
          payloadJson: JSON.stringify(postTag),
        },
      });
      postVersion.set(post.id, change.version);
    }

    const stateChange = await tx.serverChange.create({
      data: {
        entityType: "post",
        entityId: post.id,
        changeType: "post_tag_state_updated",
        payloadJson: JSON.stringify({
          postId: post.id,
          aiTagProcessedAt: post.aiTagProcessedAt,
          tagsUserEditedAt: post.tagsUserEditedAt,
        }),
      },
    });
    postVersion.set(post.id, stateChange.version);
  }

  for (const [postId, version] of postVersion) {
    await tx.post.update({
      where: {
        id: postId,
      },
      data: {
        serverVersion: version,
      },
    });
  }

  for (const [itemId, version] of checkInItemVersion) {
    await tx.checkInItem.update({
      where: {
        id: itemId,
      },
      data: {
        serverVersion: version,
      },
    });
  }
}

async function copyImportedMedia(exportDir: string, importedPaths: DataPaths): Promise<void> {
  const source = path.join(exportDir, "media", "media");
  if (!(await exists(source))) {
    return;
  }
  await rm(importedPaths.mediaDir, { recursive: true, force: true });
  await cp(source, importedPaths.mediaDir, { recursive: true });
}

async function verifyImportedData(paths: DataPaths): Promise<Record<string, unknown>> {
  const config: AppConfig = {
    host: "127.0.0.1",
    port: 0,
    logLevel: "error",
    dataDir: paths.dataDir,
    databaseUrl: `file:${paths.databasePath}`,
    aiSummary: {
      provider: "openai",
      baseUrl: "http://127.0.0.1",
      model: "unused",
      transcriptionProvider: "local",
      transcriptionModel: "unused",
      localTranscriptionPythonPath: "python",
      localTranscriptionScriptPath: "script.py",
      localTranscriptionModel: "unused",
      localTranscriptionTimeoutMs: 1,
      timeoutMs: 1,
    },
  };
  const prisma = createPrismaClient(config);
  try {
    const [
      posts,
      media,
      comments,
      tags,
      summaries,
      checkInItems,
      checkInEntries,
      checkInMedia,
      serverChanges,
      devices,
      missingMediaFiles,
    ] =
      await Promise.all([
        prisma.post.count(),
        prisma.media.count(),
        prisma.comment.count(),
        prisma.tag.count(),
        prisma.aiSummary.count(),
        prisma.checkInItem.count(),
        prisma.checkInEntry.count(),
        prisma.checkInMedia.count(),
        prisma.serverChange.count(),
        prisma.device.count(),
        countMissingMediaFiles(prisma, paths),
      ]);
    return {
      ok: missingMediaFiles === 0 && devices === 0 && serverChanges > 0,
      dataDir: paths.dataDir,
      databasePath: paths.databasePath,
      posts,
      media,
      comments,
      tags,
      aiSummaries: summaries,
      checkInItems,
      checkInEntries,
      checkInMedia,
      serverChanges,
      devices,
      missingMediaFiles,
      issues: [
        ...(missingMediaFiles > 0 ? ["missing_media_files"] : []),
        ...(devices > 0 ? ["runtime_devices_not_empty"] : []),
        ...(serverChanges === 0 ? ["missing_server_changes"] : []),
      ],
    };
  } finally {
    await prisma.$disconnect();
  }
}

async function countMissingMediaFiles(prisma: PrismaClient, paths: DataPaths): Promise<number> {
  const media = await prisma.media.findMany({
    select: {
      compressedPath: true,
      originalPath: true,
      thumbnailPath: true,
      deletedAt: true,
    },
  });
  let missing = 0;
  for (const item of media) {
    if (item.deletedAt) {
      continue;
    }
    for (const relativePath of [item.compressedPath, item.originalPath, item.thumbnailPath]) {
      if (!relativePath) {
        continue;
      }
      const absolute = path.join(paths.dataDir, relativePath);
      if (!isPathInsideOrEqual(paths.dataDir, absolute) || !(await exists(absolute))) {
        missing += 1;
      }
    }
  }
  const checkInMedia = await prisma.checkInMedia.findMany({
    select: {
      compressedPath: true,
      deletedAt: true,
    },
  });
  for (const item of checkInMedia) {
    if (item.deletedAt || !item.compressedPath) {
      continue;
    }
    const absolute = path.join(paths.dataDir, item.compressedPath);
    if (!isPathInsideOrEqual(paths.dataDir, absolute) || !(await exists(absolute))) {
      missing += 1;
    }
  }
  return missing;
}

async function findExportDirectory(root: string): Promise<string> {
  if (await exists(path.join(root, "archive.json"))) {
    return root;
  }
  const { readdir } = await import("node:fs/promises");
  const entries = await readdir(root, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const candidate = path.join(root, entry.name);
    if (await exists(path.join(candidate, "archive.json"))) {
      return candidate;
    }
  }
  throw new Error("Export package is missing archive.json");
}

async function migrateImportedDatabase(databasePath: string): Promise<void> {
  await runCommand("sqlite3", [databasePath, "PRAGMA user_version=0;"]);
  await runCommand("npm", ["run", "prisma:deploy"], {
    DATABASE_URL: `file:${databasePath}`,
  }, serverRootDir());
}

function serverRootDir(): string {
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
}

async function runCommand(
  command: string,
  args: string[],
  env: Record<string, string> = {},
  cwd?: string,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: {
        ...process.env,
        ...env,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stderr = "";
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `${command} exited with code ${code}`));
      }
    });
  });
}

async function exists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getString(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value : null;
}

function getNullableString(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === "string" ? value : null;
}

function getBoolean(record: Record<string, unknown>, key: string): boolean | null {
  const value = record[key];
  return typeof value === "boolean" ? value : null;
}

function getInteger(record: Record<string, unknown>, key: string): number | null {
  const value = record[key];
  return Number.isInteger(value) ? value as number : null;
}

function getNullableInteger(record: Record<string, unknown>, key: string): number | null {
  return getInteger(record, key);
}

function getNullableNumber(record: Record<string, unknown>, key: string): number | null {
  const value = record[key];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function getDate(record: Record<string, unknown>, key: string): Date | null {
  const value = getString(record, key);
  return value ? parseDateOrNull(value) : null;
}

function getNullableDate(record: Record<string, unknown>, key: string): Date | null {
  const value = getString(record, key);
  return value ? parseDateOrNull(value) : null;
}

function parseJsonArray(value: string): Array<unknown> {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function validCheckInTimeVisualization(value: string): string {
  return value === "timeLine" || value === "timeHeatmap" ? value : "none";
}

function parseDate(value: string): Date {
  return parseDateOrNull(value) ?? new Date();
}

function parseNullableDate(value: string | null): Date | null {
  return value ? parseDateOrNull(value) : null;
}

function parseDateOrNull(value: string): Date | null {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function sanitizeToken(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "-").slice(0, 80);
}
