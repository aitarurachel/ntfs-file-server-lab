# NTFS File Server Lab

> **Series:** Windows Infrastructure on Azure | **Lab:** 1 of 3  
> **Stack:** Terraform · PowerShell · Azure · Active Directory · NTFS · SMB  

---

## What Problem This Solves

Every organization running Windows infrastructure faces the same access control challenge: **who can see what data, and who can change it**.

- Finance data should only be readable by Finance staff
- HR files should be invisible to Sales
- IT staff need administrative access everywhere to do their jobs

The solution, still widely deployed in enterprise environments, including hybrid cloud, is a **Windows File Server backed by Active Directory security groups, with NTFS permissions enforced at the filesystem layer**.

---

## Architecture Overview and Permissions Logic

Three VMs (DC01, FS01, CLIENT01) sit inside an isolated VNet, with DC01 handling authentication, FS01 enforcing NTFS permissions on SMB shares, and CLIENT01 serving as the workstation for testing.  Azure Key Vault stores credentials, and an NSG restricts inbound RDP.
<br>
<br>
<img width="742" height="488" alt="ntfs architecture" src="https://github.com/user-attachments/assets/e0d65d08-c224-4bed-9770-0ac61018d088" />
<br>
<br>
The three VMs, right-sized to fit a constrained core quota, are running in Central US
<br>
<br>
<img width="1458" height="427" alt="ntfs VMs" src="https://github.com/user-attachments/assets/881ecff2-b9d6-4027-a5ee-3e5efd53f3ff" />
<br>

### Permission Matrix

| User | Department | \\FS01\Finance | \\FS01\HR | \\FS01\Sales | \\FS01\IT |
|---|---|---|---|---|---|
| sarah.jones | Finance | ✅ Read/Write | ❌ Denied | ❌ Denied | ❌ Denied |
| mike.brown | Finance | ✅ Read/Write | ❌ Denied | ❌ Denied | ❌ Denied |
| lisa.white | HR | ✅ Read only | ✅ Read/Write | ❌ Denied | ❌ Denied |
| john.smith | IT | ✅ Full Control | ✅ Full Control | ✅ Full Control | ✅ Full Control |
| tom.davis | Sales | ❌ Denied | ❌ Denied | ✅ Read/Write | ❌ Denied |

### How permissions are applied:

Permissions are applied by `scripts/02-configure-shares-and-permissions.ps1`, which runs on FS01. It sets share-level access to Everyone Full Control (just the network entry point) which is intentional and not a security gap, while the real enforcement happens at the NTFS layer, where the script strips default permissions and grants explicit rights to AD security groups (e.g., `GRP_Finance` = Modify, `GRP_HR` = Read-only, `GRP_IT` = Full Control) using icacls/grants. Because access is tied to group membership rather than individual users, changing someone's group instantly changes their access with no folder-level changes required.
<br>
<br>
<img width="714" height="127" alt="ntfs permissions code" src="https://github.com/user-attachments/assets/b7d23494-c361-4463-bf4b-6ac4ce7fdf1f" />
<br>

### File Structure

```
ntfs-lab-terraform/
├── backend.tf                              ← remote state → Azure Blob Storage
├── versions.tf                             ← provider versions
├── variables.tf                            ← all input variables
├── main.tf                                 ← VMs, VNet, NSG, NICs, public IPs
├── keyvault.tf                             ← Key Vault + secret + RBAC assignment
├── outputs.tf                              ← IPs and Key Vault name
├── terraform.tfvars.example               ← safe template, safe to commit
├── terraform.tfvars                        ← your real values, never commit this
├── .gitignore
├── configure-lab.ps1                       ← the only script you run manually
└── scripts/
    ├── 00-promote-dc.ps1                   ← DC01: installs AD DS, promotes DC
    ├── 01-create-ad-users-groups.ps1       ← DC01: creates OUs, groups, users
    ├── 02-configure-shares-and-permissions.ps1  ← FS01: SMB shares + NTFS ACLs
    ├── 03-configure-rdp-gpo.ps1            ← DC01: RDP Group Policy Object
    ├── 04-domain-join.ps1                  ← FS01 and CLIENT01: joins lab.local
    ├── 05-verify-ad.ps1                    ← DC01: automated PASS/FAIL AD check
    ├── 05-verify-shares.ps1                ← FS01: automated PASS/FAIL ACL check
    └── 06-add-rdp-users.ps1                ← CLIENT01: adds domain users to RDP group
```
<br>

<img width="1123" height="639" alt="ntfs file structure" src="https://github.com/user-attachments/assets/adf4e58a-9fe3-409d-8e53-d3320f893587" />
<br>

---

## Tech Stack & Why Each Tool Was Chosen

### Terraform (IaC)

The environment must be reproducible, version-controlled, and destroyable in a single command. All three VMs, the VNet, NSG, Key Vault, and remote state are declared as code. This also makes the lab auditable. Every resource and its configuration are in plain text without logging into the Azure portal.

### Azure Blob Storage (Remote State)

Terraform tracks every resource it creates in a state file. Without remote state, it sits on your local disk. If you lose it, Terraform loses track of every resource and teardown becomes very difficult. Storing it in Azure Blob Storage means it is encrypted, backed up, and accessible from any machine without carrying a local `.tfstate` file

### Azure Key Vault (Secret Management)

The VM admin password is stored in Key Vault immediately after `terraform apply`. The `configure-lab.ps1` script retrieves it at runtime using `az keyvault secret show`. The password is never written to a file, passed as a CLI argument, or stored in shell history after the initial `TF_VAR_admin_password` environment variable is set.

Key Vault is configured with `enable_rbac_authorization = true`, which activates the modern RBAC permission model. Without this flag, role assignments on the vault are silently ignored. Every secret read or write returns 403 even when the role assignment appears to exist in the portal.

### PowerShell + `az vm run-command` (Remote Execution)

Scripts are executed on VMs through the Azure VM agent rather than through WinRM or direct RDP. This bypasses the NSG entirely. The agent is already installed on every Azure Windows VM and communicates outbound through Azure's control plane, not through any inbound port.

This pattern mirrors production automation: in enterprise environments, RDP access is often blocked or restricted to jump hosts, and `az vm run-command` (or its equivalent through Azure Automation or Azure Arc) is the correct channel for script execution.

### Active Directory (Identity & Access)

AD is used rather than local Windows accounts because real enterprise permissions are group-based. A user's access is determined by their group memberships, not by individual ACLs on every folder. Changing a user's department means changing one group membership, not editing every file and folder they've ever touched.

### NTFS Permissions (Enforcement Layer)

SMB shares are configured with `Everyone Full Control` at the share level. All real security enforcement happens at the NTFS layer via `icacls`. This is standard practice; the share-level permission is a ceiling, not a floor, and NTFS is the authoritative access control mechanism. This prevents a common misconfiguration where administrators over-restrict at the share level, creating inconsistent behavior for local vs. network access to the same folder.

---

## Prerequisites

Verify all three tools are installed, and your Azure subscription is correct before starting.

```bash
terraform -version    # Must be >= 1.5.0
az version            # Azure CLI — any recent version
powershell -version   # 5.1+ (built into Windows)

# Confirm you are logged in to the correct Azure subscription
az account show

# Switch subscriptions if needed
az account set --subscription "<name or ID>"
```

---

## Pre-Setup: Remote State Backend (One Time)

Terraform state is stored in Azure Blob Storage so it is encrypted at rest, never sits on local disk, and can be shared across machines.

```bash
# Create a dedicated resource group for state storage
az group create --name RG-TerraformState --location "Central US"

# Create a storage account (name must be globally unique, 3-24 lowercase chars)
az storage account create --name <YOUR_STORAGE_ACCOUNT_NAME> \
    --resource-group RG-TerraformState \
    --sku Standard_LRS \
    --encryption-services blob

# Create the container
az storage container create --name tfstate \
    --account-name <YOUR_STORAGE_ACCOUNT_NAME>
```

Then open `backend.tf` and replace `REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME` with the name you chose above.

---

## Step 1: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and set your values:

```hcl
location       = "Central US"
rdp_source     = "YOUR_PUBLIC_IP/32"   # Find yours at whatismyip.com
server_vm_size = "Standard_B2as_v2"
client_vm_size = "Standard_B2as_v2"
```

Set the admin password as an environment variable; it never touches disk:

```powershell
# PowerShell
$env:TF_VAR_admin_password = "YourStrongPassword!"
```

```bash
# Bash / Azure Cloud Shell
export TF_VAR_admin_password="YourStrongPassword!"
```

---

## Step 2: Deploy Infrastructure

```bash
az login          # Login to Azure
terraform init    # Initialise providers and connect to remote state backend
terraform plan    # Preview what will be created 
terraform apply   # Deploy
```

On completion, Terraform prints the outputs you need next. Copy the Key Vault name and CLIENT01's public IP.

> **What gets deployed:** 3 VMs (DC01, FS01, CLIENT01), a VNet, NSG, public IPs, and an Azure Key Vault that holds the admin password. From this point forward, you never need to type the password again. The automation retrieves it from Key Vault automatically.

---

## Step 3: Configure the Lab (Automated)

This single command replaces all manual RDP sessions. It pushes PowerShell scripts to each VM through the Azure agent using `az vm run-command`. The single script runs all seven configuration stages in the correct order, retrieving the password from Key Vault and waiting for VM reboots between steps. This is what turns a pile of individual scripts into one unattended, repeatable deployment.

```powershell
.\configure-lab.ps1 -KeyVaultName "<key-vault-name>"
```

---

## Verification

This lab can be verified through automated checks built into the configuration, and manual access tests for each user.

### 1. Automated verification
You will see live output as each stage completes. A [PASS] / [FAIL] report prints at the end of each step, confirming everything is configured correctly.
<br>
<br>
<img width="542" height="701" alt="ntfs verification" src="https://github.com/user-attachments/assets/86656a38-71d2-47d4-8bf1-d32fe5d6edd3" />
<br>

### 2. Manual Access tests

RDP into CLIENT01 using the public IP from `terraform output client01_public_ip`. All test user passwords are `P@ssw0rd123!`

**sarah.jones (Finance)** — Reads and writes Finance, denied everywhere else:

| Finance — success | HR — denied |
| --- | --- |
| <img width="743" height="556" alt="Sarah Finance" src="https://github.com/user-attachments/assets/8cf38a5e-bb55-4516-87a0-ccecdb453e27" /> | <img width="857" height="406" alt="Sarah HR" src="https://github.com/user-attachments/assets/6069f832-d6c7-4b0d-9d0e-928ce7c78aad" /> |

<br>

| IT — denied | Sales — denied |
| --- | --- |
| <img width="882" height="379" alt="Sarah IT" src="https://github.com/user-attachments/assets/08394126-071f-4e32-94a5-78f60fa647c4" /> | <img width="897" height="422" alt="Sarah sales" src="https://github.com/user-attachments/assets/f82ba119-9237-4569-b96a-1d817a3c5df0" /> |

If a result is unexpected, run `whoami /groups` inside the RDP session to confirm actual group membership.

---

## Cost Management and Tear Down

```bash
# Pause — no compute charges while stopped
az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait

# Restart 
az vm start --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait

# Full teardown — only when completely done with Lab 1 and Lab 2
terraform destroy
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---|---|---|
| `configure-lab.ps1` fails at Key Vault | Session expired or missing role | Run `az login`, retry. Confirm Key Vault Secrets User role on the vault |
| Domain join fails — DNS not resolving | DC01 still finishing promotion | Wait 2 minutes and re-run — script resumes from where it stopped |
| Cannot RDP to VMs | IP changed or `rdp_source` mismatch | Run `curl ifconfig.me`, update `terraform.tfvars` `rdp_source`, run `terraform apply` |
| Access Denied unexpected | User not in the right group | Inside RDP run: `whoami /groups` to confirm group membership |
| GPO not applying | Policy cache not refreshed | Run: `gpupdate /force` inside the VM, then `gpresult /r` |
| `terraform init` fails | `backend.tf` not updated | Open `backend.tf`, confirm storage account name is correct and container exists |
| Key Vault 403 on secret read | `enable_rbac_authorization` not set | Confirm `enable_rbac_authorization = true` in `keyvault.tf`, re-apply |

---

## What I'd Do Differently in Production

### 1. Replace Public IPs with Azure Bastion

No compute resource should have a public IP. Azure Bastion provides browser-based RDP and SSH over HTTPS (port 443) without exposing port 3389 to the internet. It integrates with Azure AD for identity-based access and produces audit logs for every session.

### 2. Segment into Separate Subnets with NSG Rules

Domain Controllers, file servers, and client machines belong in separate subnets with micro-segmented NSG rules controlling which protocols are allowed between them. At minimum:
- Management subnet: DC01, restricted to port 389 (LDAP), 636 (LDAPS), 53 (DNS) inbound from server subnet
- Server subnet: FS01, restricted to port 445 (SMB) inbound from client subnet only
- Client subnet: workstations only

### 3. Use Azure AD DS or Entra ID Join Instead of On-Premises AD DS

For a pure-cloud workload, Azure Active Directory Domain Services (Azure AD DS) or Entra ID-joined VMs eliminate the need to manage a Domain Controller VM entirely. Azure AD DS is a managed service; Microsoft handles patching, replication, and availability. Entra ID join with Intune policies replaces Group Policy for modern device management.

### 4. Replace SMB with Azure Files (if workload allows)

Azure Files is a managed SMB endpoint with built-in Active Directory integration, Azure AD authentication support, and no VM to manage or patch. For many file server workloads, Azure Files + AD Kerberos authentication is a direct drop-in replacement that eliminates the FS01 VM entirely.

### 5. Implement RBAC on the Terraform State Storage Account

The storage account holding Terraform state has access controlled by storage account keys in this lab. In production, disable storage account key access entirely and require Azure AD authentication + role assignment (Storage Blob Data Contributor) for state operations. Enable blob versioning and soft delete on the container.

### 6. Enable Azure Defender for Identity on the Domain Controller

Microsoft Defender for Identity monitors AD for lateral movement, credential theft (Pass-the-Hash, Pass-the-Ticket, Golden Ticket), and reconnaissance activity. In a production AD environment, this is a day-one deployment, not an afterthought.

### 7. Extend Automated Verification into a CI/CD Gate

The `05-verify-ad.ps1` and `05-verify-shares.ps1` scripts run at the end of `configure-lab.ps1` but their output is not evaluated as part of a pipeline. In production, these verification checks would run as part of a CI/CD pipeline (Azure DevOps or GitHub Actions), and a failing check would block deployment promotion to the next environment.

### 8. Use Microsoft LAPS for Local Admin Password Randomization

All three VMs currently share the same local admin password, retrieved from Key Vault. In production, every VM should have a unique, rotated local admin password managed by Microsoft Local Administrator Password Solution (LAPS), stored in Active Directory and retrievable only by authorized administrators. This limits the blast radius of a single credential compromise.

---
 
## Skills Demonstrated
 
| Skill | Tool / Technology |
|---|---|
| Infrastructure as Code | Terraform (azurerm, random, time providers) |
| Cloud Infrastructure Deployment | Azure VMs, VNet, Subnet, NSG, Public IPs |
| Secret Management | Azure Key Vault with RBAC authorization model |
| Identity & Access Management | Active Directory DS, OUs, Security Groups, Kerberos |
| File System Security | NTFS permissions via `icacls`, inheritance, ACL management |
| Network File Sharing | SMB shares, share-level vs. NTFS-level permission model |
| Remote Execution & Automation | `az vm run-command`, Azure VM Agent, PowerShell scripting |
| Group Policy Management | GPO creation, linking, registry-based policy enforcement |
| Domain Administration | AD DS promotion, domain join, DNS configuration |
| State Management | Terraform remote state via Azure Blob Storage |
| Verification & Testing | Automated PASS/FAIL validation scripts for AD and NTFS |
| Security Hardening | NSG rules, IP restriction, credential isolation from source control |

---

*Lab 1 of 3: Windows Infrastructure on Azure*
