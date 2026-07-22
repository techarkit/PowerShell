<#
.SYNOPSIS
    Monitors CPU and memory utilization on the local Windows server.

.DESCRIPTION
    - Collects CPU and memory utilization at a configurable interval.
    - Saves records into a daily CSV file.
    - Automatically creates the output and log directories.
    - Creates a new CSV file every day.
    - Includes informational, warning, and error logging.
    - Supports configurable CPU and memory warning thresholds.
    - Prevents overlapping instances.
    - Removes old CSV and log files according to the retention period.

.NOTES
    Run PowerShell as Administrator for reliable performance-counter access.
    File will save c:\ServerMonitoring\Data\CPU_Memory_Utilization_SERVERNAME.csv
    Log will save c:\ServerMonitoring\Logs/CPU_Memory_Monitor_DATE.log
#>

[CmdletBinding()]
param (
    # Number of seconds between samples
    [ValidateRange(1, 86400)]
    [int]$SampleIntervalSeconds = 60,

    # Number of samples to collect.
    # Use 0 to run continuously.
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxSamples = 0,

    # CPU warning threshold
    [ValidateRange(0, 100)]
    [double]$CpuWarningThreshold = 85,

    # Memory warning threshold
    [ValidateRange(0, 100)]
    [double]$MemoryWarningThreshold = 85,

    # Number of days to retain CSV and log files
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 30,

    # Base directory for output
    [string]$OutputDirectory = "C:\ServerMonitoring"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

$DataDirectory = Join-Path -Path $OutputDirectory -ChildPath "Data"
$LogDirectory  = Join-Path -Path $OutputDirectory -ChildPath "Logs"
$LockFile      = Join-Path -Path $OutputDirectory -ChildPath "CPU_Memory_Monitor.lock"

$ComputerName = $env:COMPUTERNAME
$Script:LockStream = $null

# -------------------------------------------------------------------
# Functions
# -------------------------------------------------------------------

function Initialize-Directories {
    foreach ($Directory in @($OutputDirectory, $DataDirectory, $LogDirectory)) {
        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -Path $Directory -ItemType Directory -Force |
                Out-Null
        }
    }
}

function Get-CurrentLogFile {
    $Date = Get-Date -Format "yyyyMMdd"
    return Join-Path -Path $LogDirectory `
        -ChildPath "CPU_Memory_Monitor_$Date.log"
}

function Get-CurrentCsvFile {
    $Date = Get-Date -Format "yyyyMMdd"
    return Join-Path -Path $DataDirectory `
        -ChildPath "CPU_Memory_Utilization_${ComputerName}_$Date.csv"
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp [$Level] $Message"
    $LogFile = Get-CurrentLogFile

    try {
        Add-Content -LiteralPath $LogFile `
            -Value $LogMessage `
            -Encoding UTF8
    }
    catch {
        Write-Warning "Unable to write to log file: $($_.Exception.Message)"
    }

    switch ($Level) {
        "INFO" {
            Write-Host $LogMessage -ForegroundColor Green
        }
        "WARNING" {
            Write-Warning $LogMessage
        }
        "ERROR" {
            Write-Host $LogMessage -ForegroundColor Red
        }
    }
}

function Enter-SingleInstanceLock {
    try {
        $Script:LockStream = [System.IO.File]::Open(
            $LockFile,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        $LockInformation = @"
ComputerName=$ComputerName
ProcessId=$PID
StartTime=$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

        $Script:LockStream.SetLength(0)

        $Writer = [System.IO.StreamWriter]::new(
            $Script:LockStream,
            [System.Text.Encoding]::UTF8,
            1024,
            $true
        )

        $Writer.Write($LockInformation)
        $Writer.Flush()
        $Writer.Dispose()
    }
    catch {
        throw "Another monitoring instance appears to be running. Lock file: $LockFile"
    }
}

function Exit-SingleInstanceLock {
    if ($null -ne $Script:LockStream) {
        $Script:LockStream.Dispose()
        $Script:LockStream = $null
    }

    if (Test-Path -LiteralPath $LockFile) {
        Remove-Item -LiteralPath $LockFile -Force `
            -ErrorAction SilentlyContinue
    }
}

function Remove-ExpiredFiles {
    $CutoffDate = (Get-Date).AddDays(-$RetentionDays)

    $FilePatterns = @(
        @{
            Path   = $DataDirectory
            Filter = "CPU_Memory_Utilization_*.csv"
        },
        @{
            Path   = $LogDirectory
            Filter = "CPU_Memory_Monitor_*.log"
        }
    )

    foreach ($Pattern in $FilePatterns) {
        Get-ChildItem -LiteralPath $Pattern.Path `
            -Filter $Pattern.Filter `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -lt $CutoffDate
            } |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force
                    Write-Log -Level INFO `
                        -Message "Removed expired file: $($_.FullName)"
                }
                catch {
                    Write-Log -Level WARNING `
                        -Message "Could not remove expired file '$($_.FullName)': $($_.Exception.Message)"
                }
            }
    }
}

function Get-ServerUtilization {
    try {
        # CPU utilization
        $CpuInformation = Get-CimInstance `
            -ClassName Win32_Processor `
            -ErrorAction Stop

        $CpuPercent = (
            $CpuInformation |
            Measure-Object -Property LoadPercentage -Average
        ).Average

        if ($null -eq $CpuPercent) {
            throw "CPU utilization returned no data."
        }

        # Memory utilization
        $OperatingSystem = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ErrorAction Stop

        $TotalMemoryGB = [math]::Round(
            $OperatingSystem.TotalVisibleMemorySize / 1MB,
            2
        )

        $FreeMemoryGB = [math]::Round(
            $OperatingSystem.FreePhysicalMemory / 1MB,
            2
        )

        $UsedMemoryGB = [math]::Round(
            $TotalMemoryGB - $FreeMemoryGB,
            2
        )

        if ($OperatingSystem.TotalVisibleMemorySize -le 0) {
            throw "Total memory returned an invalid value."
        }

        $MemoryUsedPercent = [math]::Round(
            (
                (
                    $OperatingSystem.TotalVisibleMemorySize -
                    $OperatingSystem.FreePhysicalMemory
                ) /
                $OperatingSystem.TotalVisibleMemorySize
            ) * 100,
            2
        )

        $Timestamp = Get-Date

        return [PSCustomObject][ordered]@{
            Timestamp         = $Timestamp.ToString(
                "yyyy-MM-dd HH:mm:ss"
            )
            ComputerName      = $ComputerName
            CPUUtilizationPct = [math]::Round(
                [double]$CpuPercent,
                2
            )
            TotalMemoryGB     = $TotalMemoryGB
            UsedMemoryGB      = $UsedMemoryGB
            FreeMemoryGB      = $FreeMemoryGB
            MemoryUsedPct     = $MemoryUsedPercent
        }
    }
    catch {
        throw "Unable to collect server utilization: $($_.Exception.Message)"
    }
}

function Save-UtilizationData {
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$Utilization
    )

    $CsvFile = Get-CurrentCsvFile

    try {
        if (Test-Path -LiteralPath $CsvFile) {
            $Utilization |
                Export-Csv `
                    -LiteralPath $CsvFile `
                    -Append `
                    -NoTypeInformation `
                    -Encoding UTF8
        }
        else {
            $Utilization |
                Export-Csv `
                    -LiteralPath $CsvFile `
                    -NoTypeInformation `
                    -Encoding UTF8

            Write-Log -Level INFO `
                -Message "Created CSV file: $CsvFile"
        }
    }
    catch {
        throw "Unable to write monitoring data to '$CsvFile': $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------
# Main execution
# -------------------------------------------------------------------

try {
    Initialize-Directories
    Enter-SingleInstanceLock
    Remove-ExpiredFiles

    if ($MaxSamples -eq 0) {
        $CollectionMode = "Continuous"
    }
    else {
        $CollectionMode = "$MaxSamples samples"
    }

    Write-Log -Level INFO `
        -Message "CPU and memory monitoring started."

    Write-Log -Level INFO `
        -Message "Computer name: $ComputerName"

    Write-Log -Level INFO `
        -Message "Collection mode: $CollectionMode"

    Write-Log -Level INFO `
        -Message "Sample interval: $SampleIntervalSeconds seconds"

    Write-Log -Level INFO `
        -Message "CPU warning threshold: $CpuWarningThreshold%"

    Write-Log -Level INFO `
        -Message "Memory warning threshold: $MemoryWarningThreshold%"

    Write-Log -Level INFO `
        -Message "Data directory: $DataDirectory"

    $SampleNumber = 0

    while (($MaxSamples -eq 0) -or ($SampleNumber -lt $MaxSamples)) {
        $SampleNumber++

        try {
            $Utilization = Get-ServerUtilization
            Save-UtilizationData -Utilization $Utilization

            $StatusMessage = (
                "Sample {0}: CPU={1}%, Memory={2}% " +
                "(Used={3} GB, Free={4} GB, Total={5} GB)"
            ) -f (
                $SampleNumber,
                $Utilization.CPUUtilizationPct,
                $Utilization.MemoryUsedPct,
                $Utilization.UsedMemoryGB,
                $Utilization.FreeMemoryGB,
                $Utilization.TotalMemoryGB
            )

            if (
                ($Utilization.CPUUtilizationPct -ge $CpuWarningThreshold) -or
                ($Utilization.MemoryUsedPct -ge $MemoryWarningThreshold)
            ) {
                Write-Log -Level WARNING -Message $StatusMessage
            }
            else {
                Write-Log -Level INFO -Message $StatusMessage
            }
        }
        catch {
            Write-Log -Level ERROR `
                -Message "Sample $SampleNumber failed: $($_.Exception.Message)"
        }

        if (($MaxSamples -eq 0) -or ($SampleNumber -lt $MaxSamples)) {
            Start-Sleep -Seconds $SampleIntervalSeconds
        }
    }

    Write-Log -Level INFO `
        -Message "Requested number of samples completed."
}
catch {
    if (Test-Path -LiteralPath $LogDirectory) {
        Write-Log -Level ERROR -Message $_.Exception.Message
    }
    else {
        Write-Error $_.Exception.Message
    }

    exit 1
}
finally {
    Exit-SingleInstanceLock

    if (Test-Path -LiteralPath $LogDirectory) {
        Write-Log -Level INFO `
            -Message "CPU and memory monitoring stopped."
    }
}
