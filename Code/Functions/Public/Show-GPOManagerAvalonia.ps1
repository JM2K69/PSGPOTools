function Show-GPOManagerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical console for Group Policy.
    .DESCRIPTION
        Opens on the Group Policy Management view, as GPMC: the domain, its OUs and their GPO
        links, and the Group Policy Objects container. Its context menu edits a GPO in the
        policy editor and, on a writable directory, creates GPOs.

        Without -Directory, the domain is detected and read at launch (Get-PSGPODirectory),
        whether its domain controllers run Windows (Active Directory) or Samba (Samba AD): on a
        computer of a domain, on a domain controller, or with -Server. When the domain cannot
        be read (no Kerberos ticket, server unreachable...), the window still opens and says
        why. When no domain is discovered, the window shows the sample directory of the module
        (Samples/Directory.sample.json) under a "demonstration environment" banner.

        A status bar shows this computer (name, system, addresses), its domain and the domain
        controller the directory was read from, with its directory service.

        The policy editor displays the security settings of the computer (Windows Settings >
        Security Settings) and the policies loaded by Initialize-PSGPOAdmx (scope > categories >
        policies) with their setting form and details. When no ADMX file is loaded, a window asks
        for the PolicyDefinitions folder and the language of its ADML files (detected from the
        names of its language folders), remembering the choice for the next time; the console does
        not open without them. -PolicyDefinitions loads a folder without asking. Editing a GPO, each setting is read from
        the GPO (Registry.pol, GptTmpl.inf) and Apply saves it there.

        Hosted on Avalonia UI under PowerShell 7+; the call blocks until the window is closed.
        The Avalonia assemblies are not bundled with the module: the first time a window opens,
        the runtime of the computer is downloaded from nuget.org and checked against its pinned
        SHA-512. For a computer without internet, run .\Avalonia\Get-AvaloniaBinaries.ps1 on
        another one (see that script's help for details).
    .PARAMETER Directory
        Directory to show instead of reading the domain: from Get-PSGPODirectory, or from
        Import-PSGPODirectory (offline description, for demonstrations).
    .PARAMETER Server
        Domain controller to read the domain from (see Get-PSGPODirectory).
    .PARAMETER Credential
        Account to read the domain with (see Get-PSGPODirectory).
    .PARAMETER UseSsl
        Reads the domain over LDAPS (see Get-PSGPODirectory).
    .PARAMETER PolicyDefinitions
        PolicyDefinitions folder to load the ADMX files from, without asking (see Initialize-PSGPOAdmx).
    .PARAMETER UICulture
        Language of the ADML files of -PolicyDefinitions (en-US, fr-FR...); detected when not given.
    .PARAMETER NoDirectory
        Neither reads the domain nor shows the sample directory: the window opens on the policy
        editor to browse the ADMX policies.
    .EXAMPLE
        # The domain of the computer (Windows session, or a Kerberos ticket on Linux)
        Initialize-PSGPOAdmx -UICulture 'en-US'
        Show-GPOManagerAvalonia
    .EXAMPLE
        # Linux: the ADMX files of a copy of PolicyDefinitions, in the language of the session
        Show-GPOManagerAvalonia -PolicyDefinitions ~/PolicyDefinitions
    .EXAMPLE
        kinit administrator@HARDENBOX.LABO
        Show-GPOManagerAvalonia -Server dc.hardenbox.labo
    .EXAMPLE
        $Sample = Join-Path (Split-Path (Get-Module PSGPOTools).Path) 'Samples' 'Directory.sample.json'
        Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
    .LINK
        Get-PSGPODirectory
    #>
    [CmdletBinding(DefaultParameterSetName = 'Domain')]
    Param(
        [Parameter(Mandatory, ParameterSetName = 'Directory')]
        [GPOToolsDirectory]$Directory,

        [Parameter(ParameterSetName = 'Domain')]
        [string]$Server,

        [Parameter(ParameterSetName = 'Domain')]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'Domain')]
        [switch]$UseSsl,

        [Parameter(Mandatory, ParameterSetName = 'NoDirectory')]
        [switch]$NoDirectory,

        [ValidateScript( { Test-Path -Path $_ -PathType Container })]
        [string]$PolicyDefinitions,

        [string]$UICulture
    )

    # The ADMX files first: asked for in a window when none is loaded.
    if ($PolicyDefinitions -or $UICulture) {
        $admx = @{}
        if ($PolicyDefinitions) { $admx.Path = $PolicyDefinitions }
        if ($UICulture) { $admx.UICulture = $UICulture }
        Initialize-PSGPOAdmx @admx -WarningAction SilentlyContinue
    } elseif ([GPOToolsUtility]::Policies.Count -eq 0 -and -not (Show-PSGPOAdmxWindow)) {
        Write-Warning 'No ADMX file loaded: the console is not opened. Choose a PolicyDefinitions folder, or give -PolicyDefinitions.'
        return
    }

    $directoryError = $null
    if ($PSCmdlet.ParameterSetName -eq 'Domain') {
        $platform = Get-PSGPOPlatform
        if ($Server -or $platform.DomainName) {
            $read = @{}
            foreach ($name in 'Server', 'Credential', 'UseSsl') {
                if ($PSBoundParameters.ContainsKey($name)) { $read[$name] = $PSBoundParameters[$name] }
            }
            try {
                $Directory = Get-PSGPODirectory @read -ErrorAction Stop
                Write-Verbose "Domain read: $($Directory.Source)"
            } catch {
                $directoryError = $_.Exception.Message
                Write-Warning "The domain could not be read: $directoryError"
            }
        } else {
            # Nothing to read: the sample directory, flagged as a demonstration.
            $sample = Join-Path $PSScriptRoot 'Samples' 'Directory.sample.json'
            Write-Verbose "$platform`: no domain discovered, demonstration directory $sample."
            try {
                $Directory = Import-PSGPODirectory -Path $sample -ErrorAction Stop
                $Directory.IsDemonstration = $true
            } catch {
                Write-Warning "No domain discovered and the demonstration directory cannot be read: $($_.Exception.Message)"
            }
        }
    }

    $startView = if ($NoDirectory) { 'Editor' } else { 'Management' }
    Start-PSGPOManagerWindow -Directory $Directory -DirectoryError $directoryError -StartView $startView
}
