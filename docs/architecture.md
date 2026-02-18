# Technical Architecture Guide

This document describes the full infrastructure of the **Unagi** messenger platform.
It is intended for engineers, SREs, and operators who need to understand, modify, or
debug any part of the stack.

---

## Table of Contents

1. [High-Level Overview](#high-level-overview)
2. [AWS Account & Regions](#aws-account--regions)
3. [Network (VPC)](#network-vpc)
4. [Compute — EC2](#compute--ec2)
5. [Kubernetes — EKS](#kubernetes--eks)
6. [ECR URL and Docker Image Strategy](#ecr-url-and-docker-image-strategy)
7. [Databases](#databases)
8. [Object Storage — S3](#object-storage--s3)
9. [DNS — Route 53](#dns--route-53)
10. [Certificate Management](#certificate-management)
11. [Monitoring & Alerting](#monitoring--alerting)
12. [Ansible Roles Reference](#ansible-roles-reference)
13. [Adding a New User](#adding-a-new-user)
14. [Secrets Management](#secrets-management)
15. [CI/CD Pipeline](#cicd-pipeline)
16. [Environment Variable Reference](#environment-variable-reference)

---

## High-Level Overview

```
Internet
   │
   ▼
Route 53 (public DNS)
   │
   ▼
AWS ALB  ──────────────────────────────────────────────────────────────┐
   │                                                                    │
   ▼                                                                    │
ingress-nginx (EKS)                                          EC2 MGMT node
   │                                                      (Ansible control plane,
   ├── datacore (DocumentDB + RDS)                         RabbitMQ, monitoring)
   ├── notification-service (DocumentDB + RabbitMQ)
   ├── msgc (RDS)
   ├── agora-token-service
   ├── storage-service (S3)
   ├── chatbot (OpenAI)
   ├── support / retool / metabase
   └── website
```

---

## AWS Account & Regions

| Environment | Region |
|---|---|
| `dev` | `us-east-1` |
| `prod` | `eu-west-1` |

The Terraform backend (state + lock) is always stored in `us-east-1` regardless of
the workspace.

---

## Network (VPC)

Each environment has its own isolated VPC.

| Setting | dev | prod |
|---|---|---|
| CIDR | `172.18.0.0/16` | `172.16.0.0/16` |
| Public subnets | 2 AZs | 2 AZs |
| Private subnets | 2 AZs | 2 AZs |
| Database subnets | 2 AZs | 2 AZs |
| NAT Gateway | Yes | Yes |

Subnet tagging follows the AWS Load Balancer Controller convention so that ALBs and
NLBs can be automatically provisioned from Kubernetes `Ingress` / `Service` resources.

**File:** [terraform/vpc.tf](../terraform/vpc.tf)

---

## Compute — EC2

Two EC2 instances exist per environment:

| Instance | Type | Purpose |
|---|---|---|
| `mgmt` | t2.micro | Ansible control plane, RabbitMQ, monitoring sidecar |
| `insight` | t2.micro | Business intelligence tools (Metabase, Retool) |

Both instances use Ubuntu 22.04, have 60 GB EBS root volumes, and are reachable via
a non-standard SSH port (defined per environment in `tfvars`).

**File:** [terraform/ec2.tf](../terraform/ec2.tf)

---

## Kubernetes — EKS

- **Version:** 1.27
- **Node group:** managed, auto-scaling (`c5.large` dev / `c5.xlarge` prod)
- **Auth:** IAM users mapped to `system:masters` via `aws-auth` ConfigMap

### Installed Helm components

| Chart | Purpose |
|---|---|
| `metrics-server` | Pod resource metrics |
| `cluster-autoscaler` | Node auto-scaling |
| `aws-load-balancer-controller` | ALB/NLB integration |
| `external-dns` | Automatic Route 53 record management |
| `cert-manager` | TLS certificate automation (Let's Encrypt) |
| `ingress-nginx` | HTTP ingress with rate limiting (memcached) |
| `calico` | Network policy enforcement |
| `container-insights` | CloudWatch log/metric shipping |
| `cloudwatch-grafana` | Grafana dashboards backed by CloudWatch |

**File:** [terraform/eks.tf](../terraform/eks.tf)

---

## ECR URL and Docker Image Strategy

> **Important concept — read this before deploying any service.**

The `ecr_url` variable (defined in
[ansible/inventories/group_vars/all/all.yml](../ansible/inventories/group_vars/all/all.yml))
points to the **Elastic Container Registry** where all Unagi service images live.

### How it works

Each application service (datacore, notification-service, msgc, etc.) has its
**own separate source code repository** with its own CI pipeline.
When code is merged to the `master` branch of a service repo, that pipeline:

1. Builds a Docker image for the service.
2. Tags it with a unique identifier (pipeline ID + branch + short commit SHA),
   e.g. `1095505281-master-6324903a`.
3. Pushes the image to ECR under the shared registry path:
   `<ecr_url>/<service-name>:<tag>`

This infrastructure repository then **consumes** those pre-built images.
The Kubernetes deployment templates (Ansible Jinja2 `.j2` files) reference the ECR
URL using the `{{ ecr_url }}` variable, for example:

```yaml
image: {{ ecr_url }}/data-core:1095505281-master-6324903a
```

### Setting the ECR URL

In `ansible/inventories/group_vars/all/all.yml`, set:

```yaml
ecr_url: "<YOUR_AWS_ACCOUNT_ID>.dkr.ecr.<YOUR_AWS_REGION>.amazonaws.com/unagi"
```

Replace:
- `<YOUR_AWS_ACCOUNT_ID>` — your 12-digit AWS account ID
- `<YOUR_AWS_REGION>` — the AWS region where ECR lives (e.g. `eu-central-1`)

### Updating a service image

To deploy a new version of a service, update the image tag in the corresponding
Ansible role template (e.g.
`ansible/roles/datacore/templates/deployment.yml.j2`) and re-run the playbook.

---

## Databases

### RDS — PostgreSQL 15.3

Used by the `msgc` service.

| Setting | dev | prod |
|---|---|---|
| Identifier | `msgc-dev` | `msgc-prod` |
| Instance | `db.t4g.small` | `db.t4g.medium` |
| Storage | 25 GB (max 30 GB) | 25 GB (max 100 GB) |
| Multi-AZ | Yes | Yes |
| Encryption | Yes | Yes |
| Backups | 7 days | 7 days |

Credentials are generated by Terraform and stored in **AWS Secrets Manager**.
The secret name is referenced in the Ansible inventory (`rds_msgc_secret_name`).

**File:** [terraform/rds.tf](../terraform/rds.tf)

### DocumentDB — MongoDB 5.0

Used by `datacore` and `notification-service`.

| Setting | dev | prod |
|---|---|---|
| Cluster | `datacore-dev` | `datacore-prod` |
| Instance | `db.t4g.small` | `db.t4g.medium` |
| Instances | 2 | 2 |
| Storage encryption | Yes | Yes |
| Backups | 7 days | 7 days |

Credentials are stored in AWS Secrets Manager
(secret name referenced via `docdb_datacore_secret_name`).

**File:** [terraform/docdb.tf](../terraform/docdb.tf)

---

## Object Storage — S3

Three buckets per environment:

| Bucket | Purpose | ACL |
|---|---|---|
| `unagi-profiles-<env>` | User profile pictures | public-read |
| `unagi-files-<env>` | Shared files & media | public-read |
| `unagi-assets-<env>` | Static application assets | public-read |

An IAM user (`s3-storageservice-user-<env>`) is created with scoped S3 permissions
and its access key is stored in AWS Secrets Manager.

**File:** [terraform/s3.tf](../terraform/s3.tf)

---

## DNS — Route 53

| Zone | Type | Purpose |
|---|---|---|
| `unagi.prod` / `unagi.dev` | Private | Internal service discovery |
| `unagi.com` (prod) / `dev.unagi.com` (dev) | Public (data source) | External traffic |

EC2 instances get DNS records under the internal domain:
- `mgmt.infra.<internal_domain>`
- `insight.infra.<internal_domain>`

**File:** [terraform/route53.tf](../terraform/route53.tf)

---

## Certificate Management

`cert-manager` is installed in the EKS cluster and configured with two
Let's Encrypt issuers:

- `letsencrypt-staging` — for testing (no rate limits)
- `letsencrypt-prod` — for production certificates

Certificates are requested automatically when an `Ingress` resource references
an issuer annotation.

---

## Monitoring & Alerting

- **Prometheus + Grafana** on the MGMT EC2 node (via `monitoring` Ansible role)
- **CloudWatch Container Insights** on EKS nodes
- **Grafana dashboards** backed by CloudWatch (deployed via Helm)
- **SNS → Lambda → Slack** for CloudWatch alarms on RDS and DocumentDB

The Slack webhook URL is configured in `slack_alert_hook` (per-environment variable).

**File:** [terraform/cw-alerts.tf](../terraform/cw-alerts.tf)

---

## Ansible Roles Reference

| Role | Manages |
|---|---|
| `common` | System packages, sysctl tuning |
| `kernel` | Kernel version pinning |
| `user-mgmt` | Linux users and SSH keys |
| `unagi-ca` | Internal Certificate Authority |
| `monitoring` | Prometheus / Grafana on EC2 |
| `rabbitmq` | RabbitMQ message broker |
| `storage-service` | S3 proxy service |
| `third-parties` | Third-party API integrations |
| `notification-service` | Push / email / SMS notifications |
| `datacore` | Core data API (auth, wallet, payments) |
| `msgc` | Messaging cluster service |
| `agora-token-service` | Agora video/voice token generation |
| `ingress-nginx-memcached` | Rate-limiting cache for ingress |
| `support` | Support ticket system |
| `website` | Public marketing website |
| `metabase` | Business intelligence |
| `retool` | Internal tooling |
| `chatbot` | AI chatbot service |

---

## Adding a New User

1. Open `ansible/roles/user-mgmt/defaults/main.yml`.
2. Add an entry under `usermgmt_users` (technical) or `usermgmt_business_users` (non-technical):

```yaml
- name: "Full Name"
  username: "f-lastname"
  keys: "ssh-rsa AAAA... user@unagi.me"
  shell: "/bin/bash"
  group: "infra"          # omit for non-infra users
  add_key_to_root: true   # omit for non-infra users
```

3. Run the playbook targeting the `user-mgmt` role:

```bash
ansible-playbook site.yml -i inventories/prod \
  -e "ansible_user=<your-username>" \
  --tags user-mgmt
```

---

## Secrets Management

All runtime secrets (database credentials, API keys, webhook URLs) are stored in
**AWS Secrets Manager** and fetched at deploy time by Ansible or mounted into
Kubernetes pods via external-secrets or Ansible tasks.

**Never commit real credentials to this repository.**
Use the `*.tfvars.example` files as templates and keep your actual `*.tfvars` files
local (they are excluded by `.gitignore`).

---

## CI/CD Pipeline

This repository uses **GitHub Actions** for automated quality checks.

| Workflow | Trigger | Jobs |
|---|---|---|
| [Lint](.github/workflows/lint.yml) | push / PR to `main` | `ansible-lint`, `tflint` |
| [Security Scan](.github/workflows/security.yml) | push / PR to `main` | `terrascan`, `checkov` |

---

## Environment Variable Reference

Key variables used across `terraform/*.tfvars` and `ansible/inventories/`:

| Variable | Where | Description |
|---|---|---|
| `project` | tfvars, group_vars | Project name (`unagi`) |
| `environment` | tfvars, group_vars | Deployment environment (`dev` / `prod`) |
| `aws_region` | tfvars, group_vars | AWS region |
| `aws_account_id` | tfvars | AWS account ID |
| `public_domain` | tfvars, group_vars | Externally reachable domain |
| `internal_domain` | tfvars, group_vars | VPC-internal domain |
| `website_domain` | tfvars, group_vars | Marketing website domain |
| `ecr_url` | group_vars/all | ECR registry prefix for all service images |
| `slack_alert_hook` | tfvars, group_vars | Slack incoming webhook URL for CloudWatch alarms |
| `ec2_general_config` | tfvars | SSH port and cloud-init user-data |
| `keypair_default` | tfvars | EC2 SSH key pair (name + public key) |
