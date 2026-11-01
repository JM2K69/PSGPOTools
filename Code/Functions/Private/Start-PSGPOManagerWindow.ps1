<#
    Private implementation of Show-GPOManagerAvalonia: builds the window, wires its
    handlers and runs the Avalonia loop until the window closes.

    Each view of the console is a file of its own (Initialize-PSGPOManager*View), dot-sourced
    here: its state, functions and handlers live in this scope, with a variable per named control
    of the window. Event handlers keep resolving them because this function scope stays alive
    for the whole loop.

    -OnShown exists for the GUI tests: the scriptblock receives a hashtable of the named
    controls, runs inside the loop once the window is shown, and the window is then
    closed.
#>

function Start-PSGPOManagerWindow {
    [CmdletBinding()]
    Param(
        # Domain of the Group Policy Management view; without it the window opens on the ADMX policies.
        [GPOToolsDirectory]$Directory,

        # Why the domain could not be read: shown in the Group Policy Management view.
        [string]$DirectoryError,

        # View shown at launch: the Group Policy Management view, or the policy editor.
        [ValidateSet('Management', 'Editor')]
        [string]$StartView = 'Management',

        # Language of the interface (Resources/Strings); English by default, so that the tests do
        # not depend on the language of the computer: Show-GPOManagerAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        # The ADMX files to load the first time the console needs them (Path, UICulture), instead
        # of before it opens.
        [hashtable]$AdmxSource,

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $xaml = Get-PSGPOManagerWindowXaml

    # The configuration of HGPM for the domain shown (SYSVOL of its domain controller).
    Use-PSGPODomainConfiguration -Directory $Directory -Force
    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml $xaml))
    # The logo of HGPM: the icon of the window and the image of its header.
    Set-PSGPOWindowIcon -Window $window
    # Each named control of the window in a variable of its name ($treeView...), where the
    # handlers and the views find it; $ui holds them all (-OnShown).
    $ui = Get-PSGPOAvaloniaNamedControl -Root $window -Xaml $xaml
    foreach ($controlName in $ui.Keys) { Set-Variable -Name $controlName -Value $ui[$controlName] }
    $logoImage.Source = New-PSGPOLogoBitmap

    # The views of the console: their state, functions and handlers in this scope (dot-sourced).
    . Initialize-PSGPOManagerOperationView
    . Initialize-PSGPOManagerSettingView
    . Initialize-PSGPOManagerPreferenceView
    . Initialize-PSGPOManagerRestrictedGroupView
    . Initialize-PSGPOManagerScriptView
    . Initialize-PSGPOManagerCertificateView
    . Initialize-PSGPOManagerPolicyTreeView
    . Initialize-PSGPOManagerDirectoryView
    . Initialize-PSGPOManagerGpoFormView
    . Initialize-PSGPOManagerReportView
    . Initialize-PSGPOManagerHistoryView
    . Initialize-PSGPOManagerDelegationView
    . Initialize-PSGPOManagerDomainTreeView
    . Initialize-PSGPOManagerCommentView
    . Initialize-PSGPOManagerSearchView
    . Initialize-PSGPOManagerWmiFilterView
    . Initialize-PSGPOManagerToolbarView
    . Initialize-PSGPOManagerSomView
    . Initialize-PSGPOManagerStatusView

    $directoryHint = if ($Directory.IsReadOnly) { Get-PSGPOText 'Read-only: {0}' $Directory.Source } else { Get-PSGPOText 'Right-click a domain or an OU to create a GPO' }
    $directoryBreadcrumbTextBlock.Text = $directoryHint
    $directoryEmptyTextBlock.IsVisible = -not $Directory
    $demoBanner.IsVisible = [bool]$Directory.IsDemonstration
    $domainTreeView.IsVisible = [bool]$Directory
    if ($DirectoryError) {
        $directoryEmptyTextBlock.Text = (Get-PSGPOText 'The domain could not be read.') + "`n`n$DirectoryError"
        $directoryEmptyTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
        $directoryBreadcrumbTextBlock.Text = Get-PSGPOText 'Domain not read'
    }
    if ($Directory) { Update-DirectoryTree }
    # The editor at once: through the gate of the ADMX files, so that they are read.
    if ($StartView -eq 'Editor' -and $AdmxSource) { Open-GpoEditor -Gpo $null } else { Show-View $StartView }

    # Then the version of HGPM, and whether a newer one is on the PowerShell Gallery.
    # The version of HGPM read once (the Gallery), kept when the domain is read again.
    $versionStatusItems = @(Get-PSGPOVersionStatusItem)
    $statusBarList.ItemsSource = @(Get-PSGPOStatusBarItem -Platform (Get-PSGPOPlatform) -Directory $Directory -DirectoryError $DirectoryError) + $versionStatusItems

    Show-PSGPOWindow -Window $window

    # A hashtable, because assigning a variable inside the posted action would only set a child-scope copy.
    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Editing = $editing; Clipboard = $clipboard; Directory = $Directory; Configuration = $configurationWindow; GpoReport = $gpoReport; SaveGpoReport = ${function:Save-GpoReport} }
        foreach ($controlName in $ui.Keys) { $controls[$controlName] = $ui[$controlName] }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
        })
    }

    # Until the window is closed (Invoke-PSGPOWindowLoop).
    Invoke-PSGPOWindowLoop -Window $window -KeepOpenOnError:(-not $OnShown)

    if ($onShownState.Error) { throw $onShownState.Error }
}
