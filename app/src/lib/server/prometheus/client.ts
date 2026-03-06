import { env } from "$env/dynamic/private";

export class PrometheusError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "PrometheusError";
  }
}

export interface InstantResult {
  metric: Record<string, string>;
  value: [number, string]; // [timestamp, value]
}

export interface RangeResult {
  metric: Record<string, string>;
  values: [number, string][]; // [timestamp, value][]
}

interface PrometheusResponse<T> {
  status: "success" | "error";
  data: {
    resultType: "vector" | "matrix" | "scalar" | "string";
    result: T[];
  };
  error?: string;
  errorType?: string;
}

export class PrometheusClient {
  private baseUrl: string;
  private available: boolean | null = null;
  private availableCheckedAt = 0;
  private readonly AVAILABILITY_TTL = 60_000;

  constructor(baseUrl?: string) {
    this.baseUrl = baseUrl ?? env.PROMETHEUS_URL ?? "http://prometheus:9090";
  }

  async isAvailable(): Promise<boolean> {
    if (
      this.available !== null &&
      Date.now() - this.availableCheckedAt < this.AVAILABILITY_TTL
    ) {
      return this.available;
    }
    try {
      const response = await fetch(`${this.baseUrl}/-/healthy`, {
        signal: AbortSignal.timeout(3000),
      });
      this.available = response.ok;
    } catch {
      this.available = false;
    }
    this.availableCheckedAt = Date.now();
    return this.available;
  }

  resetAvailability() {
    this.available = null;
    this.availableCheckedAt = 0;
  }

  async instantQuery(query: string, time?: number): Promise<InstantResult[]> {
    const params = new URLSearchParams({ query });
    if (time) params.set("time", time.toString());

    const response = await this.fetch<InstantResult>(`/api/v1/query?${params}`);
    return response.data.result;
  }

  async rangeQuery(
    query: string,
    start: number,
    end: number,
    step: string,
  ): Promise<RangeResult[]> {
    const params = new URLSearchParams({
      query,
      start: start.toString(),
      end: end.toString(),
      step,
    });

    const response = await this.fetch<RangeResult>(
      `/api/v1/query_range?${params}`,
    );
    return response.data.result;
  }

  private async fetch<T>(path: string): Promise<PrometheusResponse<T>> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      throw new PrometheusError(
        response.status,
        `Prometheus query failed: ${response.status}`,
      );
    }

    const data = (await response.json()) as PrometheusResponse<T>;
    if (data.status === "error") {
      throw new PrometheusError(500, data.error ?? "Unknown Prometheus error");
    }

    return data;
  }
}

export const prometheus = new PrometheusClient();
