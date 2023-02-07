# PSADT.WIMFile 1.0
Extension for PowerShell App Deployment Toolkit to create and handle .WIM files.

## Features
- Creates WIM files from your **Files** directory by default.
- Maximum compression by default.
- Does not requires administrative rights to mount (extracts if can't mount).
- Does not requires administrative rights to create (requires [wimlib](https://github.com/LFM8787/PSADT.WIMFile/README.md#external-links)).
- Can extract to UNC Path.
- Creates remediation scheduled tasks if mount/dismount fails
- Multilanguage support.
- *ContinueOnError* and *ExitScriptOnError* support.

## Functions
* **Mount-WIMFile** - Mounts a WIM file in the MountDir folder (Files directory by default).
* **Dismount-WIMFile** - Dismounts a WIM file and deletes the path.
* **New-WIMFile** - Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).

## Internal functions
`This set of functions are internals and are not designed to be called directly`
* **New-RemediationDismountTask** - Creates an scheduled task with remediation commands.
* **Remove-RemediationDismountTask** - Removes a previously created remediation scheduled task.

## Extension Exit Codes
|Exit Code|Function|Exit Code Detail|
|:----------:|:--------------------|:-|
|<sub><sup>70101</sup></sub>|Mount-WIMFile|Unable to get full path from mount path.|
|70102|Mount-WIMFile|File not found.|
|70103|Mount-WIMFile|Invalid path or file name.|
|70104|Mount-WIMFile|No WIM file found in script directory .|
|70105|Mount-WIMFile|Failed to delete SymbolicLink extract folder.|
|70106|Mount-WIMFile|Failed to delete SymbolicLink extract folder.|
|70107|Mount-WIMFile|Failed to extract WIM file in folder.|
|70108|Mount-WIMFile|Failed to extract WIM file in folder using wimlib.exe.|
|70109|Mount-WIMFile|Extracting WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).|
|70110|Mount-WIMFile|Unexpected COMException when trying to mount WIM file in folder.|
|70111|Mount-WIMFile|Failed to mount WIM file in folder.|
|70112|Mount-WIMFile|Input object contains a null or empty path attribute.|
|70113|Dismount-WIMFile|Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter.|
|70114|New-WIMFile|Failed to create WIM file in folder using wimlib.exe.|
|70115|New-WIMFile|Unable to find wimlib executable and libraries inside SupportFiles folder.|
|70116|New-WIMFile|Creating WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).|
|70117|New-WIMFile|The capture path does not exist.|
|70118|New-WIMFile|The capture path must contains at least one file or folder.|
|70119|New-WIMFile|Unable to get full path from capture path.|
|70120|New-WIMFile|Unable to get full path from save to path.|
|70121|New-WIMFile|Unable to delete existing file.|
|70122|New-WIMFile|The file already exists, use -ReplaceExisting switch to overwrite it.|
|70123|New-WIMFile|Unexpected Exception when trying to create WIM file in folder.|
|70124|New-WIMFile|Failed to create WIM file in folder.|
|70125|New-WIMFile|The save to path does not exist.|
|70126|New-RemediationDismountTask|Failed to register remediation scheduled task.|
## How to Install
#### 1. Download and copy into Toolkit folder.
#### 2. Edit *AppDeployToolkitExtensions.ps1* file and add the following lines.
#### 3. Create an empty array (only once if multiple extensions):
```PowerShell
## Variables: Extensions to load
$ExtensionToLoad = @()
```
#### 4. Add Extension Path and Script filename (repeat for multiple extensions):
```PowerShell
$ExtensionToLoad += [PSCustomObject]@{
	Path   = "PSADT.WIMFile"
	Script = "WIMFileExtension.ps1"
}
```
#### 5. Complete with the remaining code to load the extension (only once if multiple extensions):
```PowerShell
## Loading extensions
foreach ($Extension in $ExtensionToLoad) {
	$ExtensionPath = $null
	if ($Extension.Path) {
		[IO.FileInfo]$ExtensionPath = Join-Path -Path $scriptRoot -ChildPath $Extension.Path | Join-Path -ChildPath $Extension.Script
	}
	else {
		[IO.FileInfo]$ExtensionPath = Join-Path -Path $scriptRoot -ChildPath $Extension.Script
	}
	if ($ExtensionPath.Exists) {
		try {
			. $ExtensionPath
		}
		catch {
			Write-Log -Message "An error occurred while trying to load the extension file [$($ExtensionPath)].`r`n$(Resolve-Error)" -Severity 3 -Source $ToastNotificationExtName
		}
	}
	else {
		Write-Log -Message "Unable to locate the extension file [$($ExtensionPath)]." -Severity 2 -Source $ToastNotificationExtName
	}
}
```

## Requirements
* Powershell 5.1+
* PSAppDeployToolkit 3.8.4+

## External Links
[wimlib: the open source Windows Imaging (WIM) library](https://wimlib.net/)
