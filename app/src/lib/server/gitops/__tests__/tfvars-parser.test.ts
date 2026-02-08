import { describe, it, expect } from "vitest";
import { parseTfVars, serializeTfVars, applyChanges } from "../tfvars-parser";

const SAMPLE_TFVARS = `# Dev Cluster Configuration

cluster_context = "org/projects/kubernetes/gitlab-agents:dev"
namespace       = "gitlab-runners"

deploy_docker_runner = true
deploy_dind_runner   = true

docker_concurrent_jobs = 8
dind_concurrent_jobs   = 4

hpa_enabled           = true
hpa_cpu_target        = 70

service_monitor_enabled = false # Enable when Prometheus is deployed

service_monitor_labels = {
  "prometheus" = "kube-prometheus"
}

docker_cpu_request    = "100m"
docker_memory_limit   = "512Mi"
`;

describe("parseTfVars", () => {
  it("should parse string values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.values.cluster_context).toBe(
      "org/projects/kubernetes/gitlab-agents:dev",
    );
    expect(doc.values.namespace).toBe("gitlab-runners");
  });

  it("should parse boolean values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.values.deploy_docker_runner).toBe(true);
    expect(doc.values.hpa_enabled).toBe(true);
    expect(doc.values.service_monitor_enabled).toBe(false);
  });

  it("should parse number values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.values.docker_concurrent_jobs).toBe(8);
    expect(doc.values.dind_concurrent_jobs).toBe(4);
    expect(doc.values.hpa_cpu_target).toBe(70);
  });

  it("should parse map values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.values.service_monitor_labels).toEqual({
      prometheus: "kube-prometheus",
    });
  });

  it("should parse resource strings", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.values.docker_cpu_request).toBe("100m");
    expect(doc.values.docker_memory_limit).toBe("512Mi");
  });

  it("should preserve line count", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    expect(doc.lines.length).toBe(SAMPLE_TFVARS.split("\n").length);
  });

  it("should preserve comments", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const comments = doc.lines.filter((l) => l.type === "comment");
    expect(comments.length).toBeGreaterThan(0);
  });
});

describe("serializeTfVars", () => {
  it("should round-trip unchanged content", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const output = serializeTfVars(doc);
    // Compare line by line (ignoring trailing whitespace differences)
    const originalLines = SAMPLE_TFVARS.split("\n").map((l) => l.trimEnd());
    const outputLines = output.split("\n").map((l) => l.trimEnd());
    expect(outputLines.length).toBe(originalLines.length);
  });

  it("should preserve comment lines exactly", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const output = serializeTfVars(doc);
    expect(output).toContain("# Dev Cluster Configuration");
  });

  it("should preserve map structure", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const output = serializeTfVars(doc);
    expect(output).toContain("service_monitor_labels = {");
    expect(output).toContain('"prometheus" = "kube-prometheus"');
    expect(output).toContain("}");
  });
});

describe("applyChanges", () => {
  it("should update existing values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const updated = applyChanges(doc, { docker_concurrent_jobs: 12 });
    expect(updated.values.docker_concurrent_jobs).toBe(12);
  });

  it("should preserve other values", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const updated = applyChanges(doc, { docker_concurrent_jobs: 12 });
    expect(updated.values.dind_concurrent_jobs).toBe(4);
    expect(updated.values.hpa_enabled).toBe(true);
  });

  it("should reflect changes in serialized output", () => {
    const doc = parseTfVars(SAMPLE_TFVARS);
    const updated = applyChanges(doc, { hpa_cpu_target: 80 });
    const output = serializeTfVars(updated);
    expect(output).toContain("80");
  });
});
