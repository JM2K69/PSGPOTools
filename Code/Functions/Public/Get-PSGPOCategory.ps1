function Get-PSGPOCategory {
    [cmdletbinding()]
    Param()

    ### VAR ###
    ### MAIN ###
    $Categories =  [GpoToolsUtility]::Categories
    If ($Categories.Count -eq 0){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }Else{
        return $Categories
    }
}