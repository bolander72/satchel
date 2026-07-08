import { serve } from "@hono/node-server";
import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const app = buildApp({ config });

serve({ fetch: app.fetch, port: config.port }, (info) => {
  console.log(`wallet-backend listening on :${info.port}`);
  console.log(`  esplora upstream: ${config.esploraUpstream}`);
  if (config.mempoolUpstream) console.log(`  mempool upstream: ${config.mempoolUpstream}`);
});
