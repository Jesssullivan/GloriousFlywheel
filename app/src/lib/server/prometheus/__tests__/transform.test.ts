import { describe, it, expect } from "vitest";
import { toTimeSeries, toMetricValue, toValueMap } from "../transform";
import type { RangeResult, InstantResult } from "../client";

describe("toTimeSeries", () => {
  it("should transform range results to time series", () => {
    const results: RangeResult[] = [
      {
        metric: { pod: "runner-docker-abc123" },
        values: [
          [1700000000, "0.5"],
          [1700000030, "0.7"],
        ],
      },
    ];

    const series = toTimeSeries(results);
    expect(series).toHaveLength(1);
    expect(series[0].label).toBe("runner-docker-abc123");
    expect(series[0].values).toEqual([0.5, 0.7]);
    expect(series[0].timestamps).toHaveLength(2);
  });

  it("should handle multiple series", () => {
    const results: RangeResult[] = [
      { metric: { runner: "runner-docker" }, values: [[1700000000, "1"]] },
      { metric: { runner: "runner-nix" }, values: [[1700000000, "2"]] },
    ];

    const series = toTimeSeries(results);
    expect(series).toHaveLength(2);
    expect(series[0].label).toBe("runner-docker");
    expect(series[1].label).toBe("runner-nix");
  });

  it("should handle empty results", () => {
    expect(toTimeSeries([])).toEqual([]);
  });
});

describe("toMetricValue", () => {
  it("should extract value from first result", () => {
    const results: InstantResult[] = [
      { metric: {}, value: [1700000000, "42.5"] },
    ];

    const mv = toMetricValue(results);
    expect(mv.value).toBe(42.5);
  });

  it("should return default value for empty results", () => {
    const mv = toMetricValue([], 0);
    expect(mv.value).toBe(0);
  });

  it("should use custom default value", () => {
    const mv = toMetricValue([], -1);
    expect(mv.value).toBe(-1);
  });
});

describe("toValueMap", () => {
  it("should map labels to values", () => {
    const results: InstantResult[] = [
      { metric: { pod: "docker-1" }, value: [1700000000, "0.5"] },
      { metric: { pod: "nix-1" }, value: [1700000000, "0.8"] },
    ];

    const map = toValueMap(results);
    expect(map).toEqual({ "docker-1": 0.5, "nix-1": 0.8 });
  });

  it("should use custom label key", () => {
    const results: InstantResult[] = [
      { metric: { runner: "runner-docker" }, value: [1700000000, "3"] },
    ];

    const map = toValueMap(results, "runner");
    expect(map).toEqual({ "runner-docker": 3 });
  });

  it("should use 'unknown' for missing labels", () => {
    const results: InstantResult[] = [{ metric: {}, value: [1700000000, "1"] }];

    const map = toValueMap(results);
    expect(map).toEqual({ unknown: 1 });
  });

  it("should handle empty results", () => {
    expect(toValueMap([])).toEqual({});
  });
});
