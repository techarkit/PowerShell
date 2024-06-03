# Define variables
$vmName = "<HOSTNAME>"
$ipAddress = "<IPADDRESS>"
$domainName = "<YOURDOMAIN.COM>"
$infobloxServer = "https://infoblox.yourdomain.com"

# read-host -assecurestring | convertfrom-securestring | out-file c:\infoblox.txt

# Convert password to a secure string and create a credential object
$securePassword = cat c:\infoblox.txt | ConvertTo-SecureString
$credential = New-Object System.Management.Automation.PSCredential -argumentlist "USERNAME",$securePassword

# Encode credentials in base64 for Basic Authentication
$authInfo = ("{0}:{1}" -f $credential.UserName, $credential.GetNetworkCredential().Password)
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authInfo))

# Create A record in Infoblox
Write-Output "Creating A record in Infoblox for '$vmName'..."
$aRecordUri = "${infobloxServer}/wapi/v2.10/record:a"
$aRecordBody = @{
    name = "$vmName.$domainName"
    ipv4addr = $ipAddress
    ttl = 3600
}

$jsonARecordBody = $aRecordBody | ConvertTo-Json
Write-Output "A Record JSON Body: $jsonARecordBody"

# Make the API request to create the A record
$aRecordResponse = Invoke-RestMethod -Uri $aRecordUri -Method Post -Headers @{Authorization=("Basic $base64AuthInfo")} -Body $jsonARecordBody -ContentType "application/json"
Write-Output "A record created: $($aRecordResponse | Format-List -Property *)"

Write-Output "A record for '$vmName' created in Infoblox with IP address $ipAddress."

# Create PTR record in Infoblox
Write-Output "Creating PTR record in Infoblox for '$vmName'..."
$ptrRecordUri = "${infobloxServer}/wapi/v2.10/record:ptr"
$reverseZone = ($ipAddress -split '\.')[2..0] -join '.' + '.in-addr.arpa'
$ptrRecordBody = @{
    ptrdname = "$vmName.$domainName"
    ipv4addr = $ipAddress
    ttl = 3600
}

$jsonPtrRecordBody = $ptrRecordBody | ConvertTo-Json
Write-Output "PTR Record JSON Body: $jsonPtrRecordBody"

# Make the API request to create the PTR record
$ptrRecordResponse = Invoke-RestMethod -Uri $ptrRecordUri -Method Post -Headers @{Authorization=("Basic $base64AuthInfo")} -Body $jsonPtrRecordBody -ContentType "application/json"
Write-Output "PTR record created: $($ptrRecordResponse | Format-List -Property *)"

Write-Output "PTR record for '$vmName' created in Infoblox with IP address $ipAddress."
