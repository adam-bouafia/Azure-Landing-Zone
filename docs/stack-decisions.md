# Architecture Decisions Records

This document showcase the key architectural decision made during the design and implementation of alz. Each record explains the context, the decision, and the rationale behind every choice.



## ADR-001: Hub-Spoke Topology over Azure Virtual WAN

**Context**: We need a network topology for a managed services client with production and development workloads. Azure offers two main patterns: hub-spoke with VNet peering, or Azure Virtual WAN.

**Decision**: Hub-spoke with a central hub VNet, Azure Firewall for traffic inspection, and VNet peering to spoke VNets.

**Rationale**:
- Virtual WAN is designed for large-scale (10+ spokes) or branch-heavy topologies. In our project we use only 2 spokes, it would be overkill.
- Hub-spoke gives us full control over routing and firewall rules. With Virtual WAN, Microsoft manages the hub router and you lose some granularity.
- Lower cost: no Virtual WAN hub fee (~€0.05/hr = ~€36/month) on top of the firewall cost.

---

## ADR-002: Bicep over Terraform


**Context**: Need to choose an Infrastructure as Code tool for all Azure deployments.

**Decision**: Bicep exclusively. No Terraform, no ARM templates.

**Rationale**:
- Bicep is Azure-native, it compiles 1:1 to ARM templates, so every Azure resource is supported.
- No state file management. Bicep deployments are supported via Azure Resource Manager directly. Terraform requires a backend (storage account, Terraform Cloud) to store state, which adds operational overhead.


**Trade-offs accepted**: Bicep is Azure-only. If we ever needed multi-cloud, Terraform would be the better choice. But for a managed Azure landing zone, this is the right tool.

---

## ADR-003: RBAC Authorization over Access Policies for Key Vault


**Context**: Azure Key Vault supports two authorization models: the legacy "access policies" and the newer "Azure RBAC."

**Decision**: Use Azure RBAC authorization (`enableRbacAuthorization: true`).

**Rationale**:
- RBAC is the modern approach recommended by Microsoft. Access policies are considered legacy.
- With RBAC, Key Vault permissions are managed the same way as every other Azure resource, through role assignments. This means one consistent permission model across the entire landing zone.
- Detailed built-in roles: `Key Vault Secrets User`, `Key Vault Crypto Officer`, etc. Access policies only have get/list/set/delete at the vault level.
- Audit trail: RBAC changes show up in Azure Activity Log alongside all other RBAC changes. 
The problem it's solving:

You have a client with 50 Azure resources. Security team wants to audit "who changed permissions on what, and when?" They open Azure Activity Log — that's Azure's central record of every management action.

With RBAC (what we use):

When someone gets added as Key Vault Secrets User, that event appears in Activity Log alongside:

"Assigned Contributor on VM"
"Removed Owner from storage account"
"Assigned Key Vault Secrets User on Key Vault"
One place. One query. Full picture.

With the old Access Policies:

Key Vault had its own permission system, completely separate. When someone got added to a Key Vault access policy, that event went into a different log stream — Key Vault diagnostic logs, not Activity Log.

So the auditor would have to:

Check Activity Log for all normal RBAC changes
Also check Key Vault's own logs for access policy changes
Mentally combine them
The real-world problem this causes:

"Who had access to the client's Key Vault last Tuesday?" becomes a pain. You're searching two different systems instead of one.

---

## ADR-004: Azure Monitor + Log Analytics over Third-Party Monitoring


**Context**: Need a monitoring and observability stack for all landing zone resources.

**Decision**: Azure Monitor with Log Analytics as the central log sink, Azure Monitor alerts for notifications, and native diagnostic settings on all resources.

**Rationale**:
- Native integration: every Azure resource can send diagnostic logs and metrics to Log Analytics with zero agents for PaaS resources.
- KQL (Kusto Query Language) is extremely powerful for ad-hoc investigation.
- Single pane of glass: VM metrics, network logs, firewall logs, and Key Vault audit logs all in one workspace. 
- No additional licensing cost, Log Analytics is pay-per-GB-ingested, which is predictable and scales with usage. 

**Trade-offs accepted**: Third-party tools (Datadog, Grafana Cloud) may offer better dashboarding or multi-cloud correlation. For an Azure-only managed services client, native tooling wins on integration and operational simplicity.


## ADR-005: Conditional Deployment for Expensive Resources


**Context**: Azure Firewall (~€912/month) and Azure Bastion (~€140/month) are significant costs during development and testing.

**Decision**: Use of Bicep conditional deployment (`if` expressions) with boolean parameters like `deployFirewall` and `deployBastion`. Default to `false` for dev, `true` for production.

**Rationale**:
- Allows the full architecture to be documented and coded without worrying costs when resources aren't needed.
- The Bicep modules are complete and deployable, the parameter just controls whether the resource is created.
- In production, these are always-on. In dev/test, deploy to verify, screenshot, then tear down.

**Trade-offs accepted**: Conditional deployment adds `if` checks to outputs, which means downstream modules need to handle "resource not deployed" scenarios .
The flag saves money during dev, but the cost is that your code gets more complex because every module that depends on a conditional resource has to handle "what if that resource doesn't exist?"