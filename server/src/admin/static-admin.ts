import { access } from "node:fs/promises";
import path from "node:path";

import staticPlugin from "@fastify/static";
import type { FastifyInstance } from "fastify";

export async function registerStaticAdmin(app: FastifyInstance): Promise<void> {
  const adminDistDir = path.resolve(process.cwd(), "../admin/dist");
  if (!(await pathExists(adminDistDir))) {
    app.get("/admin", async (_request, reply) => {
      return reply.status(404).send({
        error: "admin_not_built",
        message: "Admin UI has not been built. Run npm run admin:build.",
      });
    });
    return;
  }

  await app.register(staticPlugin, {
    root: adminDistDir,
    prefix: "/admin/",
    decorateReply: false,
  });

  app.get("/admin", async (_request, reply) => {
    return reply.redirect("/admin/");
  });
}

async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

