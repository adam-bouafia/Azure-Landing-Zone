# Tagging Strategy

## Why Tags Matter

Tags are key-value pairs attached to Azure resources. They serve three critical purposes in a managed
services environment:

1. **Cost allocation**: Azure Cost Management can group costs by tag. Without tags, you get one big bill
   with no visibility into which team, project, or environment is spending what.
2. **Operational automation**: Scripts can target resources by tag. Example: "stop all VMs tagged
   `AutoShutdown=true` at 7 PM" — this is a cost optimization pattern.
3. **Governance and compliance**: Azure Policy can enforce that resources without required tags are
   denied at creation time. This prevents "orphan" resources that nobody owns.

## Required Tags

Every resource in the Azutr landing zone **must** have these tags. Azure Policy will deny
resource creation if any are missing.

| Tag            | Purpose                      | Allowed Values                         | Example              |
|----------------|------------------------------|----------------------------------------|----------------------|
| `Environment`  | Deployment environment       | `Production`, `Development`, `Test`    | `Production`         |
| `ManagedBy`    | Responsible operations team  | `Adam`                              | `Adam`            |
| `CostCenter`   | Financial cost allocation    | Format: `{dept}-{code}`                | `IT-Infra-001`       |
| `Project`      | Project or client identifier | Free text                              | `ALZ`         |
| `Owner`        | Primary contact for resource | Email address                          | `adam@alz.nl`|

## Optional Tags

These are applied where relevant for automation and lifecycle management.

| Tag              | Purpose                           | Values              | Used On           |
|------------------|-----------------------------------|---------------------|-------------------|
| `AutoShutdown`   | VM start/stop scheduling          | `true`, `false`     | VMs               |
| `BackupPolicy`   | Backup tier assignment            | `Standard`, `None`  | VMs               |
| `CreatedBy`      | Deployment origin tracking        | `Pipeline`, `Manual`| All               |
| `DataClass`      | Data classification               | `Public`, `Internal`, `Confidential` | Storage, DBs |

## How Tags Are Applied in Bicep

Tags are defined once as a parameter object and passed to every resource and module:

```bicep
// In main.bicep — defined once at the top
param tags object = {
  Environment: 'Production'
  ManagedBy: 'Adam'
  CostCenter: 'IT-Infra-001'
  Project: 'ALZ'
  Owner: 'adam@alz.nl'
}

// Every resource receives the tags object
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-hub-weu'
  location: location
  tags: tags       // <-- applied here
  properties: { ... }
}
```

This pattern ensures consistency. Change the tag values in one place (the parameter file), and every
resource in the deployment gets updated.

## Tag Enforcement via Azure Policy

The policy `policies/require-tags.json` denies resource creation when required tags are missing.
This is applied at the subscription level. See [Stack-Decisions.md](./stack-decisions.md) for the rationale
on which tags we enforce vs. recommend.
