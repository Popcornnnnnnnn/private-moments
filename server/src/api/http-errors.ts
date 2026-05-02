import type { FastifyReply } from "fastify";

export function sendBadRequest(reply: FastifyReply, message: string): FastifyReply {
  return reply.status(400).send({
    error: "bad_request",
    message,
  });
}

export function sendUnauthorized(reply: FastifyReply, message = "Unauthorized"): FastifyReply {
  return reply.status(401).send({
    error: "unauthorized",
    message,
  });
}

export function sendForbidden(reply: FastifyReply, message = "Forbidden"): FastifyReply {
  return reply.status(403).send({
    error: "forbidden",
    message,
  });
}

export function sendNotFound(reply: FastifyReply, message = "Not found"): FastifyReply {
  return reply.status(404).send({
    error: "not_found",
    message,
  });
}

export function sendConflict(reply: FastifyReply, message: string): FastifyReply {
  return reply.status(409).send({
    error: "conflict",
    message,
  });
}

