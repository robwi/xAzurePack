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
        $AddOnName,
        
        [System.String]
        $CustomSetting = "DREnabled",      
        
        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName
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
        AddOnName = $AddOnName
    }
    
    $plan = Get-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName
    $addOn = Get-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $AddOnName
    
    if($addOn -and $addOn.ConfigState -eq "Configured" -and $addOn.ServiceQuotas)
    {
        if($addOn.ServiceQuotas.ServiceName -eq $RPServiceName)
        {
            #Check if AddOn is attached to Plan
            $foundAddOn = $plan.AddOns | where DisplayName -eq $AddOnName
            if($foundAddOn)
            {            
                $returnValue = @{
                    Ensure = "Present"
                    AdminUri = $AdminUri
                    CloudName = $CloudName
                    VMMServerName = $VMMServerName
                    PlanName = $PlanName
                    AddOnName = $AddOnName
                }
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
        
        [parameter(Mandatory = $true)]
		[System.String]
        $AddOnName,
        
        [System.String]
        $CustomSetting = "DREnabled",      
        
        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName
    )
    
    $CloudId = GetCloudId -VMMserverName $VMMServerName -CloudName $CloudName 

    
    Import-Module 'spfadmin' -ErrorAction Stop
    $stamp = Get-SCSPFStamp -ErrorAction Stop
    $StampId = $stamp.Id   

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
		    Write-Verbose "Get AddOn $AddOnName to check if it already exists in NotConifgured State" -Verbose
            $addOn = Get-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $AddOnName
            if($addOn -and $addOn.ConfigState -ne "Configured")
            {
			    Write-Verbose "Found $AddOnName AddOn in NotConifgured State. So deleting and creating new one" -Verbose
                Remove-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -AddOnId $addOn.Id
                $addOn = Add-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $AddOnName -State Public
            }
            if(!$addOn)
            {
                Write-Verbose "AddOn $AddOnName Not found. Creating new one" -Verbose
                $addOn = Add-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $AddOnName -State Public
            }        
        
            $plan = Get-MgmtSvcPlan -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $PlanName

            # Retrieve the System Center resource provider config data (the System Center resource provider should already exist in the Management Service node)
            $systemCenterRP = Get-MgmtSvcResourceProvider -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -name $RPServiceName
            
			#Check if RP is already asociated
			Write-Verbose "Check if RP $RPServiceName already associated with AddOn $AddOnName" -Verbose
			if(!$addOn.ServiceQuotas -or $addOn.ServiceQuotas.ServiceName -ne $RPServiceName)
			{
			    Write-Verbose "Associating RP $RPServiceName with AddOn $AddOnName" -Verbose
                Add-MgmtSvcAddOnService -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -AddOnId $addOn.Id -ServiceName $RPServiceName -InstanceId $systemCenterRP.InstanceId
		    }
            #Update the Quotas always
			Write-Verbose "Creating Quota for RP $($systemCenterRP.Name) Stamp: $StampId and CloudID: $CloudId" -Verbose
            $quotaList = CreateQuotaSettings -ResourceProvider $systemCenterRP -StampId $StampId -CloudId $CloudId -CustomSetting "DREnabled"               
            Write-Verbose "Creating Quota for RP $RPServiceName and AddOn $AddOnName" -Verbose
			Update-MgmtSvcAddOnQuota $AdminUri $token -DisableCertificateValidation -AddOnId $addOn.Id -QuotaList $quotaList -Verbose 
            
			#Associate AddOn with Plan
            $addOn = Get-MgmtSvcAddOn -AdminUri $AdminUri -Token $token -DisableCertificateValidation -DisplayName $addOnName                          
            Write-Verbose "Associating AddOn $AddOnName with Plan $PlanName" -Verbose
			Add-MgmtSvcPlanAddOn -AdminUri $AdminUri -Token $token -AddOnId $addOn.Id -PlanId $plan.Id -DisableCertificateValidation -Confirm:$false            
        }
        "Absent"
        {            
            $addOn = Get-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -DisplayName $AddOnName
            if($addOn)
            {
                Remove-MgmtSvcAddOn -AdminUri $AdminUri -Token $Token -DisableCertificateValidation -AddOnId $addOn.Id
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
        $AddOnName,
        
        [System.String]
        $CustomSetting = "DREnabled",
        
        [parameter(Mandatory = $true)]
        [System.String]
        $RPServiceName
    )

    $result = ((Get-TargetResource @PSBoundParameters).Ensure -eq $Ensure)

    $result
}


Export-ModuleMember -Function *-TargetResource