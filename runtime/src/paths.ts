import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

export type QuickchatPaths = {
  config: string;
  state: string;
  records: string;
  cache: string;
  images: string;
  adapters: string;
  runtime: string;
};

function xdg(env: NodeJS.ProcessEnv, key: string, fallback: string): string {
  const value = env[key];
  return value !== undefined && value.startsWith("/") ? value : fallback;
}

export function quickchatPaths(env: NodeJS.ProcessEnv = process.env): QuickchatPaths {
  const home = env.HOME ?? homedir();
  const configRoot = xdg(env, "XDG_CONFIG_HOME", join(home, ".config"));
  const stateRoot = xdg(env, "XDG_STATE_HOME", join(home, ".local/state"));
  const cacheRoot = xdg(env, "XDG_CACHE_HOME", join(home, ".cache"));
  const runtimeRoot = xdg(env, "XDG_RUNTIME_DIR", tmpdir());
  return {
    config: join(configRoot, "omapilot"),
    state: join(stateRoot, "quickchat"),
    records: join(stateRoot, "quickchat/chats"),
    cache: join(cacheRoot, "quickchat"),
    images: join(cacheRoot, "quickchat/images"),
    adapters: join(cacheRoot, "quickchat/adapters"),
    runtime: join(runtimeRoot, "quickchat")
  };
}
