$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | Out-Null
$ErrorActionPreference = "Continue"
Start-Transcript -Path C:\IT\Qualys-Agent.log -Append

function SetQualysRegKeys {
    New-Item -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand" -Name "Inventory"
    New-ItemProperty -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Inventory" -Name "ScanOnDemand" -Value "1"  -PropertyType DWord
    New-Item -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand" -Name Vulnerability
    New-ItemProperty -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability" -Name "ScanOnDemand" -Value "1"  -PropertyType DWord
    New-Item -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand" -Name PolicyCompliance
    New-ItemProperty -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\PolicyCompliance" -Name "ScanOnDemand" -Value "1"  -PropertyType DWord
}

$QualysRegKey = $false

Write-Host [=]
Write-Host [=]
Write-Host [+] Checking Qualys Registry Key Exists

$QualysRegKey = Test-Path -Path "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand" -ErrorAction SilentlyContinue

if($QualysRegKey -eq $false)
{
  Write-Host [=]
  Write-Host [=]
  Write-Host [x] The registry keys are missing, unable to set them. -ForegroundColor Red
  Write-Host [=]
  Write-Host [=]
  return 
}
else
{
 $QualysRegKey = $true
 Write-Host [=] Setting the On Demand Scan registry keys! -ForegroundColor Green
 SetQualysRegKeys
}

Write-Host [=]
Write-Host [=]
Write-Host [+] Qualys Scan On Demand reg keys have been set! -ForegroundColor Green
Write-Host [+] The Qualys agent will check the registry in ~3 minutes and perform an, On Demand Scan. -ForegroundColor Green
Write-Host [=]
Write-Host [=]
Write-Host [=]
Stop-Transcript
