import { McpAgent } from "agents/mcp";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { AuthError, type Session } from "../auth/supabase-auth";
import { makeSupabaseRest } from "../data/supabase-rest";
import type { AuthProps, Env } from "../types";
import { registerTools, type McpServerLike } from "./tools";

export class PersonalTrackerMCP extends McpAgent<Env, unknown, AuthProps> {
  server = new McpServer({ name: "personal-tracker", version: "1.0.0" });

  private requireProps(): AuthProps {
    if (!this.props?.accessToken) {
      throw new AuthError("SESSION_EXPIRED");
    }
    return this.props;
  }

  async init(): Promise<void> {
    const rest = makeSupabaseRest(
      { url: this.env.SUPABASE_URL, anonKey: this.env.SUPABASE_ANON_KEY },
      {
        get: (): Session => {
          const p = this.requireProps();
          return {
            supabaseUserId: p.supabaseUserId,
            email: p.email,
            accessToken: p.accessToken,
            refreshToken: p.refreshToken,
            expiresAt: p.expiresAt,
          };
        },
        // McpAgent.updateProps persists the refreshed tokens for this session's
        // Durable Object, so later tool calls reuse them.
        set: async (s: Session) => {
          await this.updateProps({ ...this.requireProps(), ...s });
        },
      },
    );

    registerTools(this.server as unknown as McpServerLike, {
      rest,
      identity: () => {
        const p = this.requireProps();
        return {
          email: p.email,
          supabaseUserId: p.supabaseUserId,
          connectedAt: p.connectedAt,
        };
      },
    });
  }
}
