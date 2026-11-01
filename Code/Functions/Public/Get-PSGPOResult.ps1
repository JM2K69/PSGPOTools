function Get-PSGPOResult {
    <#
    .SYNOPSIS
        Gets what a computer and a user applied the last time, as Group Policy Results of GPMC.
    .DESCRIPTION
        The RSoP the computer logged: the GPOs of each part, applied with their precedence (1 wins)
        or denied with their reason (Disabled link, Disabled GPO, Denied (security), Empty, WMI
        filter false, Not valid), where they are linked; with gpresult, the security groups of the
        computer and the user, their SOM and site, the status of each client-side extension.

        Windows: gpresult /x, on this computer or another one (-ComputerName; its firewall lets
        RSoP through), for the user given or the one running it; the computer part needs an
        administrator. Linux, a member of a domain: samba-gpupdate --rsop, which reads the policy
        with the machine account: root only (sudo pwsh); it also gives the settings of each GPO.
        -Path reads a file made elsewhere: the XML of gpresult /x, or what samba-gpupdate --rsop
        printed.
    .PARAMETER ComputerName
        The computer, on Windows (gpresult /s); this computer when not given.
    .PARAMETER User
        The user (DOMAIN\name): gpresult /user, samba-gpupdate -U; the one running it when not given.
    .PARAMETER Scope
        Computer, User or All (default).
    .PARAMETER Path
        A file to read in place of running gpresult or samba-gpupdate: the XML of gpresult /x, or the
        output of samba-gpupdate --rsop (one part: -Scope says which, Computer by default).
    .EXAMPLE
        Get-PSGPOResult | Select-Object -ExpandProperty ComputerGpos | Format-Table Precedence, Name, Link, Reason
    .EXAMPLE
        Get-PSGPOResult -ComputerName PC-LYON-042 -User 'CONTOSO\jdoe'
    .EXAMPLE
        Get-PSGPOResult -Path ./rsop-computer.txt -Scope Computer
    .OUTPUTS
        PSGPOTools.Result
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgporesult/
    .LINK
        Get-PSGPOModeling
    .LINK
        Invoke-PSGPOUpdate
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Result')]
    param(
        [string]$ComputerName,
        [string]$User,
        [ValidateSet('Computer', 'User', 'All')] [string]$Scope = 'All',
        [string]$Path
    )

    if ($Path) {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath)
        # gpresult writes UTF-16 with its mark; samba-gpupdate UTF-8.
        $text = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
        else { [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) }
        if ($text.TrimStart().StartsWith('<')) { return ConvertFrom-PSGPOGpresultXml -Xml $text }
        $lines = $text -split '\r?\n'
        if ($Scope -eq 'User') { return New-PSGPOSambaResult -UserLine $lines -User $User }
        return New-PSGPOSambaResult -ComputerLine $lines -Computer $(if ($ComputerName) { $ComputerName } else { '' })
    }

    if ($IsWindows) {
        $file = Join-Path ([System.IO.Path]::GetTempPath()) "PSGPOTools-gpresult-$([guid]::NewGuid().ToString('N')).xml"
        $arguments = [System.Collections.Generic.List[string]]::new()
        if ($ComputerName) { $arguments.AddRange([string[]]@('/s', $ComputerName)) }
        if ($User) { $arguments.AddRange([string[]]@('/user', $User)) }
        if ($Scope -ne 'All') { $arguments.AddRange([string[]]@('/scope', $Scope.ToLowerInvariant())) }
        $arguments.AddRange([string[]]@('/x', $file, '/f'))
        try {
            $run = Invoke-PSGPONativeCommand -FilePath (Join-Path ([Environment]::SystemDirectory) 'gpresult.exe') -ArgumentList $arguments -TimeoutSeconds 300
            if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file)) {
                throw "gpresult failed (exit code $($run.ExitCode)): $((@($run.Error) + @($run.Output) | Where-Object { $_ }) -join ' ')"
            }
            return ConvertFrom-PSGPOGpresultXml -Xml ([System.IO.File]::ReadAllText($file))
        } finally {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    }

    if ($ComputerName) { throw 'On Linux, the result is read on the computer itself (samba-gpupdate): run it there, or give -Path with what it printed.' }
    $samba = Get-PSGPOSambaGpupdatePath
    $read = {
        param([string]$Target)
        $arguments = @('--rsop', "--target=$Target")
        if ($Target -eq 'User' -and $User) { $arguments += @('-U', $User) }
        $run = Invoke-PSGPONativeCommand -FilePath $samba -ArgumentList $arguments -TimeoutSeconds 300
        if ($run.ExitCode -ne 0 -or $run.Error -match 'Traceback') { throw "samba-gpupdate --rsop --target=$Target failed: $("$($run.Error)".Trim())" }
        , [string[]]$run.Output
    }
    $computerLines = if ($Scope -ne 'User') { & $read 'Computer' }
    $userLines = if ($Scope -ne 'Computer') { & $read 'User' }
    New-PSGPOSambaResult -ComputerLine $computerLines -UserLine $userLines -Computer ([System.Net.Dns]::GetHostName()) -User $User
}
