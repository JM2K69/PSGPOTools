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
        controller the directory was read from, with its directory service, then the version of
        HGPM with a dot: green when it is the latest of the PowerShell Gallery, orange when a newer
        one is there (its tooltip gives the command that installs it), grey when the Gallery was
        not read.

        The policy editor displays the security settings of the computer (Windows Settings >
        Security Settings) and the policies loaded by Initialize-PSGPOAdmx (scope > categories >
        policies) with their setting form and details. When no ADMX file is loaded, a window asks
        for the PolicyDefinitions folder and the language of its ADML files (detected from the
        names of its language folders), remembering the choice for the next time; the console does
        not open without them. The central store of the domain shown (as GPMC), or the folder chosen
        instead in that window, is not asked for again: the console opens at once and reads them
        the first time it needs them (the policy editor, the Settings and History tabs, a report).
        The window asks again at the next start when that load fails. -PolicyDefinitions loads a
        folder without asking, before the console opens.
        Editing a GPO, each setting is read from the GPO (Registry.pol, GptTmpl.inf) and Apply saves
        it there.

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
    .PARAMETER Language
        Language of the interface: en-US, or a language of Resources/Strings (fr-FR); by default
        the language of the session, English when the module has no translation for it. The
        commands, their messages and errors stay in English.
    .PARAMETER NoDirectory
        Neither reads the domain nor shows the sample directory: the window opens on the policy
        editor to browse the ADMX policies.
    .EXAMPLE
        # The console in French
        Show-GPOManagerAvalonia -Language fr-FR
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
        $Sample = Join-Path (Split-Path (Get-Module HGPM).Path) 'Samples' 'Directory.sample.json'
        Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/show-gpomanageravalonia/
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

        [string]$UICulture,

        [string]$Language = [cultureinfo]::CurrentUICulture.Name
    )

    # The language of the interface, for the ADMX window too.
    $Language = Set-PSGPOLanguage -Language $Language

    # The ADMX files given: loaded before the console opens.
    if ($PolicyDefinitions -or $UICulture) {
        $admx = @{}
        if ($PolicyDefinitions) { $admx.Path = $PolicyDefinitions }
        if ($UICulture) { $admx.UICulture = $UICulture }
        Initialize-PSGPOAdmx @admx -WarningAction SilentlyContinue
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

    # Else, when none is loaded: the folder chosen last, else the central store of the domain
    # shown, read the first time the console needs them (the editor, the Settings and History
    # tabs, a report); a console that only links or approves never waits for them. Asked for in
    # a window when there is none, or when the last load of the console failed.
    $admxSource = $null
    if ([GPOToolsUtility]::Policies.Count -eq 0) {
        # The store of the domain read, through its domain controller too; of the computer for a
        # description (Import-PSGPODirectory).
        $start = @{}
        if ($Directory -is [GPOToolsLdapDirectory]) { $start.DomainName = $Directory.DomainName; $start.Server = $Directory.Server }
        $source = Get-PSGPOAdmxStartSource @start
        if ($source.Path) {
            $admxSource = @{ Path = $source.Path; UICulture = $source.UICulture }
            # The editor alone shows them at once: loaded now.
            if ($NoDirectory) {
                try { Initialize-PSGPOAdmx @admxSource -WarningAction SilentlyContinue -ErrorAction Stop }
                catch { Write-Warning "The ADMX files of $($source.Path) are not loaded: $($_.Exception.Message)" }
                $admxSource = $null
            }
        }
        if (-not $admxSource -and [GPOToolsUtility]::Policies.Count -eq 0) {
            $window = @{}
            if ($null -ne $source.CentralStore) { $window.CentralStore = $source.CentralStore }
            if (-not (Show-PSGPOAdmxWindow @window)) {
                Write-Warning 'No ADMX file loaded: the console is not opened. Choose a PolicyDefinitions folder, give -PolicyDefinitions, or download the ADMX files of HGPM with Install-PSGPOAdmx.'
                return
            }
        }
    }

    # The first start of the console by an administrator creates the configuration of the domain.
    if ($Directory -and -not $Directory.IsDemonstration) { $null = Initialize-PSGPODomainConfiguration -Directory $Directory }

    $startView = if ($NoDirectory) { 'Editor' } else { 'Management' }
    Start-PSGPOManagerWindow -Directory $Directory -DirectoryError $directoryError -StartView $startView -Language $Language -AdmxSource $admxSource
}
