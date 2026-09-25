function Get-PSGPOPolicy {
    [cmdletbinding()]
    Param(
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    ### VAR ###
    ### MAIN ###
    $Policies =  [GpoToolsUtility]::Policies
    if (![string]::IsNullOrWhiteSpace($Scope)) {
        $Policies = $Policies | Where-Object { $_.Scope -eq $Scope }
    }

    If ($null -eq $Policies){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Policies
    }
}