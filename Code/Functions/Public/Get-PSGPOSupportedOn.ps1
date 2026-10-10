function Get-PSGPOSupportedOn {
    [cmdletbinding()]
    Param()

    ### VAR ###
    ### MAIN ###
    $Support =  [GpoToolsUtility]::SupportOnTable
    If ($Support.Count -eq 0){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Support
    }
}