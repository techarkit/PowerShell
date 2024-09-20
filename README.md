# PowerShell
PowerShell Scripts


`SQLInstall/SQLInstallation.ps1`

This PowerShell script is designed to check for required drive letters on a system, create specific folders if they don't exist, and then proceed with an unattended SQL Server installation. Here's a breakdown of how the script works:

## 1. Defining Required Drive Letters
- The script begins by defining a list of required drive letters: E, F, G, T, and L.
- It then checks if these drive letters are present on the system using Get-PSDrive. If any are missing, the script outputs a message and exits.
## 2. Creating Folders if Missing
- Several paths are defined for SQL Server data, logs, backups, and temporary files, all mapped to specific drives.
- A function Create-FolderIfMissing is defined to check whether each folder path exists. If a folder does not exist, it is created. If the creation fails, the script exits with an error.
## 3. SQL Server Installation Preparation
- The Install-SqlServer function handles the unattended installation of SQL Server.
- Parameters like the setup files path, SQL Server version, collation, and installation paths are defined. Also, credentials for the SQL Server instance (EngineCredential and SaCredential) and the admin account are set.
## 4. Path Validation
- Before proceeding with the installation, the script checks if all required paths for SQL Server installation are valid and exist. If any path is invalid, the script outputs an error message and exits.
## 5. Module Handling
- The script checks if the dbatools PowerShell module is available. If not, it installs the module, as it's used for automating SQL Server tasks.
## 6. SQL Server Engine Installation
- If the InstallEngine flag is set to true, the script mounts the SQL Server installation ISO file, copies its contents to a local directory, and uses the Install-DbaInstance function from dbatools to perform an unattended installation with specified configuration parameters.
- The script also handles dismounting the ISO after copying the necessary files.
## 7. Installing Cumulative Updates (CU)
- If the InstallCU flag is true, the script installs the latest SQL Server cumulative update by locating the appropriate .exe file and running it with the necessary parameters.
## 8. Installing SQL Server Management Studio (SSMS)
- If InstallSSMS is set to true, the script installs SQL Server Management Studio by executing the SSMS installer with silent installation parameters.
## 9. Execution
- The script concludes by executing the Install-SqlServer function, which checks all preconditions and then performs the SQL Server installation.
### Key Points:
- The script ensures that all required drive letters are available and that the necessary folders exist before proceeding.
- It uses the dbatools module to automate SQL Server installation and related tasks.
- The script is designed to be robust, with multiple checks to ensure that all necessary conditions are met before proceeding with the installation.
-  The use of Try-Catch blocks and error handling ensures that if something goes wrong (like a missing path or failed module import), the script exits gracefully with informative error messages.
