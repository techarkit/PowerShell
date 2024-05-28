# Variables
$NetBoxName = "<NetBoxName_Here>"
# Import CSV data
$csvPath = "C:\NetBox\import.csv"
$ImportVMs = Import-Csv -Path $csvPath -Encoding UTF8

# NetBox API Headers
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Token <API_TOKEN_HERE>"
}

# Loop through each VM in the CSV file
foreach ($VM in $ImportVMs) {
    Write-Host "$($VM.name) - Creating VM record" -ForegroundColor Green

    # Set Memory value to MB
    $VMRAM = if ($VM.ram -match "GB") {
        1024 * ($VM.ram -replace " GB", "")
    } elseif ($VM.ram -match "MB") {
        $VM.ram -replace " MB", ""
    }

    # Create the VM JSON body
    $vmbody = @{
        name        = $VM.name
        status      = $VM.status
        site        = @{name = $VM.site}
        cluster     = @{name = $VM.cluster}
        role        = @{name = $VM.role}
        vcpus       = $VM.cpu
        memory      = $VMRAM
        description = $VM.description
        comments    = $VM.comments
        custom_fields = @{
            cname                   = $VM.cname
            ENV                     = $VM.env
            Managed_By              = $VM.managed_by
            OS                      = $VM.os
            Patching                = $VM.patching
            Patching_CST_Window     = $VM.patching_window
            Patching_Custom_Reboot  = $VM.patching_reboot
            Priority                = $VM.priority
            Azure_VM_Size           = $VM.vmSize
        }
    } | ConvertTo-Json

    # Create the VM and retrieve the VM ID
    try {
        $vmresponse = Invoke-RestMethod -Uri 'https://$NetBoxName/api/virtualization/virtual-machines/' -Method 'POST' -Headers $headers -Body $vmbody
        $vmid = $vmresponse.id
    } catch {
        Write-Host "Failed to create VM '$($VM.name)': $_" -ForegroundColor Red
        continue
    }

    # Create the Virtual Interface
    Write-Host "$($VM.name) - Creating Virtual Interface record" -ForegroundColor Yellow
    $NETINT = "$($VM.name)-IP"

    $intbody = @{
        virtual_machine = @{id = $vmid}
        name            = $NETINT
        enabled         = $true
    } | ConvertTo-Json

    try {
        $intresponse = Invoke-RestMethod -Uri 'https://$NetBoxName/api/virtualization/interfaces/' -Method 'POST' -Headers $headers -Body $intbody
        $intid = $intresponse.id
    } catch {
        Write-Host "Failed to create interface for VM '$($VM.name)': $_" -ForegroundColor Red
        continue
    }

    # Create IP and assign to Virtual Interface
    if ($VM.ip) {
        Write-Host "$($VM.name) - Creating IP" -ForegroundColor White

        $ipbody = @{
            address               = $VM.ip
            status                = "active"
            assigned_object_type  = "virtualization.vminterface"
            assigned_object_id    = $intid
        } | ConvertTo-Json

        try {
            $ipresponse = Invoke-RestMethod -Uri 'https://$NetBoxName/api/ipam/ip-addresses/' -Method 'POST' -Headers $headers -Body $ipbody
            $ipid = $ipresponse.id
        } catch {
            Write-Host "Failed to create IP for VM '$($VM.name)': $_" -ForegroundColor Red
            continue
        }
    } else {
        Write-Host "$($VM.name) - No IP, skipping creating one"
    }

    # Assign Primary IP to Virtual Machine
    if ($VM.ip) {
        Write-Host "$($VM.name) - Assigning Primary IP to VM" -ForegroundColor Cyan

        $body = @{
            primary_ip4 = @{id = $ipid}
        } | ConvertTo-Json

        try {
            $VMIDURL = "https://$NetBoxName/api/virtualization/virtual-machines/$vmid/"
            Invoke-RestMethod -Uri $VMIDURL -Method 'PATCH' -Headers $headers -Body $body
        } catch {
            Write-Host "Failed to assign primary IP to VM '$($VM.name)': $_" -ForegroundColor Red
            continue
        }
    } else {
        Write-Host "$($VM.name) - No IP, skipping assigning Primary IP to VM"
    }

    # Clear variables for next iteration
    $vmid = $null
    $intid = $null
}
