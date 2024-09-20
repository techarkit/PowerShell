# Check if the script is running with elevated permissions
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    # Restart the script with elevated permissions
    Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Specify desired drive letters for each uninitialized disk
$desiredDriveLetters = @("E", "F", "G", "T", "L")

# Specify disk labels for each uninitialized disk
$diskLabels = @("Programdata", "DBData", "BackupDisk", "TempData", "LogData") 

# Get all disks that are not initialized
$disks = Get-Disk | Where-Object PartitionStyle -eq 'RAW'

# Check if the number of drive letters and labels matches the number of uninitialized disks
if ($disks.Count -gt $desiredDriveLetters.Count -or $disks.Count -gt $diskLabels.Count) {
    Write-Host "Error: More disks than specified drive letters or labels. Please add more drive letters and labels."
    exit
} elseif ($disks.Count -lt $desiredDriveLetters.Count -or $disks.Count -lt $diskLabels.Count) {
    Write-Host "Warning: More drive letters or labels than disks. Extra drive letters or labels will not be used."
}

# Initialize each disk, create a partition, format it with the corresponding drive letter and label
for ($i = 0; $i -lt $disks.Count; $i++) {
    $disk = $disks[$i]
    $driveLetter = $desiredDriveLetters[$i]
    $diskLabel = $diskLabels[$i]

    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    # Create a new partition and assign the specified drive letter
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $driveLetter

    # Format the partition with NTFS and assign the specified label
    Format-Volume -DriveLetter $partition.DriveLetter -FileSystem NTFS -NewFileSystemLabel $diskLabel -Confirm:$false

    # Get the volume associated with the new partition
    $volume = Get-Volume -FileSystemLabel $diskLabel

    Write-Host "Disk $($disk.Number) initialized, partition created, formatted with NTFS, drive letter assigned to $driveLetter, and label set to $diskLabel."
}
