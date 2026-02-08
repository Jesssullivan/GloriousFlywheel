# Package Repository Options Research

## Self-Hosted RPM, NuGet, and Ansible Content Repositories

**Date:** 2026-02-05
**Status:** Research Phase
**Context:** Complementary infrastructure to Nix/Bazel caching

---

## Executive Summary

This document evaluates self-hosted package repository options for RPM, NuGet, and Ansible content that could complement the existing Nix binary cache and planned Bazel remote cache infrastructure.

### Key Recommendations

1. **Start with GitLab Package Registry** - Already available with your GitLab instance, supports NuGet, Maven, npm, PyPI, and generic packages. Zero additional infrastructure.

2. **Nexus Community Edition** for unified needs - If you need RPM support or outgrow GitLab, Nexus provides a single platform for RPM, NuGet, npm, PyPI, Maven, and more. Free tier now includes Kubernetes support.

3. **Galaxy NG (via Pulp Operator)** for Ansible - If you have significant Ansible automation, Galaxy NG provides proper collection/role hosting with enterprise patterns.

4. **BaGetter** for NuGet-only - If you only need NuGet and want minimal overhead, BaGetter is lightweight and Kubernetes-ready.

5. **createrepo + nginx** for simple RPM - For basic internal RPM hosting, this pattern is simple and requires minimal resources.

---

## 1. RPM Repository Options

### Option A: Pulp 3 with pulp_rpm Plugin

[Pulp 3](https://pulpproject.org/) is the most feature-complete open-source option, developed by Red Hat.

**Pros:**

- Full RPM lifecycle management (sync, publish, version)
- Content mirroring from upstream repos
- Plugin architecture (RPM, Ansible, Container, Deb)
- S3/MinIO backend support via django-storages
- Kubernetes deployment via [pulp-operator](https://github.com/pulp/pulp-operator)

**Cons:**

- Complex architecture (API, content, workers, Redis, PostgreSQL)
- Higher resource requirements
- Steeper learning curve

**Resource Requirements:**
| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| Pulp API | 250m-1 | 256Mi-512Mi | Main API server |
| Pulp Content | 250m | 256Mi | Serves content |
| Pulp Worker | 2+ | 512Mi-1Gi | Sync/publish tasks |
| Redis | 100m | 128Mi | Task queue |
| PostgreSQL | 500m | 1Gi | Metadata storage |
| **Total** | ~3 CPU | ~3Gi | Plus shared services |

**MinIO Integration:**

```yaml
# pulp settings.py or CR spec
storages:
  s3:
    AWS_ACCESS_KEY_ID: "${MINIO_ACCESS_KEY}"
    AWS_SECRET_ACCESS_KEY: "${MINIO_SECRET_KEY}"
    AWS_STORAGE_BUCKET_NAME: "pulp-content"
    AWS_S3_ENDPOINT_URL: "http://minio.minio.svc:9000"
    AWS_S3_REGION_NAME: "us-east-1"
    AWS_DEFAULT_ACL: null
```

### Option B: Nexus Repository Manager

[Nexus Repository](https://www.sonatype.com/products/sonatype-nexus-oss) is a mature, unified repository manager.

**Editions:**

- **Community Edition** (Free) - Includes RPM, NuGet, npm, PyPI, Maven. New in 2024: Kubernetes compatibility and improved backup/resiliency.
- **Pro Edition** (~$120/user/year) - SSO, HA, replication, 24/7 support

**Pros:**

- Single platform for many package types
- Community Edition has good feature set
- [Official Helm chart](https://github.com/sonatype/nxrm3-helm-repository)
- Mature, well-documented

**Cons:**

- Larger memory footprint than single-purpose solutions
- HA requires Pro license
- Single-instance deprecation concerns

**Resource Requirements:**
| Deployment | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Minimal | 500m | 4Gi | 50Gi |
| Recommended | 1-2 | 6Gi | 200Gi |
| HA (Pro) | 2+ per node | 8Gi+ | S3/MinIO |

**Important Note:** As of late 2024, Sonatype deprecated the single-instance OSS Helm chart due to database corruption risks with embedded databases. The HA chart requires external PostgreSQL.

### Option C: JFrog Artifactory

[Artifactory](https://jfrog.com/artifactory/) is the most feature-rich option but has significant cost.

**Editions:**

- **OSS** (Apache 2.0) - Java packages only (Maven, Gradle)
- **Community** (Free, limited) - Container + C/C++ only
- **Pro** ($150/mo minimum) - All package types including RPM, NuGet

**Note:** Not recommended unless budget allows Pro. OSS edition lacks RPM/NuGet support.

### Option D: createrepo + nginx (Simple Approach)

For basic internal RPM hosting with minimal complexity.

**Architecture:**

```
┌─────────────────────────────────────────────────────┐
│                    Kubernetes                        │
├─────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐              │
│  │    nginx     │───▶│     PVC      │              │
│  │  (RPM repo)  │    │  (repo data) │              │
│  └──────────────┘    └──────────────┘              │
│         │                   ▲                       │
│         │                   │                       │
│         │            ┌──────────────┐              │
│         │            │  CronJob:    │              │
│         │            │  createrepo  │              │
│         │            └──────────────┘              │
└─────────────────────────────────────────────────────┘
```

**Resource Requirements:**
| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| nginx | 100m | 128Mi | - |
| PVC | - | - | 50Gi+ |
| CronJob | 100m | 256Mi | - |
| **Total** | 200m | 384Mi | 50Gi |

**Kubernetes Manifest Example:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rpm-repo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rpm-repo
  template:
    metadata:
      labels:
        app: rpm-repo
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: repo-data
              mountPath: /usr/share/nginx/html
      volumes:
        - name: repo-data
          persistentVolumeClaim:
            claimName: rpm-repo-pvc
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: createrepo-update
spec:
  schedule: "*/15 * * * *" # Every 15 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: createrepo
              image: fedora:latest
              command: ["createrepo_c", "--update", "/repo"]
              volumeMounts:
                - name: repo-data
                  mountPath: /repo
          volumes:
            - name: repo-data
              persistentVolumeClaim:
                claimName: rpm-repo-pvc
          restartPolicy: OnFailure
```

**Client Configuration:**

```bash
# /etc/yum.repos.d/internal.repo
[internal]
name=Internal Packages
baseurl=http://rpm-repo.prod.example.com/
enabled=1
gpgcheck=0  # or configure signing
```

---

## 2. NuGet Repository Options

### Option A: BaGet / BaGetter

[BaGetter](https://github.com/bagetter/BaGetter) is a community fork of BaGet with active development.

**Pros:**

- Lightweight (~100MB container)
- Cross-platform (.NET, runs on ARM)
- [Kubernetes deployment guides](https://thelinuxnotes.com/how-to-deploy-and-set-up-baget-server-in-kubernetes/)
- Supports NuGet V3 protocol
- Symbol server support
- S3/Azure/GCS storage backends

**Cons:**

- NuGet only (single purpose)
- Limited upstream mirroring (community feature)
- Smaller community than Nexus

**Resource Requirements:**
| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| BaGetter | 100m-500m | 256Mi-512Mi | PVC or S3 |

**Kubernetes Deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bagetter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bagetter
  template:
    metadata:
      labels:
        app: bagetter
    spec:
      containers:
        - name: bagetter
          image: bagetter/bagetter:latest
          ports:
            - containerPort: 5000
          env:
            - name: Storage__Type
              value: "FileSystem"
            - name: Storage__Path
              value: "/data/packages"
            - name: Database__Type
              value: "PostgreSql"
            - name: Database__ConnectionString
              valueFrom:
                secretKeyRef:
                  name: bagetter-secrets
                  key: db-connection-string
          volumeMounts:
            - name: packages
              mountPath: /data/packages
      volumes:
        - name: packages
          persistentVolumeClaim:
            claimName: bagetter-packages
```

### Option B: Nexus Repository Manager

Nexus supports NuGet in both Community and Pro editions.

**NuGet Features:**

- NuGet V2 and V3 API support
- Proxy (cache upstream nuget.org)
- Hosted (internal packages)
- Group (aggregate multiple sources)
- .NET CLI and Visual Studio compatible

### Option C: ProGet

[ProGet](https://inedo.com/proget) by Inedo is a commercial option with a free tier.

**Editions:**

- **Free** - Basic features, unlimited users, self-hosted
- **Basic** ($495/year) - Vulnerability scanning, retention policies
- **Enterprise** ($9,995/year) - HA, replication, LDAP

**Pros:**

- Strong NuGet support (company specializes in .NET tooling)
- Free tier is functional for small teams
- Kubernetes/Docker deployment supported
- Replication features

**Cons:**

- Commercial product (upgrades may require payment)
- Less open-source community

**Resource Requirements:**
| Edition | CPU | Memory | Storage |
|---------|-----|--------|---------|
| Free | 500m | 2Gi | 50Gi+ |
| HA | 1+ per node | 4Gi+ | S3 |

### Option D: GitLab Package Registry

Your existing GitLab instance already supports NuGet packages.

**Capabilities:**

- Project and group-level feeds
- NuGet V3 API
- Integrated with GitLab CI/CD
- Access control via GitLab permissions

**Limitations:**

- Publishing only at project level (not group level)
- No upstream proxy/caching
- Storage counts against GitLab limits

**Usage:**

```bash
# nuget.config
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="gitlab" value="https://gitlab.example.com/api/v4/projects/PROJECT_ID/packages/nuget/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <gitlab>
      <add key="Username" value="__token__" />
      <add key="ClearTextPassword" value="%GITLAB_TOKEN%" />
    </gitlab>
  </packageSourceCredentials>
</configuration>
```

---

## 3. Pulp for Ansible Content

### Galaxy NG (Self-Hosted Ansible Galaxy)

[Galaxy NG](https://ansible.readthedocs.io/projects/galaxy-ng/) is the upstream project for Red Hat Automation Hub.

**Components:**

- Pulp 3 core with pulp_ansible plugin
- Galaxy UI
- Collection and role management
- Namespace management

**Deployment Options:**

1. **Pulp Operator (Recommended for Kubernetes)**

   - Deploys via Kubernetes CRD
   - Manages all Pulp components
   - [Installation guide](https://pulpproject.org/pulp-operator/docs/admin/tutorials/quickstart-kubernetes/)

2. **Container Deployment**
   - Single container for testing
   - Multiple containers for production

**Resource Requirements:**
| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| Galaxy API | 500m | 512Mi | Django app |
| Pulp Worker | 2 | 1Gi | Collection processing |
| PostgreSQL | 500m | 1Gi | Metadata |
| Redis | 100m | 128Mi | Task queue |
| **Total** | ~3 CPU | ~3Gi | |

**Key Features:**

- Sync collections from galaxy.ansible.com
- Host private collections
- Role support
- Signature verification
- RBAC for namespaces

**Example Pulp CR for Galaxy NG:**

```yaml
apiVersion: repo-manager.pulpproject.org/v1beta2
kind: Pulp
metadata:
  name: galaxy
spec:
  deployment_type: galaxy
  image: quay.io/pulp/galaxy:latest
  storage_type: S3
  object_storage_s3_secret: galaxy-s3-credentials
  database:
    external_db_secret: galaxy-postgres
  api:
    replicas: 1
    resource_requirements:
      requests:
        cpu: 250m
        memory: 512Mi
  worker:
    replicas: 2
    resource_requirements:
      requests:
        cpu: 1
        memory: 1Gi
```

### Ansible Configuration

```yaml
# ansible.cfg
[galaxy]
server_list = org_galaxy, community_galaxy

[galaxy_server.org_galaxy]
url=https://galaxy.prod.example.com/api/galaxy/v3/
token=<your-token>

[galaxy_server.community_galaxy]
url=https://galaxy.ansible.com/
```

---

## 4. Unified Repository Platforms Comparison

### Feature Matrix

| Feature             | Nexus Community | Nexus Pro     | Pulp 3       | Artifactory Pro |
| ------------------- | --------------- | ------------- | ------------ | --------------- |
| **Package Types**   |                 |               |              |                 |
| RPM                 | Yes             | Yes           | Yes (plugin) | Yes             |
| NuGet               | Yes             | Yes           | No           | Yes             |
| npm                 | Yes             | Yes           | No           | Yes             |
| PyPI                | Yes             | Yes           | Yes (plugin) | Yes             |
| Maven               | Yes             | Yes           | No           | Yes             |
| Docker              | Yes             | Yes           | Yes (plugin) | Yes             |
| Helm                | Yes             | Yes           | No           | Yes             |
| Ansible Collections | No              | No            | Yes (plugin) | Yes             |
| **Features**        |                 |               |              |                 |
| Upstream Proxy      | Yes             | Yes           | Yes          | Yes             |
| S3 Backend          | No              | Yes           | Yes          | Yes             |
| HA/Clustering       | No              | Yes           | Yes          | Yes             |
| REST API            | Yes             | Yes           | Yes          | Yes             |
| LDAP/SSO            | Limited         | Yes           | Limited      | Yes             |
| Kubernetes Helm     | Yes             | Yes           | Yes          | Yes             |
| **Cost**            | Free            | ~$120/user/yr | Free         | ~$150/mo min    |
| **Complexity**      | Medium          | Medium        | High         | Medium          |

### Decision Matrix

| Scenario             | Recommendation     | Rationale               |
| -------------------- | ------------------ | ----------------------- |
| NuGet only           | BaGetter or GitLab | Minimal overhead        |
| RPM only             | createrepo + nginx | Simple, low resource    |
| Ansible only         | Galaxy NG          | Full collection support |
| Mixed (.NET + RPM)   | Nexus Community    | Unified platform        |
| Enterprise needs     | Nexus Pro          | HA + support            |
| Budget no constraint | Artifactory Pro    | Most features           |

---

## 5. Integration with Existing Stack

### MinIO S3 Backend

All major platforms support S3-compatible storage.

**Shared Bucket Strategy:**

```
minio.prod.example.com
├── attic/              # Nix binary cache
├── bazel-cache/        # Bazel remote cache
├── pulp-content/       # Pulp/Galaxy content (if used)
├── nexus-blobs/        # Nexus blob store (if used)
└── rpm-repo/           # Simple RPM repo (if used)
```

**Access Policy Example:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::nexus-blobs", "arn:aws:s3:::nexus-blobs/*"]
    }
  ]
}
```

### PostgreSQL (CNPG) Considerations

**Shared vs Dedicated:**

- **Shared cluster** - Cost-effective, simpler management, requires careful resource planning
- **Dedicated cluster** - Better isolation, independent scaling, more operational overhead

**Recommendation:** For ~50 developers, a shared CNPG cluster with separate databases is practical:

```yaml
# Database per service
databases:
  - attic # Existing Nix cache
  - nexus # Package repository (if added)
  - galaxy # Ansible Galaxy (if added)
```

**Resource Adjustment:**

```yaml
# CNPG Cluster spec update
spec:
  instances: 3
  resources:
    requests:
      memory: "2Gi" # Increased from 1Gi
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"
```

### GitLab Package Registry

Already available features:

| Package Type | Support Level                |
| ------------ | ---------------------------- |
| NuGet        | Full (project-level publish) |
| npm          | Full                         |
| PyPI         | Full                         |
| Maven        | Full                         |
| Generic      | Full                         |
| Conan (C++)  | Full                         |
| Go           | Full                         |
| Helm         | Full                         |
| RPM          | Experimental                 |
| Debian       | Experimental                 |

**When to use GitLab Package Registry:**

- Small number of packages
- Tight CI/CD integration needed
- No upstream proxy requirement
- Access control via GitLab groups

**When to deploy separate solution:**

- Need upstream proxy/caching
- High volume of packages
- Need RPM with full features
- Ansible collection hosting

### OpenTofu Module Pattern

Example module for Nexus deployment:

```hcl
# tofu/modules/nexus-repository/main.tf

resource "helm_release" "nexus" {
  name       = var.name
  namespace  = var.namespace
  repository = "https://sonatype.github.io/helm3-charts/"
  chart      = "nexus-repository-manager"
  version    = var.chart_version

  values = [
    yamlencode({
      persistence = {
        enabled      = true
        storageClass = var.storage_class
        accessMode   = "ReadWriteOnce"
        size         = var.storage_size
      }
      nexus = {
        resources = {
          requests = {
            cpu    = var.cpu_request
            memory = var.memory_request
          }
          limits = {
            cpu    = var.cpu_limit
            memory = var.memory_limit
          }
        }
      }
      ingress = {
        enabled   = true
        className = "nginx"
        hostRepo  = var.hostname
      }
    })
  ]
}

resource "kubernetes_secret" "nexus_s3" {
  count = var.s3_backend_enabled ? 1 : 0

  metadata {
    name      = "${var.name}-s3-credentials"
    namespace = var.namespace
  }

  data = {
    access-key = var.s3_access_key
    secret-key = var.s3_secret_key
  }
}
```

---

## 6. Resource Requirements Summary

### By Solution (Standalone)

| Solution           | Min CPU     | Min Memory | Storage   | PostgreSQL           |
| ------------------ | ----------- | ---------- | --------- | -------------------- |
| createrepo + nginx | 200m        | 384Mi      | 50Gi PVC  | No                   |
| BaGetter           | 500m        | 512Mi      | 50Gi PVC  | Optional             |
| Nexus Community    | 1           | 4Gi        | 100Gi PVC | External recommended |
| Nexus Pro (HA)     | 2+ per node | 8Gi+       | S3        | External required    |
| Pulp 3 (basic)     | 3           | 3Gi        | S3        | Yes                  |
| Galaxy NG          | 3           | 3Gi        | S3        | Yes                  |
| Artifactory Pro    | 2           | 4Gi        | 100Gi+    | Optional             |

### Recommended Stack

**Minimal (uses existing GitLab):**
| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| GitLab Package Registry | 0 | 0 | Included | Already available |
| **Total Additional** | 0 | 0 | 0 | |

**Standard (Nexus Community):**
| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Nexus | 1-2 | 4-6Gi | 100Gi PVC | RPM, NuGet, npm, PyPI |
| **Total Additional** | 1-2 | 4-6Gi | 100Gi | |

**Full (Nexus + Galaxy):**
| Component | CPU | Memory | Storage | Notes |
|-----------|-----|--------|---------|-------|
| Nexus | 1-2 | 4-6Gi | S3 | General packages |
| Galaxy NG | 3 | 3Gi | S3 | Ansible collections |
| CNPG (expanded) | +1 | +2Gi | - | Additional databases |
| **Total Additional** | 5-6 | 9-11Gi | ~100Gi S3 | |

### Storage Estimates by Package Type

| Package Type                | Typical Size  | Est. 1-Year Storage |
| --------------------------- | ------------- | ------------------- |
| RPM packages                | 10-100MB each | 20-50Gi (internal)  |
| NuGet packages              | 1-10MB each   | 10-30Gi             |
| npm packages                | 1-50MB each   | 20-50Gi             |
| Ansible collections         | 1-10MB each   | 5-20Gi              |
| **Total internal packages** | -             | 55-150Gi            |
| **Upstream cache**          | -             | 100-300Gi           |

---

## 7. Deployment Recommendations

### Phased Approach

**Phase 1: Evaluate GitLab Package Registry (0-3 months)**

- Use existing GitLab for NuGet, npm, PyPI
- No additional infrastructure
- Assess limitations in practice

**Phase 2: Add Specialized Solutions (3-6 months)**

- Deploy BaGetter if NuGet volume grows
- Deploy createrepo + nginx if RPM needed
- Monitor storage and performance

**Phase 3: Unified Platform (6-12 months)**

- Migrate to Nexus Community if multiple package types needed
- Consider Galaxy NG if Ansible automation grows
- Evaluate HA requirements

### Architecture Recommendation

```
┌─────────────────────────────────────────────────────────────────┐
│                    Production Cluster                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                     MinIO (S3)                           │   │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │   │
│   │  │  attic   │ │  bazel   │ │  nexus   │ │  galaxy  │   │   │
│   │  │  bucket  │ │  bucket  │ │  bucket  │ │  bucket  │   │   │
│   │  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │   │
│   └─────────────────────────────────────────────────────────┘   │
│          │              │              │              │          │
│          ▼              ▼              ▼              ▼          │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐    │
│   │  Attic   │   │  bazel-  │   │  Nexus   │   │ Galaxy   │    │
│   │  Server  │   │  remote  │   │ Community│   │   NG     │    │
│   └──────────┘   └──────────┘   └──────────┘   └──────────┘    │
│          │              │              │              │          │
│          └──────────────┼──────────────┼──────────────┘          │
│                         │              │                         │
│                         ▼              ▼                         │
│                  ┌─────────────────────────────┐                │
│                  │     PostgreSQL (CNPG)        │                │
│                  │  attic_db | nexus_db | ...   │                │
│                  └─────────────────────────────┘                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Quick Decision Guide

| Question                    | If Yes                   | If No               |
| --------------------------- | ------------------------ | ------------------- |
| Need NuGet only?            | BaGetter or GitLab       | Continue            |
| Have significant RPM needs? | Nexus or Pulp            | Continue            |
| Heavy Ansible automation?   | Galaxy NG                | Skip                |
| Need upstream caching?      | Nexus (has proxy)        | GitLab is fine      |
| Budget for commercial?      | Nexus Pro or Artifactory | OSS options         |
| Want single platform?       | Nexus Community          | Purpose-built tools |

---

## 8. References

### RPM Repository

- [Pulp Project](https://pulpproject.org/) - Full-featured repository platform
- [Pulp Operator](https://github.com/pulp/pulp-operator) - Kubernetes deployment
- [Nexus Repository Manager](https://www.sonatype.com/products/sonatype-nexus-oss) - Unified platform
- [createrepo Documentation](https://quintessence.sh/blog/createrepo-guide-linux/) - Simple RPM hosting

### NuGet Repository

- [BaGetter](https://github.com/bagetter/BaGetter) - Lightweight NuGet server
- [BaGet Kubernetes Guide](https://thelinuxnotes.com/how-to-deploy-and-set-up-baget-server-in-kubernetes/)
- [ProGet](https://inedo.com/proget) - Commercial NuGet server
- [NuGet Private Server Comparison 2025](https://blog.inedo.com/nuget/private-server-comparison-guide/)
- [GitLab NuGet Registry](https://docs.gitlab.com/user/packages/nuget_repository/)

### Ansible Content

- [Galaxy NG Documentation](https://ansible.readthedocs.io/projects/galaxy-ng/)
- [Galaxy NG Setup Guide](https://c2platform.org/docs/howto/awx/galaxy/)
- [Pulp Ansible Plugin](https://docs.pulpproject.org/pulp_ansible/)

### Unified Platforms

- [Nexus OSS vs Pro Features](https://www.sonatype.com/products/sonatype-nexus-oss-vs-pro-features)
- [Nexus Helm Charts](https://github.com/sonatype/nxrm3-helm-repository)
- [Artifactory Pricing](https://jfrog.com/pricing/)
- [Repository Comparison](https://blog.packagecloud.io/repository-showdown-artifactory-vs-nexus-vs-proget/)

### Storage Configuration

- [Pulp S3 Storage](https://pulpproject.org/pulpcore/docs/admin/guides/configure-pulp/configure-storages/)
- [Nexus Blob Stores](https://help.sonatype.com/en/blob-store-types.html)
- [GitLab Package Registry Administration](https://docs.gitlab.com/administration/packages/)

---

## Appendix: OpenTofu Module Stubs

### BaGetter Module

```hcl
# tofu/modules/bagetter/variables.tf
variable "namespace" {
  type    = string
  default = "package-registry"
}

variable "storage_class" {
  type    = string
  default = "standard"
}

variable "storage_size" {
  type    = string
  default = "50Gi"
}

variable "postgres_connection_string" {
  type      = string
  sensitive = true
}

variable "hostname" {
  type = string
}
```

```hcl
# tofu/modules/bagetter/main.tf
resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_deployment" "bagetter" {
  metadata {
    name      = "bagetter"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "bagetter"
      }
    }

    template {
      metadata {
        labels = {
          app = "bagetter"
        }
      }

      spec {
        container {
          name  = "bagetter"
          image = "bagetter/bagetter:latest"

          port {
            container_port = 5000
          }

          env {
            name  = "Storage__Type"
            value = "FileSystem"
          }

          env {
            name  = "Storage__Path"
            value = "/data/packages"
          }

          env {
            name  = "Database__Type"
            value = "PostgreSql"
          }

          env {
            name = "Database__ConnectionString"
            value_from {
              secret_key_ref {
                name = "bagetter-db"
                key  = "connection-string"
              }
            }
          }

          volume_mount {
            name       = "packages"
            mount_path = "/data/packages"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "packages"
          persistent_volume_claim {
            claim_name = "bagetter-packages"
          }
        }
      }
    }
  }
}
```

### Galaxy NG Module (Pulp Operator)

```hcl
# tofu/modules/galaxy-ng/main.tf
resource "helm_release" "pulp_operator" {
  name       = "pulp-operator"
  namespace  = var.namespace
  repository = "https://pulp.github.io/pulp-operator/"
  chart      = "pulp-operator"
  version    = var.operator_version

  create_namespace = true
}

resource "kubectl_manifest" "galaxy" {
  depends_on = [helm_release.pulp_operator]

  yaml_body = yamlencode({
    apiVersion = "repo-manager.pulpproject.org/v1beta2"
    kind       = "Pulp"
    metadata = {
      name      = "galaxy"
      namespace = var.namespace
    }
    spec = {
      deployment_type = "galaxy"
      image           = "quay.io/pulp/galaxy:latest"
      storage_type    = "S3"
      object_storage_s3_secret = "galaxy-s3"
      database = {
        external_db_secret = "galaxy-postgres"
      }
      api = {
        replicas = 1
      }
      worker = {
        replicas = 2
      }
    }
  })
}
```
