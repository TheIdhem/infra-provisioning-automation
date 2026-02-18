# Quick-Start: Deploy Unagi Infrastructure

This guide walks you through provisioning the Unagi messenger infrastructure from scratch.
No prior Terraform or Ansible experience is required — just follow the steps in order.

---

## Prerequisites

Install the following tools on your machine before you begin:

| Tool | Minimum version | Install |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.4 | `brew install terraform` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.x | `brew install awscli` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.27 | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | `brew install helm` |
| [Python](https://www.python.org/downloads/) | 3.11 | `brew install python` |
| [Pipenv](https://pipenv.pypa.io/en/latest/installation/) | latest | `pip install pipenv` |

---

## Step 1 — Clone the repository

```bash
git clone <YOUR_REPOSITORY_URL>
cd infrastructure-as-code
git submodule update --init --recursive
```

> The `--recursive` flag pulls in all Ansible collections required for the playbooks.

---

## Step 2 — Create the Terraform state bucket and lock table

Before running Terraform, you need two AWS resources that store its state:

1. **S3 Bucket** — stores the Terraform state file
   Name: `unagi-iac-terraform-state`

2. **DynamoDB Table** — prevents concurrent runs from conflicting
   Name: `unagi-iac-terraform-locks` | Partition key: `LockID`

You can create them via the AWS Console or with these commands:

```bash
# Create the S3 state bucket (replace <REGION> with your AWS region)
aws s3api create-bucket \
  --bucket unagi-iac-terraform-state \
  --region <REGION> \
  --create-bucket-configuration LocationConstraint=<REGION>

aws s3api put-bucket-versioning \
  --bucket unagi-iac-terraform-state \
  --versioning-configuration Status=Enabled

# Create the DynamoDB lock table
aws dynamodb create-table \
  --table-name unagi-iac-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region <REGION>
```

---

## Step 3 — Set up AWS credentials

```bash
export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
export AWS_DEFAULT_REGION="<YOUR_AWS_REGION>"
```

The IAM user associated with these keys needs at minimum the permissions listed in
[docs/iam-permissions.md](iam-permissions.md) (or use `AdministratorAccess` for initial setup,
then tighten later).

---

## Step 4 — Create your environment variables file

Copy the example and fill in your values:

```bash
# For production
cp terraform/prod.tfvars.example terraform/prod.tfvars

# For development
cp terraform/dev.tfvars.example terraform/dev.tfvars
```

Open the file you just created and replace every `<PLACEHOLDER>` with real values.
The comments in the example file explain what each variable means.

> **Security note:** `*.tfvars` files are in `.gitignore` and will never be committed.
> Keep them local or store them in a secrets manager.

---

## Step 5 — Provision AWS infrastructure with Terraform

```bash
cd terraform

terraform init

# Select or create the workspace for your environment
terraform workspace new prod   # first time
# or
terraform workspace select prod

# Preview what will be created
terraform plan --var-file=prod.tfvars

# Apply (this takes 15-20 minutes)
terraform apply --var-file=prod.tfvars
```

When complete, Terraform prints the outputs (EKS cluster name, RDS endpoint, etc.).
Note these down — you will need them in the next step.

---

## Step 6 — Configure infrastructure with Ansible

### 6a — Add your SSH key

```bash
cd ../assets
chmod 400 prod_keypair_default
eval $(ssh-agent)
ssh-add prod_keypair_default
# Enter your key passphrase when prompted
```

### 6b — Install Ansible dependencies

```bash
cd ../ansible
pipenv install
pipenv shell
```

### 6c — Fresh installation (first time only)

```bash
ansible-playbook site.yml \
  -i inventories/prod \
  -e "presetup_mode=upgrade ansible_user=root" \
  --tags never,all
```

### 6d — Subsequent runs

```bash
ansible-playbook site.yml \
  -i inventories/prod \
  -e "ansible_user=<your-username>"
```

---

## Step 7 — Verify the deployment

```bash
# Configure kubectl to talk to the new cluster
aws eks update-kubeconfig \
  --region <YOUR_AWS_REGION> \
  --name <EKS_CLUSTER_NAME>

# Check that all pods are running
kubectl get pods --all-namespaces
```

All pods should reach `Running` or `Completed` state within a few minutes.

---

## Tear-down

```bash
cd terraform
terraform destroy --var-file=prod.tfvars
```

> This removes **all** AWS resources including data. Only do this in a development environment.

---

## Getting Help

- See [Technical Architecture Guide](architecture.md) for a deeper explanation of every component.
- Open an issue in this repository for infrastructure-related problems.
