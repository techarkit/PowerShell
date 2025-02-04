# Load Posh-SSH Module
Import-Module Posh-SSH

# Credentials Setup
$ComputerName = "test-host"
$username = "root"
$password = ConvertTo-SecureString -String "Password" -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $password
$Command = "hostname"    

$session = New-SSHSession -ComputerName $ComputerName -Credential $creds -AcceptKey -ErrorAction Stop
    if ($session.Connected) {
        Write-Host "Connected to $ComputerName successfully via SSH." -ForegroundColor Green
        Write-Host "Executing the command on the remote server..."
        $output = Invoke-SSHCommand -Command $Command -SessionId $session.SessionId -TimeOut 300 -ErrorAction Stop

        # Display the Output
        Write-Host "Command Output:" $output.Output -ForegroundColor Yellow
    }
