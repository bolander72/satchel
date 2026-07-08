export interface Config {
  port: number;
  /** Esplora-compatible upstream, e.g. https://mempool.space/api or a self-hosted esplora. */
  esploraUpstream: string;
  /** mempool.space-style base (for /v1/fees/recommended). Optional; falls back to esplora fee-estimates. */
  mempoolUpstream: string | undefined;
  feeCacheSeconds: number;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  return {
    port: Number(env.PORT ?? 3040),
    esploraUpstream: (env.ESPLORA_UPSTREAM ?? "https://mempool.space/api").replace(/\/$/, ""),
    mempoolUpstream: env.MEMPOOL_UPSTREAM?.replace(/\/$/, ""),
    feeCacheSeconds: Number(env.FEE_CACHE_SECONDS ?? 30),
  };
}
