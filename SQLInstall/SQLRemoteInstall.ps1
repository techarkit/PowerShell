## REsolve TLS/SSL Error for connecting to vCenter
Set-PowerCLIConfiguration -Confirm:$false -Scope AllUsers -InvalidCertificateAction Ignore -DefaultVIServerMode Single

$remoteServer = "ServerName"
$destinationBasePath = "\\$remoteServer\C$\"

# Copy Powershell script to remote server and execute
Write-Host "Copying SQLInstallation.ps1..."
Copy-Item -Path C:\SQLInstallation.ps1 -Destination $destinationBasePath -Force

## Create Encrypted password string
# Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File C:\Creds\adminuser.txt

$pass = Get-Content "C:\Creds\adminuser.txt" | ConvertTo-SecureString
$guestCred = New-Object System.Management.Automation.PSCredential -ArgumentList "adminuser",$pass

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## vCenter Details
$vCenter = "vcenter@vsphere.local"
$username = 'administrator@vsphere.local'
$password = 'password'

Connect-VIServer -Server $vCenter -User $username -Password $password -WarningAction SilentlyContinue

# Execute the script inside the VM
Write-Output "Executing the Software Installation script inside the VM..."
$executeScript1 = "powershell.exe -ExecutionPolicy Bypass -File C:\SQLInstallation.ps1 -server $remoteServer"
Invoke-VMScript -VM $remoteServer -ScriptText $executeScript1 -GuestCredential $guestCred -ScriptType bat
Write-Output "Software Installation Script Executed."
