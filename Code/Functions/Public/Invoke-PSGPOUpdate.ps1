function Invoke-PSGPOUpdate {
    <#
    .SYNOPSIS
        Has computers apply their GPOs now, as Group Policy Update of GPMC and gpupdate.
    .DESCRIPTION
        Windows: gpupdate on this computer; on other computers (-ComputerName), Invoke-GPUpdate of
        RSAT when it is there, as GPMC does (a scheduled task on the computer, for it and for each
        user logged on), else gpupdate through PowerShell remoting (the computer part, and the user
        of the remote session). Linux, a member of a domain: samba-gpupdate, which applies the
        policy with the machine account: root only (sudo pwsh); the user part for the user given.
        -Force applies every setting again, not only those of the GPOs that changed.
    .PARAMETER ComputerName
        The computers, on Windows; this computer when not given.
    .PARAMETER Target
        Computer, User or All (default): the parts to apply.
    .PARAMETER User
        On Linux, the user whose part is applied (samba-gpupdate -U).
    .PARAMETER Force
        Every setting applied again (gpupdate /force, samba-gpupdate --force).
    .EXAMPLE
        Invoke-PSGPOUpdate -Target Computer -Force
    .EXAMPLE
        Invoke-PSGPOUpdate -ComputerName PC-LYON-041, PC-LYON-042
    .OUTPUTS
        PSGPOTools.UpdateResult
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/invoke-psgpoupdate/
    .LINK
        Get-PSGPOResult
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.UpdateResult')]
    param(
        [string[]]$ComputerName,
        [ValidateSet('Computer', 'User', 'All')] [string]$Target = 'All',
        [string]$User,
        [switch]$Force
    )

    $result = {
        param([string]$Computer, [bool]$Succeeded, $Output)
        [pscustomobject]@{ PSTypeName = 'PSGPOTools.UpdateResult'; Computer = $Computer; Target = $Target; Succeeded = $Succeeded; Output = (@($Output | Where-Object { $_ }) -join [Environment]::NewLine).Trim() }
    }

    if (-not $IsWindows) {
        if ($ComputerName) { throw 'On Linux, the policy is applied on the computer itself (samba-gpupdate): run it there.' }
        $targets = switch ($Target) { 'All' { if ($User) { 'Computer', 'User' } else { 'Computer' } } default { $Target } }
        if ($Target -eq 'User' -and -not $User) { throw 'samba-gpupdate applies the user part for a user: give -User.' }
        $samba = $null
        foreach ($part in $targets) {
            if (-not $PSCmdlet.ShouldProcess([System.Net.Dns]::GetHostName(), "Apply the $($part.ToLowerInvariant()) GPOs (samba-gpupdate)")) { continue }
            # Root only, when it runs: -WhatIf needs no root.
            if (-not $samba) { $samba = Get-PSGPOSambaGpupdatePath }
            $arguments = @("--target=$part")
            if ($Force) { $arguments += '--force' }
            if ($part -eq 'User') { $arguments += @('-U', $User) }
            $run = Invoke-PSGPONativeCommand -FilePath $samba -ArgumentList $arguments -TimeoutSeconds 600
            & $result ([System.Net.Dns]::GetHostName()) ($run.ExitCode -eq 0 -and $run.Error -notmatch 'Traceback') (@($run.Output) + @($run.Error))
        }
        return
    }

    $switches = @(switch ($Target) { 'Computer' { '/target:computer' } 'User' { '/target:user' } }) + @(if ($Force) { '/force' }) + @('/wait:600')
    if (-not $ComputerName) {
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Apply the GPOs (gpupdate)')) { return }
        $run = Invoke-PSGPONativeCommand -FilePath (Join-Path ([Environment]::SystemDirectory) 'gpupdate.exe') -ArgumentList $switches -TimeoutSeconds 700
        return & $result $env:COMPUTERNAME ($run.ExitCode -eq 0) (@($run.Output) + @($run.Error))
    }
    $gpmc = Get-Command -Name 'Invoke-GPUpdate' -ErrorAction SilentlyContinue
    foreach ($computer in $ComputerName) {
        if (-not $PSCmdlet.ShouldProcess($computer, $(if ($gpmc) { 'Apply the GPOs (Invoke-GPUpdate, as GPMC)' } else { 'Apply the GPOs (gpupdate through PowerShell remoting)' }))) { continue }
        try {
            if ($gpmc) {
                $update = @{ Computer = $computer; RandomDelayInMinutes = 0; Force = [bool]$Force; ErrorAction = 'Stop' }
                if ($Target -ne 'All') { $update.Target = $Target }
                $output = Invoke-GPUpdate @update 2>&1
                & $result $computer $true $output
            } else {
                $output = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock { $arguments = $using:switches; & gpupdate.exe @arguments 2>&1; $LASTEXITCODE }
                & $result $computer ($output[-1] -eq 0) @($output | Select-Object -SkipLast 1)
            }
        } catch {
            & $result $computer $false $_.Exception.GetBaseException().Message
        }
    }
}
