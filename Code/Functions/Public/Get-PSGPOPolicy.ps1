function Get-PSGPOPolicy {
    [cmdletbinding()]
    Param(
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    ### VAR ###
    ### MAIN ###
    $Policies =  [GpoToolsUtility]::Policies
    If ($Policies.Count -eq 0){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }ElseIf ($PSBoundParameters.ContainsKey('Scope')){
        return $Policies | Where-Object { $_.Scope -eq $Scope }
    }Else{
        return $Policies
    }
}
