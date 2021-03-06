$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xAzurePackHelper.psm1 -Verbose:$false -ErrorAction Stop

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Admin API","Tenant API","Tenant Public API","SQL Server Extension","MySQL Extension","Admin Site","Admin Authentication Site","Tenant Site","Tenant Authentication Site")]
		[System.String]
		$Role,

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

	$returnValue = @{
		Role = $Role
		SourcePath = $SourcePath
		SourceFolder = $SourceFolder
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Admin API","Tenant API","Tenant Public API","SQL Server Extension","MySQL Extension","Admin Site","Admin Authentication Site","Tenant Site","Tenant Authentication Site")]
		[System.String]
		$Role,

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

    Import-Module $PSScriptRoot\..\..\xPDT.psm1
        
    if($SourceCredential)
    {
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        $TempFolder = [IO.Path]::GetTempPath()
        & robocopy.exe (Join-Path -Path $SourcePath -ChildPath $SourceFolder) (Join-Path -Path $TempFolder -ChildPath $SourceFolder) /e
        $SourcePath = $TempFolder
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
    }
    $Path = "msiexec.exe"
    $Path = ResolvePath $Path
    Write-Verbose "Path: $Path"

    $TempPath = [IO.Path]::GetTempPath().TrimEnd("\")
    $Products = (Get-WmiObject -Class Win32_Product).IdentifyingNumber
    $Components = GetWAPComponents -Role $Role
    foreach($Component in $Components)
    {
        $ComponentInstalled = $true
        if($ComponentInstalled)
        {
            $IdentifyingNumber = GetxPDTVariable -Component "AzurePack" -Role "$Component" -Version "Default" -Name "IdentifyingNumber"
            if(!($Products | Where-Object {$_ -eq $IdentifyingNumber}))
            {
                $MSIPath = ResolvePath "$SourcePath\$SourceFolder\$Component.msi"
                Copy-Item -Path $MSIPath -Destination $TempPath
                $Arguments = "/q /lv $TempPath\$Component.log /i $TempPath\$Component.msi ALLUSERS=2"
                Write-Verbose "Arguments: $Arguments"
                $Process = StartWin32Process -Path $Path -Arguments $Arguments -Credential $SetupCredential
                Write-Verbose $Process
                WaitForWin32ProcessEnd -Path $Path -Arguments $Arguments -Credential $SetupCredential
                Remove-Item -Path "$TempPath\$Component.msi"
                $ComponentInstalled = GetComponentInstalled -Products $Products -IdentifyingNumbers $IdentifyingNumbers
            }
        }
    }

    if($ForceReboot -or ((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) -ne $null))
    {
	    if(!($SuppressReboot))
        {
            $global:DSCMachineStatus = 1
        }
        else
        {
            Write-Verbose "Suppressing reboot"
        }
    }

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[ValidateSet("Admin API","Tenant API","Tenant Public API","SQL Server Extension","MySQL Extension","Admin Site","Admin Authentication Site","Tenant Site","Tenant Authentication Site")]
		[System.String]
		$Role,

		[System.String]
		$SourcePath = "$PSScriptRoot\..\..\",

		[System.String]
		$SourceFolder = "Source",

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$SetupCredential,

		[System.Management.Automation.PSCredential]
		$SourceCredential,

		[System.Boolean]
		$SuppressReboot,

		[System.Boolean]
		$ForceReboot
	)

    Import-Module $PSScriptRoot\..\..\xPDT.psm1
            
    $result = $true
    $Products = (Get-WmiObject -Class Win32_Product).IdentifyingNumber
    $Components = GetWAPComponents -Role $Role
    foreach($Component in $Components)
    {
        if($result)
        {
            $IdentifyingNumber = GetxPDTVariable -Component "AzurePack" -Role "$Component" -Version "Default" -Name "IdentifyingNumber"
            if(!($Products | Where-Object {$_ -eq $IdentifyingNumber}))
            {
                $result = $false
            }
        }
    }

	$result
}


function GetWAPComponents
{
    param
    (
        [String]
        $Role
    )

    switch($Role)
    {
        "Admin API"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-WebAppGallery",
                "MgmtSvc-Monitoring",
                "MgmtSvc-Usage",
                "MgmtSvc-AdminAPI"
            )
        }
        "Tenant API"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-TenantAPI"
            )
        }
        "Tenant Public API"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-TenantPublicAPI"
            )
        }
        "SQL Server Extension"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-SQLServer"
            )
        }
        "MySQL Extension"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-MySQL"
            )
        }
        "Admin Site"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-AdminSite"
            )
        }
        "Admin Authentication Site"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-WindowsAuthSite"
            )
        }
        "Tenant Site"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-TenantSite"
            )
        }
        "Tenant Authentication Site"
        {
            return @(
                "MgmtSvc-PowerShellAPI",
                "MgmtSvc-AuthSite"
            )
        }
    }
}


Export-ModuleMember -Function *-TargetResource