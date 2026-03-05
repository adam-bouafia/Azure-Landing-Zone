# Naming Protocol

## Why This Matters

Every resource in Azure gets a name, and once deployed, most names **cannot be changed**. A consistent
naming lets any engineer on the team look at a resource and immediately know what it is, which
environment it belongs to, and where it lives. Companies manages hundreds of resources across client
subscriptions, without naming standards, it becomes chaos.

## The Pattern

```
{resource-prefix}-{workload/purpose}-{environment}-{azure-region}
```

- **resource-prefix**: A short abbreviation for the resource type (see table below).
- **workload/purpose**: What the resource is for. Keep it short: `hub`, `spoke`, `web`, `app`.
- **environment**: `prod`, `dev`, `test`, `shared`. Omitted for resources that span environments (like the hub).
- **azure-region**: Abbreviated region. `weu` = West Europe, `neu` = North Europe.

## Resource Naming Table

| Resource Type          | Prefix  | Pattern                                | Example                  |
|------------------------|---------|----------------------------------------|--------------------------|
| Resource Group         | `rg`    | `rg-{workload}-{env}-{region}`         | `rg-hub-weu`             |
| Virtual Network        | `vnet`  | `vnet-{workload}-{env}-{region}`       | `vnet-spoke-prod-weu`    |
| Subnet                 | `snet`  | `snet-{purpose}`                       | `snet-web`, `snet-data`  |
| Network Security Group | `nsg`   | `nsg-{subnet}-{env}`                   | `nsg-web-prod`           |
| Azure Firewall         | `afw`   | `afw-{workload}-{region}`              | `afw-hub-weu`            |
| Firewall Policy        | `afwp`  | `afwp-{workload}-{region}`             | `afwp-hub-weu`           |
| Azure Bastion          | `bas`   | `bas-{workload}-{region}`              | `bas-hub-weu`            |
| Public IP              | `pip`   | `pip-{resource}-{region}`              | `pip-afw-hub-weu`        |
| Route Table            | `rt`    | `rt-{purpose}-{env}`                   | `rt-spoke-prod`          |
| Virtual Machine        | `vm`    | `vm-{role}-{env}-{number}`             | `vm-jumpbox-hub-001`     |
| Network Interface      | `nic`   | `nic-{vm-name}`                        | `nic-vm-jumpbox-hub-001` |
| OS Disk                | `osdisk`| `osdisk-{vm-name}`                     | `osdisk-vm-jumpbox-hub-001` |
| Key Vault              | `kv`    | `kv-{workload}-{env}-{unique}`         | `kv-azl-prod-001`    |
| Log Analytics          | `log`   | `log-{workload}-{env}`                 | `log-azl-prod`       |
| Recovery Services Vault| `rsv`   | `rsv-{workload}-{env}`                 | `rsv-azl-prod`       |
| Storage Account        | `st`    | `st{workload}{env}{unique}` (no dashes)| `stazlprod001`       |
| VNet Peering           | `peer`  | `peer-{source}-to-{destination}`       | `peer-hub-to-spoke-prod` |

## Azure Naming Constraints to Know

These are real constraints that will break your deployment if you ignore them:

- **Storage Accounts**: 3-24 chars, lowercase + numbers only, **no dashes**. Globally unique.
- **Key Vault**: 3-24 chars, alphanumeric + dashes. Globally unique.
- **VMs**: 1-15 chars for Windows (NetBIOS limit), 1-64 for Linux.
- **Resource Groups**: 1-90 chars, most special chars allowed.
- **Subnets with fixed names**: `AzureFirewallSubnet`, `AzureBastionSubnet`, `GatewaySubnet` — Azure **requires** these exact names. You cannot rename them.

## Region Abbreviations

| Region       | Abbreviation |
|--------------|-------------|
| West Europe  | `weu`       |
| North Europe | `neu`       |
| East US      | `eus`       |