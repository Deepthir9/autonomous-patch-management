# Autonomous Patch Management — IBM Cloud VPC Baseline

Terraform project for the **Autonomous Patch Management with watsonx Orchestrate** proof-of-concept.

This configuration provisions the minimum IBM Cloud infrastructure required to reach the next phase of the project:

```
Terraform → IBM Cloud VPC → Ubuntu VM → Floating IP
```

> **Provider-verified** — all resources audited against the IBM Cloud Terraform provider source and the official [`terraform-ibm-modules/landing-zone-vsi`](https://registry.terraform.io/modules/terraform-ibm-modules/landing-zone-vsi/ibm/latest) reference module (v6.6.2, 407 K downloads).

---

## Resources created

| Resource | IBM Cloud type | Name pattern |
|---|---|---|
| VPC | `ibm_is_vpc` | `<instance_name>-vpc` |
| Subnet | `ibm_is_subnet` | `<instance_name>-subnet` |
| Security group | `ibm_is_security_group` | `<instance_name>-sg` |
| SSH inbound rule (TCP 22) | `ibm_is_security_group_rule` | — |
| Outbound allow-all rule | `ibm_is_security_group_rule` | — |
| SSH key | `ibm_is_ssh_key` | `<instance_name>-key` |
| Virtual server instance | `ibm_is_instance` | `<instance_name>-vsi` |
| Floating IP | `ibm_is_floating_ip` | `<instance_name>-fip` |

The VSI uses **Ubuntu 24.04 LTS** (latest available public image) and the `bx2-2x8` profile (2 vCPU / 8 GB RAM) — the smallest balanced profile suitable for a demo workload.

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- IBM Cloud Terraform provider >= 1.70.0 (pinned `>= 1.70.0, < 3.0.0` in `versions.tf`)
- An [IBM Cloud API key](https://cloud.ibm.com/iam/apikeys) with VPC Infrastructure Editor and Resource Group Viewer permissions
- An existing IBM Cloud resource group
- An SSH key pair — RSA or Ed25519 both work (`ssh-keygen -t ed25519 -C "apm-demo"`)

---

## Variables

| Variable | Description | Default |
|---|---|---|
| `ibmcloud_api_key` | IBM Cloud API key (**sensitive**) | — |
| `instance_name` | Name prefix for all resources | `apm-demo` |
| `region` | IBM Cloud region | `us-south` |
| `resource_group` | Existing resource group name | `Default` |
| `ssh_public_key` | SSH public key contents (**sensitive**) | — |
| `zone` | Availability zone | `us-south-1` |

---

## Usage

### Option 1 — Local Terraform CLI

1. Copy the example variable file and fill in your values:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

   > **Never commit `terraform.tfvars` to version control.** It is listed in `.gitignore`.

2. Initialise, plan, and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. Retrieve the floating IP:

   ```bash
   terraform output instance_floating_ip
   ```

4. SSH into the instance:

   ```bash
   ssh ubuntu@$(terraform output -raw instance_floating_ip)
   ```

5. Destroy when done:

   ```bash
   terraform destroy
   ```

### Option 2 — IBM Cloud Schematics

1. Create a new **Schematics Workspace** in the [IBM Cloud console](https://cloud.ibm.com/schematics/workspaces).
2. Point it at this repository (or upload a `.tar.gz` of the project).
3. Set the Terraform version to **1.5** or later.
4. Add the required variables in the workspace **Variables** panel:
   - Mark `ibmcloud_api_key` and `ssh_public_key` as **sensitive**.
5. Click **Generate plan**, review, then **Apply plan**.
6. Find the `instance_floating_ip` value in the **Outputs** tab.

---

## Example `terraform.tfvars`

Create a `terraform.tfvars` file (never commit this file):

```hcl
ibmcloud_api_key = "YOUR_IBM_CLOUD_API_KEY"
ssh_public_key   = "ssh-ed25519 AAAA... your-comment"
region           = "us-south"
zone             = "us-south-1"
resource_group   = "Default"
instance_name    = "apm-demo"
```

---

## Outputs

| Output | Description |
|---|---|
| `instance_floating_ip` | Public IP address of the Ubuntu VSI |
| `instance_id` | IBM Cloud resource ID of the VSI |
| `instance_name` | Name of the VSI |
| `vpc_id` | IBM Cloud resource ID of the VPC |

---

## Security notes

- The SSH security group rule allows inbound TCP 22 from `0.0.0.0/0`. Restrict the `remote` CIDR to your own IP range before using in any shared environment.
- The API key and SSH public key variables are marked `sensitive = true` and will not appear in Terraform plan/apply output or Schematics logs.
- No credentials are stored in any Terraform file. Supply them via `terraform.tfvars` (local) or Schematics workspace variables (cloud).

---

## Provider audit notes

The following issues were identified and corrected against the IBM Cloud provider docs and the official `landing-zone-vsi` reference module:

| Issue | Fix applied |
|---|---|
| `ibm_is_security_group_rule` used a nested `tcp {}` block — removed in provider ≥ 1.60 and not supported in Schematics | Replaced with flat `protocol = "tcp"`, `port_min`, `port_max` arguments |
| `data "ibm_is_images"` used a `filter {}` nested block that does not exist on this data source | Replaced with top-level `status` and `name_filter` arguments |
| Image selection used `[0]` on an unsorted list — non-deterministic across API calls | Added `reverse(sort(...))` to consistently pick the newest image ID |
| `ibm_is_instance` had no `lifecycle` block — risk of unintended re-creation if the base image is updated | Added `lifecycle { ignore_changes = [image] }` matching the official IBM module pattern |
| Provider version `>= 1.67.0` admitted versions below 1.70 that lack full SG rule / VNI support | Tightened to `>= 1.70.0, < 3.0.0` |

---

## Next steps

Once the floating IP is reachable, the next phase of the project will layer in:

- watsonx Orchestrate integration
- Automated patch detection and application workflow
- Reporting and audit trail

---

## License

Apache 2.0
