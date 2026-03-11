# Azure Policies

## What Are Azure Policies?

Azure Policies are **governance rules** that Azure enforces automatically on every resource
operation -- create, update, or delete. Think of them as the security guards at the entrance
of our Azure subscription: every time someone tries to create or change a resource, Azure
checks it against our active policies *before* the operation goes through.

The key word here is **automatic**. It does not matter if a developer deploys through Bicep,
through the Azure CLI, through a CI/CD pipeline, or even manually clicks around in the Azure
Portal. The policy engine sits between the request and the resource provider, and it evaluates
every single operation.

If a resource violates a policy with a **Deny** effect, Azure blocks the operation immediately.
The user sees an error like:

```
Resource creation denied by policy: require-tags
```

This is what makes policies so powerful -- they are impossible to bypass (unless we have the
permissions to modify the policy itself). They are our last line of defense against
misconfigurations, compliance violations, and security gaps.

---

## Our Three Policies

The project landing zone uses three custom policy definitions, each targeting a specific
governance concern. All three use the **Deny** effect, meaning violations are blocked outright
rather than just flagged.

The policy definition files live in the `policies/` directory at the root of this repository.

---

### 1. Require Tags (`require-tags.json`)

| Property | Value |
|----------|-------|
| **Effect** | Deny |
| **Category** | Tags |
| **Scope** | Entire subscription |

#### What it does

This policy blocks the creation of any resource that is missing one or more of these four
mandatory tags:

- **Environment** -- Is this `dev` or `prod`? Without this, we cannot tell which environment
  a resource belongs to.
- **ManagedBy** -- Which team or pipeline deployed this resource? Critical for accountability.
- **CostCenter** -- Which billing code should this resource's cost be allocated to?
- **Project** -- Which project or workload does this resource support?

#### Why we need it

In a managed services environment, untagged resources are invisible. They do not show up in
cost reports (so we cannot bill the right team), they are impossible to filter in dashboards,
and they become "orphaned" -- nobody knows who created them or whether they are still needed.

This policy makes sure that problem never happens. If we forget a tag, Azure will not let us
create the resource at all.

#### Full policy definition

```json
{
  "properties": {
    "displayName": "Require mandatory tags on resources",
    "description": "Denies creation of resources that are missing required tags: Environment, ManagedBy, CostCenter, Project.",
    "mode": "Indexed",
    "policyRule": {
      "if": {
        "anyOf": [
          { "field": "tags['Environment']", "exists": "false" },
          { "field": "tags['ManagedBy']", "exists": "false" },
          { "field": "tags['CostCenter']", "exists": "false" },
          { "field": "tags['Project']", "exists": "false" }
        ]
      },
      "then": { "effect": "deny" }
    },
    "metadata": {
      "category": "Tags",
      "version": "1.0.0"
    }
  }
}
```

**How to read this rule:** The `anyOf` operator means "if *any* of these conditions is true."
Each condition checks whether a specific tag does *not* exist on the resource. If even one
of the four tags is missing, the policy triggers and the resource creation is denied.

---

### 2. Allowed Locations (`allowed-locations.json`)

| Property | Value |
|----------|-------|
| **Effect** | Deny |
| **Category** | General |
| **Scope** | Entire subscription |

#### What it does

This policy restricts resource deployment to only two Azure regions:

- **West Europe** (Amsterdam, Netherlands) -- our primary region
- **North Europe** (Dublin, Ireland) -- our disaster recovery / secondary region

It also allows **global**, because some Azure resources (like policy definitions, role
assignments, and action groups) are region-less and report their location as "global."

#### Why we need it

Data sovereignty. Our client is a Dutch enterprise, and Dutch organizations -- especially
those in government-adjacent industries -- have strict requirements about where data is
stored. The **GDPR** (General Data Protection Regulation) requires that personal data stays
within the EU. Both West Europe and North Europe are EU data centers, so they satisfy this
requirement.

Without this policy, a developer could accidentally deploy a database to `eastus` (Virginia)
or `southeastasia` (Singapore), immediately violating data residency rules. This policy
makes that impossible.

#### Full policy definition

```json
{
  "properties": {
    "displayName": "Restrict resource locations to West Europe and North Europe",
    "description": "Only allows resource creation in West Europe (Amsterdam) and North Europe (Dublin). Ensures data sovereignty compliance for Dutch clients.",
    "mode": "Indexed",
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "location",
            "notIn": [
              "westeurope",
              "northeurope",
              "global"
            ]
          }
        ]
      },
      "then": { "effect": "deny" }
    },
    "metadata": {
      "category": "General",
      "version": "1.0.0"
    }
  }
}
```

**How to read this rule:** The `notIn` operator checks whether the resource's location is
*not* in the allowed list. If someone tries to deploy to any region other than `westeurope`,
`northeurope`, or `global`, the operation is denied.

---

### 3. Deny Public IP (`deny-public-ip.json`)

| Property | Value |
|----------|-------|
| **Effect** | Deny |
| **Category** | Network |
| **Scope** | Spoke resource groups only (NOT the hub) |

#### What it does

This policy blocks the creation of public IP addresses in spoke resource groups. Any attempt
to create a resource of type `Microsoft.Network/publicIPAddresses` is denied.

#### Why we need it

A public IP address on a spoke VM means that VM is **directly reachable from the internet**.
This completely bypasses the Azure Firewall in the hub -- all of our carefully crafted
network security rules become useless.

This is the **number one security anti-pattern** in hub-spoke architectures. The entire
point of routing spoke traffic through the hub Firewall is to inspect and filter traffic
centrally. A public IP on a spoke VM creates a backdoor that skips all of that.

#### Scope matters: hub vs. spoke

This policy is only assigned to **spoke resource groups**, not the hub. Why? Because the hub
*needs* public IP addresses for two legitimate reasons:

- **Azure Firewall** requires a public IP to serve as the internet-facing endpoint
- **Azure Bastion** requires a public IP to allow secure remote access to VMs

If we assigned this policy to the hub, those critical services would not be deployable.

#### Full policy definition

```json
{
  "properties": {
    "displayName": "Deny public IP addresses on spoke VNets",
    "description": "Prevents creation of public IP addresses in spoke resource groups. All internet access must go through the hub Azure Firewall. Assign this policy to spoke resource groups only.",
    "mode": "Indexed",
    "policyRule": {
      "if": {
        "field": "type",
        "equals": "Microsoft.Network/publicIPAddresses"
      },
      "then": { "effect": "deny" }
    },
    "metadata": {
      "category": "Network",
      "version": "1.0.0"
    }
  }
}
```

**How to read this rule:** Unlike the other two policies that check properties of a resource,
this one checks the **resource type** itself. If the resource being created is a public IP
address, the operation is denied. The scoping (hub vs. spoke) is controlled at assignment
time, not in the policy definition.

---

## How to Deploy Policies

Azure Policy deployment is a two-step process: first we **define** the policy (upload the
rule), then we **assign** it (tell Azure where to enforce it).

### Step 1: Create policy definitions

```bash
# Create the tag enforcement policy
az policy definition create \
  --name 'require-tags' \
  --display-name 'Require mandatory tags on resources' \
  --rules policies/require-tags.json \
  --mode Indexed

# Create the location restriction policy
az policy definition create \
  --name 'allowed-locations' \
  --display-name 'Restrict resource locations to West Europe and North Europe' \
  --rules policies/allowed-locations.json \
  --mode Indexed

# Create the public IP denial policy
az policy definition create \
  --name 'deny-public-ip' \
  --display-name 'Deny public IP addresses on spoke VNets' \
  --rules policies/deny-public-ip.json \
  --mode Indexed
```

### Step 2: Assign policies to the correct scope

```bash
# Assign tag policy to the entire subscription
az policy assignment create \
  --name 'require-tags' \
  --policy 'require-tags' \
  --scope '/subscriptions/{subscription-id}'

# Assign location policy to the entire subscription
az policy assignment create \
  --name 'allowed-locations' \
  --policy 'allowed-locations' \
  --scope '/subscriptions/{subscription-id}'

# Assign deny-public-ip to prod spoke ONLY
az policy assignment create \
  --name 'deny-public-ip-prod' \
  --policy 'deny-public-ip' \
  --scope '/subscriptions/{subscription-id}/resourceGroups/rg-spoke-prod-weu'

# Assign deny-public-ip to dev spoke ONLY
az policy assignment create \
  --name 'deny-public-ip-dev' \
  --policy 'deny-public-ip' \
  --scope '/subscriptions/{subscription-id}/resourceGroups/rg-spoke-dev-weu'
```

Notice how the tag and location policies are assigned at the **subscription** level (they
apply everywhere), while the public IP policy is assigned at the **resource group** level
(only spoke resource groups).

---

## Policy Mode: "Indexed"

We may have noticed that all three policies use `"mode": "Indexed"`. This is an important
setting that deserves explanation.

Azure resources come in two flavours:

- **Top-level resources** that support tags and locations (VMs, VNets, storage accounts, etc.)
- **Sub-resources** or child resources that do *not* support tags or locations (subnet
  configurations, firewall rules, diagnostic settings, etc.)

When we set the mode to `"Indexed"`, the policy **only evaluates resources that support tags
and locations**. It automatically skips sub-resources that do not have these properties.

Why does this matter? If we used `"All"` mode instead, our tag enforcement policy would try
to check tags on resources that *cannot have tags*, causing false positives and blocking
legitimate operations. `"Indexed"` mode avoids this by only evaluating resources where the
check actually makes sense.

**Rule of thumb:** Use `"Indexed"` for any policy that checks tags or locations. Use `"All"`
only when we need to evaluate every resource type, including sub-resources.
