export type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export class UpstreamError extends Error {
  constructor(
    public readonly status: number,
    public readonly body: string,
  ) {
    super(`upstream ${status}: ${body.slice(0, 200)}`);
  }
}

/** Thin client for an Esplora-compatible HTTP API (blockstream.info, mempool.space, self-hosted). */
export class EsploraUpstream {
  constructor(
    private readonly baseUrl: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  private async get(path: string): Promise<Response> {
    const res = await this.fetchImpl(`${this.baseUrl}${path}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) throw new UpstreamError(res.status, await res.text());
    return res;
  }

  async addressInfo(address: string): Promise<unknown> {
    return (await this.get(`/address/${address}`)).json();
  }

  async addressUtxos(address: string): Promise<unknown> {
    return (await this.get(`/address/${address}/utxo`)).json();
  }

  async addressTxs(address: string, afterTxid?: string): Promise<unknown> {
    const suffix = afterTxid ? `/chain/${afterTxid}` : "";
    return (await this.get(`/address/${address}/txs${suffix}`)).json();
  }

  async tx(txid: string): Promise<unknown> {
    return (await this.get(`/tx/${txid}`)).json();
  }

  async txStatus(txid: string): Promise<unknown> {
    return (await this.get(`/tx/${txid}/status`)).json();
  }

  async txHex(txid: string): Promise<string> {
    return (await this.get(`/tx/${txid}/hex`)).text();
  }

  async tipHeight(): Promise<string> {
    return (await this.get(`/blocks/tip/height`)).text();
  }

  async feeEstimates(): Promise<Record<string, number>> {
    return (await this.get(`/fee-estimates`)).json() as Promise<Record<string, number>>;
  }

  async broadcast(rawTxHex: string): Promise<string> {
    const res = await this.fetchImpl(`${this.baseUrl}/tx`, {
      method: "POST",
      headers: { "content-type": "text/plain" },
      body: rawTxHex,
    });
    const body = await res.text();
    if (!res.ok) throw new UpstreamError(res.status, body);
    return body.trim(); // txid
  }
}
