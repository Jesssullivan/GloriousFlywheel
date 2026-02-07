import { json } from "@sveltejs/kit";
import type { RequestHandler } from "./$types";
import { detectDrift } from "$lib/server/gitops/drift";
import { parseTfVars } from "$lib/server/gitops/tfvars-parser";
import { k8sClient } from "$lib/server/k8s/client";
import type { K8sHPA } from "$lib/server/k8s/client";
import { MOCK_HPA_STATUS } from "$lib/mocks";
import type { HPAStatus } from "$lib/types/metrics";
import { readFileSync } from "fs";
import { resolve } from "path";

function mapHPA(k8s: K8sHPA): HPAStatus {
  const cpuMetric = k8s.spec.metrics?.find(
    (m) => m.resource?.name === "cpu",
  );
  const memMetric = k8s.spec.metrics?.find(
    (m) => m.resource?.name === "memory",
  );
  return {
    name: k8s.metadata.name,
    current_replicas: k8s.status.currentReplicas,
    desired_replicas: k8s.status.desiredReplicas,
    min_replicas: k8s.spec.minReplicas,
    max_replicas: k8s.spec.maxReplicas,
    cpu_current: k8s.status.currentMetrics?.find(
      (m) => m.resource?.name === "cpu",
    )?.resource?.current?.averageUtilization,
    cpu_target: cpuMetric?.resource?.target?.averageUtilization,
    memory_current: k8s.status.currentMetrics?.find(
      (m) => m.resource?.name === "memory",
    )?.resource?.current?.averageUtilization,
    memory_target: memMetric?.resource?.target?.averageUtilization,
    conditions: [],
  };
}

export const GET: RequestHandler = async () => {
  try {
    const tfvarsPath = resolve(
      "..",
      "tofu/stacks/bates-ils-runners/beehive.tfvars",
    );
    const content = readFileSync(tfvarsPath, "utf-8");
    const doc = parseTfVars(content);

    let hpas: HPAStatus[];
    if (await k8sClient.isAvailable()) {
      const k8sHpas = await k8sClient.listHPAs();
      hpas = k8sHpas.map(mapHPA);
    } else {
      hpas = MOCK_HPA_STATUS;
    }

    const drifts = detectDrift(doc, hpas);
    return json({ drifts });
  } catch {
    return json({ drifts: [] });
  }
};
