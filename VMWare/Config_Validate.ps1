# Import VMware PowerCLI Module
Write-Host "Importing PowerCLI Module" -ForegroundColor Green
Import-Module VMware.PowerCLI

# Set TLS to 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ignore SSL/TLS errors
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


# Load the JSON file
$jsonPath = "C:\VMWare\Config\default.json"
$jsonContent = Get-Content $jsonPath | ConvertFrom-Json

# Assign JSON values to variables
$vcServer = $jsonContent.vcServer
$datacenterName = $jsonContent.datacenterName
$clusterName = $jsonContent.clusterName
$datastoreName = $jsonContent.datastoreName
$networkName = $jsonContent.networkName
$templateName = $jsonContent.templateName
$libraryName = $jsonContent.libraryName

# Define vCenter server lists for different credentials
$vCentersVsphere = @(
    "vcserver1.example.com"
)

$vCentersVsphere2 = @(
    "vcserver2.example.com"
)

# Determine the credentials to use based on the vCenter server name
if ($vCentersVsphere -contains $vcServer) {

        ## Create a Secure String for vCenter credentials
        Remove-Item -Path D:\Creds\Encrypted_Password.txt.txt -Force -ErrorAction SilentlyContinue

        $VMSFile = "C:\VMWare\Creds\Encrypted_Password.txt.txt"

        #Check if the file already exists
           if (-not (Test-Path -Path $VMSFile)) {
               New-Item -Path $VMSFile -ItemType File
               Write-Host "Cred file created at: $VMSFile"
           } else {
               Write-Host "Cred file already exists, skipping creation."
           }

        # Convert the password to a secure string
        $VMWarePasswordFilePath = Join-Path -Path C:\VMWare\Secrets -ChildPath "password.txt"
        $vmwarepassword = Get-Content -Path $VMWarePasswordFilePath -Raw
        $securePassword2 = ConvertTo-SecureString -String $vmwarepassword -AsPlainText -Force
        $encryptedPassword2 = $securePassword2 | ConvertFrom-SecureString
        $encryptedPassword2 | Out-File C:\VMWare\Creds\Encrypted_Password.txt.txt
        $vcPass = Get-Content "C:\VMWare\Creds\Encrypted_Password.txt.txt" | ConvertTo-SecureString
        $vcCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "username@vsphere.local",$vcPass
    
} elseif ($vCentersVsphere2 -contains $vcServer) {
        # Create a Secure String for vCenter credentials
        Remove-Item -Path C:\VMWare\Creds\Encrypted_Password2.txt -Force -ErrorAction SilentlyContinue

        $VMSFile1 = "C:\VMWare\Creds\Encrypted_Password2.txt"

        #Check if the file already exists
           if (-not (Test-Path -Path $VMSFile1)) {
               New-Item -Path $VMSFile1 -ItemType File
               Write-Host "Cred file created at: $VMSFile1"
           } else {
               Write-Host "Cred file already exists, skipping creation."
           }

        # Convert the password to a secure string
        $VMWarePasswordFilePath = Join-Path -Path C:\VMWare\Secrets -ChildPath "password2.txt"
        $vmwarepassword = Get-Content -Path $VMWarePasswordFilePath -Raw
        $securePassword2 = ConvertTo-SecureString -String $vmwarepassword -AsPlainText -Force
        $encryptedPassword2 = $securePassword2 | ConvertFrom-SecureString
        $encryptedPassword2 | Out-File C:\VMWare\Creds\Encrypted_Password2.txt
        $vcPass = Get-Content "C:\VMWare\Creds\Encrypted_Password2.txt" | ConvertTo-SecureString
        $vcCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "username@vcenter.local",$vcPass
    
} else {
    Write-Error "vCenter server '$vcServer' is not recognized in the configuration lists."
}

# Connect to vCenter
Write-Host "Connecting to vCenter Server: $vcServer..." -ForegroundColor Yellow
Connect-VIServer -Server $vcServer -Credential $vcCred -ErrorAction Stop
Write-Host "Validating the given config is correct!" -ForegroundColor Yellow

# Function to Validate VMware Resources
function Validate-VMwareResources {
    param (
        [string]$datacenterName,
        [string]$clusterName,
        [string]$datastoreName,
        [string]$networkName,
        [string]$templateName
    )

    # Validate Datacenter
    $datacenter = Get-Datacenter -Name $datacenterName -ErrorAction SilentlyContinue
    if (-not $datacenter) {
        Write-Warning "Datacenter '$datacenterName' not found. Here are the available datacenters:"
        Get-Datacenter | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
        return $false
    } else {
        Write-Host "Datacenter '$datacenterName' validated successfully." -ForegroundColor Green
    }

    # Validate Cluster
    $cluster = Get-Cluster -Name $clusterName -Location $datacenter -ErrorAction SilentlyContinue
    if (-not $cluster) {
        Write-Warning "Cluster '$clusterName' not found in Datacenter '$datacenterName'. Available clusters:"
        Get-Cluster -Location $datacenter | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
        return $false
    } else {
        Write-Host "Cluster '$clusterName' validated successfully." -ForegroundColor Green
    }

    # Validate Datastore
    $datastore = Get-Datastore -Name $datastoreName -Location $datacenter -ErrorAction SilentlyContinue
    if (-not $datastore) {
        Write-Warning "Datastore '$datastoreName' not found in Datacenter '$datacenterName'. Available datastores:"
        Get-Datastore -Location $datacenter | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
        return $false
    } else {
        Write-Host "Datastore '$datastoreName' validated successfully." -ForegroundColor Green
    }

    # Validate Network (Port Group or Distributed Port Group)
    $network = Get-VirtualPortGroup -Name $networkName -ErrorAction SilentlyContinue
    if (-not $network) {
        $network = Get-VDPortGroup -Name $networkName -ErrorAction SilentlyContinue
        if (-not $network) {
            Write-Warning "Network '$networkName' not found. Available networks:"
            Get-VirtualPortGroup | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
            Get-VDPortGroup | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
            return $false
        }
    }
    Write-Host "Network '$networkName' validated successfully." -ForegroundColor Green

    # Validate Template
    $template = Get-Template -Name $templateName -ErrorAction SilentlyContinue
    if (-not $template) {
        Write-Warning "Template '$templateName' not found. Searching in Content Library..."
        $library = Get-ContentLibrary -Name $libraryName -ErrorAction SilentlyContinue
        if ($library) {
            $template = Get-ContentLibraryItem -ContentLibrary $library -Name $templateName -ErrorAction SilentlyContinue
            if ($template) {
                Write-Host "Template '$templateName' found in Content Library '$libraryName'." -ForegroundColor Green
            } else {
                Write-Warning "Template '$templateName' not found in Content Library '$libraryName'."
                Get-ContentLibraryItem -ContentLibrary $library | Select-Object -Property Name | ForEach-Object { Write-Host "- $($_.Name)" }
                return $false
            }
        } else {
            Write-Warning "Content Library '$libraryName' not found or unavailable."
            return $false
        }
    } else {
        Write-Host "Template '$templateName' validated successfully." -ForegroundColor Green
    }

    Write-Host "All resources validated successfully." -ForegroundColor Green
    return $true
}

# Call the Validation Function
if (-not (Validate-VMwareResources -datacenterName $datacenterName `
                                    -clusterName $clusterName `
                                    -datastoreName $datastoreName `
                                    -templateName $templateName `
                                    -networkName $networkName)) {
    Write-Error "Resource validation failed. Stopping deployment."
    Disconnect-VIServer -Server $vcServer -Confirm:$false
    exit 1
}

Write-Host "Validation successful. Proceed with deployment..." -ForegroundColor Green

Disconnect-VIServer -Server $vcServer -Confirm:$false
