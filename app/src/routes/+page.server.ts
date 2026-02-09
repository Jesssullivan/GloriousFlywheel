import { MOCK_RUNNERS, MOCK_HPA_STATUS, MOCK_DASHBOARD_METRICS } from "$lib/mocks";
import type { PageServerLoad } from "./$types";

export const load: PageServerLoad = async ({ fetch }) => {
  const [runnersRes, metricsRes, hpaRes] = await Promise.all([
    fetch("/api/runners").catch(() => null),
    fetch("/api/metrics").catch(() => null),
    fetch("/api/k8s/hpa").catch(() => null),
  ]);

  const runnersData = runnersRes?.ok ? await runnersRes.json() : null;
  const metricsData = metricsRes?.ok ? await metricsRes.json() : null;
  const hpaData = hpaRes?.ok ? await hpaRes.json() : null;

  return {
    runners: runnersData?.runners ?? MOCK_RUNNERS,
    metrics: metricsData?.metrics ?? MOCK_DASHBOARD_METRICS,
    hpas: hpaData?.hpas ?? MOCK_HPA_STATUS,
  };
};
