import { describe, it, expect, vi, beforeEach } from "vitest";
import { K8sClient } from "../client";
import type { K8sPod, K8sDeployment, K8sHPA } from "../client";

// Mock $env/dynamic/private
vi.mock("$env/dynamic/private", () => ({
  env: {
    K8S_PROXY_URL: "http://localhost:8001",
  },
}));

describe("K8sClient", () => {
  let client: K8sClient;

  beforeEach(() => {
    client = new K8sClient();
    client.resetAvailability();
    vi.restoreAllMocks();
  });

  describe("isAvailable", () => {
    it("should return true when API responds OK", async () => {
      vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response("{}", { status: 200 }),
      );
      expect(await client.isAvailable()).toBe(true);
    });

    it("should return false when API responds with error", async () => {
      vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response("", { status: 403 }),
      );
      expect(await client.isAvailable()).toBe(false);
    });

    it("should return false when fetch throws", async () => {
      vi.spyOn(globalThis, "fetch").mockRejectedValue(
        new Error("Connection refused"),
      );
      expect(await client.isAvailable()).toBe(false);
    });

    it("should cache availability result", async () => {
      const fetchSpy = vi
        .spyOn(globalThis, "fetch")
        .mockResolvedValue(new Response("{}", { status: 200 }));
      await client.isAvailable();
      await client.isAvailable();
      expect(fetchSpy).toHaveBeenCalledTimes(1);
    });
  });

  describe("listPods", () => {
    it("should return parsed pod items", async () => {
      const pods: K8sPod[] = [
        {
          metadata: {
            name: "bates-docker-abc",
            namespace: "bates-ils-runners",
            labels: { app: "gitlab-runner" },
            creationTimestamp: "2024-01-01T00:00:00Z",
          },
          status: { phase: "Running" },
        },
      ];

      vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response(
          JSON.stringify({ kind: "PodList", items: pods, metadata: {} }),
          {
            status: 200,
          },
        ),
      );

      const result = await client.listPods();
      expect(result).toHaveLength(1);
      expect(result[0].metadata.name).toBe("bates-docker-abc");
    });
  });

  describe("listDeployments", () => {
    it("should return parsed deployment items", async () => {
      const deployments: K8sDeployment[] = [
        {
          metadata: { name: "bates-docker", namespace: "bates-ils-runners" },
          spec: { replicas: 2 },
          status: {
            replicas: 2,
            readyReplicas: 2,
            availableReplicas: 2,
            updatedReplicas: 2,
          },
        },
      ];

      vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response(
          JSON.stringify({
            kind: "DeploymentList",
            items: deployments,
            metadata: {},
          }),
          { status: 200 },
        ),
      );

      const result = await client.listDeployments();
      expect(result).toHaveLength(1);
      expect(result[0].spec.replicas).toBe(2);
    });
  });

  describe("listHPAs", () => {
    it("should return parsed HPA items", async () => {
      const hpas: K8sHPA[] = [
        {
          metadata: {
            name: "bates-docker-hpa",
            namespace: "bates-ils-runners",
          },
          spec: { minReplicas: 1, maxReplicas: 5, metrics: [] },
          status: {
            currentReplicas: 2,
            desiredReplicas: 2,
            currentMetrics: [],
          },
        },
      ];

      vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response(
          JSON.stringify({ kind: "HPAList", items: hpas, metadata: {} }),
          { status: 200 },
        ),
      );

      const result = await client.listHPAs();
      expect(result).toHaveLength(1);
      expect(result[0].spec.maxReplicas).toBe(5);
    });
  });
});
