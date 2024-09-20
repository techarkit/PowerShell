# Define the required drive letters
$requiredDrives = @("E", "F", "G", "T", "L")

# Get all the current drive letters on the system
$existingDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name

# Check if all required drives exist
$missingDrives = $requiredDrives | Where-Object { $_ -notin $existingDrives }

# If any drives are missing, exit the script
if ($missingDrives.Count -gt 0) {
    Write-Host "The following required drive(s) are missing: $($missingDrives -join ', ')"
    Write-Host "Exiting script."
    exit 1
} else {
    Write-Host "All required drives are present. Proceeding with SQL installation."
}

# Define the paths
$ProgData = "E:\Data\MSSQL"
$DataPath = "F:\Data"
$LogPath = "L:\Log"
$TempPath = "T:\TempDB"
$BackupPath = "G:\Backup"

# Function to check if a folder exists and create it if it doesn't
function Create-FolderIfMissing {
    param (
        [string]$FolderPath
    )
    
    if (-not (Test-Path $FolderPath)) {
        try {
            New-Item -Path $FolderPath -ItemType Directory -Force
            Write-Host "Created folder: $FolderPath"
        } catch {
            Write-Host "Failed to create folder: $FolderPath"
            exit 1
        }
    } else {
        Write-Host "Folder already exists: $FolderPath"
    }
}

# Create the folders if they are missing
Create-FolderIfMissing -FolderPath $ProgData
Create-FolderIfMissing -FolderPath $DataPath
Create-FolderIfMissing -FolderPath $LogPath
Create-FolderIfMissing -FolderPath $TempPath
Create-FolderIfMissing -FolderPath $BackupPath

function Install-SqlServer {
    [CmdletBinding()]
    param ()

    # Parameters (You can modify these as per your environment)
    $SetupFilesPath = "C:\Setup"
    $Version = 2019
    $InstallEngine = $true
    $InstallCU = $false
    $InstallSSMS = $true
    $SqlCollation = "Latin1_General_CI_AS"
    $InstancePath = "E:\Data\MSSQL"
    $DataPath = "F:\Data"
    $LogPath = "L:\Log"
    $TempPath = "T:\TempDB"
    $BackupPath = "G:\Backup"
    #$EngineCredential = Get-Credential -Message "Enter Engine Credential Local Admin User"
    #$SaCredential = Get-Credential -Message "Enter SA Credential"
    $EngineCredential = New-Object System.Management.Automation.PSCredential ("domain\serviceaccount", (ConvertTo-SecureString 'password' -AsPlainText -Force))
    $SaCredential = New-Object System.Management.Automation.PSCredential ("sa", (ConvertTo-SecureString 'password' -AsPlainText -Force))
    $AdminAccount = "$($env:userdomain)\$($env:USERNAME)"
    $Restart = $true
    $VerboseCommand = $true
    $EnableException = $true

    $ErrorActionPreference = 'Stop'

    # Path existence validation
    $Paths = @($DataPath, $LogPath, $TempPath, $BackupPath, $ProgData)
    foreach ($Path in $Paths) {
        if (-Not (Test-Path -Path $Path)) {
            Write-Host "ERROR: The path '$Path' does not exist. The script will not proceed." -ForegroundColor Red
            return
        }
    }

	$IsoFileNamee = Get-ChildItem -Path "$SetupFilesPath\$Version" -Filter "*$Version*.ISO" | Sort-Object @{Expression = {$_.VersionInfo.ProductBuildPart}; Descending = $true} | Select-Object -First 1 -ExpandProperty FullName
	$CuFilePathh = Get-ChildItem -Path "$SetupFilesPath\$Version\CU" -Filter "*SQLServer$Version*.exe" | Sort-Object @{Expression = {$_.VersionInfo.ProductBuildPart}; Descending = $true} | Select-Object -First 1 -ExpandProperty FullName
	$SSMSFilePathh = Get-ChildItem -Path "$SetupFilesPath\$Version\Tools" -Filter "*SSMS*.exe" | Sort-Object @{Expression = {$_.VersionInfo.ProductBuildPart}; Descending = $true} | Select-Object -First 1 -ExpandProperty FullName
	
	# Path existence validation
	$Pathss = @($IsoFileNamee, $CuFilePathh, $SSMSFilePathh)
	
	foreach ($Pathh in $Pathss) {
		if ([string]::IsNullOrEmpty($Pathh)) {
			Write-Host "ERROR: The path '$Pathh' variable is null or empty. The script will not proceed." -ForegroundColor Red
			return
		}
	
		if (-Not (Test-Path -Path $Pathh)) {
			Write-Host "ERROR: The path '$Pathh' does not exist. The script will not proceed." -ForegroundColor Red
			return
		}
	}
	
	Write-Host "All paths are valid. Proceeding with the script..." -ForegroundColor Green

    Write-Host "### SQL Server Unattended Installation for Local Machine ###" -ForegroundColor Yellow

    if(!$InstallEngine -and !$InstallCU -and !$InstallSSMS) {
        Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'No action.'") -ForegroundColor Gray
    }
    else {
        #region dbatools
        try {
            if (Get-Module -ListAvailable -Name dbatools) {
                Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'dbatools module exists. Skipping this command.'") -ForegroundColor Gray
                Import-Module dbatools
            }
            else {
                Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'dbatools module does not exist. Downloading... '") -NoNewline
                Install-PackageProvider -Name NuGet -Force -Confirm:$false > $null 
                Install-module dbatools -Force -Confirm:$false
                Import-Module dbatools
                Write-Host "OK" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "ERROR: Failed to import the dbatools module. The script will not proceed." -ForegroundColor Red
            return
        }
        #endregion dbatools

        #region InstallEngine
        if ($InstallEngine) {
            $IsoFileName = Get-ChildItem -Path "$SetupFilesPath\$Version" -Filter "*$Version*.ISO" | 
                Sort-Object @{Expression = {$_.VersionInfo.ProductBuildPart}; Descending = $true} | Select-Object -First 1 -ExpandProperty Name
    
            Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'Mounting ISO file... '") -NoNewline
            $mountResult = Mount-DiskImage -ImagePath "$SetupFilesPath\$Version\$IsoFileName" -PassThru 
            $volumeInfo = $mountResult | Get-Volume
            $driveInfo = Get-PSDrive -Name $volumeInfo.DriveLetter
            Write-Host "OK" -ForegroundColor Green
            
            Start-Sleep -Seconds 1
    
            Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'Extracting ISO files to local folder... '") -NoNewline
            Remove-Item -Path ("$InstancePath\SqlServerSetup\$IsoFileName").Replace(".ISO", "\") -Force -ErrorAction SilentlyContinue -Recurse -Confirm:$false 
            Copy-Item -Path $driveInfo.Root -Destination ("$InstancePath\SqlServerSetup\$IsoFileName").Replace(".ISO", "\") -Recurse
            Dismount-DiskImage -ImagePath "$SetupFilesPath\$Version\$IsoFileName"
            Write-Host "OK" -ForegroundColor Green
    
            # Custom Config
            $configParams = @{
                AGTSVCSTARTUPTYPE = "Automatic"
                SQLCOLLATION = $SqlCollation
                SQLTEMPDBFILESIZE = 1024
                SQLTEMPDBFILEGROWTH = 512
                SQLTEMPDBLOGFILESIZE = 1024
                SQLTEMPDBLOGFILEGROWTH = 256
            }
    
            $InstallParams = @{
                SqlInstance = $env:COMPUTERNAME
                Version = $Version
                Feature = "Engine"
                SaCredential = $SaCredential
                Path = ("$InstancePath\SqlServerSetup\$IsoFileName").Replace(".ISO", "\") 
                DataPath = $DataPath 
                LogPath = $LogPath 
                TempPath = $TempPath 
                BackupPath = $BackupPath
                AdminAccount = $AdminAccount 
                AuthenticationMode = "Mixed" 
                EngineCredential = $EngineCredential 
                PerformVolumeMaintenanceTasks = $true
                Restart = $Restart 
                Verbose = $VerboseCommand 
                EnableException = $EnableException
                InstancePath = $InstancePath 
                Configuration = $configParams
                Confirm = $false
            }
    
            Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'Installing engine... '")
            Install-DbaInstance @InstallParams
    
        }
        #endregion InstallEngine
    
        #region InstallCU
        if ($InstallCU) {
            
            $CuFilePath = Get-ChildItem -Path "$SetupFilesPath\$Version\CU" -Filter "SQLServer$Version*.exe" | 
                    Sort-Object @{Expression = {$_.VersionInfo.ProductBuildPart}; Descending = $true} | Select-Object -First 1 -ExpandProperty FullName
    
            $UpdateParams = @{
                ComputerName = $env:COMPUTERNAME
                Path = $CuFilePath
                Credential = $EngineCredential
                Restart = $Restart 
                Verbose = $VerboseCommand 
                Confirm = $false 
                EnableException = $EnableException
            }
            
            Get-DbaBuildReference -Update -EnableException
            Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'Installing CU... '")
            Update-DbaInstance @UpdateParams
        }
        #endregion InstallCU
    
        #region InstallSSMS
        if ($InstallSSMS) {
            # Copy SSMS exe locally
            $SSMSPath = "$SetupFilesPath\$Version\Tools\SSMS-Setup-ENU-19.3.exe"
    
            Write-Host (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff 'Installing SSMS... '") -NoNewline
            $ArgList = "/install /quiet /norestart /log $InstancePath\Log\ssms.log"
    
            if(!(Test-Path -Path "$InstancePath\Log\" )) { New-Item -ItemType Directory -Path "$InstancePath\Log" -ErrorAction SilentlyContinue > $null }
            Start-Process $SSMSPath $ArgList -Wait
            
            if (Get-Content -Path "$InstancePath\Log\ssms.log" -Tail 1 | Select-String "Exit code: 0x0, restarting" -Quiet) {
                Write-Host "OK" -ForegroundColor Green
            }
            else {
                Write-Host "Failed" -ForegroundColor Red
            }
        }
        #endregion InstallSSMS
    
        Write-Host "### SQL Server Unattended Installation Completed ###" -ForegroundColor Green
    }
}

# Execute the function
Install-SqlServer
