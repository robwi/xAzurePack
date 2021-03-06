# NOTE: This resource requires WMF5 and PsDscRunAsCredential

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
        [ValidateSet("AdminSite","TenantSite")]
		[System.String]
		$Namespace,

		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
        $Value,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    if($SQLInstance -eq "MSSQLSERVER")
    {
        $ConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
    }
    else
    {
        $ConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
    }

    $Value = (Get-MgmtSvcDatabaseSetting -Namespace $Namespace -Name $Name -ConnectionString $ConnectionString).Value

    $returnValue = @{
        Name = $Name
        Value = $Value
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
        [ValidateSet("AdminSite","TenantSite")]
		[System.String]
		$Namespace,

		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
        $Value,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

   
    if($SQLInstance -eq "MSSQLSERVER")
    {
        $ConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
    }
    else
    {
        $ConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
    }

    Set-MgmtSvcDatabaseSetting -Namespace $Namespace -Name $Name -Value $Value -ConnectionString $ConnectionString -Force

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
        [ValidateSet("AdminSite","TenantSite")]
		[System.String]
		$Namespace,

		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[parameter(Mandatory = $true)]
		[System.String]
        $Value,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    $result = ((Get-TargetResource @PSBoundParameters).Value -eq $Value)

	$result
}


Export-ModuleMember -Function *-TargetResource