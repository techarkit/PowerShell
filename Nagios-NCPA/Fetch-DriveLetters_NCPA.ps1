<#
.SYNOPSIS
    Retrieves logical disk capacity information from remote NCPA Windows agents.

.DESCRIPTION
    Reads a list of remote servers from a TXT or CSV file, calls the NCPA
    /api/disk/logical endpoint through curl.exe, displays the results in a
    PowerShell table, and exports the results to CSV.

    Output columns:
      ServerName, DiskLetter, Total, Used, Free, PercentUsed

.PARAMETER ServerListPath
    Path to a TXT file containing one server/IP per line, or a CSV containing
    one of these columns: ServerName, Server, Hostname, Host, IPAddress, IP.

.PARAMETER Token
    NCPA community token. If omitted, the script reads NCPA_API_TOKEN from the
    current process environment.

.PARAMETER Port
    NCPA listener TCP port. Default: 5693.

.PARAMETER TimeoutSeconds
    Maximum time allowed for each API request. Default: 30 seconds.

.PARAMETER OutputFolder
    Folder used for CSV and log output. Default: NCPA-Disk-Reports beneath the
    script folder.

.PARAMETER SkipCertificateCheck
    Uses curl.exe --insecure for NCPA agents with self-signed certificates.

.EXAMPLE
    $env:NCPA_API_TOKEN = Read-Host "Enter NCPA token"
    .\Fetch-DriveLetters_NCPA.ps1 `
        -ServerListPath "C:\Scripts\Servers.txt" `
        -SkipCertificateCheck

.EXAMPLE
    .\Fetch-DriveLetters_NCPA.ps1 `
        -ServerListPath "C:\Scripts\Servers.csv" `
        -Token 'Your-NCPA-Token' `
        -OutputFolder "C:\Scripts\Reports" `
        -SkipCertificateCheck
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ServerListPath,

    [Parameter()]
    [string]$Token = $env:NCPA_API_TOKEN,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 5693,

    [Parameter()]
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 30,

    [Parameter()]
    [string]$OutputFolder = $(
        if ($PSScriptRoot) {
            Join-Path $PSScriptRoot "NCPA-Disk-Reports"
        }
        else {
            Join-Path (Get-Location).Path "NCPA-Disk-Reports"
        }
    ),

    [Parameter()]
    [switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw @"
NCPA token was not provided.

Use either:
  -Token 'Your-NCPA-Token'

Or preferably:
  `$env:NCPA_API_TOKEN = Read-Host "Enter NCPA token"
"@
}

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$OutputFolder = (Resolve-Path -LiteralPath $OutputFolder).Path
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$CsvReport = Join-Path $OutputFolder "NCPA_Disk_Details_$TimeStamp.csv"
$LogFile = Join-Path $OutputFolder "NCPA_Disk_Query_$TimeStamp.log"

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $LogEntry = "{0} [{1}] {2}" -f `
        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    $Color = switch ($Level) {
        "INFO"    { "Cyan" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
    }

    Write-Host $LogEntry -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value $LogEntry
}

function Get-ServerList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Extension = [System.IO.Path]::GetExtension($Path)

    if ($Extension -ieq ".csv") {
        $CsvData = @(Import-Csv -LiteralPath $Path)

        if ($CsvData.Count -eq 0) {
            throw "The server CSV is empty: $Path"
        }

        $AcceptedColumns = @(
            "ServerName", "Server", "Hostname", "Host", "IPAddress", "IP"
        )

        $ServerColumn = $AcceptedColumns |
            Where-Object { $_ -in $CsvData[0].PSObject.Properties.Name } |
            Select-Object -First 1

        if (-not $ServerColumn) {
            throw "The CSV must contain ServerName, Server, Hostname, Host, IPAddress, or IP."
        }

        return @(
            $CsvData |
                ForEach-Object { [string]$_.$ServerColumn } |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    }

    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                -not $_.StartsWith("#")
            } |
            Sort-Object -Unique
    )
}

function Invoke-NcpaApi {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$ServerName
    )

    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue

    if (-not $Curl) {
        throw "curl.exe is not installed or is not available through PATH."
    }

    $CurlArguments = @(
        "--silent",
        "--show-error",
        "--fail",
        "--tlsv1.2",
        "--connect-timeout", "15",
        "--max-time", $TimeoutSeconds.ToString(),
        "--header", "Accept: application/json"
    )

    if ($SkipCertificateCheck) {
        $CurlArguments += "--insecure"
    }

    $CurlArguments += $Uri
    Write-Verbose "Calling the NCPA logical-disk API on $ServerName."

    $ApiOutput = & $Curl.Source @CurlArguments 2>&1
    $CurlExitCode = $LASTEXITCODE

    if ($CurlExitCode -ne 0) {
        $CurlError = ($ApiOutput | Out-String).Trim()
        throw "curl.exe exit code $CurlExitCode. $CurlError"
    }

    $JsonText = ($ApiOutput | Out-String).Trim()

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "NCPA returned an empty response."
    }

    try {
        return $JsonText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "NCPA returned invalid JSON. $($_.Exception.Message)"
    }
}

function Convert-NcpaMeasurement {
    [CmdletBinding()]
    param (
        [Parameter()]
        $Measurement,

        [Parameter()]
        [switch]$Percent
    )

    if ($null -eq $Measurement) {
        return $null
    }

    $Items = @($Measurement)
    $Value = $Items[0]

    if ($Percent) {
        return ("{0}%" -f $Value)
    }

    if ($Items.Count -ge 2 -and $null -ne $Items[1]) {
        return ("{0} {1}" -f $Value, $Items[1])
    }

    return [string]$Value
}

function ConvertFrom-NcpaLogicalDisks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $ApiResponse,

        [Parameter(Mandatory)]
        [string]$ServerName
    )

    if ($null -eq $ApiResponse.logical) {
        throw "The NCPA response does not contain the expected 'logical' object."
    }

    $Rows = [System.Collections.Generic.List[object]]::new()

    foreach ($DiskProperty in $ApiResponse.logical.PSObject.Properties) {
        $NcpaDiskName = [string]$DiskProperty.Name

        # Windows NCPA disk keys normally appear as C:|, D:|, and so on.
        if ($NcpaDiskName -notmatch "^(?<Drive>[A-Za-z]):") {
            continue
        }

        $Disk = $DiskProperty.Value

        $Rows.Add(
            [PSCustomObject]@{
                ServerName = $ServerName
                DiskLetter = $Matches.Drive.ToUpper() + ":"
                Total = Convert-NcpaMeasurement -Measurement $Disk.total
                Used = Convert-NcpaMeasurement -Measurement $Disk.used
                Free = Convert-NcpaMeasurement -Measurement $Disk.free
                PercentUsed = Convert-NcpaMeasurement `
                    -Measurement $Disk.used_percent `
                    -Percent
            }
        )
    }

    return @($Rows | Sort-Object DiskLetter)
}

try {
    $Servers = @(Get-ServerList -Path $ServerListPath)

    if ($Servers.Count -eq 0) {
        throw "No servers were found in $ServerListPath"
    }

    Write-Log "Found $($Servers.Count) server(s) in the input file."

    $AllResults = [System.Collections.Generic.List[object]]::new()
    $FailedServers = [System.Collections.Generic.List[object]]::new()
    $ServerNumber = 0

    foreach ($Server in $Servers) {
        $ServerNumber++

        Write-Progress `
            -Activity "Fetching NCPA logical disk information" `
            -Status "$ServerNumber of $($Servers.Count): $Server" `
            -PercentComplete (($ServerNumber / $Servers.Count) * 100)

        Write-Log "Querying logical disks from $Server."

        try {
            $EncodedToken = [System.Uri]::EscapeDataString($Token)
            $ApiUri = "https://${Server}:${Port}/api/disk/logical?token=$EncodedToken"

            $Response = Invoke-NcpaApi -Uri $ApiUri -ServerName $Server
            $ServerDisks = @(
                ConvertFrom-NcpaLogicalDisks `
                    -ApiResponse $Response `
                    -ServerName $Server
            )

            if ($ServerDisks.Count -eq 0) {
                Write-Log `
                    -Level "WARNING" `
                    -Message "$Server returned no Windows logical disks."
                continue
            }

            foreach ($DiskRow in $ServerDisks) {
                $AllResults.Add($DiskRow)
            }

            Write-Log "$Server returned $($ServerDisks.Count) logical disk(s)."
        }
        catch {
            $ErrorMessage = $_.Exception.Message

            $FailedServers.Add(
                [PSCustomObject]@{
                    ServerName = $Server
                    Error = $ErrorMessage
                }
            )

            Write-Log `
                -Level "ERROR" `
                -Message "Unable to query $Server. $ErrorMessage"
        }
    }

    Write-Progress `
        -Activity "Fetching NCPA logical disk information" `
        -Completed

    if ($AllResults.Count -gt 0) {
        $AllResults |
            Export-Csv `
                -LiteralPath $CsvReport `
                -NoTypeInformation `
                -Encoding UTF8

        Write-Host "`nNCPA logical disk report:`n" -ForegroundColor Green

        $AllResults |
            Format-Table `
                ServerName, DiskLetter, Total, Used, Free, PercentUsed `
                -AutoSize

        Write-Log "CSV report created: $CsvReport"
    }
    else {
        Write-Log `
            -Level "WARNING" `
            -Message "No disk information was collected; no CSV was created."
    }

    if ($FailedServers.Count -gt 0) {
        Write-Host "`nFailed servers:`n" -ForegroundColor Yellow
        $FailedServers | Format-Table ServerName, Error -AutoSize -Wrap
    }

    Write-Host "`nCompleted." -ForegroundColor Green
    Write-Host "Successful disk rows : $($AllResults.Count)"
    Write-Host "Failed servers       : $($FailedServers.Count)"

    if ($AllResults.Count -gt 0) {
        Write-Host "CSV report           : $CsvReport"
    }

    Write-Host "Log file             : $LogFile"
}
catch {
    Write-Log -Level "ERROR" -Message $_.Exception.Message
    throw
}
