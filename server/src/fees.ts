import type { FetchLike } from "./upstream.js";
import { EsploraUpstream } from "./upstream.js";

/** sat/vB tiers the client renders as slow / normal / fast. */
export interface FeeRecommendation {
  fastestFee: number;
  halfHourFee: number;
  hourFee: number;
  economyFee: number;
  minimumFee: number;
}

interface CacheEntry {
  value: FeeRecommendation;
  fetchedAtMs: number;
}

export class FeeService {
  private cache: CacheEntry | null = null;

  constructor(
    private readonly esplora: EsploraUpstream,
    private readonly opts: {
      mempoolUpstream: string | undefined;
      cacheSeconds: number;
      fetchImpl?: FetchLike;
      now?: () => number;
    },
  ) {}

  private now(): number {
    return (this.opts.now ?? Date.now)();
  }

  async recommended(): Promise<FeeRecommendation> {
    if (this.cache && this.now() - this.cache.fetchedAtMs < this.opts.cacheSeconds * 1000) {
      return this.cache.value;
    }
    const value = await this.fetchFresh();
    this.cache = { value, fetchedAtMs: this.now() };
    return value;
  }

  private async fetchFresh(): Promise<FeeRecommendation> {
    if (this.opts.mempoolUpstream) {
      try {
        const fetchImpl = this.opts.fetchImpl ?? fetch;
        const res = await fetchImpl(`${this.opts.mempoolUpstream}/v1/fees/recommended`);
        if (res.ok) {
          const body = (await res.json()) as Partial<FeeRecommendation>;
          if (typeof body.fastestFee === "number") return normalize(body as FeeRecommendation);
        }
      } catch {
        // fall through to esplora fee-estimates
      }
    }
    return fromEsploraEstimates(await this.esplora.feeEstimates());
  }
}

/** Convert Esplora's { "1": rate, "3": rate, ... confirmation-target map } into tiers. */
export function fromEsploraEstimates(estimates: Record<string, number>): FeeRecommendation {
  const at = (target: number): number => {
    // Esplora returns a sparse map; take the closest target at or above the requested one.
    const targets = Object.keys(estimates)
      .map(Number)
      .filter((t) => Number.isFinite(t))
      .sort((a, b) => a - b);
    const chosen = targets.find((t) => t >= target) ?? targets[targets.length - 1];
    const rate = chosen !== undefined ? estimates[String(chosen)] : undefined;
    return rate ?? 1;
  };
  return normalize({
    fastestFee: at(1),
    halfHourFee: at(3),
    hourFee: at(6),
    economyFee: at(144),
    minimumFee: 1,
  });
}

function normalize(fees: FeeRecommendation): FeeRecommendation {
  const ceil = (n: number) => Math.max(1, Math.ceil(n));
  const fastest = ceil(fees.fastestFee);
  const halfHour = Math.min(ceil(fees.halfHourFee), fastest);
  const hour = Math.min(ceil(fees.hourFee), halfHour);
  const economy = Math.min(ceil(fees.economyFee), hour);
  return {
    fastestFee: fastest,
    halfHourFee: halfHour,
    hourFee: hour,
    economyFee: economy,
    minimumFee: Math.min(ceil(fees.minimumFee), economy),
  };
}
