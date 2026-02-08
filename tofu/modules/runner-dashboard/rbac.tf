# Runner Dashboard Module - RBAC
#
# ServiceAccount for the dashboard pod + ClusterRole with read access
# to the runners namespace (pods, deployments, HPAs, events).

# =============================================================================
# ServiceAccount
# =============================================================================

resource "kubernetes_service_account" "dashboard" {
  metadata {
    name      = var.name
    namespace = local.namespace_name

    labels = local.labels
  }
}

# =============================================================================
# ClusterRole - Read access to runner resources
# =============================================================================

resource "kubernetes_cluster_role" "dashboard_reader" {
  metadata {
    name = "${var.name}-reader"

    labels = local.labels
  }

  # Pods - list, get, watch for status display
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "events", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  # Deployments - list, get for runner deployment status
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  # HPA - list, get for autoscaler status
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  # PDB - list, get for disruption budget status
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch"]
  }

  # Helm releases (if needed for runner status)
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = []
    verbs          = ["list"]
  }

  # Metrics (if metrics-server is available)
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

# =============================================================================
# ClusterRoleBinding - Bind to runners namespace
# =============================================================================

resource "kubernetes_cluster_role_binding" "dashboard_reader" {
  metadata {
    name = "${var.name}-reader"

    labels = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.dashboard_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.dashboard.metadata[0].name
    namespace = local.namespace_name
  }
}

# =============================================================================
# RoleBinding - Scoped read access to runners namespace specifically
# =============================================================================

resource "kubernetes_role_binding" "runners_reader" {
  metadata {
    name      = "${var.name}-reader"
    namespace = var.runners_namespace

    labels = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.dashboard_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.dashboard.metadata[0].name
    namespace = local.namespace_name
  }
}
