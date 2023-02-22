# PSADT.WIMFile
Extension for PowerShell App Deployment Toolkit to create and handle .WIM files.

## Features
- Creates WIM files from your **Files** directory by default.
- Maximum compression by default.
- Does not requires administrative rights to mount (extracts if can't mount).
- Does not requires administrative rights to create (requires [wimlib](https://github.com/LFM8787/PSADT.WIMFile/blob/master/README.md#external-links)).
- Can extract to UNC Path.
- Creates remediation scheduled tasks if mount/dismount fails
- Multilanguage support.
- *ContinueOnError* and *ExitScriptOnError* support.

## Disclaimer
```diff
- Test the functions before production.
- Make a backup before applying.
- Check the config file options description.
- Run AppDeployToolkitHelp.ps1 for more help and parameter descriptions.
```

## Functions
* **New-WIMFile** - Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).
* **Mount-WIMFile** - Mounts a WIM file in the MountDir folder (Files directory by default).
* **Dismount-WIMFile** - Dismounts a WIM file and deletes the path.

## Usage
```PowerShell
# Creates a new WIM File based on the content of the Files directory
New-WIMFile
```

```PowerShell
# Comments or removes the function once it's been used
# New-WIMFile

# Mount any WIM file found in script directory (last modified one if multiple)
$MountedObject = Mount-WIMFile

# <Normal script commands go here>

# Dismount the previously mounted/extracted WIM file
$MountedObject | Dismount-WIMFile
```

## Internal functions
`This set of functions are internals and are not designed to be called directly`
* **Expand-WIMFile** - Expand a WIM file using native method or wimlib executable if exists.
* **New-RemediationDismountTask** - Creates an scheduled task with remediation commands.
* **Remove-RemediationDismountTask** - Removes a previously created remediation scheduled task.

## Extension Exit Codes
|Exit Code|Function|Exit Code Detail|
|:----------:|:--------------------|:-|
|70101|Mount-WIMFile|Unable to get full path from mount path.|
|70102|Mount-WIMFile|The WIM file could not be found.|
|70103|Mount-WIMFile|The WIM file contains an invalid path or file name.|
|70104|Mount-WIMFile|No WIM file found in script directory.|
|70111|Mount-WIMFile|Failed to mount or extract WIM file in path.|
|70105|Expand-WIMFile|Failed to delete SymbolicLink extraction path.|
|70107|Expand-WIMFile|Failed to extract WIM file in path.|
|70108|Expand-WIMFile|Failed to extract WIM file in path using wimlib.exe.|
|70109|Expand-WIMFile|This script support wimlib as alternative method to expand WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).|
|70112|Dismount-WIMFile|Input object contains a null or empty path attribute.|
|70113|Dismount-WIMFile|Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter.|
|70114|New-WIMFile|Failed to create WIM file using wimlib.exe.|
|70115|New-WIMFile|Unable to find wimlib executable and libraries inside SupportFiles folder, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).|
|70116|New-WIMFile|This script support wimlib as alternative method to create WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).|
|70117|New-WIMFile|The capture path does not exist.|
|70118|New-WIMFile|The capture path is empty, must contains at least one element.|
|70119|New-WIMFile|Unable to get full path from capture path.|
|70120|New-WIMFile|Unable to get full path from save to path.|
|70121|New-WIMFile|Unable to delete existing file.|
|70122|New-WIMFile|The file already exists, use -ReplaceExisting switch to overwrite it.|
|70123|New-WIMFile|Failed to create WIM file. Exception ErrorCode...|
|70125|New-WIMFile|The save to path does not exist.|
|70127|New-WIMFile|Remove the 'New-WIMFile' function from the script to continue.|
|70128|New-WIMFile|Provide an existing directory path for the -CapturePath parameter.|
|70129|New-WIMFile|Provide an existing directory path for the -SavetoPath parameter.|
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
			Write-Log -Message "An error occurred while trying to load the extension file [$($ExtensionPath)].`r`n$(Resolve-Error)" -Severity 3 -Source $appDeployToolkitExtName
		}
	}
	else {
		Write-Log -Message "Unable to locate the extension file [$($ExtensionPath)]." -Severity 2 -Source $appDeployToolkitExtName
	}
}
```

## Requirements
* Powershell 5.1+
* PSAppDeployToolkit 3.8.4+

## Multilanguage support progress (feel free to upload translated strings):
* 🇺🇸 100%
* 🇩🇰 0%
* 🇫🇷 0%
* 🇩🇪 0%
* 🇮🇹 0%
* 🇯🇵 0%
* 🇳🇴 0%
* 🇳🇱 0%
* 🇵🇱 0%
* 🇵🇹 0%
* 🇧🇷 0%
* 🇪🇸 100%
* 🇸🇪 0%
* 🇸🇦 0%
* 🇮🇱 0%
* 🇰🇷 0%
* 🇷🇺 0%
* 🇨🇳 (Simplified) 0%
* 🇨🇳 (Traditional) 0%
* 🇸🇰 0%
* 🇨🇿 0%
* 🇭🇺 0%

## External Links
* [PowerShell App Deployment Toolkit](https://psappdeploytoolkit.com/)
* [wimlib: the open source Windows Imaging (WIM) library](https://wimlib.net/)