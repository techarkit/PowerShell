param (
    [string]$VMName,
    [string]$VMIPAddress,
    [string[]]$Tags
)

# Define variables
$QualysBaseURL = "https://qualysapi.qg3.apps.qualys.com"
$Username = "<USERNAME>"
$Password = "<PASSWORD>"
$lowercaseVMName = $VMName.ToLower()
$FQDN = "$lowercaseVMName.domain.com"

# Encode credentials for Basic Authentication
$AuthInfo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:${Password}"))
$Credential = New-Object -TypeName PSCredential -ArgumentList $Username, (ConvertTo-SecureString -String $Password -AsPlainText -Force)

# Function to search for the host asset
function Get-QualysAsset {
    param (
        [string]$VMName,
        [string]$FQDN,
        [string]$VMIPAddress
    )

    $SearchBodyDnsName = @{
        "ServiceRequest" = @{
            "filters" = @{
                "Criteria" = @(
                    @{
                        "field" = "dnsHostName"
                        "operator" = "EQUALS"
                        "value" = $VMName
                    }
                )
            }
        }
    } | ConvertTo-Json -Depth 10

    $SearchBodyFQDN = @{
        "ServiceRequest" = @{
            "filters" = @{
                "Criteria" = @(
                    @{
                        "field" = "dnsHostName"
                        "operator" = "EQUALS"
                        "value" = $FQDN
                    }
                )
            }
        }
    } | ConvertTo-Json -Depth 10

    $SearchBodyIPAddress = @{
        "ServiceRequest" = @{
            "filters" = @{
                "Criteria" = @(
                    @{
                        "field" = "privateIpAddress"
                        "operator" = "EQUALS"
                        "value" = $VMIPAddress
                    }
                )
            }
        }
    } | ConvertTo-Json -Depth 10

    $SearchBodies = @($SearchBodyDnsName, $SearchBodyFQDN, $SearchBodyIPAddress)
    foreach ($SearchBody in $SearchBodies) {
        Write-Output "Sending Search Request:"
        Write-Output $SearchBody

        try {
            $AssetResponse = Invoke-RestMethod -Uri "$QualysBaseURL/qps/rest/2.0/search/am/hostasset" -Method Post -Headers @{
                Authorization=("Basic {0}" -f $AuthInfo)
                "X-Requested-With" = "PowerShell"
                "Content-Type" = "application/json"
                "Accept" = "application/json"
            } -Body $SearchBody

            Write-Output "Received Asset Response:"
            Write-Output ($AssetResponse | ConvertTo-Json -Depth 10)

            # Extract Asset ID
            $AssetId = $AssetResponse.ServiceResponse.data.HostAsset.id
            if ($AssetId) {
                Write-Output "Asset ID: $AssetId"
                return $AssetId
            }
        } catch {
            Write-Error "Error during asset search: $_"
            return $null
        }
    }

    Write-Output "No asset found for the given DNS name, FQDN, or IP address."
    return $null
}

# Function to search for the tag
function Get-QualysTag {
    param (
        [string]$TagName
    )

    $TagSearchBody = @{
        "ServiceRequest" = @{
            "filters" = @{
                "Criteria" = @(
                    @{
                        "field" = "name"
                        "operator" = "EQUALS"
                        "value" = $TagName
                    }
                )
            }
        }
    } | ConvertTo-Json -Depth 10

    Write-Output "Sending Search Tag Request:"
    Write-Output $TagSearchBody

    try {
        $TagSearchResponse = Invoke-RestMethod -Uri "$QualysBaseURL/qps/rest/2.0/search/am/tag" -Method Post -Headers @{
            Authorization=("Basic {0}" -f $AuthInfo)
            "X-Requested-With" = "PowerShell"
            "Content-Type" = "application/json"
            "Accept" = "application/json"
        } -Body $TagSearchBody

        Write-Output "Received Search Tag Response:"
        Write-Output ($TagSearchResponse | ConvertTo-Json -Depth 10)

        # Extract Tag ID
        $TagId = $TagSearchResponse.ServiceResponse.data.Tag.id
        if ($TagId) {
            Write-Output "Tag ID: $TagId"
            return $TagId
        }
    } catch {
        Write-Error "Error during tag search: $_"
        return $null
    }

    Write-Output "No tag found with the name '$TagName'."
    return $null
}

# Function to add a tag to an asset
function Add-QualysAssetTagAssignment {
    param (
        [Int64]$AssetId,
        [Int64]$TagId
    )

    $BodyAddTag = @"
<ServiceRequest>
    <data>
        <HostAsset>
            <tags>
                <add>
                    <TagSimple>
                        <id>$TagId</id>
                    </TagSimple>
                </add>
            </tags>
        </HostAsset>
    </data>
</ServiceRequest>
"@

    $RestSplat = @{
        Uri         = "$QualysBaseURL/qps/rest/2.0/update/am/hostasset/$AssetId"
        Method      = 'POST'
        Body        = $BodyAddTag
        ContentType = 'application/xml'
        Headers     = @{
            "Authorization" = "Basic $AuthInfo"
            "X-Requested-With" = "PowerShell"
        }
    }

    Log-DebugInfo "Sending Tag Add Request" $BodyAddTag

    try {
        $response = Invoke-RestMethod @RestSplat
        Log-DebugInfo "Tag added successfully to asset ID $AssetId" $response
    } catch {
        Log-DebugInfo "Error adding tag ${TagId} to asset ${AssetId}" $_
    }
}


# Add tags to the specified VM
foreach ($Tag in $Tags) {
    $AssetId = Get-QualysAsset -VMName $VMName -FQDN $FQDN -VMIPAddress $VMIPAddress

    if ($null -eq $AssetId -or $AssetId -match "^\{.*\}$") {
        Write-Error "No valid asset ID found for the name '$VMName', FQDN '$FQDN', or IP address '$VMIPAddress'."
        continue
    }

    Write-Output "Asset ID: $AssetId"

     
    $fileContent = $AssetId
    
    # Initialize an empty variable to store the AssetID
    $assetID = $null
    
    # Loop through each line of the content
    foreach ($line in $fileContent) {
        if ($line -match "Asset ID: (\d+)") {
            $assetID = $matches[1]
            break
        }
    }
    
    $ParsedAssetId = 0
    if (-not [Int64]::TryParse($assetID.ToString(), [ref]$ParsedAssetId)) {
        Write-Error "Invalid AssetId: $assetID"
        continue
    }

    $TagId = Get-QualysTag -TagName $Tag
    if ($null -eq $TagId) {
        Write-Error "No tag found with the name '$Tag'."
        continue
    }

    Write-Output "Tag ID: $TagId"

    
    $fileContent = $TagId
    
    $tagID = $null
    
    foreach ($line in $fileContent) {
        if ($line -match "Tag ID: (\d+)") {
            $tagID = $matches[1]
            break
        }
    }

    $ParsedTagId = 0
    if (-not [Int64]::TryParse($tagId.ToString(), [ref]$ParsedTagId)) {
        Write-Error "Invalid TagId: $tagId"
        continue
    }

    Add-QualysAssetTagAssignment -AssetId $ParsedAssetId -TagId $ParsedTagId
}
