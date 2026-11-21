/**
 * Contratto d'errore tra Edge Functions e app iOS (vedi ios/CaloScan/Core/Networking/APIError.swift).
 * Formato: { "error": { "code": ErrorCode, "message"?: string, "plan"?: string, "minimum"?: string } }
 */
export type ErrorCode =
  | "unauthorized" | "quota_exceeded" | "plan_required" | "ai_unavailable" | "invalid_input" | "internal";

const STATUS: Record<ErrorCode, number> = {
  unauthorized: 401,
  quota_exceeded: 429,
  plan_required: 403,
  ai_unavailable: 503,
  invalid_input: 400,
  internal: 500,
};

export function errorResponse(
  code: ErrorCode,
  extra: { message?: string; plan?: string; minimum?: string } = {},
): Response {
  return new Response(JSON.stringify({ error: { code, ...extra } }), {
    status: STATUS[code],
    headers: { "Content-Type": "application/json" },
  });
}
