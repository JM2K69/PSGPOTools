<#
.Synopsis
   This function return all GPO parameter
.DESCRIPTION
   This function return all GPO parameter, you can choose a Scope Machine or User
.EXAMPLE
   PS> Get-PSGPOPolicy
.EXAMPLE
    PS> Get-PSGPOPolicy -Scope Machine
.EXAMPLE
    PS> Get-PSGPOPolicy -ScopeUser
.NOTES
   The fuction return all GPO parameter found in all Admx with the Adml with the OSCulture
#>

function Get-PSGPOPolicy {
    [cmdletbinding()]
    Param(
        [Parameter (Mandatory = $false)]
        [ValidateSet('Machine','User')]
        [string]$Scope

    )

   begin
   {
    $Policies =  [GpoToolsUtility]::Policies
   }
   process{

    if ( $PsBoundParameters.ContainsKey('Scope') ) {
        switch ($Scope) {
            'Machine' {  $Policies = $Policies| Where-Object {$_.Scope -eq 'Machine'} }
            'User'{ $Policies = $Policies| Where-Object {$_.Scope -eq 'User'} }
            Default {}
        }
    }
    If ($null -eq $Policies){
        Write-Warning "Initiate ADMX and ADML files with Initialize-PSGPOAdmx cmdlet."
    }
   }
   end
   {
       return $Policies
    }

}