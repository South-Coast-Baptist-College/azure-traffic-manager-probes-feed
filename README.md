# Azure Traffic Manager Probes Feed

Plain-text IP prefix feeds for Azure Traffic Manager health probe source ranges.

The feeds are generated from the public Microsoft Service Tags JSON and do not require Azure CLI, Azure login, Azure subscription access, or any Azure secrets.

## Feed files

```text
feeds/azure-traffic-manager-probes.txt       # IPv4 + IPv6
feeds/azure-traffic-manager-probes-ipv4.txt  # IPv4 only
feeds/azure-traffic-manager-probes-ipv6.txt  # IPv6 only