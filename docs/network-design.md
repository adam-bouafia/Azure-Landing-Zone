# Network Design

## Key Concepts — What All These Terms Mean

Before looking at the topology and address plan, let's define every networking term used in
this document. If we already know what a VNet and a subnet are, feel free to skip ahead to
the [topology diagram](#topology-hub-spoke). Otherwise, read through — each term builds on
the previous one.

### VNet (Virtual Network)

A **Virtual Network** (VNet) is Azure's version of a traditional network. It's a logically
isolated chunk of IP address space that lives entirely in the cloud. Think of it as your own
private network inside Azure, resources we place inside a VNet can talk to each other by
default, but they're invisible to the outside world unless we explicitly allow it.

Every VNet has an **address space**, a range of IP addresses it "owns." For example,
`10.0.0.0/16` means this VNet controls all 65,536 addresses from `10.0.0.0` to `10.0.255.255`.

![Hub-spoke network topology](https://miro.medium.com/1*9dpxSaew3flbzVc-67jXtA.gif)


### Subnet

A **subnet** is a subdivision of a VNet. we can't just dump all your resources into one big
VNet, we divide it into subnets to organize resources and apply different security rules to
each group.

For example, we might have:
- A subnet for web servers (public-facing)
- A subnet for application servers (internal logic)
- A subnet for databases (most restricted)

Each subnet gets its own slice of the VNet's address space. A VNet with address space
`10.0.0.0/16` might have a subnet `10.0.2.0/24` (256 addresses for web servers) and another
`10.1.2.0/24` (256 addresses for app servers). The subnets don't overlap — they're distinct
portions of the larger VNet range.

![Hub-spoke network topology](https://www.patrickkoch.dev/images/post_26/architecture.png)

### Hub

The **hub** is the central VNet in a hub-spoke topology. It doesn't run your application
workloads. Instead, it holds **shared infrastructure services** that every other network needs
to use:

- **Firewalls**: to inspect and filter all traffic
- **Bastion hosts**: to provide secure remote access to VMs
- **VPN/ExpressRoute gateways**: to connect to on-premises networks
- **Management tools**: jumpboxes, monitoring agents, etc.

Think of it like the lobby of an office building: we don't do work there, but everyone passes
through it to get where they need to go.


![Hub-spoke network topology](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/_images/hub-spoke.png)
### Spoke

A **spoke** is a workload VNet where your actual applications, APIs, and databases live.
Each spoke is connected to the hub but **not directly to other spokes**. In our design:

- **Spoke Production** (`10.1.0.0/16`) runs the live application
- **Spoke Development** (`10.2.0.0/16`) runs the dev/test environment

This separation is intentional. If a developer accidentally misconfigures something in dev,
it cannot affect production because the two spokes have no direct link. Any traffic between
them must pass through the hub's firewall, which enforces strict rules.

![Hub-spoke network topology](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/_images/spoke-spoke-routing.png)


### Peering (VNet Peering)

**VNet peering** is the connection between two VNets. By default, VNets are completely
isolated, even if two VNets are in the same Azure subscription, resources in one can't talk
to resources in the other. Peering links them so traffic can flow between them over Azure's
private backbone (not the internet).

In a hub-spoke topology, each spoke is peered with the hub. The spokes are **not** peered
with each other. This forces all cross-spoke traffic through the hub, where the firewall
can inspect it.

```
Spoke Prod ←──peering──→ Hub ←──peering──→ Spoke Dev
```

Peering is fast (Azure backbone speeds), low-latency, and the traffic never leaves Microsoft's
network.


![Peering](https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/_images/spoke-spoke-routing.png)

### Azure Firewall

**Azure Firewall** is a managed, cloud-native network security service that sits in the hub
VNet and inspects all traffic flowing through it. It acts as the gatekeeper for your entire
network.

It can enforce three types of rules:
- **Network rules** — allow or deny traffic based on source IP, destination IP, port, and
  protocol (e.g., "allow TCP 443 from spoke-prod to the internet")
- **Application rules** — allow or deny traffic based on fully qualified domain names
  (e.g., "allow `*.ubuntu.com` for package updates, deny everything else")
- **DNAT rules** — translate incoming public IP traffic to a private IP inside a spoke
  (this is how external users reach your web servers without the servers having a public IP)

All traffic decisions are logged, so we have a full audit trail.

![Peering](https://kodekloud.com/kk-media/image/upload/v1752882189/notes-assets/images/Microsoft-Azure-Security-Technologies-AZ-500-Implementing-Azure-Firewall/azure-firewall-implementation-diagram-2.jpg)



### DNAT (Destination Network Address Translation)

**DNAT** is a firewall technique for handling inbound traffic from the internet. When someone
on the internet accesses your application, they connect to the firewall's public IP address.
The firewall then **translates** (rewrites) the destination address to the private IP of the
actual web server inside a spoke.

```
User hits: 52.136.x.x (firewall's public IP)
Firewall rewrites destination to: 10.1.1.4 (web server's private IP)
Web server responds back through the firewall
```

This way, your web servers never need a public IP address. The firewall is the only thing
with a public-facing address, and it controls exactly what traffic gets forwarded where.

![DNAT](https://blogger.googleusercontent.com/img/a/AVvXsEgdIQc8s_mGicNgKoSXUcI4D4BCzvbuRafLBeAdim3EEyxPA8o31qmCYxO2TMx18FnvlwAhYh1Q4_HE4xfpRk3rTXsxbGr3fi0lNARdoQ19A67VTUz5LOa2OODnxZTu1z3SIybuSXtpiVrMZObAJ030EdM_LB2OOEmBm1dg8mnMYe5tOjFArsRjZ_nOyDD4=w640-h194-rw)
### SNAT (Source Network Address Translation)

**SNAT** is the opposite of DNAT — it handles **outbound** traffic. When a VM inside a spoke
needs to reach the internet (for example, to download a package update or call an external API),
it has a private IP like `10.1.2.5` that means nothing on the public internet. Routers on the
internet wouldn't know how to send a reply back to `10.1.2.5` — that address only exists
inside your private network.

SNAT solves this by **rewriting the source address**. As the traffic passes through Azure Firewall
on its way out, the firewall replaces the VM's private IP with the firewall's own public IP:

```
VM sends from:    10.1.2.5 (private, meaningless on the internet)
Firewall rewrites source to: 52.136.x.x (firewall's public IP)
External server sees the request as coming from 52.136.x.x
External server sends reply to 52.136.x.x
Firewall receives reply, translates back to 10.1.2.5, forwards to the VM
```

The VM never knows this happened — it just sees a response to its request. The external server
never knows the VM's private IP either — it only sees the firewall's public IP.

![SNAT](https://blogger.googleusercontent.com/img/a/AVvXsEgzFZG_PDSfHTK9Oubwg7AJYjUlGUDyCLRoFQgBoVVtpK16NQiof_IAjNoVppSJ4fPD_UB8sTlKGb2ysA3LdM-ijBmlP-mDiZKMs3FvdX44Q-rrpox2sP-ku4yyKbt8TYPlGH_zYPeyZSED3EVEgJu0DzBstt9w8EziRwb-ehX-Doh9cAyMnMgPqytt6dTR=w640-h178-rw)


**DNAT vs SNAT — the simple version:**

| Direction | What it rewrites | When it's used |
|-----------|-----------------|----------------|
| **DNAT** | The **destination** address (incoming traffic) | Internet user → your web server |
| **SNAT** | The **source** address (outgoing traffic) | Your VM → the internet |

Both are forms of NAT (Network Address Translation). They just work in opposite directions.
Together, they let your entire network share a single public IP while keeping all internal
resources on private addresses.


![DNAT-vs-SNAT](https://blogger.googleusercontent.com/img/a/AVvXsEiCixZXHAr5hDrdSwYoBDJY_WCMNoQzP2xmBse_6IJvYRIiIGL0wFtXX_2NKulbQ5fYX-kL6eoUhnieP5wRCMm-Do2WQDbWiMKZiLbKVM2vGteOpcbcoeebuodL1H4vAqsLze7CSPQT1y5BKOv8AsBRcjpN7ALk3k7JOJHPln_4jxyNcUIru1Smoli4CyJ4)

### Azure Bastion

**Azure Bastion** is a managed service for secure remote access to your virtual machines.
Normally, to SSH into a Linux VM or RDP into a Windows VM, you'd need to expose port 22
or 3389 to the internet, which is a massive security risk.

Bastion eliminates that risk entirely:
1. we open the Azure Portal in your browser
2. Click "Connect" on a VM
3. Bastion creates a secure tunnel over HTTPS (port 443) through Azure's backbone
4. we get a remote session directly in the browser, no public IP on the VM, no open
   management ports, no VPN client needed

Bastion lives in a dedicated subnet (`AzureBastionSubnet`) in the hub VNet and can reach
VMs in any peered spoke.

![Bastion](https://imgopt.infoq.com/fit-in/3000x4000/filters:quality(85)/filters:no_upscale()/news/2019/06/Azure-Bastion-VM/en/resources/2architecture-1561226707732.png)


### GatewaySubnet (VPN / ExpressRoute)

The **GatewaySubnet** is a special subnet reserved for Azure's virtual network gateways.
It's where you'd place a **VPN Gateway** (encrypted tunnel over the public internet to your
on-premises network) or an **ExpressRoute Gateway** (dedicated private connection to your
on-premises network, provided by a telecom carrier).

Azure requires this subnet to be named exactly `GatewaySubnet`. Even if we don't need
on-premises connectivity today, reserving this subnet (we use `/27` — 32 addresses) means
you're ready to add it later without redesigning your network.


![Bastion](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/images/expressroute-vpn-failover.svg)

### Private Endpoint

A **Private Endpoint** is a network interface that gives an Azure PaaS service (like Key Vault,
Storage Account, or SQL Database) a **private IP address inside your VNet**.

Without Private Endpoints, when your app talks to Key Vault, the traffic goes:

```
Your VM → internet → Key Vault's public endpoint
```

With a Private Endpoint, the traffic stays entirely on the private network:

```
Your VM → private IP (10.1.3.x) → Key Vault (privately)
```

The PaaS service essentially "appears" inside your VNet with a private IP. The public endpoint
can then be disabled entirely, so the service is only reachable from within your network.


![priv8](https://azure.microsoft.com/en-us/blog/wp-content/uploads/2019/09/6436278d-251a-48f0-9846-d9a01f3621b4.webp)

### Private DNS Zone 

When we create a Private Endpoint for, say, Key Vault, the hostname
`kv-prod-001.vault.azure.net` still resolves to a public IP by default. A **Private DNS Zone**
overrides this: it tells your VNets that `kv-prod-001.vault.azure.net` should resolve to the
**private IP** of the Private Endpoint instead.

Without it, your app would try to connect to the public IP and get blocked by your firewall
rules. With it, DNS silently resolves to the private address and traffic flows internally.

![priv8](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/media/private-link-example-central-dns-multi-regions.png)


### RFC 1918 (Private IP Space)

**RFC 1918** is the internet standard that defines three IP address ranges reserved for private
use. These ranges are guaranteed to never be used on the public internet, so we can use them
freely inside your own networks without conflict:

| Range              | Size        | Common usage                         |
|--------------------|-------------|--------------------------------------|
| `10.0.0.0/8`       | 16 million  | Enterprise / cloud networks (we use this) |
| `172.16.0.0/12`    | 1 million   | Medium-sized private networks        |
| `192.168.0.0/16`   | 65,536      | Home routers, small offices          |

We use the `10.x.x.x` range because it gives us the most room — 16 million addresses to
carve into VNets, subnets, and future expansions without ever worrying about running out.


![rfc](https://static.packt-cdn.com/products/9781789340501/graphics/assets/e3bf647a-f2b1-4d81-ae69-512dbaa160c9.png)

---

## Topology: Hub-Spoke

Now that we know what all these pieces are, here's how they fit together. See
[ADR-001](./stack-decisions.md) for why we chose hub-spoke over Virtual WAN.

```
                        ┌──────────────────────────────────────┐
                        │         Hub VNet (10.0.0.0/16)       │
                        │                                      │
                        │  ┌──────────────┐ ┌────────────────┐ │
                        │  │ AzureFirewall│ │ AzureBastion   │ │
                        │  │ 10.0.1.0/26  │ │ 10.0.2.0/26    │ │
                        │  └──────────────┘ └────────────────┘ │
                        │  ┌──────────────┐ ┌────────────────┐ │
                        │  │ Management   │ │ GatewaySubnet  │ │
                        │  │ 10.0.3.0/24  │ │ 10.0.4.0/27    │ │
                        │  └──────────────┘ └────────────────┘ │
                        └──────┬─────────────────────┬─────────┘
                               │ Peering             │ Peering
                 ┌─────────────┴───────┐  ┌──────────┴─────────────┐
                 │ Spoke: Production   │  │ Spoke: Development     │
                 │ (10.1.0.0/16)       │  │ (10.2.0.0/16)          │
                 │                     │  │                        │
                 │ Web  10.1.1.0/24    │  │ Web  10.2.1.0/24       │
                 │ App  10.1.2.0/24    │  │ App  10.2.2.0/24       │
                 │ Data 10.1.3.0/24    │  │ Data 10.2.3.0/24       │
                 └─────────────────────┘  └────────────────────────┘
```

## IP Addressing Plan

### Why /16 per VNet?

Private IP space (RFC 1918) is free. Being stingy causes pain later when we need more subnets.
A /16 gives 65,536 addresses per VNet. We use a tiny fraction now, but the space is reserved for
growth: additional subnets for AKS, dedicated subnets for Private Endpoints, management tools, etc.

### Understanding CIDR Notation (the `/` number)

Before diving into the address map, let's break down what those `/16`, `/24`, `/26` numbers
actually mean. If you've ever looked at `10.0.1.0/24` and wondered what the `/24` part does,
this section is for you.

#### IP addresses are just 32 bits

An IP address like `10.0.1.0` is a human-friendly way of writing a 32-bit binary number.
Each of the four numbers separated by dots (called **octets**) is 8 bits, and 4 x 8 = 32 bits total.

Here's what the computer actually sees:

```
10  .  0  .  1  .  0
00001010 . 00000000 . 00000001 . 00000000
```

Every IP address — whether it's `10.0.1.0` or `192.168.1.1` — is just 32 ones and zeros under the hood.
The dot-decimal notation is simply a convenience so humans don't have to read binary.

#### The `/` number splits those 32 bits into two parts

The number after the slash is called the **prefix length**. It tells we how many of those 32 bits
belong to the **network portion** (the part that stays the same for every device in that network).
The remaining bits are the **host portion** (the part that changes — each device gets a unique value).

- **Left side** (network bits) = locked, identical for every address in this network
- **Right side** (host bits) = free, each device or resource gets a unique combination

Think of it like a street address: the network bits are the street name (same for everyone on that
street), and the host bits are the house number (unique per household).

#### /24 — the most common and easiest to understand

A `/24` means 24 bits are locked for the network, leaving 8 bits free for hosts:

```
10.0.1.0/24

00001010.00000000.00000001 | 00000000
├── 24 bits: LOCKED ──────┤ ├ 8 bits: FREE ┤
```

With 8 free bits, each bit can be 0 or 1, so we get 2^8 = **256 possible addresses**
(from `10.0.1.0` through `10.0.1.255`).

This is the default "small subnet" in most networks. You'll see it used for individual subnets
like our web, app, and data tiers in the spoke VNets.

#### /16 — a large network

A `/16` locks only 16 bits, leaving 16 bits free:

```
10.0.0.0/16

00001010.00000000 | 00000001.00000000
├─ 16 bits: LOCKED ┤ ├─ 16 bits: FREE ─┤
```

16 free bits gives we 2^16 = **65,536 addresses** (from `10.0.0.0` through `10.0.255.255`).

This is why we use `/16` for each VNet's overall address space — it gives us plenty of room
to carve out many subnets inside it without ever running out of addresses.

#### /26 — a smaller subnet

A `/26` locks 26 bits, leaving only 6 bits free:

```
10.0.1.0/26

00001010.00000000.00000001.00 | 000000
├──── 26 bits: LOCKED ───────┤ ├ 6 FREE ┤
```

6 free bits gives we 2^6 = **64 addresses** (from `10.0.1.0` through `10.0.1.63`).

We use `/26` for subnets like Azure Firewall and Azure Bastion. These services don't need
hundreds of IPs, so a 64-address block is the right size — large enough to meet Azure's
minimum requirements, small enough not to waste space.

#### /27 — even smaller

A `/27` locks 27 bits, leaving just 5 bits free:

```
10.0.4.0/27

00001010.00000000.00000100.000 | 00000
├───── 27 bits: LOCKED ───────┤ ├ 5 FREE ┤
```

5 free bits gives we 2^5 = **32 addresses** (from `10.0.4.0` through `10.0.4.31`).

We use `/27` for the GatewaySubnet. Azure requires this subnet to exist for VPN or
ExpressRoute gateways, but it only needs a small number of IPs.

#### The formula

There's one formula that covers all cases:

```
Total addresses = 2 ^ (32 - prefix length)
Usable in Azure = total - 5     (because Azure reserves 5 per subnet)
```

Here's a quick reference table:

| CIDR | Calculation       | Total Addresses | Usable in Azure |
|------|-------------------|-----------------|-----------------|
| /16  | 2^(32-16) = 2^16  | 65,536          | 65,531          |
| /24  | 2^(32-24) = 2^8   | 256             | 251             |
| /26  | 2^(32-26) = 2^6   | 64              | 59              |
| /27  | 2^(32-27) = 2^5   | 32              | 27              |

**Key insight:** a bigger number after `/` means more bits are locked for the network,
which means fewer bits are free for hosts, which means a **smaller** network.
Conversely, a smaller prefix like `/16` gives we a much larger address space.

That's all CIDR notation is. One formula: `2 ^ (32 - n)`. Now when we see `/26` in the
address map below, we know exactly what it means: 26 bits locked, 6 bits free, 64 total
addresses, 59 usable in Azure.

### Full Address Map

| VNet            | Address Space  | Subnet              | CIDR           | Usable IPs | Purpose                        |
|-----------------|---------------|----------------------|----------------|------------|--------------------------------|
| **Hub**         | 10.0.0.0/16   | AzureFirewallSubnet  | 10.0.1.0/26    | 59         | Azure Firewall                 |
|                 |               | AzureBastionSubnet   | 10.0.2.0/26    | 59         | Azure Bastion                  |
|                 |               | snet-management      | 10.0.3.0/24    | 251        | Jumpbox VM, management tools   |
|                 |               | GatewaySubnet        | 10.0.4.0/27    | 27         | VPN/ExpressRoute (reserved)    |
| **Spoke Prod**  | 10.1.0.0/16   | snet-web             | 10.1.1.0/24    | 251        | Web frontends                  |
|                 |               | snet-app             | 10.1.2.0/24    | 251        | Application/API tier           |
|                 |               | snet-data            | 10.1.3.0/24    | 251        | Databases, Private Endpoints   |
| **Spoke Dev**   | 10.2.0.0/16   | snet-web             | 10.2.1.0/24    | 251        | Web frontends                  |
|                 |               | snet-app             | 10.2.2.0/24    | 251        | Application/API tier           |
|                 |               | snet-data            | 10.2.3.0/24    | 251        | Databases, Private Endpoints   |

### Why Azure reserves 5 IPs per subnet

In every subnet, Azure reserves the first 4 and last 1 addresses:
- `.0` — Network address
- `.1` — Default gateway
- `.2`, `.3` — Azure DNS mapping
- Last IP — Broadcast address

So a /24 (256 addresses) gives we 251 usable. A /26 (64 addresses) gives 59.

## Traffic Flow

### Spoke-to-Internet (Outbound)

```
VM in spoke → spoke VNet → peering → hub VNet → Azure Firewall → Internet
```

The firewall inspects outbound traffic, applying application rules (URL filtering)
and network rules. All outbound traffic is logged.

### Internet-to-Spoke (Inbound)

```
Internet → Firewall Public IP → DNAT rule → Firewall → peering → spoke VNet → Web VM
```

The firewall performs Destination NAT (DNAT): it translates its public IP to the
private IP of the web server. This way, web servers never have a public IP.

### Spoke-to-Spoke

```
VM in spoke-prod → peering → hub → Azure Firewall → hub → peering → spoke-dev VM
```

Spokes cannot talk directly. All cross-spoke traffic routes through the hub firewall.
This is intentional — the firewall enforces that prod can't accidentally access dev, etc.

### Management Access (Bastion)

```
Admin browser → Azure Portal → Bastion → private connection → VM in any VNet
```

No RDP/SSH exposed to the internet. The VM has no public IP. Bastion handles the
secure tunnel through the Azure backbone.

## DNS Resolution Strategy

For this landing zone, we use Azure's built-in DNS (168.63.129.16). Each VNet
automatically resolves Azure resource names.

For Private Endpoints (e.g., Key Vault), we'll add Private DNS Zones linked to
the hub VNet. This ensures that `kv-prod-001.vault.azure.net` resolves
to the private IP instead of the public IP.