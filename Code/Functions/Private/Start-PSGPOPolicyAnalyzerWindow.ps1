<#
    Private implementation of Show-PolicyAnalyzerAvalonia: builds the window, wires its handlers
    (Initialize-PSGPOPolicyAnalyzerView, dot-sourced in this scope) and runs the Avalonia loop until
    the window closes.

    -OnShown exists for the GUI tests, as for Start-PSGPOManagerWindow: the scriptblock receives a
    hashtable of the named controls, runs inside the loop once the window is shown, and the window
    is then closed. Event handlers keep resolving the local variables below because this function
    scope stays alive for the whole loop.
#>

function Start-PSGPOPolicyAnalyzerWindow {
    [CmdletBinding()]
    param(
        # The domain of the GPOs added as rule sets; read with -DomainParameters the first time
        # GPOs of the domain are asked for when not given.
        [AllowNull()] [GPOToolsDirectory]$Directory,

        # Parameters of Get-PSGPODirectory (Server, Credential, UseSsl).
        [hashtable]$DomainParameters = @{},

        # The folder of the .PolicyRules files shown at start, instead of the one of the last time.
        [string]$Path,

        # Language of the interface; English by default, so that the tests do not depend on the
        # language of the computer: Show-PolicyAnalyzerAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOPolicyAnalyzerWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $ui = @{}
    foreach ($name in 'logoImage', 'subtitleTextBlock', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText') { $ui[$name] = Get-PSGPOAvaloniaControl $window $name }
    $ui.logoImage.Source = New-PSGPOLogoBitmap

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $window -ToggleText $ui.themeToggleText -ToggleIcon $ui.themeToggleIcon
    $ui.themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # The Policy Analyzer: its controls, state and functions in this scope (dot-sourced).
    . Initialize-PSGPOPolicyAnalyzerView
    $analyzerView.IsVisible = $true
    if ($Directory) { $ui.subtitleTextBlock.Text = Get-PSGPOText 'GPOs and security baselines compared setting by setting - {0}' $Directory.DomainName }
    if (-not @([GPOToolsUtility]::Policies).Count) {
        $ui.subtitleTextBlock.Text = Get-PSGPOText 'No ADMX file loaded: the registry values are shown by their key, not by their policy (-PolicyDefinitions).'
    }
    Open-AnalyzerView -Folder $Path

    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Analyzer = $analyzer } + $ui
        foreach ($name in $analyzerControlNames) { $controls[$name] = Get-PSGPOAvaloniaControl $window $name }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
            })
    }

    Invoke-PSGPOWindowLoop -Window $window

    if ($onShownState.Error) { throw $onShownState.Error }
}
