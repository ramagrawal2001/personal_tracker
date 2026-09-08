import type { Session } from "./auth/supabase-auth";

/**
 * Stored in the encrypted OAuth grant; reaches the agent as `this.props`.
 * The `Record<string, unknown>` intersection satisfies McpAgent's Props
 * constraint without weakening the known fields.
 */
export type AuthProps = Session & { connectedAt: string } & Record<string, unknown>;

export interface Env {
  OAUTH_KV: KVNamespace;
  MCP_OBJECT: DurableObjectNamespace;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}
