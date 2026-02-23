# Roadmap Construction


**To Start our project, the logic is simple, we build things that have zero dependencies first, then build things that depend on them.**


We think of it as like building a house:
 
- **Foundation** = NSG, Log Analytics, Storage (no dependencies)
- 
- **Walls** = VNets (need NSGs attached)
- 
- **Hallways** = Peering (connects the rooms)
- 
- **Security system** = Firewall, Bastion (installed into the building)
- 
- **Furniture** = VMs, Key Vault (placed inside rooms)
- 
- **Alarms** = Alerts (monitor the furniture)
- 
- **Insurance** = Recovery Vault (backs everything up)
- 
- **Blueprint** = main.bicep (describes the whole house)

Then after all Bicep modules, we have policies, scripts, pipeline YAML. Those don't depend on Bicep at all, we think of it as like house bills.