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
        [ValidateSet("Admin","Tenant")]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
        $FullyQualifiedDomainName,

        [System.UInt16]
        $Port,

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

    switch($Target)
    {
        "Admin"
        {
            $Namespace = "AdminSite"
        }
        "Tenant"
        {
            $Namespace = "TenantSite"
        }
    }
    $FQDN = ((ConvertFrom-Json (Get-MgmtSvcDatabaseSetting -Namespace $Namespace -Name Authentication.IdentityProvider -ConnectionString $ConnectionString).Value).Endpoint).Split("/")[2]

    $returnValue = @{
        Target = $Target
        FullyQualifiedDomainName = $FQDN.Split(":")[0]
        Port = $FQDN.Split(":")[1]
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
        [ValidateSet("Admin","Tenant")]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
        $FullyQualifiedDomainName,

        [System.UInt16]
        $Port,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    if($Port -eq 0)
    {
        Switch($Target)
        {
            "Admin"
            {
                $Port = 30072
            }
            "Tenant"
            {
                $Port = 30071
            }
        }
    }
    
    if($SQLInstance -eq "MSSQLSERVER")
    {
        $PortalConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
        $ManagementConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True";
    }
    else
    {
        $PortalConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.PortalConfigStore;Integrated Security=True";
        $ManagementConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True";
    }

    Set-MgmtSvcRelyingPartySettings -Target $Target -MetadataEndpoint "https://$FullyQualifiedDomainName`:$Port/FederationMetadata/2007-06/FederationMetadata.xml" -PortalConnectionString $PortalConnectionString -ManagementConnectionString $ManagementConnectionString -DisableCertificateValidation;

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
        [ValidateSet("Admin","Tenant")]
		[System.String]
		$Target,

		[parameter(Mandatory = $true)]
		[System.String]
        $FullyQualifiedDomainName,

        [System.UInt16]
        $Port,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    if($Port -eq 0)
    {
        Switch($Target)
        {
            "Admin"
            {
                $Port = 30072
            }
            "Tenant"
            {
                $Port = 30071
            }
        }
    }

    $FQDN = Get-TargetResource @PSBoundParameters
    
    $result = (($FQDN.FullyQualifiedDomainName -eq $FullyQualifiedDomainName) -and ($FQDN.Port -eq $Port))

	$result
}


Export-ModuleMember -Function *-TargetResource