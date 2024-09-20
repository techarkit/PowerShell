New-Item -ItemType Directory -Path C:\Scripts -Force
New-Item -Path "C:\Scripts\Wind_Updates.log" -ItemType File

# Define the log file path
$logFilePath = "C:\Scripts\Wind_Updates.log"

# Function to write output to both console and log file
function Write-Log {
    param (
        [string]$message
    )
    # Write to console
    Write-Output $message
    # Append to log file
    $message | Out-File -FilePath $logFilePath -Append
}

# Check if Windows Update module is installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
    Write-Log "PSWindowsUpdate module installed."
}

# Import the Windows Update module
Import-Module PSWindowsUpdate

# Log the start of the update check
Write-Log "Starting Windows Update status check at $(Get-Date)"

# Get Windows Update status (installed updates)
$windowsUpdateStatus = Get-WindowsUpdate -IsInstalled -ErrorAction SilentlyContinue

if ($windowsUpdateStatus) {
    Write-Log "Windows Update status:"
    foreach ($update in $windowsUpdateStatus) {
        Write-Log "Title: $($update.Title)"
        Write-Log "KB: $($update.KBArticleID)"
        Write-Log "Installed On: $($update.InstallDate)"
        Write-Log "Status: Installed"
        Write-Log "---------------------------------"
    }
} else {
    Write-Log "No installed updates found or an error occurred."
}

# Check for pending updates
$pendingUpdates = Get-WindowsUpdate -ErrorAction SilentlyContinue

if ($pendingUpdates) {
    Write-Log "Pending Windows Updates:"
    foreach ($update in $pendingUpdates) {
        Write-Log "Title: $($update.Title)"
        Write-Log "KB: $($update.KBArticleID)"
        Write-Log "Status: Pending"
        Write-Log "---------------------------------"
    }

    # Install the pending updates
    Write-Log "Installing pending Windows Updates..."
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Installed Update: $($_.Title)"
        Write-Log "Reboot Required: $($_.RebootRequired)"
        Write-Log "---------------------------------"
    }
} else {
    Write-Log "No pending updates found or an error occurred."
}

# Log the end of the update check and installation process
Write-Log "Finished Windows Update status check and installation at $(Get-Date)"
