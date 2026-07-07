# Azure Traffic Manager Probes Feed

Plain-text IP prefix feeds for Azure Traffic Manager health probe source ranges.

## Feed files

```text
feeds/azure-traffic-manager-probes.txt       # IPv4 + IPv6
feeds/azure-traffic-manager-probes-ipv4.txt  # IPv4 only
feeds/azure-traffic-manager-probes-ipv6.txt  # IPv6 only
```

## Update feeds from Azure

The source of truth is the Azure `AzureTrafficManager` service tag.

### Bash

```bash
mkdir -p feeds

az network list-service-tags \
  --location australiaeast \
  --query "values[?name=='AzureTrafficManager'].properties.addressPrefixes[]" \
  -o tsv > feeds/azure-traffic-manager-probes.txt

grep -F "." feeds/azure-traffic-manager-probes.txt > feeds/azure-traffic-manager-probes-ipv4.txt
grep -F ":" feeds/azure-traffic-manager-probes.txt > feeds/azure-traffic-manager-probes-ipv6.txt
```

### PowerShell

```powershell
New-Item -ItemType Directory -Force .\feeds | Out-Null

$prefixes = az network list-service-tags `
  --location australiaeast `
  --query "values[?name=='AzureTrafficManager'].properties.addressPrefixes[]" `
  -o tsv

$prefixes | Set-Content .\feeds\azure-traffic-manager-probes.txt -Encoding ascii
$prefixes | Where-Object { $_ -match '\.' } | Set-Content .\feeds\azure-traffic-manager-probes-ipv4.txt -Encoding ascii
$prefixes | Where-Object { $_ -match ':' } | Set-Content .\feeds\azure-traffic-manager-probes-ipv6.txt -Encoding ascii
```

Do not use plain PowerShell redirection if running Windows PowerShell 5.x:

```powershell
az ... > .\feeds\azure-traffic-manager-probes-ipv4.txt
```

Windows PowerShell 5.x can write UTF-16 output, which may not be parsed correctly. Use `Set-Content -Encoding ascii` as shown above.

## Check the result

```powershell
(Get-Content .\feeds\azure-traffic-manager-probes.txt).Count
(Get-Content .\feeds\azure-traffic-manager-probes-ipv4.txt).Count
(Get-Content .\feeds\azure-traffic-manager-probes-ipv6.txt).Count

Get-Content .\feeds\azure-traffic-manager-probes-ipv4.txt -First 10
```

Optional encoding check in Windows PowerShell:

```powershell
$bytes = Get-Content .\feeds\azure-traffic-manager-probes-ipv4.txt -Encoding Byte -TotalCount 16
($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
```

Good output should look like normal ASCII bytes, for example:

```text
34 2E 31 35 30 2E 35 37 2E 32 30 33 2F 33 32
```

Bad output usually starts with `FF FE` or contains `00` bytes between characters.

## Usage example

For a normal IPv4 policy, use the IPv4-only feed:

```shell
config system external-resource
    edit "res-ext-ATM_Probes_IPv4"
        set status enable
        set type address
        set resource "https://<github-pages-or-raw-url>/feeds/azure-traffic-manager-probes-ipv4.txt"
        set refresh-rate 1440
        set server-identity-check none
    next
end
```

Force an update and check the feed:

```shell
execute update-external-resource res-ext-ATM_Probes_IPv4
diagnose sys external-resource stats
```

Expected result:

```text
total lines: 210; valid lines: 210; error lines: 0; used: yes
```

## Notes

This feed is intended to allow Azure Traffic Manager health probes only.

Policies should still restrict:

- destination address
- destination port/service
- published application endpoint

Do not use this feed as a broad allow-list for all Azure traffic.
