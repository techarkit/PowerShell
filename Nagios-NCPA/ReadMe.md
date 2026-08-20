# Examples
./Fetch-DriveLetters_NCPA.ps1 -ServerListPath C:\Scripts\Servers.txt -Token mytoken -SkipCertificateCheck

| Parameter               |      Required | Default               | Description                                          |
| ----------------------- | ------------: | --------------------- | ---------------------------------------------------- |
| `-ServerListPath`       |           Yes | None                  | TXT or CSV file containing server names/IP addresses |
| `-Token`                |           No* | `$env:NCPA_API_TOKEN` | NCPA API/community token                             |
| `-Port`                 |            No | `5693`                | NCPA listener port                                   |
| `-TimeoutSeconds`       |            No | `30`                  | Maximum API request time per server                  |
| `-OutputFolder`         |            No | `NCPA-Disk-Reports`   | CSV and log destination                              |
| `-SkipCertificateCheck` |            No | Disabled              | Allows self-signed/untrusted NCPA certificates       |
| `-Verbose`              |            No | Disabled              | Displays additional diagnostic information           |
| `-ErrorAction`          |            No | PowerShell default    | Controls terminating-error behavior                  |
| `-WhatIf`               | Not supported | —                     | The script does not make remote changes              |
| `-Confirm`              | Not supported | —                     | The script performs read-only API operations         |
