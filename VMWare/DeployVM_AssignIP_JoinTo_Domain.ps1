# Install Required PowerShell Modules
Install-Module -Name VMWare.PowerCLI
Install-Module -Name Infoblox

# Load the VMware PowerCLI module
Import-Module VMware.PowerCLI
Import-Module Infoblox

## Create a Secure String
# Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File D:\Creds\VMWareSecureString.txt

# Create a Secure String for vCenter credentials
$vcPass = Get-Content "D:\Creds\VMWareSecureString.txt" | ConvertTo-SecureString
$vcCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "administrator@vsphere.local",$vcPass

# Guest OS credentials
$pass = Get-Content "D:\Creds\VMLocalAdmin.txt" | ConvertTo-SecureString
$guestCred = New-Object System.Management.Automation.PSCredential -ArgumentList "localadmin",$pass

# Define variables
$vcServer = "<vCENTER_NAME>"
$templateName = "<VM_TEMPLATE_NAME>"
$vmName = "<VM_NAME>"
$datacenterName = "<DATACENTER_NAME>"
$clusterName = "<VMWARE_CLUSTER_NAME>"
$datastoreName = "<DATASTORE_NAME>"
$networkName = "<VM_NETWORK_NAME>"
$osCustomizationSpecName = "<VM_CUSTOMIZATION_SPECIFICATION_NAME>"  ##You have to Create One
$adminPassword = ConvertTo-SecureString "<VM_LOCAL_ADMIN_PASSWORD>" -AsPlainText -Force
$timeZone = 035 # Eastern (U.S. and Canada)
$numCpu = 4
$memoryGB = 16

# Infoblox settings
$infobloxServer = "https://<INFOBLOX_URL>"
$infobloxUsername = "<INFOBLOX_LOCALADMIN_USERNAME>"
$infobloxPassword = "<INFOBLOX_PASSWORD>"
$network = "192.168.1.0/24"  # The network from which you want to get available IPs

# Domain join settings
$domainName = "<DOMAIN_NAME>"
$domainJoinUser = "<DOMAIN_ADMIN_ACCOUNT>"
$domainJoinPassword = ConvertTo-SecureString "<DOMAIN_ADMIN_PASSWORD>" -AsPlainText -Force
$ouPath = "OU=Servers,DC=DOMAIN,DC=DOMAIN,DC=com"

# Set TLS to 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Convert credentials to Base64
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${infobloxUsername}:${infobloxPassword}")))

try {
    # Define the URI for the API request to get network reference
    $uri = "${infobloxServer}/wapi/v2.10/network?network=${network}&_return_fields=extattrs"

    # Make the API request to get the network reference
    $response = Invoke-RestMethod -Uri $uri -Method Get -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

    if ($response -eq $null) {
        throw "No response from the server. Please check the network and try again."
    }

    # Extract the network reference
    $networkRef = $response[0]._ref

    # Define the URI to get the next available IPs
    $uri = "${infobloxServer}/wapi/v2.10/${networkRef}?_function=next_available_ip"

    # Define the body of the request
    $body = @{
        num = 1  # Number of IPs you want to retrieve
    }

    # Convert body to JSON
    $jsonBody = $body | ConvertTo-Json

    # Make the API request to get the next available IP
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $jsonBody -ContentType "application/json"

    # Retrieve the available IP address
    $ipAddress = $response.ips[0]
    Write-Output "Obtained IP address from Infoblox: $ipAddress"

    # Network settings
    $subnetMask = "255.255.255.0"
    $gateway = "192.168.1.1"
    $dnsServers = "192.168.2.5,192.168.1.10"

    # Connect to vCenter server
    Write-Output "Connecting to vCenter server '$vcServer'..."
    Connect-VIServer -Server $vcServer -Credential $vcCred

    # Check if the customization spec already exists
    $osCustomizationSpec = Get-OSCustomizationSpec -Name $osCustomizationSpecName -ErrorAction SilentlyContinue
    if (-not $osCustomizationSpec) {
        # Create a new customization spec if it doesn't exist
        $osCustomizationSpec = New-OSCustomizationSpec -Name $osCustomizationSpecName -Type NonPersistent -FullName "Administrator" -OrgName "<ORGANIZATION_NAME>" -Workgroup "WORKGROUP" -ChangeSID $true
    } else {
        # Update the existing customization spec
        Set-OSCustomizationSpec -OSCustomizationSpec $osCustomizationSpec -Description "Customization spec for WS2019 with static IP configuration and domain join" -AdminPassword $adminPassword -TimeZone $timeZone -ChangeSID $true
    }

    # Retrieve the customization spec again to ensure it is up-to-date
    $osCustomizationSpec = Get-OSCustomizationSpec -Name $osCustomizationSpecName

    # Create network adapter mapping for static IP configuration
    $adapterMapping = Get-OSCustomizationNicMapping -OSCustomizationSpec $osCustomizationSpec
    $adapterMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $ipAddress -SubnetMask $subnetMask -DefaultGateway $gateway -Dns $dnsServers.Split(",")

    # Get the template
    $template = Get-Template -Name $templateName

    # Get the cluster
    $cluster = Get-Cluster -Name $clusterName

    # Get the datastore
    $datastore = Get-Datastore -Name $datastoreName

    # Get the network
    $vds = Get-VDSwitch -Location (Get-Datacenter -Name $datacenterName)
    $network = Get-VDPortGroup -Name $networkName -Vds $vds

    # Get the resource pool
    $resourcePool = Get-ResourcePool -Location $cluster

    # Create the VM with essential parameters
    Write-Output "Creating VM '$vmName' from template with essential parameters..."
    $vm = New-VM -Name $vmName -Template $template -VMHost (Get-VMHost -Location $cluster | Get-Random) -Datastore $datastore -ResourcePool $resourcePool
    Write-Output "VM created with essential parameters: $($vm | Format-List -Property *)"

    # Add OCustomizationSpec
    Write-Output "Adding OCustomizationSpec..."
    Set-VM -VM $vm -OSCustomizationSpec $osCustomizationSpec -Confirm:$false
    Write-Output "OCustomizationSpec added."

    # Add NumCpu
    Write-Output "Adding NumCpu..."
    Set-VM -VM $vm -NumCpu $numCpu -Confirm:$false
    Write-Output "NumCpu added."

    # Add MemoryGB
    Write-Output "Adding MemoryGB..."
    Set-VM -VM $vm -MemoryGB $memoryGB -Confirm:$false
    Write-Output "MemoryGB added."

    # Add PortGroup
    Write-Output "Adding PortGroup..."
    $vm | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $networkName -Confirm:$false
    Write-Output "PortGroup added."

    # Power on the VM
    Write-Output "Powering on VM '$vmName'..."
    Start-VM -VM $vm
    Write-Output "VM powered on."

    Write-Output "VM '$vmName' created, customized with static IP, and powered on successfully."

    # Wait for VM to be fully started
    Start-Sleep -Seconds 120

    # Join the domain using Invoke-VMScript
    $domainJoinScript = @"
\$adminPass = ConvertTo-SecureString -String "$domainJoinPassword" -AsPlainText -Force
\$credential = New-Object System.Management.Automation.PSCredential("$domainJoinUser", \$adminPass)
Add-Computer -DomainName "$domainName" -OUPath "$ouPath" -Credential \$credential -Restart
"@

    Write-Output "Joining VM '$vmName' to domain '$domainName'..."
    Invoke-VMScript -VM $vm -ScriptText $domainJoinScript -GuestCredential $guestCred -Confirm:$false
    Write-Output "Domain join script executed."

    # Create an A record in Infoblox
    Write-Output "Creating A record in Infoblox for '$vmName'..."
    $aRecordUri = "${infobloxServer}/wapi/v2.10/record:a"
    $aRecordBody = @{
        name = "$vmName.corp.duracell.com"
        ipv4addr = $ipAddress
        ttl = 3600
    }

    $jsonARecordBody = $aRecordBody | ConvertTo-Json
    Write-Output "A Record JSON Body: $jsonARecordBody"

    # Make the API request to create the A record
    $aRecordResponse = Invoke-RestMethod -Uri $aRecordUri -Method Post -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Body $jsonARecordBody -ContentType "application/json"
    Write-Output "A record created: $($aRecordResponse | Format-List -Property *)"

    Write-Output "A record for '$vmName' created in Infoblox with IP address $ipAddress."

} catch {
    Write-Error "An error occurred: $_"
}
