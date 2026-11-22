import {
  onRequest as apiOnRequest,
  getOAuthProtectedResourceMetadata,
  getOAuthAuthorizationServerMetadata,
} from "./api/[[route]].js";

const PUBLIC_CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, MCP-Protocol-Version, Mcp-Session-Id, Accept",
  "Access-Control-Expose-Headers":
    "Content-Type, WWW-Authenticate, MCP-Protocol-Version, Mcp-Session-Id",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

export async function onRequest(context) {
  const { request } = context;
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");

  // 1. OAuth 2.0 Protected Resource Metadata (RFC 9728)
  if (path.startsWith("/.well-known/oauth-protected-resource")) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: PUBLIC_CORS_HEADERS });
    }
    const suffix = path.slice("/.well-known/oauth-protected-resource".length);
    const resourcePath = suffix && suffix.startsWith("/") ? suffix : "/api/mcp";
    return new Response(
      JSON.stringify(getOAuthProtectedResourceMetadata(url, resourcePath)),
      { status: 200, headers: PUBLIC_CORS_HEADERS }
    );
  }

  // 2. OAuth 2.0 Authorization Server Metadata (RFC 8414) & OpenID Connect Discovery
  if (
    path.startsWith("/.well-known/oauth-authorization-server") ||
    path.startsWith("/.well-known/openid-configuration")
  ) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: PUBLIC_CORS_HEADERS });
    }
    return new Response(
      JSON.stringify(getOAuthAuthorizationServerMetadata(url)),
      { status: 200, headers: PUBLIC_CORS_HEADERS }
    );
  }

  // 3. Atalho de URL curta para MCP (/mcp -> /api/mcp)
  if (
    path === "/mcp" ||
    path === "/mcp/sse" ||
    path === "/mcp/messages"
  ) {
    const rewrittenUrl = new URL(`/api${path}${url.search}`, url.origin);
    const rewrittenReq = new Request(rewrittenUrl.toString(), request);
    return apiOnRequest({ ...context, request: rewrittenReq });
  }

  // 4. Atalhos de raiz para clientes OAuth legados (/authorize, /token, /register, /oauth/*)
  if (
    path === "/authorize" ||
    path === "/token" ||
    path === "/register" ||
    path === "/oauth/authorize" ||
    path === "/oauth/token" ||
    path === "/oauth/register"
  ) {
    const endpoint = path.startsWith("/oauth/") ? path.slice(7) : path.slice(1);
    const rewrittenUrl = new URL(`/api/oauth/${endpoint}${url.search}`, url.origin);
    const rewrittenReq = new Request(rewrittenUrl.toString(), request);
    return apiOnRequest({ ...context, request: rewrittenReq });
  }

  return context.next();
}
