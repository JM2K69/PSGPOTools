#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Group Policy Results and Update (Get-PSGPOResult, Invoke-PSGPOUpdate, PSGPOResult.ps1): what
# gpresult /x and samba-gpupdate --rsop give, read from files the labs made (Fixtures/Rsop: the
# Windows member CLI of powershell.labo, the Samba domain controller of hardenbox.labo), the commands
# run as they are called, mocked.
BeforeDiscovery {
    $ModuleManifest = Join-Path $PSScriptRoot '..' '..' 'HGPM' 'HGPM.psd1'
    Get-Module HGPM | Remove-Module -Force
    Import-Module $ModuleManifest -Force
}

InModuleScope -ModuleName HGPM {
    BeforeAll {
        $Fixtures = Join-Path $PSScriptRoot 'Fixtures' 'Rsop'
        # A gpresult /x of one computer part: two GPOs applied, the others denied for each reason.
        function New-GpresultXml {
            param([string[]]$Gpo)
            @"
<?xml version="1.0" encoding="utf-16"?>
<Rsop xmlns="http://www.microsoft.com/GroupPolicy/Rsop">
  <ReadTime>2026-11-01T14:06:58Z</ReadTime>
  <ComputerResults><Name>CONTOSO\PC01`$</Name><SOM>contoso.com/Workstations</SOM><Site>Lyon</Site>$($Gpo -join '')</ComputerResults>
</Rsop>
"@
        }
        function New-GpoXml {
            param([string]$Name, [int]$Applied = 0, [string]$LinkEnabled = 'true', [string]$Enabled = 'true', [string]$AccessDenied = 'false', [string]$FilterAllowed = 'true', [int]$Version = 3, [string]$Enforced = 'false')
            "<GPO><Name>$Name</Name><Path><Identifier>{$([guid]::NewGuid())}</Identifier></Path><VersionDirectory>$Version</VersionDirectory><VersionSysvol>$Version</VersionSysvol><Enabled>$Enabled</Enabled><IsValid>true</IsValid><FilterAllowed>$FilterAllowed</FilterAllowed><AccessDenied>$AccessDenied</AccessDenied><Link><SOMPath>contoso.com/Workstations</SOMPath><AppliedOrder>$Applied</AppliedOrder><LinkOrder>1</LinkOrder><Enabled>$LinkEnabled</Enabled><NoOverride>$Enforced</NoOverride></Link></GPO>"
        }
    }

    Describe 'Results of gpresult /x' {
        It 'Reads the result of a Windows member, its GPOs, groups and extensions' {
            $Result = Get-PSGPOResult -Path (Join-Path $Fixtures 'gpresult.xml')
            $Result.PSObject.TypeNames | Should -Contain 'PSGPOTools.Result'
            $Result.Source | Should -Be 'gpresult'
            $Result.Computer | Should -Be 'POWERSHELL\CLI$'
            $Result.User | Should -Be 'POWERSHELL\Administrator'
            $Result.Site | Should -Be 'Default-First-Site-Name'
            $Applied = @($Result.ComputerGpos | Where-Object Applied)
            $Applied.Name | Should -Be @('Default Domain Policy')
            $Applied[0].Precedence | Should -Be 1
            $Applied[0].Id | Should -Be ([guid]'31B2F340-016D-11D2-945F-00C04FB984F9')
            $Applied[0].Link | Should -Be 'powershell.labo'
            $Applied[0].SecurityFilter | Should -Be @('NT AUTHORITY\Authenticated Users')
            (@($Result.ComputerGpos | Where-Object Name -EQ 'Local Group Policy')[0]).Reason | Should -Be 'Empty'
            @($Result.UserGpos | Where-Object Applied) | Should -BeNullOrEmpty -Because 'the user part of the Default Domain Policy is empty'
            @($Result.UserGroups.Sid) | Should -Contain 'S-1-5-11'
            @($Result.ComputerExtensions.Name) | Should -Contain 'Security'
        }

        It 'Gives the precedence of GPMC (applied last, wins) and the reason of each GPO denied' {
            $Xml = New-GpresultXml @(
                (New-GpoXml 'Applied first' -Applied 1), (New-GpoXml 'Applied last' -Applied 2 -Enforced 'true'),
                (New-GpoXml 'Link off' -LinkEnabled 'false'), (New-GpoXml 'Status off' -Enabled 'false'), (New-GpoXml 'No access' -AccessDenied 'true'),
                (New-GpoXml 'Filter false' -FilterAllowed 'false'), (New-GpoXml 'Nothing' -Version 0))
            $Rows = @((ConvertFrom-PSGPOGpresultXml -Xml $Xml).ComputerGpos)
            @($Rows | Where-Object Applied | ForEach-Object { "$($_.Precedence) $($_.Name)" }) | Should -Be @('1 Applied last', '2 Applied first')
            ($Rows | Where-Object Name -EQ 'Applied last').Enforced | Should -BeTrue
            @($Rows | Where-Object { -not $_.Applied } | ForEach-Object { "$($_.Name): $($_.Reason)" }) | Should -Be @(
                'Link off: Disabled link', 'Status off: Disabled GPO', 'No access: Denied (security)', 'Filter false: WMI filter false', 'Nothing: Empty')
        }

        It 'Refuses what is not a result of gpresult, or a document with a DTD' {
            { ConvertFrom-PSGPOGpresultXml -Xml '<Other/>' } | Should -Throw '*not the result of gpresult*'
            { ConvertFrom-PSGPOGpresultXml -Xml '<!DOCTYPE x [<!ENTITY a "a">]><Rsop/>' } | Should -Throw '*DTD*'
        }
    }

    Describe 'Results of samba-gpupdate --rsop' {
        It 'Reads the GPOs of a Samba domain controller in the order they apply, and their settings' {
            $Result = Get-PSGPOResult -Path (Join-Path $Fixtures 'rsop-computer.txt') -Scope Computer
            $Result.Source | Should -Be 'samba-gpupdate'
            @($Result.ComputerGpos | ForEach-Object { "$($_.Precedence) $($_.Name)" }) | Should -Be @('1 Default Domain Controllers Policy', '2 Default Domain Policy')
            $Setting = @($Result.Settings | Where-Object Name -EQ 'MinimumPasswordLength')[0]
            $Setting.Gpo | Should -Be 'Default Domain Policy'
            $Setting.Extension | Should -Be 'gp_access_ext'
            $Setting.PolicyType | Should -Be 'System Access'
            $Setting.Value | Should -Be '12'
            @((Get-PSGPOResult -Path (Join-Path $Fixtures 'rsop-user.txt') -Scope User).UserGpos.Name) | Should -Be @('Default Domain Policy')
        }

        It 'Refuses what samba-gpupdate did not print' {
            { ConvertFrom-PSGPOSambaRsop -Line @('Traceback (most recent call last):', '  File x') -Scope Computer } | Should -Throw '*not what samba-gpupdate --rsop prints*'
        }

        It 'Runs samba-gpupdate as root only, which reads the policy with the machine account' {
            Mock Get-Command { [pscustomobject]@{ Source = '/usr/sbin/samba-gpupdate' } } -ParameterFilter { $Name -eq 'samba-gpupdate' }
            Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @('1000'); Error = '' } } -ParameterFilter { $FilePath -eq 'id' }
            { Get-PSGPOSambaGpupdatePath } | Should -Throw '*run it as root (sudo pwsh)*'
            Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @('0'); Error = '' } } -ParameterFilter { $FilePath -eq 'id' }
            Get-PSGPOSambaGpupdatePath | Should -Be '/usr/sbin/samba-gpupdate'
        }
    }

    Describe 'Invoke-PSGPOUpdate' {
        It 'Runs gpupdate on this computer, for the part asked' -Skip:(-not $IsWindows) {
            Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @('Computer Policy update has completed successfully.'); Error = '' } }
            $Result = Invoke-PSGPOUpdate -Target Computer -Force -Confirm:$false
            $Result.Succeeded | Should -BeTrue
            $Result.Target | Should -Be 'Computer'
            $Result.Output | Should -BeLike '*completed successfully*'
            Should -Invoke Invoke-PSGPONativeCommand -Times 1 -ParameterFilter { $FilePath -like '*gpupdate.exe' -and ($ArgumentList -join ' ') -eq '/target:computer /force /wait:600' }
        }

        It 'Runs gpupdate through PowerShell remoting on another computer without RSAT, and says a failure' -Skip:(-not $IsWindows) {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Invoke-GPUpdate' }
            Mock Invoke-Command { 'Updating policy...'; 0 } -ParameterFilter { $ComputerName -eq 'PC01' }
            Mock Invoke-Command { throw 'WinRM cannot complete the operation' } -ParameterFilter { $ComputerName -eq 'PC02' }
            $Results = @(Invoke-PSGPOUpdate -ComputerName PC01, PC02 -Confirm:$false)
            $Results[0].Succeeded | Should -BeTrue
            $Results[0].Output | Should -Be 'Updating policy...'
            $Results[1].Succeeded | Should -BeFalse
            $Results[1].Output | Should -BeLike '*WinRM*'
        }

        It 'Runs samba-gpupdate on this computer, the user part for the user given' -Skip:$IsWindows {
            Mock Get-PSGPOSambaGpupdatePath { '/usr/sbin/samba-gpupdate' }
            Mock Invoke-PSGPONativeCommand { [pscustomobject]@{ ExitCode = 0; Output = @(); Error = '' } }
            $Results = @(Invoke-PSGPOUpdate -User 'CONTOSO\jdoe' -Force -Confirm:$false)
            @($Results.Target).Count | Should -Be 2
            Should -Invoke Invoke-PSGPONativeCommand -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -eq '--target=Computer --force' }
            Should -Invoke Invoke-PSGPONativeCommand -Times 1 -ParameterFilter { ($ArgumentList -join ' ') -eq '--target=User --force -U CONTOSO\jdoe' }
            { Invoke-PSGPOUpdate -Target User -Confirm:$false } | Should -Throw '*give -User*'
            { Invoke-PSGPOUpdate -ComputerName PC01 -Confirm:$false } | Should -Throw '*on the computer itself*'
        }

        It 'Changes nothing with -WhatIf, and needs no root for it' {
            Mock Invoke-PSGPONativeCommand { throw 'not run' }
            Mock Get-PSGPOSambaGpupdatePath { throw 'run it as root (sudo pwsh)' }
            Invoke-PSGPOUpdate -WhatIf 6>$null | Should -BeNullOrEmpty
            Should -Invoke Invoke-PSGPONativeCommand -Times 0
            Should -Invoke Get-PSGPOSambaGpupdatePath -Times 0
        }
    }
}
