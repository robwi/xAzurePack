# Set Global Module Verbose
$VerbosePreference = 'Continue' 

# Load Localization Data 
Import-LocalizedData LocalizedData -filename xAzurePack.strings.psd1 -ErrorAction SilentlyContinue
Import-LocalizedData USLocalizedData -filename xAzurePack.strings.psd1 -UICulture en-US -ErrorAction SilentlyContinue

function New-TerminatingError 
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $ErrorType,

        [parameter(Mandatory = $false)]
        [String[]]
        $FormatArgs,

        [parameter(Mandatory = $false)]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory = [System.Management.Automation.ErrorCategory]::OperationStopped,

        [parameter(Mandatory = $false)]
        [Object]
        $TargetObject = $null
    )

    $errorMessage = $LocalizedData.$ErrorType
    
    if(!$errorMessage)
    {
        $errorMessage = ($LocalizedData.NoKeyFound -f $ErrorType)

        if(!$errorMessage)
        {
            $errorMessage = ("No Localization key found for key: {0}" -f $ErrorType)
        }
    }

    $errorMessage = ($errorMessage -f $FormatArgs)

    $callStack = Get-PSCallStack 

    # Get Name of calling script
    if($callStack[1] -and $callStack[1].ScriptName)
    {
        $scriptPath = $callStack[1].ScriptName

        $callingScriptName = $scriptPath.Split('\')[-1].Split('.')[0]
    
        $errorId = "$callingScriptName.$ErrorType"
    }
    else
    {
        $errorId = $ErrorType
    }


    Write-Verbose -Message "$($USLocalizedData.$ErrorType -f $FormatArgs) | ErrorType: $errorId"

    $exception = New-Object System.Exception $errorMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $ErrorCategory, $TargetObject

    return $errorRecord
}

function GetCloudID
{
    [CmdletBinding()] 
    param 
    ( 
        [parameter(Mandatory = $true)]
        [string]$VMMserverName,

        [parameter(Mandatory = $true)]
        [string]$CloudName
    )
    
    $CloudID = Invoke-Command -ComputerName $VMMserverName {
                  Import-Module VirtualMachineManager -ErrorAction Stop
                  $vmm = Get-SCVMMServer -ComputerName 'localhost' -ErrorAction Stop
                  $cloud = Get-SCCloud -Name $args[0] -ErrorAction Stop
                  $cloud.ID       
               } -ArgumentList @($CloudName)
    $CloudID
}

function CreateQuotaSettings
{
    [CmdletBinding()] 
    param 
    ( 
        [parameter(Mandatory = $true)]
        [string]$StampId,
        
        [parameter(Mandatory = $true)]
        [string]$CloudId,        
        
        [parameter(Mandatory = $true)]
        [object]$ResourceProvider,        

		[string[]]$ResourceQuotas,        

		[string[]]$NetworkQuotas,      
        
        [string]$CustomSetting        

    )   

    $serviceName = $ResourceProvider.Name
    $serviceDisplayName = $ResourceProvider.DisplayName
    $serviceInstanceDisplayName = $ResourceProvider.InstanceDisplayName
	$ServiceInstanceId = $ResourceProvider.InstanceId
	
    #$customSettings="DREnabled"

    # Add Quotas to the AddOn created
    $QuotaList = New-MgmtSvcQuotaList

    $quota = Add-MgmtSvcListQuota -QuotaList $QuotaList -ServiceName $serviceName -ServiceInstanceId $ServiceInstanceId
    $quota.ServiceDisplayName = $serviceDisplayName
    $quota.ServiceInstanceDisplayName = $serviceInstanceDisplayName

    # quota settings (for System Center, these values are complex and depend upon the environment; one example shown for each)

    $quotaSettingKey1 = "Actions"
    $quotaSettingValue1 = "<Actions><Stamp Id='" + $StampId + "'><Action>Author</Action><Action>Create</Action><Action>CreateFromVHDOrTemplate</Action><Action>AllowLocalAdmin</Action><Action>Start</Action><Action>Stop</Action><Action>PauseAndResume</Action><Action>Shutdown</Action><Action>Remove</Action><Action MaximumNetwork='' MaximumMemberNetwork='' MaximumBandwidthIn='' MaximumBandwidthOut='' MaximumVPNConnection='99' MaximumMemberVPNConnection='99'>AuthorVMNetwork</Action></Stamp></Actions>"

    $quotaSettingKey2 = "Clouds"
    $quotaSettingValue2 = "<Clouds><Cloud Id='" + $CloudId + "' StampId='" + $StampId + "'><Quota><RoleVMCount></RoleVMCount><MemberVMCount></MemberVMCount><RoleCPUCount></RoleCPUCount><MemberCPUCount></MemberCPUCount><RoleMemoryMB></RoleMemoryMB><MemberMemoryMB></MemberMemoryMB><RoleStorageGB></RoleStorageGB><MemberStorageGB></MemberStorageGB></Quota></Cloud></Clouds>"

    $quotaSettingKey3 = "VmResources"
	$quotaSettingValue3 = "<Resources></Resources>"
	if($ResourceQuotas)
	{
	    $quotaSettingValue3 = "<Resources>$ResourceQuotas</Resources>"
	}
        
    $quotaSettingKey4 = "Networks"
    $quotaSettingValue4 = "<Networks></Networks>"   
	if($NetworkQuotas)
	{
	    $quotaSettingValue4 = "<Networks>$NetworkQuotas</Networks>"   
	}
    
    $quotaSettingKey5 = "CustomSettings"
    $quotaSettingValue5 = "<CustomSettings>"
    if($CustomSetting)
    {
        $guid = [guid]::NewGuid().Guid.ToString()
        $quotaSettingValue5 = $quotaSettingValue5 + "<CustomSetting Key='" + $guid + "' Value='" + $CustomSetting + "'/>"            
    }        
    $quotaSettingValue5 = $quotaSettingValue5 + "</CustomSettings>"        
    

    $setting1 = Add-MgmtSvcQuotaSetting -Quota $quota -Key $quotaSettingKey1 -Value $quotaSettingValue1
    $setting2 = Add-MgmtSvcQuotaSetting -Quota $quota -Key $quotaSettingKey2 -Value $quotaSettingValue2
    $setting3 = Add-MgmtSvcQuotaSetting -Quota $quota -Key $quotaSettingKey3 -Value $quotaSettingValue3
    $setting4 = Add-MgmtSvcQuotaSetting -Quota $quota -Key $quotaSettingKey4 -Value $quotaSettingValue4
    $setting5 = Add-MgmtSvcQuotaSetting -Quota $quota -Key $quotaSettingKey5 -Value $quotaSettingValue5

    $QuotaList
}
