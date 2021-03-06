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
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[System.String]
		$Principal,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    if($SQLInstance -eq "MSSQLSERVER")
    {
        $ConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True"
    }
    else
    {
        $ConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True"
    }

    if(Get-MgmtSvcAdminUser -Principal $Principal -ConnectionString $ConnectionString)
    {
        $Ensure = "Present"
    }
    else
    {
        $Ensure = "Absent"
    }

    $returnValue = @{
        Ensure = $Ensure
        Principal = $Principal
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
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[System.String]
		$Principal,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    if($SQLInstance -eq "MSSQLSERVER")
    {
        $ConnectionString = "Data Source=$SQLServer;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True"
    }
    else
    {
        $ConnectionString = "Data Source=$SQLServer\$SQLInstance;Initial Catalog=Microsoft.MgmtSvc.Store;Integrated Security=True"
    }

    switch($Ensure)
    {
        "Present"
        {
            if(!(Get-MgmtSvcAdminUser -Principal $Principal -ConnectionString $ConnectionString))
            {
                Add-MgmtSvcAdminUser -Principal $Principal -ConnectionString $ConnectionString
            }
        }
        "Absent"
        {
            if(Get-MgmtSvcAdminUser -Principal $Principal -ConnectionString $ConnectionString)
            {
                Remove-MgmtSvcAdminUser -Principal $Principal -ConnectionString $ConnectionString
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
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",

		[parameter(Mandatory = $true)]
		[System.String]
		$Principal,

		[parameter(Mandatory = $true)]
		[System.String]
		$SQLServer,

		[System.String]
		$SQLInstance = "MSSQLSERVER"
	)

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

	$result
}


Export-ModuleMember -Function *-TargetResource