# Azure Traffic Manager Probes Feed

Plain-text IP prefix feeds for Azure Traffic Manager health probe source ranges.

## Feed files

```text
feeds/azure-traffic-manager-probes.txt       # IPv4 + IPv6
feeds/azure-traffic-manager-probes-ipv4.txt  # IPv4 only
feeds/azure-traffic-manager-probes-ipv6.txt  # IPv6 only
```

## Update feeds from Azure

Run from the repository root.

All prefixes:

```powershell
az network list-service-tags `
  --location australiaeast `
  --query "values[?name=='AzureTrafficManager'].properties.addressPrefixes[]" `
  -o tsv > .\feeds\azure-traffic-manager-probes.txt
```

IPv4 only:

```powershell
az network list-service-tags `
  --location australiaeast `
  --query "values[?name=='AzureTrafficManager'].properties.addressPrefixes[] | [?contains(@, '.')]" `
  -o tsv > .\feeds\azure-traffic-manager-probes-ipv4.txt
```

IPv6 only:

```powershell
az network list-service-tags `
  --location australiaeast `
  --query "values[?name=='AzureTrafficManager'].properties.addressPrefixes[] | [?contains(@, ':')]" `
  -o tsv > .\feeds\azure-traffic-manager-probes-ipv6.txt
```

## Check the result

```powershell
(Get-Content .\feeds\azure-traffic-manager-probes.txt).Count
(Get-Content .\feeds\azure-traffic-manager-probes-ipv4.txt).Count
(Get-Content .\feeds\azure-traffic-manager-probes-ipv6.txt).Count

Get-Content .\feeds\azure-traffic-manager-probes-ipv4.txt -First 10
```

## Usage example

For a normal IPv4 firewall policy, use the IPv4-only feed:

```shell
config system external-resource
    edit "res-ext-ATM_Probes_IPv4"
        set status enable
        set type address
        set resource "https://<github-pages-url>/feeds/azure-traffic-manager-probes-ipv4.txt"
        set refresh-rate 1440
        set server-identity-check full
    next
end
```

The external resource can then be used as a source address object in firewall policies.

## Notes

This feed is intended to allow Azure Traffic Manager health probes only.

Firewall policies should still restrict:

- destination address
- destination port/service
- published application endpoint

Do not use this feed as a broad allow-list for all Azure traffic.
