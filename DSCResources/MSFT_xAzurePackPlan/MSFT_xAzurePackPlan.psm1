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
        [System.String]
        [string]$AuthenticationSite,

        [parameter(Mandatory = $true)]
        [System.String]
        $AdminUri,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [parameter(Mandatory = $true)]
        [System.String]
        $CloudName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMMServerName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $PlanName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName = "systemcenter",

        [String[]]
        $VmNetworkNames
    )
    
    Import-Module 'MgmtSvcAdmin'
    Import-Module 'MgmtSvcConfig'
    
    $TokenTry = 0
    While (!($Token) -and ($TokenTry -lt 5)) {
        $Token = Get-MgmtSvcToken -Type Windows -AuthenticationSite $AuthenticationSite -ClientRealm 'http://azureservices/AdminSite' -DisableCertificateValidation
        If (!($Token)) {
            Start-Sleep 5
            $TokenTry++
        }
    }
    
    if($Token -eq $null)
    {
        throw New-TerminatingError -ErrorType RetrieveTokenFailed -ErrorCategory ObjectNotFound 
    }

    $returnValue = @{
        Ensure = "Absent"
        AdminUri = $AdminUri
        CloudName = $CloudName
        VMMServerName = $VMMServerName
        PlanName = $PlanName
    }
    
    $plan = Get-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName
    
    if($plan -and $plan.ServiceQuotas -and $plan.ConfigState -eq "Configured")
    {
        $planRP = $plan.ServiceQuotas | where ServiceName -eq $RPServiceName
        if($planRP)
        {
            $returnValue = @{
                Ensure = "Present"
                AdminUri = $AdminUri
                CloudName = $CloudName
                VMMServerName = $VMMServerName
                PlanName = $PlanName
            }
        }            
    }

    $returnValue
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        [string]$AuthenticationSite,

        [parameter(Mandatory = $true)]
        [System.String]
        $AdminUri,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [parameter(Mandatory = $true)]
        [System.String]
        $CloudName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMMServerName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $PlanName,
        
        [System.String]
        $CustomSetting = "DRAddOn",

        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName = "systemcenter",

        [String[]]
        $VmNetworkNames
    )
    
    $CloudId = GetCloudId -VMMserverName $VMMServerName -CloudName $CloudName 
    
	#SPF Cmdlet Get-SCSPFStamp requires CredSsp authetication and credentials. This is the reason we are assming that SPF is installed on local server
    Write-Verbose "Going to retrieve StampID from local SPF" -Verbose
    Import-Module 'spfadmin' -ErrorAction Stop
    $stamp = Get-SCSPFStamp -ErrorAction Stop
    $StampId = $stamp.Id   
    Write-Verbose "Got StampID: $StampId from local SPF" -Verbose

    Import-Module 'MgmtSvcAdmin' -ErrorAction Stop
    Import-Module 'MgmtSvcConfig' -ErrorAction Stop
    
    $TokenTry = 0
    While (!($Token) -and ($TokenTry -lt 5)) {
        $Token = Get-MgmtSvcToken -Type Windows -AuthenticationSite $AuthenticationSite -ClientRealm 'http://azureservices/AdminSite' -DisableCertificateValidation
        If (!($Token)) {
            Start-Sleep 5
            $TokenTry++
        }
    }
    
    if($Token -eq $null)
    {
        throw New-TerminatingError -ErrorType RetrieveTokenFailed -ErrorCategory ObjectNotFound 
    }

    switch($Ensure)
    {
        "Present"
        {
            # Retrieve the System Center resource provider config data (the System Center resource provider should already exist in the Management Service node)
            $systemCenterRP = Get-MgmtSvcResourceProvider -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -name $RPServiceName
            Write-Verbose "Trying to get existing Plan(if any) by name: $PlanName " -Verbose 
            $plan = Get-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName
            if($plan)
            {
                Write-Verbose "Trying to remove existing Plan by ID: $($plan.Id) " -Verbose 
                Remove-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -PlanId $plan.Id -ErrorAction Stop
            }

			Write-Verbose "Trying to Get All Templates and VMNetworks from VMM to add into Plan quota settings: $($newPlan.Id) " -Verbose 

		    $ResourceQuotas = Invoke-Command -ComputerName $VMMServerName {
                 $stampId = $args[0]
			     Import-Module VirtualMachineManager -ErrorAction Stop
                 $vmm = Get-SCVMMServer -ComputerName 'localhost' -ErrorAction Stop
                 $templates = Get-SCVMTemplate -ErrorAction Stop
				 $templateQuotas = @()
                 $templates | Foreach-Object { $templateQuotas += "<VmTemplate Id='$($_.ID)' StampId='$stampId'/>" }       
				 $templateQuotas
            } -ArgumentList @($StampId)

		    $NetworkQuotas = Invoke-Command -ComputerName $VMMServerName {
                 $stampId = $args[0]
				 $vmNetworkNames = $args[1]
			     Import-Module VirtualMachineManager -ErrorAction Stop
                 $vmm = Get-SCVMMServer -ComputerName 'localhost' -ErrorAction Stop

				 $networkQuotas = @()
				 $vmNetworkNames | Foreach-Object {
				    $vmn = Get-SCVMNetwork -Name $_
					if($vmn) { $networkQuotas += "<Network Id='$($vmn.ID)' StampId='$stampId'/>" }    
				 }
                 
				 $networkQuotas
            } -ArgumentList @($StampId,$VmNetworkNames)


			Write-Verbose "Resource Quotas $($ResourceQuotas.Count)" -Verbose

            Write-Verbose "Trying to Create New Plan: $PlanName " -Verbose 
            $newPlan = Add-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName -State Public -ErrorAction Stop
            Write-Verbose "Trying to Add Service into Plan: $($newPlan.Id) " -Verbose 
            Add-MgmtSvcPlanService -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -PlanId $newPlan.Id -ServiceName $RPServiceName -InstanceId $systemCenterRP.InstanceId -ErrorAction Stop

            Write-Verbose "Trying to Create Quota Settings Plan: $($newPlan.Id) " -Verbose  

            $quotaList = CreateQuotaSettings -ResourceProvider $systemCenterRP -StampId $StampId -CloudId $CloudId -ResourceQuotas $ResourceQuotas -NetworkQuotas $NetworkQuotas
            
            Write-Verbose "Trying to Update Plan with Quota Settings: $($newPlan.Id) " -Verbose  
            Update-MgmtSvcPlanQuota -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -PlanId $newPlan.Id -QuotaList $QuotaList -Verbose -ErrorAction Stop 
        }
        "Absent"
        {
            $plan = Get-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName
            if($plan)
            {
                Remove-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -PlanId $plan.Id
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
        [System.String]
        [string]$AuthenticationSite,

        [parameter(Mandatory = $true)]
        [System.String]
        $AdminUri,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",

        [parameter(Mandatory = $true)]
        [System.String]
        $CloudName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMMServerName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $PlanName,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName = "systemcenter",

        [String[]]
        $VmNetworkNames
    )

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

    $result
}


Export-ModuleMember -Function *-TargetResource