<#
.SYNOPSIS
	WIM File Extension script file, must be dot-sourced by the AppDeployToolkitExtension.ps1 script.
.DESCRIPTION
	Contains various functions used for creating and mounting WIM files.
	If a failure occurs at any point in the process, scheduled cleanup tasks are created.
.NOTES
	Extension Exit Codes:
	70101: Mount-WIMFile - Unable to get full path from mount path.
	70102: Mount-WIMFile - The WIM file could not be found.
	70103: Mount-WIMFile - The WIM file contains an invalid path or file name.
	70104: Mount-WIMFile - No WIM file found in script directory.
	70111: Mount-WIMFile - Failed to mount or extract WIM file in path.
	70105: Expand-WIMFile - Failed to delete SymbolicLink extraction path.
	70107: Expand-WIMFile - Failed to extract WIM file in path.
	70108: Expand-WIMFile - Failed to extract WIM file in path using wimlib.exe.
	70109: Expand-WIMFile - This script support wimlib as alternative method to expand WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).
	70112: Dismount-WIMFile - Input object contains a null or empty path attribute.
	70113: Dismount-WIMFile - Input object not detected as a valid object, please use Mount-WIMFile function and use the object returned as -ImageObject parameter.
	70114: New-WIMFile - Failed to create WIM file using wimlib.exe.
	70115: New-WIMFile - Unable to find wimlib executable and libraries inside SupportFiles folder, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).
	70116: New-WIMFile - This script support wimlib as alternative method to create WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).
	70117: New-WIMFile - The capture path does not exist.
	70118: New-WIMFile - The capture path is empty, must contains at least one element.
	70119: New-WIMFile - Unable to get full path from capture path.
	70120: New-WIMFile - Unable to get full path from save to path.
	70121: New-WIMFile - Unable to delete existing file.
	70122: New-WIMFile - The file already exists, use -ReplaceExisting switch to overwrite it.
	70123: New-WIMFile - Failed to create WIM file. Exception ErrorCode...
	70125: New-WIMFile - The save to path does not exist.
	70127: New-WIMFile - Remove the 'New-WIMFile' function from the script to continue.
	70128: New-WIMFile - Provide an existing directory path for the -CapturePath parameter.
	70129: New-WIMFile - Provide an existing directory path for the -SavetoPath parameter.
	70126: New-RemediationDismountTask - Failed to register remediation scheduled task.

	Author:  Leonardo Franco Maragna
	Version: 1.0.2
	Date:    2023/02/22
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
$WIMFileExtScriptVersion = "1.0.2"
$WIMFileExtScriptDate = "2023/02/22"
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

## Variables: Check for Zero-Config MSI/MST
[scriptblock]$CheckZeroConfigInstallation = {
	## If the default Deploy-Application.ps1 hasn't been modified, and the main script was not called by a referring script, check for MSI / MST and modify the install accordingly
	if ((-not $appName) -and (-not $ReferredInstallName)) {
		#  Build properly formatted Architecture String
		if ($Is64Bit) { $formattedOSArch = "x64" } else { $formattedOSArch = "x86" }

		#  Find the first MSI file in the Files folder and use that as our install
		if ([string]$defaultMsiFile = (Get-ChildItem -LiteralPath $dirFiles -ErrorAction SilentlyContinue | Where-Object { (-not $_.PsIsContainer) -and ([IO.Path]::GetExtension($_.Name) -eq ".msi") -and ($_.Name.EndsWith(".$formattedOSArch.msi")) } | Select-Object -ExpandProperty "FullName" -First 1)) {
			Write-Log -Message "Discovered $formattedOSArch Zerotouch MSI under $defaultMSIFile" -Source $appDeployToolkitName
		}
		elseif ([string]$defaultMsiFile = (Get-ChildItem -LiteralPath $dirFiles -ErrorAction SilentlyContinue | Where-Object { (-not $_.PsIsContainer) -and ([IO.Path]::GetExtension($_.Name) -eq ".msi") } | Select-Object -ExpandProperty "FullName" -First 1)) {
			Write-Log -Message "Discovered Arch-Independent Zerotouch MSI under $defaultMSIFile" -Source $appDeployToolkitName
		}

		if ($defaultMsiFile) {
			try {
				[Boolean]$useDefaultMsi = $true
				Write-Log -Message "Discovered Zero-Config MSI installation file [$defaultMsiFile]." -Source $appDeployToolkitName

				#  Discover if there is a zero-config MST file
				[string]$defaultMstFile = [IO.Path]::ChangeExtension($defaultMsiFile, "mst")
				if (Test-Path -LiteralPath $defaultMstFile -PathType "Leaf") {
					Write-Log -Message "Discovered Zero-Config MST installation file [$defaultMstFile]." -Source $appDeployToolkitName
				}
				else {
					[string]$defaultMstFile = ""
				}

				#  Discover if there are zero-config MSP files. Name multiple MSP files in alphabetical order to control order in which they are installed.
				[String[]]$defaultMspFiles = Get-ChildItem -LiteralPath $dirFiles -ErrorAction SilentlyContinue | Where-Object { (-not $_.PsIsContainer) -and ([IO.Path]::GetExtension($_.Name) -eq ".msp") } | Select-Object -ExpandProperty "FullName"
				if ($defaultMspFiles) {
					Write-Log -Message "Discovered Zero-Config MSP installation file(s) [$($defaultMspFiles -join ',')]." -Source $appDeployToolkitName
				}

				#  Read the MSI and get the installation details
				[hashtable]$GetDefaultMsiTablePropertySplat = @{ Path = $defaultMsiFile; Table = "Property"; ContinueOnError = $false; ErrorAction = "Stop" }
				if ($defaultMstFile) { $GetDefaultMsiTablePropertySplat.Add("TransformPath", $defaultMstFile) }
				[PSObject]$defaultMsiPropertyList = Get-MsiTableProperty @GetDefaultMsiTablePropertySplat
				[string]$appVendor = $defaultMsiPropertyList.Manufacturer
				[string]$appName = $defaultMsiPropertyList.ProductName
				[string]$appVersion = $defaultMsiPropertyList.ProductVersion

				#  Read the MSI file list
				$GetDefaultMsiTablePropertySplat.Set_Item("Table", "File")
				[PSObject]$defaultMsiFileList = Get-MsiTableProperty @GetDefaultMsiTablePropertySplat
				[String[]]$defaultMsiExecutables = Get-Member -InputObject $defaultMsiFileList -ErrorAction Stop | Select-Object -ExpandProperty "Name" -ErrorAction Stop | Where-Object { [IO.Path]::GetExtension($_) -eq ".exe" } | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }
				[string]$defaultMsiExecutablesList = $defaultMsiExecutables -join ","
				Write-Log -Message "App Vendor [$appVendor]." -Source $appDeployToolkitName
				Write-Log -Message "App Name [$appName]." -Source $appDeployToolkitName
				Write-Log -Message "App Version [$appVersion]." -Source $appDeployToolkitName
				Write-Log -Message "MSI Executable List [$defaultMsiExecutablesList]." -Source $appDeployToolkitName
			}
			catch {
				Write-Log -Message "Failed to process Zero-Config MSI Deployment. `r`n$(Resolve-Error)" -Source $appDeployToolkitName
				$useDefaultMsi = $false ; $appVendor = "" ; $appName = "" ; $appVersion = ""
			}
		}
	}
}

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
	ExitScriptOnError                      = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.ExitScriptOnError)) } catch { $true }'
	ShowNewWIMFileWarningMessage           = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.ShowNewWIMFileWarningMessage)) } catch { $true }'
	NewWIMFileWarningMessageTimeout        = Invoke-Expression -Command 'try { [int32]::Parse([string]($xmlWIMFileOptions.NewWIMFileWarningMessageTimeout)) } catch { 120 }'
	DeleteAlternativeMountPathWhenDismount = Invoke-Expression -Command 'try { [boolean]::Parse([string]($xmlWIMFileOptions.DeleteAlternativeMountPathWhenDismount)) } catch { $true }'
}

#  Define ScriptBlock for Loading Message UI Language Options (default for English if no localization found)
[scriptblock]$xmlLoadLocalizedUIWIMFileMessages = {
	[Xml.XmlElement]$xmlUIWIMFileMessages = $xmlWIMFileConfig.$xmlUIMessageLanguage
	$configUIWIMFileMessages = [PSCustomObject]@{
		NewWIMFile_ProgressMessage = [string]$xmlUIWIMFileMessages.NewWIMFile_ProgressMessage
		NewWIMFile_WarningMessage  = [string]$xmlUIWIMFileMessages.NewWIMFile_WarningMessage
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

#region Function New-WIMFile
Function New-WIMFile {
	<#
	.SYNOPSIS
		Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).
	.DESCRIPTION
		Creates a WIM file with the content of CapturePath (Files directory by default) and saves it in the SavetoPath folder (Script directory by default).
	.PARAMETER CapturePath
		Path containing the files that will be added to the WIM file.
	.PARAMETER SavetoPath
		Specifies the folder where the WIM file will be created, by default Script directory.
	.PARAMETER Name
		Specifies the name of the image in the WIM file, $installName by default.
	.PARAMETER ForceUsewimlib
		Use wimlib instead of Windows API since the first one has better compression ratio.
	.PARAMETER ContinueOnError
		Continue if an error is encountered. Default is: $true.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
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
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$CapturePath = $dirFiles,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$SavetoPath = $scriptParentPath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Name = $installName,
		[switch]$ForceUsewimlib,
		[switch]$ReplaceExisting,
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
		## Get full path of CapturePath parameter
		if ([string]::IsNullOrWhiteSpace($CapturePath)) {
			Write-Log -Message "Provide an existing directory path for the -CapturePath parameter." -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70128 }
				throw "Provide an existing directory path for the -CapturePath parameter."
			}
			return
		}
		else {
			try {
				$CapturePath = [IO.Path]::GetFullPath($CapturePath)
				if ($?) {
					if (-not (Test-Path -Path $CapturePath -ErrorAction SilentlyContinue)) {
						Write-Log -Message "The capture path [$CapturePath] does not exist." -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70117 }
							throw "The capture path [$CapturePath] does not exist."
						}
						return
					}
					elseif (-not (Get-ChildItem -Path $CapturePath -Recurse -Force)) {
						Write-Log -Message "The capture path [$CapturePath] is empty, must contains at least one element." -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70118 }
							throw "The capture path [$CapturePath] is empty, must contains at least one element."
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
		}

		## Get full path of SavetoPath parameter
		if ([string]::IsNullOrWhiteSpace($SavetoPath)) {
			Write-Log -Message "Provide an existing directory path for the -SavetoPath parameter." -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70129 }
				throw "Provide an existing directory path for the -SavetoPath parameter."
			}
			return
		}
		else {
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
		}

		## Create WIM file
		if ([string]::IsNullOrWhiteSpace($Name)) {
			Write-Log -Message "The -Name parameter is empty, using -CapturePath folder name by default." -Severity 2 -Source ${CmdletName}
			$Name = Split-Path -Path $CapturePath -Leaf -ErrorAction Stop
		}

		if (Test-Path -Path $SavetoPath -ErrorAction SilentlyContinue) {
			[IO.FileInfo]$ImagePath = Join-Path -Path $SavetoPath -ChildPath "$($Name).wim"

			if (Test-Path -Path $ImagePath -ErrorAction SilentlyContinue) {
				if ($ReplaceExisting) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "-ReplaceExisting switch specified, existing file [$ImagePath] will be deleted." -Severity 2 -Source ${CmdletName} }
					try {
						Remove-File -Path $ImagePath -ContinueOnError $false
					}
					catch {
						Write-Log -Message "Unable to delete existing file [$ImagePath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70121 }
							throw "Unable to delete existing file [$ImagePath]: $($_.Exception.Message)"
						}
						return
					}
				}
				else {
					Write-Log -Message "The file [$ImagePath] already exists, use -ReplaceExisting switch to overwrite it." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70122 }
						throw "The file [$ImagePath] already exists, use -ReplaceExisting switch to overwrite it."
					}
					return
				}
			}

			## Commands to find and execute wimlib if included in SupportFiles
			[ScriptBlock]$CompressUsingwimlib = {
				if ($wimlibApplicationPath -and $wimlibLibraryPath) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to create WIM file [$ImagePath] using wimlib.exe." -Source ${CmdletName} }
					try {
						$CreatingResult = Execute-Process -Path $wimlibApplicationPath -Parameter @("capture", "`"$($CapturePath)`"", "`"$($ImagePath)`"", "`"$($Name)`"", "--compress=LZX:100", "--chunk-size=32K") -WindowStyle Hidden -PassThru
						if ($? -and $CreatingResult.ExitCode -eq 0) {
							if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully created WIM file [$ImagePath] using wimlib.exe." -Source ${CmdletName} }
						}
					}
					catch {
						Write-Log -Message "Failed to create WIM file [$ImagePath] using wimlib.exe.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70114 }
							throw "Failed to create WIM file [$ImagePath] using wimlib.exe: $($_.Exception.Message)"
						}
					}
				}
				else {
					if ($ForceUsewimlib) {
						Write-Log -Message "Unable to find wimlib executable and libraries inside SupportFiles folder, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)." -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70115 }
							throw "Unable to find wimlib executable and libraries inside SupportFiles folder, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)."
						}
					}
					else {
						Write-Log -Message "This script support wimlib as alternative method to create WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)." -Severity 3 -Source ${CmdletName}
						if (-not $ContinueOnError) {
							if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70116 }
							throw "This script support wimlib as alternative method to create WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory)."
						}
					}
				}
			}

			try {
				Show-InstallationProgress -StatusMessage ($configUIWIMFileMessages.NewWIMFile_ProgressMessage -f ( <#0#> [Security.SecurityElement]::Escape($CapturePath)), ( <#1#> [Security.SecurityElement]::Escape($SavetoPath)), ( <#2#> [Security.SecurityElement]::Escape($ImagePath.Name)))
				if ($ForceUsewimlib) {
					#  Using wimlib by default if included in function parameters
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "-ForceUsewimlib switch specified, using wimlib by default if included in SupportFiles." -Source ${CmdletName} }
					Invoke-Command -ScriptBlock $CompressUsingwimlib -NoNewScope
				}
				else {
					#  Try using Windows API
					$null = New-WindowsImage -ImagePath $ImagePath -CapturePath $CapturePath -Name $Name -CompressionType Max
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully created WIM file [$ImagePath]." -Source ${CmdletName} }
					}
				}
			}
			catch {
				Write-Log -Message "Failed to create WIM file [$ImagePath]. Exception ErrorCode: $('{0:x}' -f $_.Exception.ErrorCode)`r`n$(Resolve-Error)" -Severity 2 -Source ${CmdletName}
				if (-not $ForceUsewimlib) {
					## Trying to use wimlib to workaround elevation and other exceptions
					Invoke-Command -ScriptBlock $CompressUsingwimlib -NoNewScope
				}
				else {
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70123 }
						throw "Failed to create WIM file [$ImagePath]. Exception ErrorCode: $('{0:x}' -f $_.Exception.ErrorCode): $($_.Exception.Message)"
					}
					return
				}
			}
			finally {
				Close-InstallationProgress
			}
		}
		else {
			Write-Log -Message "The save to path [$SavetoPath] does not exist." -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70125 }
				throw "The save to path [$SavetoPath] does not exist."
			}
			return
		}

		## Show warning message if the function is executed as a remainder to comment or remove it before production
		if ($configWIMFileGeneralOptions.ShowNewWIMFileWarningMessage) {
			$WarningMessageResult = Show-DialogBox -Title $WIMFileExtScriptFriendlyName -Text $configUIWIMFileMessages.NewWIMFile_WarningMessage -Timeout $configWIMFileGeneralOptions.NewWIMFileWarningMessageTimeout -Buttons YesNo -Icon Exclamation -TopMost $true
			if ($WarningMessageResult -ne "Yes") {
				Write-Log -Message "Remove the 'New-WIMFile' function from the script to continue." -Severity 2 -Source ${CmdletName}
				Exit-Script -ExitCode 70127
			}
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Expand-WIMFile
Function Expand-WIMFile {
	<#
	.SYNOPSIS
		Expands a WIM file using native method or wimlib executable if exists.
	.DESCRIPTION
		Expands a WIM file using native method or wimlib executable if exists.
	.PARAMETER ImagePath
		Absolute path to the file to be expanded.
	.PARAMETER Name
		Specifies the name of an image in the WIM file.
	.PARAMETER Index
		Specifies the index number of a Windows image in the WIM file, by default 1.
	.PARAMETER ApplyPath
		Specifies the folder where the WIM file will be expanded.
	.PARAMETER NoFixedDrive
		Indicates that the function was called because could not mount to a non fixed disk.
	.PARAMETER NoAdministrator
		Indicates that the user does not have administrator privileges.
	.PARAMETER NoStandardWIMFile
		Indicates that the WIM file is non standard.
	.PARAMETER ContinueOnError
		Continue if an error is encountered. Default is: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		[PSCustomObject]
		Returns and object including the path where the wim file was extracted.
	.EXAMPLE
		Expand-WIMFile -ImagePath 'C:\path to the file\file.wim' -ApplyPath 'C:\destination folder\'
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$ImagePath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Name,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int]$Index,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$ApplyPath,
		[switch]$NoFixedDrive,
		[switch]$NoAdministrator,
		[switch]$NoStandardWIMFile,
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
		## Resulting variable
		$ImageExpanded = $false

		[ScriptBlock]$ExpandUsingwimlib = {
			if ($wimlibApplicationPath -and $wimlibLibraryPath) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to extract WIM file [$ImagePath] in path [$ApplyPath] using wimlib.exe." -Source ${CmdletName} }
				try {
					if ($Name) { $IMAGEParameter = $Name }
					else { $IMAGEParameter = $Index }
			
					#  Trying to expand the image using wimlib
					$ExtractedResult = Execute-Process -Path $wimlibApplicationPath -Parameter @("apply", "`"$($ImagePath)`"", "`"$($IMAGEParameter)`"", "`"$($ApplyPath)`"") -WindowStyle Hidden -PassThru

					if ($? -and $ExtractedResult.ExitCode -eq 0) {
						$ImageExpanded = $true

						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully extracted WIM file [$ImagePath] in path [$ApplyPath] using wimlib.exe." -Source ${CmdletName} }
					}
				}
				catch {
					Write-Log -Message "Failed to extract WIM file [$ImagePath] in path [$ApplyPath] using wimlib.exe.`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70108 }
						throw "Failed to extract WIM file [$ImagePath] in path [$ApplyPath] using wimlib.exe: $($_.Exception.Message)"
					}
				}
			}
			else {
				Write-Log -Message "This script support wimlib as alternative method to expand WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory).`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70109 }
					throw "This script support wimlib as alternative method to expand WIM files, (try downloading wimlib to [..\SupportFiles\PSADT.WIMFile\] directory): $($_.Exception.Message)"
				}
			}
		}

		if ($NoAdministrator -or $NoStandardWIMFile) {
			## Trying to use wimlib to workaround elevation or non standard WIM files
			Invoke-Command -ScriptBlock $ExpandUsingwimlib -NoNewScope
		}
		elseif ($NoFixedDrive) {
			## The drive of the specified mount path is not supported. Please mount to a volume on a fixed drive.
			#  Commands to remove SymbolicLink extraction path
			[ScriptBlock]$RemoveExpandPath = {
				try {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "The SymbolicLink extraction path will be deleted." -Source ${CmdletName} }
					[IO.Directory]::Delete($ExpandPath, $true)
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully deleted SymbolicLink extraction path [$ExpandPath]." -Source ${CmdletName} }
					}
				}
				catch {
					Write-Log -Message "Failed to delete SymbolicLink extraction path [$ExpandPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70105 }
						throw "Failed to delete SymbolicLink extraction path [$ExpandPath]: $($_.Exception.Message)"
					}
				}
			}

			#  Trying to SymLink the ApplyPath
			try {
				[IO.FileInfo]$ExpandPath = Join-Path -Path $envTemp -ChildPath "Mount_$($installName.Replace(" ","_"))"
				if ($ExpandPath.Exists) {
					Write-Log -Message "The SymbolicLink extraction path already exists [$ExpandPath], probably a failed past attempt." -Severity 2 -Source ${CmdletName}
					Invoke-Command -ScriptBlock $RemoveExpandPath -NoNewScope
				}
	
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "Creating SymbolicLink extraction path [$ExpandPath] targetting [$ApplyPath]." -Source ${CmdletName} }
	
				#  Create SymLink targetting ApplyPath if not fixed
				$null = New-Item -Path $ExpandPath -ItemType SymbolicLink -Value $ApplyPath
	
				if ($?) {
					if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully linked SymbolicLink path [$ApplyPath] to local path [$ExpandPath]." -Source ${CmdletName} }

					#  Trying to expand the image using native cmdlet
					if ($Name) { $null = Expand-WindowsImage -ImagePath $ImagePath -ApplyPath $ExpandPath -Name $Name }
					else { $null = Expand-WindowsImage -ImagePath $ImagePath -ApplyPath $ExpandPath -Index $Index }
			
					if ($?) {
						$ImageExpanded = $true

						Write-Log -Message "Successfully extracted WIM file [$ImagePath] in path [$ApplyPath]." -Source ${CmdletName}
						if ($UseSymbolicLinkToExtract) {
							if (-not ($DisableFunctionLogging)) { Write-Log -Message "Removing the SymbolicLink extraction path [$ExpandPath], since it is no longer needed." -Source ${CmdletName} }
							Invoke-Command -ScriptBlock $RemoveExpandPath -NoNewScope
						}
					}
				}
			}
			catch {
				Write-Log -Message "Failed to extract WIM file [$ImagePath] in path [$ApplyPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70107 }
					throw "Failed to extract WIM file [$ImagePath] in path [$ApplyPath]: $($_.Exception.Message)"
				}
				else {
					## Trying to use wimlib to workaround exception
					Invoke-Command -ScriptBlock $ExpandUsingwimlib -NoNewScope
				}
			}
		}
		else {
			## If any previously scenario is not triggered and couldn't mount try with wimlib as last resource
			Invoke-Command -ScriptBlock $ExpandUsingwimlib -NoNewScope
		}

		## Returns a PSCustomObject compatible with Dismoun-WIMFile
		if ($ImageExpanded) {
			return [PSCustomObject]@{ Path = $ApplyPath }
		}
	}
	End {
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
	}
}
#endregion


#region Function Mount-WIMFile
Function Mount-WIMFile {
	<#
	.SYNOPSIS
		Mounts a WIM file in the MountPath folder (Files directory by default).
	.DESCRIPTION
		Mounts a WIM file in the MountPath folder (Files directory by default) so the rest of the script can use the content.
	.PARAMETER Path
		Path to the file to be mounted. If no value is supplied, the script directory is scanned searching for WIM files.
	.PARAMETER Name
		Specifies the name of an image in the WIM file.
	.PARAMETER Index
		Specifies the index number of a Windows image in the WIM file, by default 1.
	.PARAMETER MountPath
		Specifies the folder where the WIM file will be mounted, by default Files folder.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		[PSCustomObject], [Microsoft.Dism.Commands.BaseDismObject]
		Returns and object including the path where the wim file was mounted or extracted.
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
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[Alias("FilePath")]
		[string]$ImagePath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[string]$Name,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[int]$Index = 1,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[Alias("Path")]
		[string]$MountPath = $dirFiles,
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
		## Get full path of MountPath parameter
		try {
			$MountPath = [IO.Path]::GetFullPath($MountPath)
		}
		catch {
			Write-Log -Message "Unable to get full path from mount path [$MountPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
			if (-not $ContinueOnError) {
				if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70101 }
				throw "Unable to get full path from mount path [$MountPath]: $($_.Exception.Message)"
			}
			return
		}

		## Validate and find the fully qualified path for the $Path variable.
		if ($PSBoundParameters.ContainsKey("ImagePath") -and [IO.Path]::IsPathRooted($ImagePath) -and [IO.Path]::HasExtension($ImagePath)) {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "[$ImagePath] is a valid fully qualified path, continue." -Source ${CmdletName} }
			if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf -ErrorAction Stop)) {
				Write-Log -Message "The WIM file [$ImagePath] could not be found." -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70102 }
					throw "The WIM file [$ImagePath] could not be found."
				}
				return
			}
		}
		else {
			## If the WIM file is in the Script directory, set the full path to the WIM file
			if ($PSBoundParameters.ContainsKey("ImagePath")) {
				$SearchFilter = [IO.Path]::GetFileNameWithoutExtension($ImagePath)
			}
			else {
				$SearchFilter = "*"
			}

			[array]$ImageFilesInScriptDirectory = Get-ChildItem -Path $scriptParentPath -Filter "$($SearchFilter).wim" -Depth 0 -Force -ErrorAction SilentlyContinue

			if ($ImageFilesInScriptDirectory.Count -lt 1) {
				if ($PSBoundParameters.ContainsKey("ImagePath")) {
					Write-Log -Message "The WIM file [$ImagePath] contains an invalid path or file name." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70103 }
						throw "The WIM file [$ImagePath] contains an invalid path or file name."
					}
				}
				else {
					Write-Log -Message "No WIM file found in script directory [$scriptParentPath]." -Severity 3 -Source ${CmdletName}
					if (-not $ContinueOnError) {
						if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70104 }
						throw "No WIM file found in script directory [$scriptParentPath]."
					}
				}
				return
			}
			else {
				if ($ImageFilesInScriptDirectory.Count -gt 1) {
					Write-Log -Message "Multiple WIM files found [$($ImageFilesInScriptDirectory.Name -join ', ')]." -Severity 2 -Source ${CmdletName}
					$ImageFilesInScriptDirectory = $ImageFilesInScriptDirectory | Sort-Object -Property LastWriteTime, Length | Select-Object -Last 1
					Write-Log -Message "Using last modified WIM file [$($ImageFilesInScriptDirectory.FullName)]." -Severity 2 -Source ${CmdletName}
				}
				else {
					Write-Log -Message "Using WIM file found [$($ImageFilesInScriptDirectory.FullName)]." -Severity 2 -Source ${CmdletName}
				}
				$ImagePath = $ImageFilesInScriptDirectory.FullName
			}
		}

		## Check if the mount path already exists and if can be deleted
		if (Test-Path $MountPath -ErrorAction SilentlyContinue) {
			if ($IsAdmin) { $MountedImage = Get-WindowsImage -Mounted | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq $MountPath } }
			if ($MountedImage) {
				Write-Log -Message "The WIM file [$($MountedImage.ImagePath)] is already mounted in mount path [$MountPath]. It will be dismounted." -Severity 2 -Source ${CmdletName}
				Dismount-WIMFile -ImageObject ([PSCustomObject]@{ Path = $MountPath })
			}
			else {
				Write-Log -Message "The mount path [$MountPath] already exists, all its content will be deleted." -Severity 2 -Source ${CmdletName}
				Remove-Folder -Path $MountPath -ContinueOnError $false
			}
		}

		## Create new mount path folder
		New-Folder -Path $MountPath -ContinueOnError $false

		try {
			## Mount WIM file in Files directory
			if ($Name) {
				$ImageObject = Mount-WindowsImage -ImagePath $ImagePath -Path $MountPath -Name $Name
			}
			else {
				$ImageObject = Mount-WindowsImage -ImagePath $ImagePath -Path $MountPath -Index $Index
			}

			if ($?) {
				Write-Log -Message "Successfully mounted WIM file [$ImagePath] in path [$MountPath]." -Source ${CmdletName}

				#  Create remediation dismount task to run when the system startup
				New-RemediationDismountTask -ImagePath ([IO.Path]::GetFileName($ImagePath)) -Path $MountPath

				#  Returns the ImageObject
				return $ImageObject
			}
		}
		catch {
			Write-Log -Message "Could not mount WIM file [$ImagePath] in path [$MountPath]. Exception ErrorCode: $('{0:x}' -f $_.Exception.ErrorCode)`r`n$(Resolve-Error)" -Severity 2 -Source ${CmdletName}

			## Unable to mount to the specified mount path, the WIM file will be extracted
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "Attempting to extract WIM file [$ImagePath] in path [$MountPath]." -Source ${CmdletName} }

			## Define the splatter parameters to use to expand the image
			$ExpandWIMFileParameters = @{
				ImagePath       = $ImagePath
				ApplyPath       = $MountPath
				ContinueOnError = $ContinueOnError
			}

			if ($Name) {
				$ExpandWIMFileParameters += @{ Name = $Name }
			}
			else {
				$ExpandWIMFileParameters += @{ Index = $Index }
			}

			if ($DisableFunctionLogging) {
				$ExpandWIMFileParameters += @{ DisableFunctionLogging = $true }
			}

			if ($_.Exception.ErrorCode -eq 0xC1420134) {
				#  The drive of the specified mount path is not supported. Please mount to a volume on a fixed drive.
				$ExpandWIMFileParameters += @{ NoFixedDrive = $true }
			}

			if ($_.Exception.ErrorCode -eq 0x800702E4 -or -not $IsAdmin) {
				#  Administrator privileges needed
				$ExpandWIMFileParameters += @{ NoAdministrator = $true }
			}

			if ($_.Exception.ErrorCode -eq 0x8007000B) {
				#  Non standard or not recognized WIM File
				$ExpandWIMFileParameters += @{ NoStandardWIMFile = $true }
			}

			## Calls the expanding function
			$ExpandResult = Expand-WIMFile @ExpandWIMFileParameters

			if ($null -eq $ExpandResult) {
				Write-Log -Message "Failed to mount or extract WIM file [$ImagePath] in path [$MountPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70111 }
					throw "Failed to mount or extract  WIM file [$ImagePath] in path [$MountPath]: $($_.Exception.Message)"
				}
			}
		}

		## Recheck Zero-Config Installation after mount/expand
		if ($MountPath = $dirFiles) {
			Invoke-Command -ScriptBlock $CheckZeroConfigInstallation -NoNewScope
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
		Microsoft.Dism.Commands.BaseDismObject or PSCustomObject previously generated by Mount-WIMFile.
	.PARAMETER AlternativeMountPath
		Microsoft.Dism.Commands.BaseDismObject or PSCustomObject previously generated by Mount-WIMFile.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		ImageObject generated by Mount-WIMFile function.
	.OUTPUTS
		None
		This function does not generate any output.
	.EXAMPLE
		Dismount-WIMFile -ImageObject $MountedWIMObject
	.NOTES
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
		$ImageObject,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$AlternativeMountPath = $dirFiles,
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
			[IO.FileInfo]$DismountPath = [IO.Path]::GetFullPath($ImageObject.Path)
		}
		elseif ($ImageObject -is [PSCustomObject]) {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "Input object detected as [PSCustomObject] object type." -Source ${CmdletName} }
			if ([string]::IsNullOrWhiteSpace($ImageObject.Path)) {
				Write-Log -Message "Input object contains a null or empty path attribute." -Severity 3 -Source ${CmdletName}
				if (-not $ContinueOnError) {
					if ($configWIMFileGeneralOptions.ExitScriptOnError) { Exit-Script -ExitCode 70112 }
					throw "Input object contains a null or empty path attribute."
				}
			}
			else {
				[IO.FileInfo]$DismountPath = [IO.Path]::GetFullPath($ImageObject.Path)
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
		elseif ($AlternativeMountPath) {
			Write-Log -Message "Input object not detected, using alternative mount path [$AlternativeMountPath]." -Severity 2 -Source ${CmdletName}
			[IO.FileInfo]$DismountPath = [IO.Path]::GetFullPath($AlternativeMountPath)
		}

		## Remove the mounted path
		if (Test-Path -Path $DismountPath -ErrorAction SilentlyContinue) {

			#  Check if there is a mounted wim file
			if ($IsAdmin) { $MountedImage = Get-WindowsImage -Mounted | Where-Object { [IO.Path]::GetFullPath($_.Path).StartsWith($DismountPath.DirectoryName) } }
			if ($MountedImage) {
				[IO.FileInfo]$ImagePath = $MountedImage.ImagePath
				try {
					$null = Dismount-WindowsImage -Path $DismountPath -Discard
					if ($?) {
						if (-not ($DisableFunctionLogging)) { Write-Log -Message "Successfully dismounted WIM file [$ImagePath] from mount path [$DismountPath]." -Source ${CmdletName} }

						#  Deleting previously created Remediation Task no longer needed
						Remove-RemediationDismountTask -ImagePath $ImagePath
					}
				}
				catch {
					#  Dismount failed, a scheduled task will be created to remediate the situation on startup
					Write-Log -Message "Unable to dismount the WIM file [$ImagePath] from mount path [$DismountPath].`r`n$(Resolve-Error)" -Severity 3 -Source ${CmdletName}

					New-RemediationDismountTask -ImagePath $ImagePath -DismountPath $DismountPath
				}
			}
			elseif ($ImageObject -is [Microsoft.Dism.Commands.BaseDismObject]) {
				Write-Log -Message "No mounted WIM file found in path [$DismountPath], already dismounted?" -Severity 2 -Source ${CmdletName}
			}

			#  Remove the folder
			if ($configWIMFileGeneralOptions.DeleteAlternativeMountPathWhenDismount) {
				if (-not ($DisableFunctionLogging)) { Write-Log -Message "The mount path [$DismountPath] and all its content will be deleted." -Source ${CmdletName} }
				Remove-Folder -Path $DismountPath
			}
		}
		else {
			Write-Log -Message "The mount path [$DismountPath] does not exist, already dismounted and deleted?" -Severity 2 -Source ${CmdletName}
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
	.PARAMETER ImagePath
		Absolute path to the WIM file to be dismounted.
	.PARAMETER DismountPath
		Specifies the absolute path to the mount folder.
	.PARAMETER ContinueOnError
		Continue if an error occured while trying to start the process. Default: $false.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$ImagePath,
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$DismountPath,
		[boolean]$ContinueOnError = $false,
		[switch]$DisableFunctionLogging
	)

	Begin {
		## Get the name of this function and write header
		[string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
		Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header

		## Deleting previously created Remediation Task no longer needed
		Remove-RemediationDismountTask -ImagePath $ImagePath

		## Force function logging if debugging
		if ($configToolkitLogDebugMessage) { $DisableFunctionLogging = $false }
	}
	Process {
		## Creates remediation scheduled task
		#  Remove illegal characters from the scheduled task name
		[char[]]$invalidScheduledTaskChars = '$', '!', '''', '"', '(', ')', ';', '\', '`', '*', '?', '{', '}', '[', ']', '<', '>', '|', '&', '%', '#', '~', '@', ' '
		$ScheduledTaskName = "Remediation_dismount_WIM_file_$($ImagePath.Name)"
		foreach ($invalidChar in $invalidScheduledTaskChars) { $ScheduledTaskName = $ScheduledTaskName -replace [regex]::Escape($invalidChar), "" }

		#  Defines the action to execute
		$ActionVariables = @'
[IO.FileInfo]$ImagePath = "{0}"
[IO.FileInfo]$DismountPath = "{1}"
$ScheduledTaskName = "{2}"
'@ -f ( <#0#> $ImagePath), ( <#1#> $DismountPath), ( <#2#> $ScheduledTaskName)
		$ActionScript = @'
Function Get-MountedImages {
	Param ( [IO.FileInfo]$ImageName = $ImagePath.Name, [IO.FileInfo]$Path = $DismountPath )
	Get-WindowsImage -Mounted | Where-Object { $_.MountStatus -eq "Invalid" -or $_.ImagePath.EndsWith($ImageName) -or [IO.Path]::GetFullPath($_.Path).StartsWith($Path.DirectoryName) }
}

$MountedImages = Get-MountedImages

foreach ($MountedImage in $MountedImages) {
	try { 
		Dismount-WindowsImage -Path $MountedImage.Path -Discard
		if ($?) {
			[IO.Directory]::Delete($MountedImage.Path, $true)
		}
	}
	catch { Clear-WindowsCorruptMountPoint }
}

$MountedImages = Get-MountedImages

if ($null -eq $MountedImages) {
	Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false
}
'@
		$TaskAction = $ActionVariables + "`r`n" + $ActionScript

		#  Parameters definition for the scheduled task
		$ScheduledTaskParameters = @{
			TaskName    = $ScheduledTaskName
			Principal   = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -RunLevel Highest #NT AUTHORITY\SYSTEM
			Action      = New-ScheduledTaskAction -Execute "$($PSHome)\powershell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($TaskAction)))"
			Description = "Remediation task that will dismount invalid mount status or any mount point of [$($ImagePath.Name)] or any image mounted inside [$($DismountPath.DirectoryName)]."
			Settings    = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -WakeToRun
			Trigger     = New-ScheduledTaskTrigger -AtStartup
			Force       = $true
		}

		#  Register scheduled task
		try {
			if (-not ($DisableFunctionLogging)) { Write-Log -Message "The remediation scheduled task [$ScheduledTaskName] will be created." -Source ${CmdletName} }
			$null = Register-ScheduledTask @ScheduledTaskParameters
			if ($?) {
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
	.PARAMETER ImagePath
		Absolute path to the WIM file to be dismounted.
	.PARAMETER DisableFunctionLogging
		Disables logging messages to the script log file.
	.INPUTS
		None
		You cannot pipe objects to this function.
	.OUTPUTS
		None
		This function does not generate any output.
	.NOTES
		This is an internal script function and should typically not be called directly.
		Author: Leonardo Franco Maragna
		Part of WIM File Extension
	.LINK
		https://github.com/LFM8787/PSADT.WIMFile
		https://psappdeploytoolkit.com
		http://psappdeploytoolkit.com
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()]
		[IO.FileInfo]$ImagePath,
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
		$ScheduledTaskName = "Remediation_dismount_WIM_file_$($ImagePath.Name)"
		foreach ($invalidChar in $invalidScheduledTaskChars) { $ScheduledTaskName = $ScheduledTaskName -replace [regex]::Escape($invalidChar), "" }

		$RemediationDismountTask = Get-ScheduledTask | Where-Object { $_.TaskName -like "*$($ScheduledTaskName)*" } -ErrorAction SilentlyContinue
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
				Write-Log -Message "Unable to delete the remediation task [$($RemediationDismountTask.TaskName)]. Remember it deletes itself when running.`r`n$(Resolve-Error)" -Severity 2 -Source ${CmdletName}
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