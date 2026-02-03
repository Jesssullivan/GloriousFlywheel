# CloudNativePG PostgreSQL Cluster Module - Variables
#
# Comprehensive variable definitions for production PostgreSQL deployments.

# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  description = "Name of the PostgreSQL cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Name must be lowercase alphanumeric with optional hyphens"
  }
}

variable "namespace" {
  description = "Kubernetes namespace for the cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "Namespace must be lowercase alphanumeric with optional hyphens"
  }
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.database_name))
    error_message = "Database name must start with letter, contain only lowercase letters, numbers, underscores"
  }
}

variable "owner_name" {
  description = "Database owner/application user name"
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.owner_name))
    error_message = "Owner name must start with letter, contain only lowercase letters, numbers, underscores"
  }
}

# =============================================================================
# Instance Configuration
# =============================================================================

variable "instances" {
  description = "Number of PostgreSQL instances (1=standalone, 3=HA recommended)"
  type        = number
  default     = 3

  validation {
    condition     = var.instances >= 1 && var.instances <= 10
    error_message = "instances must be between 1 and 10"
  }
}

variable "part_of" {
  description = "Application this database is part of (for labeling)"
  type        = string
  default     = "application"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "storage_size" {
  description = "Storage size for each PostgreSQL instance"
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "Kubernetes storage class"
  type        = string
  default     = "civo-volume"
}

# =============================================================================
# PostgreSQL Configuration
# =============================================================================

variable "max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections >= 10 && var.max_connections <= 10000
    error_message = "max_connections must be between 10 and 10000"
  }
}

variable "shared_buffers" {
  description = "Shared buffer memory"
  type        = string
  default     = "256MB"
}

variable "statement_timeout" {
  description = "Statement timeout (e.g., '60s', '5min')"
  type        = string
  default     = "60s"
}

variable "log_statement" {
  description = "SQL statement logging level (none, ddl, mod, all)"
  type        = string
  default     = "ddl"

  validation {
    condition     = contains(["none", "ddl", "mod", "all"], var.log_statement)
    error_message = "log_statement must be one of: none, ddl, mod, all"
  }
}

variable "locale" {
  description = "Database locale"
  type        = string
  default     = "en_US.UTF-8"
}

variable "additional_postgresql_parameters" {
  description = "Additional PostgreSQL parameters"
  type        = map(string)
  default     = {}
}

variable "additional_pg_hba_rules" {
  description = "Additional pg_hba.conf rules"
  type        = list(string)
  default     = []
}

# =============================================================================
# Authentication
# =============================================================================

variable "generate_password" {
  description = "Generate a random password for the application user"
  type        = bool
  default     = true
}

variable "app_password" {
  description = "Application user password (required if generate_password is false)"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# Resource Limits
# =============================================================================

variable "cpu_request" {
  description = "CPU request for each PostgreSQL instance"
  type        = string
  default     = "250m"
}

variable "cpu_limit" {
  description = "CPU limit for each PostgreSQL instance"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request for each PostgreSQL instance"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit for each PostgreSQL instance"
  type        = string
  default     = "1Gi"
}

# =============================================================================
# High Availability
# =============================================================================

variable "pod_anti_affinity_type" {
  description = "Pod anti-affinity type (required or preferred)"
  type        = string
  default     = "required"

  validation {
    condition     = contains(["required", "preferred"], var.pod_anti_affinity_type)
    error_message = "pod_anti_affinity_type must be 'required' or 'preferred'"
  }
}

variable "topology_key" {
  description = "Topology key for pod anti-affinity"
  type        = string
  default     = "kubernetes.io/hostname"
}

variable "primary_update_strategy" {
  description = "Primary update strategy (unsupervised or supervised)"
  type        = string
  default     = "unsupervised"

  validation {
    condition     = contains(["unsupervised", "supervised"], var.primary_update_strategy)
    error_message = "primary_update_strategy must be 'unsupervised' or 'supervised'"
  }
}

variable "switchover_delay" {
  description = "Switchover delay in seconds"
  type        = number
  default     = 60
}

variable "start_delay" {
  description = "Start delay in seconds"
  type        = number
  default     = 30
}

variable "stop_delay" {
  description = "Stop delay in seconds"
  type        = number
  default     = 30
}

# =============================================================================
# Pod Disruption Budget
# =============================================================================

variable "enable_pdb" {
  description = "Enable Pod Disruption Budget"
  type        = bool
  default     = true
}

variable "pdb_min_available" {
  description = "Minimum available pods (integer or percentage)"
  type        = string
  default     = "2"
}

# =============================================================================
# Backup Configuration
# =============================================================================

variable "enable_backup" {
  description = "Enable backup to S3-compatible storage"
  type        = bool
  default     = true
}

variable "backup_s3_endpoint" {
  description = "S3 endpoint URL for backups"
  type        = string
  default     = ""
}

variable "backup_s3_bucket" {
  description = "S3 bucket for backups"
  type        = string
  default     = ""
}

variable "backup_s3_credentials_secret" {
  description = "Name of existing secret with S3 credentials"
  type        = string
  default     = ""
}

variable "create_s3_credentials_secret" {
  description = "Create S3 credentials secret (provide access_key_id and secret_access_key)"
  type        = bool
  default     = false
}

variable "backup_s3_access_key_id" {
  description = "S3 access key ID (required if create_s3_credentials_secret is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "backup_s3_secret_access_key" {
  description = "S3 secret access key (required if create_s3_credentials_secret is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "backup_retention_policy" {
  description = "Backup retention policy (e.g., '30d')"
  type        = string
  default     = "30d"
}

variable "backup_wal_compression" {
  description = "WAL compression algorithm (gzip, bzip2, snappy)"
  type        = string
  default     = "gzip"
}

variable "backup_wal_max_parallel" {
  description = "Max parallel WAL uploads"
  type        = number
  default     = 2
}

variable "backup_data_compression" {
  description = "Data backup compression algorithm"
  type        = string
  default     = "gzip"
}

variable "enable_scheduled_backup" {
  description = "Enable scheduled backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule in cron format"
  type        = string
  default     = "0 0 * * *" # Daily at midnight
}

variable "backup_immediate" {
  description = "Take an immediate backup when scheduled backup is created"
  type        = bool
  default     = true
}

# =============================================================================
# TLS Configuration
# =============================================================================

variable "enable_tls" {
  description = "Enable TLS for client connections"
  type        = bool
  default     = true
}

variable "server_tls_secret" {
  description = "Name of secret containing server TLS certificate"
  type        = string
  default     = ""
}

variable "server_ca_secret" {
  description = "Name of secret containing server CA certificate"
  type        = string
  default     = ""
}

variable "client_ca_secret" {
  description = "Name of secret containing client CA certificate"
  type        = string
  default     = ""
}

variable "replication_tls_secret" {
  description = "Name of secret containing replication TLS certificate"
  type        = string
  default     = ""
}

# =============================================================================
# Monitoring
# =============================================================================

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "custom_queries_configmap" {
  description = "Name of ConfigMap containing custom Prometheus queries"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Operator log level for this cluster"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warning", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warning, error"
  }
}
