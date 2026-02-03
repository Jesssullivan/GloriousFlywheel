# CloudNativePG PostgreSQL - Backup Resources
#
# Additional backup-related resources including:
# - Backup bucket (Civo Object Storage)
# - On-demand backup resource
# - Recovery configuration helpers

# =============================================================================
# Civo Object Storage for Backups (Optional)
# =============================================================================

# This can be used if you want this module to create the backup bucket
# Alternatively, use the civo-object-store module separately

resource "kubectl_manifest" "backup_bucket_secret" {
  count = var.enable_backup && var.create_backup_bucket && var.backup_s3_access_key_id != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "${var.name}-backup-s3"
      namespace = var.namespace
      labels    = local.labels
    }
    type = "Opaque"
    stringData = {
      ACCESS_KEY_ID     = var.backup_s3_access_key_id
      SECRET_ACCESS_KEY = var.backup_s3_secret_access_key
    }
  })
}

# =============================================================================
# On-Demand Backup Template
# =============================================================================

# This creates an on-demand backup that can be triggered manually
# Use: kubectl apply -f - to trigger a backup

resource "kubernetes_config_map" "backup_template" {
  count = var.enable_backup ? 1 : 0

  metadata {
    name      = "${var.name}-backup-template"
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "on-demand-backup.yaml" = <<-EOT
      # On-demand backup for ${var.name}
      # Apply this manifest to trigger an immediate backup:
      #   kubectl apply -f on-demand-backup.yaml
      #
      apiVersion: postgresql.cnpg.io/v1
      kind: Backup
      metadata:
        name: ${var.name}-backup-$(date +%Y%m%d-%H%M%S)
        namespace: ${var.namespace}
      spec:
        cluster:
          name: ${var.name}
    EOT

    "pitr-recovery.yaml" = <<-EOT
      # Point-in-Time Recovery template for ${var.name}
      # WARNING: This will destroy existing data and restore from backup
      #
      # 1. Delete the existing cluster:
      #    kubectl delete cluster ${var.name} -n ${var.namespace}
      #
      # 2. Modify recovery_target_time below and apply:
      #    kubectl apply -f pitr-recovery.yaml
      #
      apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      metadata:
        name: ${var.name}
        namespace: ${var.namespace}
      spec:
        instances: ${var.instances}

        storage:
          size: ${var.storage_size}
          storageClass: ${var.storage_class}

        # Recovery from backup
        bootstrap:
          recovery:
            source: ${var.name}
            # Uncomment and set target time for PITR:
            # recoveryTarget:
            #   targetTime: "2024-01-15 10:30:00"  # ISO 8601 format

        # Backup source reference
        externalClusters:
          - name: ${var.name}
            barmanObjectStore:
              destinationPath: s3://${var.backup_s3_bucket}/${var.name}/
              endpointURL: ${var.backup_s3_endpoint}
              s3Credentials:
                accessKeyId:
                  name: ${var.create_s3_credentials_secret ? "${var.name}-s3-credentials" : var.backup_s3_credentials_secret}
                  key: ACCESS_KEY_ID
                secretAccessKey:
                  name: ${var.create_s3_credentials_secret ? "${var.name}-s3-credentials" : var.backup_s3_credentials_secret}
                  key: SECRET_ACCESS_KEY
    EOT
  }
}

# =============================================================================
# Backup Configuration Variables
# =============================================================================

variable "create_backup_bucket" {
  description = "Create backup bucket resources (use civo-object-store module for full control)"
  type        = bool
  default     = false
}
