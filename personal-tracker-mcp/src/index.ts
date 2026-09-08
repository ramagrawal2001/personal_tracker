import OAuthProvider from "@cloudflare/workers-oauth-provider";
import { loginApp } from "./auth/login-handler";
import { PersonalTrackerMCP } from "./mcp/agent";
import type { Env } from "./types";

// The Durable Object class must be exported so the runtime can bind it
// (see wrangler.jsonc: durable_objects.bindings + migrations.new_sqlite_classes).
export { PersonalTrackerMCP };

export default new OAuthProvider<Env>({
  apiHandlers: {
    "/mcp": PersonalTrackerMCP.serve("/mcp") as never,
    "/sse": PersonalTrackerMCP.serveSSE("/sse") as never,
  },
  defaultHandler: loginApp as never,
  authorizeEndpoint: "/authorize",
  tokenEndpoint: "/token",
  clientRegistrationEndpoint: "/register",
  scopesSupported: ["personal-tracker"],
});
