$Date = Get-Date -Format MMddyyyyhhss
$NoPing = "C:\SQLReports\NoPing-$Date.txt"
$SQLReport = "C:\SQLReports\SQLReport-$Date.csv"

Function Get-SQLSvrVer {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.String] $ComputerName
    )

    try {
        if (Test-Connection @Splat -Count 1 -Quiet) {
            $SqlVer = New-Object PSObject
            $SqlVer | Add-Member -MemberType NoteProperty -Name ServerName -Value $ComputerName

            $key = "SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
            $type = [Microsoft.Win32.RegistryHive]::LocalMachine
            $regKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($type, $ComputerName)
            $SqlKey = $regKey.OpenSubKey($key)
            
            foreach ($instance in $SqlKey.GetValueNames()) {
                $instName = $SqlKey.GetValue("$instance")
                $instKey = $regKey.OpenSubkey("SOFTWARE\Microsoft\Microsoft SQL Server\$instName\Setup")
                $SqlVer | Add-Member -MemberType NoteProperty -Name Edition -Value $instKey.GetValue("Edition") -Force
                $SqlVer | Add-Member -MemberType NoteProperty -Name Version -Value $instKey.GetValue("Version") -Force
                $SqlVer | Add-Member -MemberType NoteProperty -Name Name -Value $instName -Force
            }

            $SqlVer
        } else {
            Write-Host "Server $ComputerName unavailable..." -ForegroundColor red
            Write-Output "$ComputerName" >> $NoPing
        }
    } catch {
        Write-Host "Error accessing registry on $ComputerName: $_" -ForegroundColor red
    }
}

$AllServers = Get-ADComputer -Filter {Enabled -eq $True} -Properties OperatingSystem | 
    Where-Object {($_.OperatingSystem -match "Windows Server") -and ($_.DistinguishedName -notmatch "OU=Domain Controllers") -and ($_.Name -notmatch "SQL2019CLUSTER")} | 
    Select-Object Name, OperatingSystem

$c1 = 0
$Total = $AllServers.Count
$Report = @()

foreach ($Server in $AllServers) {
    $ServerName = $Server.Name
    $ServerOS = $Server.OperatingSystem
    $SQLVersion = @()
    $CPUInfo = @()

    $c1++
    Write-Progress -Id 0 -Activity 'Checking Servers for SQL Version' -Status "Processing $($c1) of $Total" -CurrentOperation $ServerName -PercentComplete (($c1/$Total) * 100)

    try {
        $SQLVersion = Get-SQLSvrVer -ComputerName $ServerName | Select-Object Name, Edition, Version
    } catch {
        Write-Host "$ServerName does not have MS SQL installed" -ForegroundColor Yellow
    }

    if ($SQLVersion) {
        $CPUInfo = (Get-CimInstance -Class Win32_ComputerSystem -ComputerName $ServerName).NumberOfLogicalProcessors
        foreach ($SQLLine in $SQLVersion) {
            $Report += [pscustomobject][ordered] @{
                "Server" = $ServerName
                "ServerOS" = $ServerOS
                "SQLinstance" = $SQLLine.Name
                "SQLedition" = $SQLLine.Edition
                "SQLversion" = $SQLLine.Version
                "CPUcores" = $CPUInfo
            }
        }
    }
}

$Report | Export-Csv -NoTypeInformation $SQLReport
