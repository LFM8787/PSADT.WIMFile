<#
.SYNOPSIS
	WIM File Extension script file, must be dot-sourced by the AppDeployToolkitExtension.ps1 script.
.DESCRIPTION
	Contains various functions used for creating and mounting WIM files.
	If a failure occurs at any point in the process, scheduled cleanup tasks are created.
.NOTES
	Extension Exit Codes:
	70101: Mount-WIMFile - Unable to get full path from mount path.
	70102: Mount-WIMFile - File not found.
	70103: Mount-WIMFile - Invalid path or file name.
	70104: Mount-WIMFile - No WIM file found in script directory .
	70105: Mount-WIMFile - Failed to delete SymbolicLink extract folder.
	70106: Mount-WIMFile - Failed to delete SymbolicLink extract folder.
	70107: Mount-WIMFile - Failed to extract WIM file in folder.
	70108: Mount-WIMFile - Failed to extract WIM file in folder using wimlib.exe.
	70109: Mount-WIMFile - Extracting WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).
	70110: Mount-WIMFile - Unexpected COMException when trying to mount WIM file in folder.
	70111: Mount-WIMFile - Failed to mount WIM file in folder.
	70112: Mount-WIMFile - Input object contains a null or empty path attribute.
	70113: Dismount-WIMFile - Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter.
	70114: New-WIMFile - Failed to create WIM file in folder using wimlib.exe.
	70115: New-WIMFile - Unable to find wimlib executable and libraries inside SupportFiles folder.
	70116: New-WIMFile - Creating WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).
	70117: New-WIMFile - The capture path does not exist.
	70118: New-WIMFile - The capture path must contains at least one file or folder.
	70119: New-WIMFile - Unable to get full path from capture path.
	70120: New-WIMFile - Unable to get full path from save to path.
	70121: New-WIMFile - Unable to delete existing file.
	70122: New-WIMFile - The file already exists, use -ReplaceExisting switch to overwrite it.
	70123: New-WIMFile - Unexpected Exception when trying to create WIM file in folder.
	70124: New-WIMFile - Failed to create WIM file in folder.
	70125: New-WIMFile - The save to path does not exist.
	70126: New-RemediationDismountTask - Failed to register remediation scheduled task.

	Author:  Leonardo Franco Maragna
	Version: 1.0
	Date:    2023/02/07
#>
[CmdletBinding()]
Param (
)

##*===============================================
##* VARIABLE DECLARATION
##*===============================================
#region VariableDeclaration

## Variables: Extension Info
$WIMFileExtName = "WIMFileExtension"
$WIMFileExtScriptFriendlyName = "WIM File Extension"
$WIMFileExtScriptVersion = "1.0"
$WIMFileExtScriptDate = "2023/02/07"
$WIMFileExtSubfolder = "PSADT.WIMFile"
$WIMFileExtConfigFileName = "WIMFileConfig.xml"

## Variables: WIM File Script Dependency Files
[IO.FileInfo]$dirWIMFileExtFiles = Join-Path -Path $scriptRoot -ChildPath $WIMFileExtSubfolder
[IO.FileInfo]$dirWIMFileExtSupportFiles = Join-Path -Path $dirSupportFiles -ChildPath $WIMFileExtSubfolder
[IO.FileInfo]$WIMFileConfigFile = Join-Path -Path $dirWIMFileExtFiles -ChildPath $WIMFileExtConfigFileName
if (-not $WIMFileConfigFile.Exists) { throw "$($WIMFileExtScriptFriendlyName) XML configuration file [$WIMFileConfigFile] not found." }

## Variables: Required Support Files
[IO.FileInfo]$wimlibApplicationPath = (Get-ChildItem -Path $dirWIMFileExtSupportFiles -Recurse -Filter "*wimlib*.exe").FullName | Select-Object -First 1
if ($wimlibApplicationPath) { [IO.FileInfo]$wimlibLibraryPath = Get-ChildItem -Path $wimlibApplicationPath.Directory -Filter "*libwim*.dll" }

## Import variables from XML configuration file
[Xml.XmlDocument]$xmlWIMFileConfigFile = Get-Content -LiteralPath $WIMFileConfigFile -Encoding UTF8
[Xml.XmlElement]$xmlWIMFileConfig = $xmlWIMFileConfigFile.WIMFile_Config

#  Get Config File Details
[Xml.XmlElement]$configWIMFileConfigDetails = $xmlWIMFileConfig.Config_File

#  Check compatibility version
$configWIMFileConfigVersion = [string]$configWIMFileConfigDetails.Config_Version
#$configWIMFileConfigDate = [string]$configWIMFileConfigDetails.Config_Date

try {
	if ([version]$WIMFileExtScriptVersion -ne [version]$configWIMFileConfigVersion) {
		Write-Log -Message "The $($WIMFileExtScriptFriendlyName) version [$([version]$WIMFileExtScriptVersion)] is not the same as the $($WIMFileExtConfigFileName) version [$([version]$configWIMFileConfigVersion)]. Problems may occurs." -Severity 2 -Source ${CmdletName}
	}
}
catch {}

#  Get WIM File General Options
[Xml.XmlElement]$xmlWIMFileOptions = $xmlWIMFileConfig.WIMFile_Options
$configWIMFileGeneralOptions = [PSCustomObject]@{
	ExitScriptOnError                     = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.ExitScriptOnError)) } catch { $true }'
	ShowNewWIMFileWarningMessage          = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.ShowNewWIMFileWarningMessage)) } catch { $true }'
	NewWIMFileWarningMessageTimeout       = Invoke-Expression -Command 'try { [int32]::Parse([string]($xmlWIMFileOptions.NewWIMFileWarningMessageTimeout)) } catch { 120 }'
	DeleteAlternativeMountDirWhenDismount = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.DeleteAlternativeMountDirWhenDismount)) } catch { $true }'
}

#  Define ScriptBlock for Loading Message UI Language Options (default for English if no localization found)
[scriptblock]$xmlLoadLocalizedUIWIMFileMessages = {
	[Xml.XmlElement]$xmlUIWIMFileMessages = $xmlWIMFileConfig.$xmlUIMessageLanguage
	$configUIWIMFileMessages = [PSCustomObject]@{
		NewWIMFile_WarningMessage = [string]$xmlUIWIMFileMessages.NewWIMFile_WarningMessage
	}
}

#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

#region Function Mount-WIMFile
Function Mount-WIMFile {
	<#
	.SYNOPSIS
		Mounts a WIM file in the MountDir folder (Files directory by default).
	.DESCRIPTION
		Mounts a WIM file in the MountDir folder (Files directory by default) so the rest of the script can use the content.
	.PARAMETER FilePath
		Path to the file to be mounted. If no value is supplied, the script directory is scanned searching for WIM files.
	.PARAMETER Name
		Specifies the name of an image in the WIM file.
	.PARAMETER Index
		Specifies the index number of a Windows image in the WIM file, by default 1.
	.PARAMETER MountDir
		Specifies the folder where the WIM file will be mounted, by default Files folder.
	.PARAMETER PassThru
		By default returns and object including the path where the wim file was mounted or extracted.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.EXAMPLE
		Mount-WIMFile
		If the file is in the script directory of the App Deploy Toolkit, it will be mounted in Files folder.
	.EXAMPLE
		Mount-WIMFile -Name 'adobe_es'
		Mount the image corresponding to the Name parameter.
	.EXAMPLE
		Mount-WIMFile -Index 2
		Mount the image corresponding to the Index parameter.
	.NOTES
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$FilePath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Name,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int]$Index = 1,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$MountDir = $dirFiles,
		[Parameter(Mandatory = $false)]
		[boolean]$PassThru = $true,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false,
		[switch]$DisableFunctionLogging
	)
	
	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		## Get full path of MuntDir parameter
		try {
			$MountDir = [IO.Path]::GetFullPath($MountDir)
		}
		catch {
			Write-Log -Message "Unable to get full path from mount path [$MountDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70101 }
				throw "Unable to get full path from mount path [$MountDir]: $($_.Exception.Message)"
			}
			return
		}

		if ($FilePath) {
			## Validate and find the fully qualified path for the $FilePath variable.
			if (([IO.Path]::IsPathRooted($FilePath)) -and ([IO.Path]::HasExtension($FilePath))) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "[$FilePath] is a valid fully qualified path, continue." -Source ${CmdletName} }
				if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf -ErrorAction Stop)) {
					Write-Log -Message "File [$FilePath] not found." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70102 }
						throw "File [$FilePath] not found."
					}
					return
				}
			}
			else {
				#  The first directory to search will be the script directory
				[string]$PathFolders = $scriptParentPath
				#  Add the current location of the console (Windows always searches this location first)
				[string]$PathFolders = $PathFolders + ";" + (Get-Location -PSProvider "FileSystem").Path
				#  Add the new path locations to the PATH environment variable
				$env:PATH = $PathFolders + ";" + $env:PATH

				#  Get the fully qualified path for the file. Get-Command searches PATH environment variable to find this value.
				[string]$FullyQualifiedPath = Get-Command -Name $FilePath -CommandType "Application" -TotalCount 1 -Syntax -ErrorAction Stop

				#  Revert the PATH environment variable to it's original value
				$env:PATH = $env:PATH -replace [regex]::Escape($PathFolders + ";"), ""

				if ($FullyQualifiedPath) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "[$FilePath] successfully resolved to fully qualified path [$FullyQualifiedPath]." -Source ${CmdletName} }
					$FilePath = $FullyQualifiedPath
				}
				else {
					Write-Log -Message "[$FilePath] contains an invalid path or file name." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70103 }
						throw "[$FilePath] contains an invalid path or file name."
					}
					return
				}
			}
		}
		else {
			## If the WIM file is in the Script directory, set the full path to the WIM file
			[array]$wimFile = Get-ChildItem -Path $scriptParentPath -Filter "*.wim" -Depth 0 -Force -ErrorAction SilentlyContinue

			if ($wimFile.Count -gt 1) {
				Write-Log -Message "Multiple WIM files found [$($wimFile.Name -join ', ')]." -Severity 2 -Source ${CmdletName}
				$wimFile = $wimFile | Sort-Object -Property LastWriteTime, Length | Select-Object -Last 1
				Write-Log -Message "Using last modified WIM file [$($wimFile.Name)]." -Severity 2 -Source ${CmdletName}
				$FilePath = ($wimFile).FullName
			}
			elseif ($wimFile.Count -eq 1) {
				Write-Log -Message "Using WIM file found [$($wimFile.Name)]." -Severity 2 -Source ${CmdletName}
				$FilePath = ($wimFile).FullName
			}
			else {
				Write-Log -Message "No WIM file found in script directory [$scriptParentPath]." -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70104 }
					throw "No WIM file found in script directory [$scriptParentPath]."
				}
				return
			}
		}

		## File name with extension
		$FilePathName = [IO.Path]::GetFileName($FilePath)

		## Check if the mount folder already exists and if can be deleted
		if (Test-Path $MountDir -ErrorAction SilentlyContinue) {
			if ($IsAdmin) { $MountedImage = Get-WindowsImage -Mounted | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq $MountDir } }
			if ($MountedImage) {
				$wimFile = [IO.Path]::GetFileName($MountedImage.ImagePath)
				Write-Log -Message "The WIM file [$wimFile] is already mounted in mount path [$MountDir]. It will be dismounted." -Severity 2 -Source ${CmdletName}
				Dismount-WIMFile -ImageObject (New-Object -TypeName "PSObject" -Property @{ Path = $MountDir })
			}
			else {
				Write-Log -Message "The mount folder [$MountDir] already exists, all its content will be deleted." -Severity 2 -Source ${CmdletName}
				Remove-Folder -Path $MountDir -ContinueOnError $false
			}
		}

		## Create new mount folder
		New-Folder -Path $MountDir -ContinueOnError $false

		try {
			## Mount WIM file in Files directory
			if ($Name) {
				$ImageObject = Mount-WindowsImage -ImagePath $FilePath -Path $MountDir -Name $Name
			}
			else {
				$ImageObject = Mount-WindowsImage -ImagePath $FilePath -Path $MountDir -Index $Index
			}
			if ($?) {
				Write-Log -Message "Successfully mounted WIM file [$FilePathName] in folder [$MountDir]." -Source ${CmdletName}

				#  Create remediation dismount task to run when the system startup
				New-RemediationDismountTask -wimFile ([IO.Path]::GetFileName($FilePath)) -wimTargetPath $MountDir

				## If the passthru switch is specified, return the ImageObject
				if ($PassThru) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "PassThru parameter specified, returning ImageObject." -Source ${CmdletName} }
					return $ImageObject
				}
			}
		}
		catch [System.Runtime.InteropServices.COMException] {
			Write-Log -Message "Could not mount WIM file [$FilePathName] in folder [$MountDir].`r`n$(Resolve-Error)" -Severity 2 -Source ${CmdletName}
			#Write-Log -Message "[System.Runtime.InteropServices.COMException] ErrorCode: $('{0:x}' -f $_.Exception.ErrorCode)" -Severity 2 -Source ${CmdletName}

			if ($_.Exception.ErrorCode -eq 0xC1420134) {
				## The drive of the specified mount path is not supported. Please mount to a volume on a fixed drive.

				## Unable to mount to the specified mount folder, the WIM file will be extracted
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to extract WIM file [$FilePathName] in folder [$MountDir]." -Source ${CmdletName}}

				#  Trying to SymLink the Path
				$ExtractDir = Join-Path -Path $envTemp -ChildPath "Mount_$($appName.Replace(" ","_"))"
				if (Test-Path $ExtractDir -ErrorAction SilentlyContinue) {
					Write-Log -Message "The SymbolicLink extract folder already exists [$ExtractDir], probably a failed past attempt." -Severity 2 -Source ${CmdletName}
					try {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "The SymbolicLink extract folder will be deleted." -Source ${CmdletName} }
						[IO.Directory]::Delete($ExtractDir, $true)
						if ($?) {
							if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully deleted SymbolicLink extract folder [$ExtractDir]." -Source ${CmdletName} }
						}
					}
					catch {
						Write-Log -Message "Failed to delete SymbolicLink extract folder [$ExtractDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70105 }
							throw "Failed to delete SymbolicLink extract folder [$ExtractDir]: $($_.Exception.Message)"
						}                        
					}
				}
				
				try {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "Creating SymbolicLink folder [$ExtractDir] targetting [$MountDir]." -Source ${CmdletName} }

					$null = New-Item -Path $ExtractDir -ItemType SymbolicLink -Value $MountDir
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully linked path [$MountDir] to local folder [$ExtractDir]." -Source ${CmdletName} }
						if ($Name) {
							$null = Expand-WindowsImage -ImagePath $FilePath -ApplyPath $ExtractDir -Name $Name
						}
						else {
							$null = Expand-WindowsImage -ImagePath $FilePath -ApplyPath $ExtractDir -Index $Index
						}
						if ($?) {
							Write-Log -Message "Successfully extracted WIM file [$FilePathName] in folder [$MountDir]." -Source ${CmdletName}
							if (-not ($DisableFunctionLogging)) { Write-Log -Message "Removing the SymbolicLink extract folder [$ExtractDir], since it is no longer needed." -Source ${CmdletName} }
							try {
								[IO.Directory]::Delete($ExtractDir, $true)
								if ($?) {
									if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully deleted SymbolicLink extract folder [$ExtractDir]." -Source ${CmdletName} }
								}
							}
							catch {
								Write-Log -Message "Failed to delete SymbolicLink extract folder [$ExtractDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
								if (-not $ContinueOnError) {
									if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70106 }
									throw "Failed to delete SymbolicLink extract folder [$ExtractDir]: $($_.Exception.Message)"
								}
							}

							if ($PassThru) {
								if (-not ($DisableFunctionLogging)) { Write-Log -Message "PassThru parameter specified, returning extraction details object." -Source ${CmdletName} }
								[psobject]$ImageObject = New-Object -TypeName "PSObject" -Property @{ Path = $MountDir }
								return $ImageObject
							}
						}
					}
				}
				catch {
					Write-Log -Message "Failed to extract WIM file [$FilePathName] in folder [$MountDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70107 }
						throw "Failed to extract WIM file [$FilePathName] in folder [$MountDir]: $($_.Exception.Message)"
					}
				}
			}
			elseif ($_.Exception.ErrorCode -eq 0x800702E4) {
				## Trying to use wimlib to workaround elevation
				if ($wimlibApplicationPath -and $wimlibLibraryPath) {
					#  Unable to mount to the specified mount folder, the WIM file will be extracted using wimlib.exe
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to extract WIM file [$FilePathName] in folder [$MountDir] using wimlib.exe." -Source ${CmdletName} }
					try {
						$ExtractedResult = Execute-Process -Path $wimlibApplicationPath -Parameter @("apply", $FilePath, $MountDir) -WindowStyle Hidden -PassThru
						if ($? -and $ExtractedResult.ExitCode -eq 0) {
							if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully extracted WIM file [$FilePathName] in folder [$MountDir] using wimlib.exe." -Source ${CmdletName} }
							if ($PassThru) {
								if (-not ($DisableFunctionLogging)) { Write-Log -Message "PassThru parameter specified, returning extraction details object." -Source ${CmdletName} }
								[psobject]$ImageObject = New-Object -TypeName "PSObject" -Property @{ Path = $MountDir }
								return $ImageObject
							}
						}
					}
					catch {
						Write-Log -Message "Failed to extract WIM file [$FilePathName] in folder [$MountDir] using wimlib.exe.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70108 }
							throw "Failed to extract WIM file [$FilePathName] in folder [$MountDir] using wimlib.exe: $($_.Exception.Message)"
						}
					}
				}
				else {
					Write-Log -Message "Extracting WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70109 }
						throw "Extracting WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory): $($_.Exception.Message)"
					}
				}
			}
			else {
				Write-Log -Message "Unexpected COMException when trying to mount WIM file [$FilePathName] in folder [$MountDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70110 }
					throw "Unexpected COMException when trying to mount WIM file [$FilePathName] in folder [$MountDir]: $($_.Exception.Message)"
				}
			}
		}
		catch {
			Write-Log -Message "Failed to mount WIM file [$FilePathName] in folder [$MountDir].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70111 }
				throw "Failed to mount WIM file [$FilePathName] in folder [$MountDir]: $($_.Exception.Message)"
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Dismount-WIMFile
Function Dismount-WIMFile {
	<#
	.SYNOPSIS
		Dismounts a WIM file and deletes the path.
	.DESCRIPTION
		Dismounts a WIM file and deletes the path.
	.PARAMETER ImageObject
		Microsoft.Dism.Commands.BaseDismObject or psobject previously generated by Mount-WIMFile.
	.PARAMETER AlternativeMountDir
		Microsoft.Dism.Commands.BaseDismObject or psobject previously generated by Mount-WIMFile.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.EXAMPLE
		Dismount-WIMFile -ImageObject $MountedWIMObject
	.NOTES
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		$ImageObject,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$AlternativeMountDir = $dirFiles,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false,
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		## Determines if the ImageObject given is based in a mounted or extracted WIM file
		if ($ImageObject -is [Microsoft.Dism.Commands.BaseDismObject]) {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "Input object detected as [Microsoft.Dism.Commands.BaseDismObject] object type." -Source ${CmdletName} }
			$wimTargetPath = [IO.Path]::GetFullPath($ImageObject.Path)
		}
		elseif ($ImageObject -is [psobject]) {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "Input object detected as [psobject] object type." -Source ${CmdletName} }
			if ([string]::IsNullOrWhiteSpace($ImageObject.Path)) {
				Write-Log -Message "Input object contains a null or empty path attribute." -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70112 }
					throw "Input object contains a null or empty path attribute."
				}
			}
			else {
				$wimTargetPath = [IO.Path]::GetFullPath($ImageObject.Path)
			}
		}
		elseif ($null -ne $ImageObject) {
			Write-Log -Message "Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter." -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70113 }
				throw "Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter."
			}
			Break
		}
		elseif ($AlternativeMountDir) {
			Write-Log -Message "Input object not detected, using alternative mount path [$AlternativeMountDir]." -Severity 2 -Source ${CmdletName}
			$wimTargetPath = [IO.Path]::GetFullPath($AlternativeMountDir)
		}

		## Remove the mounted path
		if (Test-Path $wimTargetPath -ErrorAction SilentlyContinue) {

			#  Check if there is a mounted wim file
			if ($IsAdmin) { $MountedImage = Get-WindowsImage -Mounted | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq $wimTargetPath } }
			if ($MountedImage) {
				$wimFile = [IO.Path]::GetFileName($MountedImage.ImagePath)
				try {
					$null = Dismount-WindowsImage -Path $wimTargetPath -Discard
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully dismounted WIM file [$wimFile] from mount path [$wimTargetPath]." -Source ${CmdletName} }

						#  Deleting previously created Remediation Task no longer needed
						Remove-RemediationDismountTask -wimFile $wimFile
					}
				}
				catch {
					#  Dismount failed, a scheduled task will be created to remediate the situation on startup
					Write-Log -Message "Unable to dismount the WIM file [$wimFile] from mount path [$wimTargetPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

					New-RemediationDismountTask -wimFile $wimFile -wimTargetPath $wimTargetPath
				}
			}
			elseif ($ImageObject -is [Microsoft.Dism.Commands.BaseDismObject]) {
				Write-Log -Message "No mounted WIM file found in path [$wimTargetPath], already dismounted?" -Severity 2 -Source ${CmdletName}
			}

			#  Remove the folder
			if ($configWIMFileGeneralOptions.DeleteAlternativeMountDirWhenDismount) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "The mount folder [$wimTargetPath] and all its content will be deleted." -Source ${CmdletName} }
				Remove-Folder -Path $wimTargetPath
			}
		}
		else {
			Write-Log -Message "The mount path [$wimTargetPath] does not exist, already deleted?" -Severity 2 -Source ${CmdletName}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-WIMFile
Function New-WIMFile {
	<#
	.SYNOPSIS
		Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).
	.DESCRIPTION
		Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).
	.PARAMETER SavetoPath
		Specifies the folder where the WIM file will be created, by default Script directory.
	.PARAMETER Name
		Specifies the name of the image in the WIM file, $installName by default.
	.PARAMETER ForceUsewimlib
		Use wimlib instead of Windows API since the first one has better compression ratio.
	.PARAMETER CapturePath
		Path containing the files that will be added to the WIM file.
	.PARAMETER ContinueOnError
		Continue if an error is encountered. Default is: $true.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.EXAMPLE
		New-WIMFile
		The content of Files folder will be compressed and the file will be saved in Script directory.
	.EXAMPLE
		New-WIMFile -Name 'app_ver2.0'
		The content of Files folder will be compressed and the file app_ver2.0.wim will be saved in Script directory.
	.EXAMPLE
		New-WIMFile -CapturePath "C:\folder_with_files\"
		The content of CapturePath folder will be compressed and the file will be saved in Script directory.
	.NOTES
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$SavetoPath = $scriptParentPath,
		[Parameter(Mandatory = $false)]
		[string]$Name = $installName,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$CapturePath = $dirFiles,
		[Parameter(Mandatory = $false)]
		[switch]$ForceUsewimlib,
		[Parameter(Mandatory = $false)]
		[switch]$ReplaceExisting,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[boolean]$ContinueOnError = $false,
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		## Commands to find and execute wimlib if included in SupportFiles
		[ScriptBlock]$wimlibCommands = {
			if ($wimlibApplicationPath -and $wimlibLibraryPath) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to create WIM file [$wimFileName] in folder [$SavetoPath] using wimlib.exe." -Source ${CmdletName} }
				try {
					$CreatingResult = Execute-Process -Path $wimlibApplicationPath -Parameter @("capture", "`"$($CapturePath)`"", "`"$($wimFile)`"") -WindowStyle Hidden -PassThru
					if ($? -and $CreatingResult.ExitCode -eq 0) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully created WIM file [$wimFileName] in folder [$SavetoPath] using wimlib.exe." -Source ${CmdletName} }
					}
				}
				catch {
					Write-Log -Message "Failed to create WIM file [$wimFileName] in folder [$SavetoPath] using wimlib.exe.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70114 }
						throw "Failed to create WIM file [$wimFileName] in folder [$SavetoPath] using wimlib.exe: $($_.Exception.Message)"
					}
				}
			}
			else {
				if ($ForceUsewimlib) {
					Write-Log -Message "Unable to find wimlib executable and libraries inside SupportFiles folder." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70115 }
						throw "Unable to find wimlib executable and libraries inside SupportFiles folder."
					}
				}
				else {
					Write-Log -Message "Creating WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70116 }
						throw "Creating WIM file natively requires elevation, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)."
					}
				}
			}  
		}

		## Get full path of CapturePath parameter
		try {
			$CapturePath = [IO.Path]::GetFullPath($CapturePath)
			if ($?) {
				if (-not (Test-Path $CapturePath -ErrorAction SilentlyContinue)) {
					Write-Log -Message "The capture path [$CapturePath] does not exist." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70117 }
						throw "The capture path [$CapturePath] does not exist."
					}
					return
				}
				elseif (-not (Get-ChildItem -Path $CapturePath -Recurse -Force)) {
					Write-Log -Message "The capture path [$CapturePath] must contains at least one file or folder." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70118 }
						throw "The capture path [$CapturePath] must contains at least one file or folder."
					}
					return
				}
			}
		}
		catch {
			Write-Log -Message "Unable to get full path from capture path [$CapturePath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70119 }
				throw "Unable to get full path from capture path [$CapturePath]: $($_.Exception.Message)"
			}
			return
		}

		## Get full path of SavetoPath parameter
		try {
			$SavetoPath = [IO.Path]::GetFullPath($SavetoPath)
		}
		catch {
			Write-Log -Message "Unable to get full path from save to path [$SavetoPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70120 }
				throw "Unable to get full path from save to path [$SavetoPath]: $($_.Exception.Message)"
			}
			return
		}

		## Create WIM file
		if (Test-Path $SavetoPath -ErrorAction SilentlyContinue) {
			#  Sanitize the Name parameter
			if ([string]::IsNullOrWhiteSpace($Name)) {
				$Name = "no_name"
			}
			else {
				$Name = Remove-InvalidFileNameChars -Name ($Name.Trim())
			}
			[IO.FileInfo]$wimFile = Join-Path -Path $SavetoPath -ChildPath "$($Name).wim"
			$wimFileName = [IO.Path]::GetFileName($wimFile)

			if ($wimFile.Exists) {
				if ($ReplaceExisting) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "-ReplaceExisting switch specified, existing file [$wimFileName] in folder [$SavetoPath] will be deleted." -Severity 2 -Source ${CmdletName} }
					try {
						Remove-File -Path $wimFile -ContinueOnError $false
					}
					catch {
						Write-Log -Message "Unable to delete existing file [$wimFileName] in folder [$SavetoPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70121 }
							throw "Unable to delete existing file [$wimFileName] in folder [$SavetoPath]: $($_.Exception.Message)"
						}
						return
					}
				}
				else {
					Write-Log -Message "The file [$wimFileName] already exists in folder [$SavetoPath], use -ReplaceExisting switch to overwrite it." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70122 }
						throw "The file [$wimFileName] already exists in folder [$SavetoPath], use -ReplaceExisting switch to overwrite it."
					}
					return
				}
			}

			try {
				if ($ForceUsewimlib) {
					#  Using wimlib by default if included in function parameters
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "-ForceUsewimlib switch specified, using wimlib by default if included in SupportFiles." -Source ${CmdletName} }
					Invoke-Command -ScriptBlock $wimlibCommands -NoNewScope        
				}
				else {
					#  Try using Windows API
					New-WindowsImage -ImagePath $wimFile -CapturePath $CapturePath -Name $Name -CompressionType Max -Verbose
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully created WIM file [$wimFileName] in folder [$SavetoPath]." -Source ${CmdletName} }
					}
				}
			}
			catch [System.Runtime.InteropServices.COMException], [System.Exception] {
				if ($_.Exception.HResult -in (0x80070522, 0x80131500, 0x800700A1, 0x80004002)) {
					if (-not $ForceUsewimlib) {
						## Trying to use wimlib to workaround elevation
						Invoke-Command -ScriptBlock $wimlibCommands -NoNewScope        
					}
				}
				else {
					Write-Log -Message "Unexpected Exception [$('{0:x}' -f $_.Exception.HResult)] when trying to create WIM file [$wimFileName] in folder [$SavetoPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70123 }
						throw "Unexpected Exception [$($_.Exception.HResult)] when trying to create WIM file [$wimFileName] in folder [$SavetoPath]: $($_.Exception.Message)"
					}
					return
				}
			}
			catch {
				Write-Log -Message "Failed to create WIM file [$wimFileName] in folder [$SavetoPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70124 }
					throw "Failed to create WIM file [$wimFileName] in folder [$SavetoPath]: $($_.Exception.Message)"
				}
			}
		}
		else {
			Write-Log -Message "The save to path [$CapturePath] does not exist." -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70125 }
				throw "The save to path [$CapturePath] does not exist."
			}
			return
		}

		## Show warning message if the function is executed as a remainder to comment or remove it before production
		if ($configWIMFileGeneralOptions.ShowNewWIMFileWarningMessage) {
			Show-InstallationPrompt -Title $WIMFileExtScriptFriendlyName -Message $configUIWIMFileMessages.NewWIMFile_WarningMessage -Timeout $configWIMFileGeneralOptions.NewWIMFileWarningMessageTimeout -ButtonRightText 'OK' -Icon "Warning"
			Exit-Script -ExitCode $configInstallationUIExitCode
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function New-RemediationDismountTask
Function New-RemediationDismountTask {
	<#
	.SYNOPSIS
		Creates an scheduled task with remediation commands.
	.DESCRIPTION
		Creates an scheduled task with remediation commands.
	.PARAMETER wimFile
		Specifies the name of the WIM file.
	.PARAMETER wimTargetPath
		Specifies the name of the mount folder.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$wimFile,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$wimTargetPath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[boolean]$ContinueOnError = $false,
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Deleting previously created Remediation Task no longer needed
		Remove-RemediationDismountTask -wimFile $wimFile

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		## Creates remediation scheduled task
		#  Remove illegal characters from the scheduled task name
		[char[]]$invalidScheduledTaskChars = '$', '!', '''', '"', '(', ')', ';', '\', '`', '*', '?', '{', '}', '[', ']', '<', '>', '|', '&', '%', '#', '~', '@', ' '
		$ScheduledTaskName = "Remediation dismount WIM file $($wimFile)"
		foreach ($invalidChar in $invalidScheduledTaskChars) { $ScheduledTaskName = $ScheduledTaskName -replace [regex]::Escape($invalidChar), "" }

		#  Defines the action to execute
		$ActionVariables = @'
$wimTargetPath = [IO.Path]::GetFullPath("{0}")
$wimTaskName = "{1}"
$wimFile = "{1}"
'@ -f ( <#0#> Split-Path -Path $wimTargetPath -Parent), ( <#1#> $ScheduledTaskName), ( <#2#> $wimFile)
		$ActionScript = @'
function Get-MountedImages {
	param ( [string]$wimFile, [string]$wimTargetPath )
	Get-WindowsImage -Mounted | Where-Object { $_.MountStatus -eq "Invalid" -or $_.ImagePath.EndsWith($wimFile) -or [IO.Path]::GetFullPath($_.Path).StartsWith($wimTargetPath) }
}
$MountedImages = Get-MountedImages
foreach ($MountedImage in $MountedImages) { try { Dismount-WindowsImage -Path $MountedImage.Path -Discard; if ($?) { [IO.Directory]::Delete($MountedImage.Path, $true) } } catch { Clear-WindowsCorruptMountPoint } }
$MountedImages = Get-MountedImages
if ($null -eq $MountedImages) { Unregister-ScheduledTask -TaskName $wimTaskName -Confirm:$false }
'@
		$TaskAction = $ActionVariables + "`r`n" + $ActionScript

		#  Parameters definition for the scheduled task
		$ScheduledTaskParameters = @{
			TaskName    = $ScheduledTaskName
			Principal   = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -RunLevel Highest #NT AUTHORITY\SYSTEM
			Action      = New-ScheduledTaskAction -Execute "$($PSHome)\powershell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($TaskAction)))"
			Description = "Remediation task that will dismount invalid or in use mount points for [$wimFile] in [$wimTargetPath]."
			Settings    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun
			Trigger     = New-ScheduledTaskTrigger -AtStartup
			Force       = $true
		}

		#  Register scheduled task
		try {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "The remediation scheduled task [$ScheduledTaskName] will be created." -Source ${CmdletName} }
			$null = Register-ScheduledTask @ScheduledTaskParameters
			if ($? -and (Get-ScheduledTask -TaskName $ScheduledTaskName)) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully registered remediation scheduled task [$ScheduledTaskName]." -Source ${CmdletName} }
			}
		}
		catch {
			Write-Log -Message "Failed to register remediation scheduled task [$ScheduledTaskName].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70126 }
				throw "Failed to register remediation scheduled task [$ScheduledTaskName]: $($_.Exception.Message)"
			}
			return
		}    
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Remove-RemediationDismountTask
Function Remove-RemediationDismountTask {
	<#
	.SYNOPSIS
		Removes a previously created remediation scheduled task.
	.DESCRIPTION
		Removes a previously created remediation scheduled task.
	.PARAMETER wimFile
		Specifies the name of the WIM file.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$wimFile,
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		#  Remove illegal characters from the scheduled task name
		[char[]]$invalidScheduledTaskChars = '$', '!', '''', '"', '(', ')', ';', '\', '`', '*', '?', '{', '}', '[', ']', '<', '>', '|', '&', '%', '#', '~', '@', ' '
		$ScheduledTaskName = "Remediation dismount WIM file $($wimFile)"
		foreach ($invalidChar in $invalidScheduledTaskChars) { $ScheduledTaskName = $ScheduledTaskName -replace [regex]::Escape($invalidChar), "" }

		$RemediationDismountTask = Get-ScheduledTask | Where-Object { $_.TaskName -like "*$($ScheduledTaskName )*" } -ErrorAction SilentlyContinue
		if ($RemediationDismountTask) {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "Deleting previously remeditation task created [$($RemediationDismountTask.TaskName)]." -Source ${CmdletName} }
			try {
				$null = $RemediationDismountTask | Stop-ScheduledTask -ErrorAction SilentlyContinue
				$null = $RemediationDismountTask | Unregister-ScheduledTask -ErrorAction SilentlyContinue -Confirm:$false
				if ($?) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "Succesfully deleted the remediation task [$($RemediationDismountTask.TaskName)]." -Source ${CmdletName} }
				}
			}
			catch {
				Write-Log -Message "Unable to delete the remediation task [$($RemediationDismountTask.TaskName)]. Remember it deletes itself when running.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion

#endregion
##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================
#region ScriptBody

## Append localized UI messages from WIM File config XML
$xmlLoadLocalizedUIMessages = [scriptblock]::Create($xmlLoadLocalizedUIMessages.ToString() + ";" + $xmlLoadLocalizedUIWIMFileMessages.ToString())

if ($scriptParentPath) {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $WIMFileExtName
}
else {
	Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $WIMFileExtName
}

#endregion
##*===============================================
##* END SCRIPT BODY
##*===============================================