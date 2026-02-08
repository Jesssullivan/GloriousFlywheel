import type { DriftItem } from "$lib/types";
import type { TfVarsDocument } from "./tfvars-parser";
import type { HPAStatus } from "$lib/types";

/**
 * Detect drift between desired config (tfvars) and live K8s state.
 */
export function detectDrift(
  config: TfVarsDocument,
  hpas: HPAStatus[],
): DriftItem[] {
  const drifts: DriftItem[] = [];

  // Check HPA replica counts against config
  for (const hpa of hpas) {
    const runnerPrefix = hpa.name.replace("runner-", "");

    // Check min replicas
    const configMinKey = `${runnerPrefix}_hpa_min_replicas`;
    const configMin = config.values[configMinKey];
    if (
      configMin !== undefined &&
      typeof configMin === "number" &&
      hpa.min_replicas !== configMin
    ) {
      drifts.push({
        runner: hpa.name,
        field: "hpa.min_replicas",
        expected: String(configMin),
        actual: String(hpa.min_replicas),
        severity: "warning",
      });
    }

    // Check max replicas
    const configMaxKey = `${runnerPrefix}_hpa_max_replicas`;
    const configMax = config.values[configMaxKey];
    if (
      configMax !== undefined &&
      typeof configMax === "number" &&
      hpa.max_replicas !== configMax
    ) {
      drifts.push({
        runner: hpa.name,
        field: "hpa.max_replicas",
        expected: String(configMax),
        actual: String(hpa.max_replicas),
        severity: "warning",
      });
    }
  }

  // Check for runners that should be deployed but aren't in HPA list
  const deployedRunners = ["docker", "dind", "rocky8", "rocky9", "nix"];
  for (const runner of deployedRunners) {
    const deployKey = `deploy_${runner}_runner`;
    const shouldDeploy = config.values[deployKey];
    if (shouldDeploy === true) {
      const hpaName = `runner-${runner}`;
      const found = hpas.some(
        (h) => h.name === hpaName || h.name.startsWith(hpaName),
      );
      if (!found && hpas.length > 0) {
        drifts.push({
          runner: hpaName,
          field: "deployment",
          expected: "deployed",
          actual: "not found",
          severity: "error",
        });
      }
    }
  }

  return drifts;
}
