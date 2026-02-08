import { describe, it, expect } from "vitest";
import { detectDrift } from "../drift";
import { parseTfVars } from "../tfvars-parser";
import type { HPAStatus } from "$lib/types";

const SAMPLE = `deploy_docker_runner = true
deploy_dind_runner = false
deploy_nix_runner = false
deploy_rocky8_runner = false
deploy_rocky9_runner = false
docker_hpa_min_replicas = 1
docker_hpa_max_replicas = 5`;

describe("detectDrift", () => {
  it("should detect no drift when config matches", () => {
    const doc = parseTfVars(SAMPLE);
    const hpas: HPAStatus[] = [
      {
        name: "runner-docker",
        current_replicas: 2,
        desired_replicas: 2,
        min_replicas: 1,
        max_replicas: 5,
        conditions: [],
      },
    ];
    const drifts = detectDrift(doc, hpas);
    expect(drifts).toHaveLength(0);
  });

  it("should detect max_replicas drift", () => {
    const doc = parseTfVars(SAMPLE);
    const hpas: HPAStatus[] = [
      {
        name: "runner-docker",
        current_replicas: 2,
        desired_replicas: 2,
        min_replicas: 1,
        max_replicas: 3, // Config says 5
        conditions: [],
      },
    ];
    const drifts = detectDrift(doc, hpas);
    expect(drifts.some((d) => d.field === "hpa.max_replicas")).toBe(true);
  });

  it("should detect missing deployments", () => {
    const multiDeploy = `deploy_docker_runner = true
deploy_dind_runner = true
deploy_nix_runner = false
deploy_rocky8_runner = false
deploy_rocky9_runner = false
docker_hpa_min_replicas = 1
docker_hpa_max_replicas = 5`;
    const doc = parseTfVars(multiDeploy);
    // docker is deployed, dind is missing
    const hpas: HPAStatus[] = [
      {
        name: "runner-docker",
        current_replicas: 1,
        desired_replicas: 1,
        min_replicas: 1,
        max_replicas: 5,
        conditions: [],
      },
    ];
    const drifts = detectDrift(doc, hpas);
    const missing = drifts.filter((d) => d.field === "deployment");
    expect(missing.length).toBeGreaterThan(0);
  });
});
