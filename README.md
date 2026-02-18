# Unagi — Telecommunications Infrastructure as Code

Unagi is the infrastructure layer for a cloud-native messenger platform built on AWS.
This repository provisions and configures every component required to run the Unagi messaging services — from the VPC and EKS cluster down to per-service Kubernetes deployments.

## Documentation

| Audience | Document |
|---|---|
| **Just want to deploy the infra** | [Quick-Start Guide](docs/quick-start.md) |
| **Engineers & operators** | [Technical Architecture Guide](docs/architecture.md) |

## Repository Layout

```
.
├── terraform/          # AWS infrastructure (VPC, EKS, RDS, DocumentDB, S3, …)
├── ansible/            # Configuration management and Kubernetes service deployments
│   ├── inventories/    # Per-environment host and variable files
│   └── roles/          # Ansible roles (one per service or concern)
├── assets/             # Lambda functions and SSH key pairs
├── .github/workflows/  # CI/CD pipelines (lint + security scan)
└── docs/               # Extended documentation
```

## Tech Stack

- **Terraform** — AWS infrastructure provisioning
- **Ansible** — EC2 configuration & Kubernetes manifest deployment
- **AWS EKS** — Managed Kubernetes cluster
- **AWS RDS (PostgreSQL)** — Relational database (`msgc` service)
- **AWS DocumentDB** — MongoDB-compatible document store (`datacore` service)
- **AWS S3** — Object storage (profiles, files, assets)
- **Helm** — Kubernetes package manager (ingress-nginx, cert-manager, monitoring …)

## Environments

| Name | Purpose |
|---|---|
| `dev` | Development & integration testing |
| `prod` | Production |

## Contributing

1. Fork and branch off `main`
2. Follow the [Technical Architecture Guide](docs/architecture.md) for conventions
3. Run `ansible-lint` and `tflint` locally before opening a PR
4. The CI pipeline will run full lint and security scans automatically

## License

Apache 2.0 — see [LICENSE](LICENSE).
