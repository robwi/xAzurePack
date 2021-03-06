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

		[parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
		$Passphrase = $SetupCredential,

		[System.String]
		$SQLServer = "localhost",

		[System.String]
		$SQLInstance = "MSSQLSERVER",

		[System.Management.Automation.PSCredential]
		$dbUser,

		[System.String]
		$EnableCeip = "No"
	)

	$returnValue = @{
		Role = $Role
		SQLServer = $SQLServer
		SQLInstance = $SQLInstance
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

        [parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$Passphrase = $SetupCredential,

		[System.String]
		$SQLServer = "localhost",

		[System.String]
		$SQLInstance = "MSSQLSERVER",

		[System.Management.Automation.PSCredential]
		$dbUser,

		[System.String]
		$EnableCeip = "No"
	)

    if($EnableCeip -ne "Yes")
    {
        $EnableCeip = "No"
    }
    $Features = GetWAPFeatures -Role $Role
    $ConfigStorePassphrase = $Passphrase.GetNetworkCredential().Password
    foreach($Feature in $Features)
    {
        Write-Verbose "Feature: $Feature"
        if (!(Get-MgmtSvcFeature -Name $Feature).Configured)
        {
            if($SQLInstance -eq "MSSQLSERVER")
            {
                $Server = $SQLServer
            }
            else
            {
                $Server = "$SQLServer\$SQLInstance"
            }
            if ([string]::IsNullOrEmpty($dbUser))
            {
                Initialize-MgmtSvcFeature -Name $Feature -Passphrase "$ConfigStorePassphrase" -EnableCeip $EnableCeip -Server $Server
            }
            else
            {
                Initialize-MgmtSvcFeature -Name $Feature -Passphrase "$ConfigStorePassphrase" -EnableCeip $EnableCeip -Server $Server -UserName $dbUser.UserName -Password $dbUser.GetNetworkCredential().Password
            }
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

        [parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$Passphrase = $SetupCredential,

		[System.String]
		$SQLServer = "localhost",

		[System.String]
		$SQLInstance = "MSSQLSERVER",

		[System.Management.Automation.PSCredential]
		$dbUser,

		[System.String]
		$EnableCeip = "No"
	)

    $result = $true
    $Features = GetWAPFeatures -Role $Role
    foreach($Feature in $Features)
    {
        if($result)
        {
            Write-Verbose "Feature: $Feature"
            $result = (Get-MgmtSvcFeature -Name $Feature).Configured
            Write-Verbose "Configured: $result"
        }
    }

	$result
}


function GetWAPFeatures
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
                "AdminAPI",
                "WebAppGallery",
                "Monitoring",
                "UsageCollector",
                "UsageService"
            )
        }
        "Tenant API"
        {
            return @(
                "TenantAPI"
            )
        }
        "Tenant Public API"
        {
            return @(
                "TenantPublicAPI"
            )
        }
        "SQL Server Extension"
        {
            return @(
                "SQLServer"
            )
        }
        "MySQL Extension"
        {
            return @(
                "MySQL"
            )
        }
        "Admin Site"
        {
            return @(
                "AdminSite"
            )
        }
        "Admin Authentication Site"
        {
            return @(
                "WindowsAuthSite"
            )
        }
        "Tenant Site"
        {
            return @(
                "TenantSite"
            )
        }
        "Tenant Authentication Site"
        {
            return @(
                "AuthSite"
            )
        }
    }
}


Export-ModuleMember -Function *-TargetResource