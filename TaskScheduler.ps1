# Create a Task schedule using powershell
$taskAction = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-File C:\Scripts\FirstRun.ps1"
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -Action $taskAction -Trigger $taskTrigger -TaskName "FirstRunTask" -Description "Run task on first boot" -User “NT AUTHORITY\SYSTEM” -RunLevel Highest -Force


### Script C:\Scripts\FirstRun.ps1 ###
New-Item -Path C:\Scripts -ItemType Directory

$markerFile = "C:\Scripts\FirstRunMarker.txt"


if (-Not (Test-Path $markerFile)) {
    
    Write-Host "Running the one-time initialization task..."

    New-Item -Path "C:\Scripts\InitializationTask.log" -ItemType File -Force
    Add-Content -Path "C:\Scripts\InitializationTask.log" -Value "Task completed at $(Get-Date)"
    
    New-Item -Path $markerFile -ItemType File -Force

    Write-Host "Task completed. Marker file created to prevent re-execution."
} else {
    Write-Host "Initialization task has already been run. Skipping execution."
}


### Delete the Task schedule ###
Unregister-ScheduledTask -TaskName "FirstRunTask" -Confirm:$false


### Create a Task Schedule ###
$action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-File C:\Scripts\FirstRun.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId “NT AUTHORITY\SYSTEM” -LogonType Password -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName “Installation of Software" -Action $action -Trigger $trigger -Principal $principal -Settings $settings 


Start-vm -VM <Name> -runAsync
$vm = get-vm <name>
Start-Sleep -Seconds 20;
$vm  | Get-VMQuestion | Set-VMQuestion -DefaultOption -confirm:$false;
do
{
  Start-Sleep -Seconds 5;
  $toolsStatus = $vm.extensionData.Guest.ToolsStatus;
}while($toolsStatus -ne "toolsOK");
