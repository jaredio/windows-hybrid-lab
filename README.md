# Windows Server Hybrid Infrastructure Lab (AZ-800)

Portfolio project demonstrating Infrastructure-as-Code, Windows Server administration, and hybrid identity/networking fundamentals using Azure and Bicep.

## Project Summary

This lab simulates a small enterprise environment and is designed to prove hands-on capability across:

- Infrastructure provisioning with reusable Bicep modules
- Active Directory domain services setup and expansion
- Core Windows network services (DNS, DHCP)
- Client domain join and Group Policy validation
- CI/CD-oriented deployment workflow with GitHub Actions

## Environment Scope

- 2x Windows Server 2022 VMs (`dc1`, `dc2`)
- 1x Windows 10 client VM (`cl1`)
- Dedicated Azure virtual network + subnet
- Network security group with controlled RDP ingress
- Parameterized `dev` and `prod` deployment profiles

## Architecture at a Glance

1. `dc1` is promoted to the first domain controller (`lab.local`).
2. `dc2` is joined to the domain and promoted as an additional domain controller.
3. DHCP and DNS are configured for centralized name resolution and IP assignment.
4. `cl1` joins the domain for GPO and identity testing.

## Repository Structure

- `infra/main.bicep`: Primary resource group deployment template.
- `infra/modules/windows-vm.bicep`: Reusable Windows VM module used by all nodes.
- `infra/parameters/dev.bicepparam`: Cost-conscious baseline for development.
- `infra/parameters/prod.bicepparam`: Higher-capacity profile for full lab runs.
- `scripts/validate.ps1`: Local validation of templates and parameter files.
- `scripts/whatif.ps1`: Change preview before deployment.
- `scripts/deploy.ps1`: Resource group deployment command wrapper.
- `docs/post-deploy-checklist.md`: AD DS, DNS, DHCP, and domain-join runbook.
- `.github/workflows/azure-lab.yml`: Manual GitHub Actions pipeline for what-if/deploy.

## Technical Highlights

- Modular Bicep design for repeatable provisioning
- Environment-specific parameterization
- Security-conscious defaults (no wildcard ingress in parameter files)
- Scripted deployment workflow for local and CI execution
- Clear post-deployment operational checklist

## Tooling

- Azure CLI
- Bicep
- PowerShell 7
- GitHub Actions

## Usage

### 1. Validate templates locally

```powershell
./scripts/validate.ps1
```

### 2. When a subscription is available, run what-if

```powershell
./scripts/whatif.ps1 `
  -ResourceGroupName rg-az800-lab-dev `
  -Environment dev `
  -AdminPassword "<StrongPassword>"
```

### 3. Deploy

```powershell
./scripts/deploy.ps1 `
  -ResourceGroupName rg-az800-lab-dev `
  -Environment dev `
  -AdminPassword "<StrongPassword>"
```

## Security

- Set `allowedSourceAddressPrefix` to your public IP in `x.x.x.x/32` format.
- Use a strong local admin password or retrieve one from a secure secret store.
- Public IP assignment is optional and parameterized per VM.
