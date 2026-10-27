<#
    Private implementation of Start-HGPM: a tile for each console, a click on a tile runs its
    command in a PowerShell process of its own (Start-PSGPOToolProcess), so several consoles can be
    open at once, each with its own windows and loop, and they stay open once the launcher is
    closed; the tile of an open console is disabled until its process ends.

    The language of the launcher can be changed in its window: its texts change at once, the consoles
    opened after are in it, and Start-HGPM starts on it the next time (the settings of the user).

    -OnShown exists for the GUI tests, as for Start-PSGPOManagerWindow: the scriptblock receives a
    hashtable of the named controls and the tiles, runs inside the loop once the window is shown,
    and the window is then closed.
#>

function Start-PSGPOLauncherWindow {
    [CmdletBinding()]
    param(
        # The consoles: hashtables with Command, Title, Description (translated) and Icon (a name of Resources/Icons): Get-PSGPOLauncherTool.
        [Parameter(Mandatory)]
        [hashtable[]]$Tools,

        # Language of the interface, given to the consoles too.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $Language = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOLauncherWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $ui = @{}
    foreach ($name in 'logoImage', 'subtitleTextBlock', 'languageComboBox', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText', 'toolsPanel', 'statusTextBlock') {
        $ui[$name] = Get-PSGPOAvaloniaControl $window $name
    }
    $ui.logoImage.Source = New-PSGPOLogoBitmap

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $window -ToggleText $ui.themeToggleText -ToggleIcon $ui.themeToggleIcon
    $ui.themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # The tiles: an icon, the title and what the console does; the tool is the Tag of the button.
    # Built again in the language chosen.
    $tiles = [System.Collections.Generic.List[object]]::new()
    function Update-LauncherTile {
        $ui.toolsPanel.Children.Clear()
        $tiles.Clear()
        foreach ($tool in $Tools) {
            $icon = [Avalonia.Controls.PathIcon]::new()
            $icon.Data = [Avalonia.Media.Geometry]::Parse((Get-PSGPOIconData -Name $tool.Icon))
            $icon.Width = 40
            $icon.Height = 40
            # The brushes follow the theme (DynamicResource).
            $null = $icon.Bind([Avalonia.Controls.PathIcon]::ForegroundProperty, [Avalonia.Controls.ResourceNodeExtensions]::GetResourceObservable($window, 'PrimaryBrush', $null))

            $title = [Avalonia.Controls.TextBlock]::new()
            $title.Text = $tool.Title
            $title.FontWeight = [Avalonia.Media.FontWeight]::SemiBold
            $title.TextAlignment = [Avalonia.Media.TextAlignment]::Center
            $title.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
            # Its own brush, as the description: the foreground the tile gives it on pointer over made it
            # lay out its lines again, on the left, once the pointer left.
            $null = $title.Bind([Avalonia.Controls.TextBlock]::ForegroundProperty, [Avalonia.Controls.ResourceNodeExtensions]::GetResourceObservable($window, 'TextBrush', $null))

            $description = [Avalonia.Controls.TextBlock]::new()
            $description.Text = $tool.Description
            $description.FontSize = 11
            $description.TextAlignment = [Avalonia.Media.TextAlignment]::Center
            $description.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
            $null = $description.Bind([Avalonia.Controls.TextBlock]::ForegroundProperty, [Avalonia.Controls.ResourceNodeExtensions]::GetResourceObservable($window, 'SecondaryTextBrush', $null))

            # The texts as wide as the inside of the tile, centered by their TextAlignment: measured on
            # the width of their panel, a title on two lines was drawn on another once the pointer left
            # the tile, its lines then on the left.
            $icon.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Center
            foreach ($text in $title, $description) { $text.Width = 220 - 2 * 12 - 2 }
            $content = [Avalonia.Controls.StackPanel]::new()
            $content.Spacing = 8
            $content.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
            $content.VerticalAlignment = [Avalonia.Layout.VerticalAlignment]::Center
            foreach ($child in $icon, $title, $description) { $content.Children.Add($child) }

            $tile = [Avalonia.Controls.Button]::new()
            $tile.Width = 220
            $tile.Height = 160
            $tile.Margin = [Avalonia.Thickness]::new(6)
            $tile.Padding = [Avalonia.Thickness]::new(12)
            $tile.HorizontalContentAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
            $tile.Content = $content
            $tile.Tag = $tool
            [Avalonia.Controls.ToolTip]::SetTip($tile, $tool.Command)
            $ui.toolsPanel.Children.Add($tile)
            $tiles.Add($tile)
        }
    }

    # A click on a tile starts its console in a PowerShell process of its own (Start-PSGPOToolProcess):
    # its tile stays disabled while that process runs, and says why it stopped when it did not open.
    # Running: the consoles started, each @{ Tile; Tool; Started }.
    $launch = @{ Language = $Language; Running = [System.Collections.Generic.List[hashtable]]::new(); Timer = $null }
    function Show-LauncherProblem {
        param([string]$Text)
        $ui.statusTextBlock.Text = $Text
        $ui.statusTextBlock.IsVisible = $true
    }
    function Update-LauncherProcess {
        foreach ($entry in @($launch.Running)) {
            if (-not $entry.Started.Process.HasExited) { continue }
            [void]$launch.Running.Remove($entry)
            $entry.Tile.IsEnabled = $true
            $code = $entry.Started.Process.ExitCode
            if ($code) {
                $problem = Read-PSGPOToolProblem -Path $entry.Started.ProblemPath
                Show-LauncherProblem (Get-PSGPOText '{0} did not open: {1}' $entry.Tool.Command $(if ($problem) { $problem } else { Get-PSGPOText 'its process stopped with the code {0}' $code }))
            }
        }
        if (-not $launch.Running.Count -and $launch.Timer) { $launch.Timer.Stop() }
    }
    $ui.toolsPanel.AddHandler([Avalonia.Controls.Button]::ClickEvent, [EventHandler[Avalonia.Interactivity.RoutedEventArgs]] {
            param($source, $e)
            $tile = $e.Source
            $tool = $tile.Tag
            if ($tool -isnot [hashtable]) { return }
            $e.Handled = $true
            $ui.statusTextBlock.IsVisible = $false
            try {
                $started = Start-PSGPOToolProcess -Command $tool.Command -Language $launch.Language
            } catch {
                Write-PSGPOLogEntry -Level Error -Source 'Launcher' -Message "$($tool.Command) did not open." -ErrorRecord $_
                Show-LauncherProblem (Get-PSGPOText '{0} did not open: {1}' $tool.Command $_.Exception.GetBaseException().Message)
                return
            }
            $tile.IsEnabled = $false
            $launch.Running.Add(@{ Tile = $tile; Tool = $tool; Started = $started })
            if (-not $launch.Timer) {
                $launch.Timer = [Avalonia.Threading.DispatcherTimer]::new()
                $launch.Timer.Interval = [TimeSpan]::FromMilliseconds(500)
                $launch.Timer.Add_Tick({ Update-LauncherProcess })
            }
            $launch.Timer.Start()
        })

    # The language: an item for each one of the module, in its own language. The texts of the window
    # and of the tiles change with it (the titles of the tools from Get-PSGPOLauncherTool).
    function Update-LauncherText {
        $ui.subtitleTextBlock.Text = Get-PSGPOText 'Choose a console'
        [Avalonia.Controls.ToolTip]::SetTip($ui.languageComboBox, (Get-PSGPOText 'Language of the consoles'))
        $ui.themeToggleText.Text = Get-PSGPOText $(if (Get-PSGPOThemeIsDark) { 'Light mode' } else { 'Dark mode' })
        $translated = @{}
        foreach ($tool in Get-PSGPOLauncherTool) { $translated[$tool.Command] = $tool }
        foreach ($tool in $Tools) {
            if (-not $translated.ContainsKey($tool.Command)) { continue }
            $tool.Title = $translated[$tool.Command].Title
            $tool.Description = $translated[$tool.Command].Description
        }
        Update-LauncherTile
    }
    foreach ($name in Get-PSGPOLanguage) {
        $neutral = ([cultureinfo]::GetCultureInfo($name)).Parent
        $item = [Avalonia.Controls.ComboBoxItem]::new()
        $item.Content = $neutral.TextInfo.ToTitleCase($neutral.NativeName)
        $item.Tag = $name
        $null = $ui.languageComboBox.Items.Add($item)
        if ($name -eq $launch.Language) { $ui.languageComboBox.SelectedItem = $item }
    }
    Update-LauncherTile
    $ui.languageComboBox.add_SelectionChanged({
            $chosen = $ui.languageComboBox.SelectedItem.Tag
            if (-not $chosen -or $chosen -eq $launch.Language) { return }
            $launch.Language = Set-PSGPOLanguage -Language $chosen
            Update-LauncherText
            try { Set-PSGPOUserSetting -Values @{ Language = $launch.Language } -Confirm:$false } catch { Write-Verbose "Language not saved: $($_.Exception.Message)" }
        })

    # The consoles keep running once the launcher is closed; it stops looking at them.
    $window.Add_Closed({ if ($launch.Timer) { $launch.Timer.Stop() } })
    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Tiles = $tiles } + $ui
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
            })
    }

    Invoke-PSGPOWindowLoop -Window $window

    if ($onShownState.Error) { throw $onShownState.Error }
}

# Starts a console of the launcher in a new PowerShell process: the same pwsh and the same HGPM,
# without the profile, in the language given. Run in the process of the launcher, a console ran in
# its loop, and the handlers of one window found the variables of another: the audit log opened
# beside the GPO console gave it no domain; the launcher closed stopped the GPO console, whose
# window stayed open without its code. Returns Process and ProblemPath, the file where the console
# writes why it did not open.
function Start-PSGPOToolProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string]$Language
    )

    $module = $MyInvocation.MyCommand.Module
    $manifest = Join-Path $module.ModuleBase "$($module.Name).psd1"
    # The pwsh of this session; pwsh from the Microsoft Store runs from its alias (the files of a
    # package cannot be started from their folder).
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf) -or $PSHOME -match '[\\/]WindowsApps[\\/]') {
        $found = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw "pwsh is not found: $pwsh" }
        $pwsh = $found.Source
    }
    $problemPath = Join-Path ([System.IO.Path]::GetTempPath()) "HGPM-launcher-$([guid]::NewGuid().ToString('N')).txt"
    $quote = { param([string]$Text) "'" + $Text.Replace("'", "''") + "'" }
    # A command that can be read in the list of the processes (no encoded command).
    $script = 'Import-Module -Name {0}; & (Get-Module -Name {1}) {{ Invoke-PSGPOLauncherTool @args }} {2} {3} {4}' -f (& $quote $manifest), (& $quote $module.Name), (& $quote $Command), (& $quote $Language), (& $quote $problemPath)

    $info = [System.Diagnostics.ProcessStartInfo]::new($pwsh)
    foreach ($argument in '-NoProfile', '-NoLogo', '-Command', $script) { $info.ArgumentList.Add($argument) }
    $info.UseShellExecute = $false
    # Windows: a console of its own, hidden, so that closing the terminal of the launcher does not
    # close the consoles.
    $info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($info)
    Write-Verbose "$Command started in the process $($process.Id)."
    [pscustomobject]@{ Process = $process; ProblemPath = $problemPath }
}

# In the process of a console the launcher started: its command; why it did not open in the
# technical log, and in the file the launcher reads (it then stops with the code 1).
function Invoke-PSGPOLauncherTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string]$Language,
        [Parameter(Mandatory)] [string]$ProblemPath
    )

    try {
        & $Command -Language $Language
    } catch {
        Write-PSGPOLogEntry -Level Error -Source 'Launcher' -Message "$Command did not open." -ErrorRecord $_
        try { [System.IO.File]::WriteAllText($ProblemPath, $_.Exception.GetBaseException().Message) } catch { Write-Verbose "Not written in ${ProblemPath}: $($_.Exception.Message)" }
        exit 1
    }
}

# Why a console did not open, as its process wrote it (the file is then deleted); $null without it.
function Read-PSGPOToolProblem {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { "$(Get-Content -LiteralPath $Path -Raw)".Trim() } finally { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
}

# The consoles of the launcher, their texts in the language of the interface. A new console is one
# more entry here.
function Get-PSGPOLauncherTool {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Command     = 'Show-GPOManagerAvalonia'
        Title       = Get-PSGPOText 'Group Policy Management'
        Description = Get-PSGPOText 'The GPOs of the domain, their links, settings, delegation and backups'
        Icon        = 'organization'
    }
    @{
        Command     = 'Show-PSOManagerAvalonia'
        Title       = Get-PSGPOText 'Password Settings'
        Description = Get-PSGPOText 'The fine-grained password policies (PSO) and the ones a user or a group gets'
        Icon        = 'key'
    }
    @{
        Command     = 'Show-WmiFilterCreatorAvalonia'
        Title       = Get-PSGPOText 'WMI Filter Creator'
        Description = Get-PSGPOText 'Build, check and test WMI filters from ready-made queries, then export them to .mof'
        Icon        = 'filter'
    }
    @{
        Command     = 'Show-PolicyAnalyzerAvalonia'
        Title       = Get-PSGPOText 'Policy Analyzer'
        Description = Get-PSGPOText 'GPOs and the security baselines of Microsoft compared setting by setting, as in the Security Compliance Toolkit'
        Icon        = 'table-search'
    }
    @{
        Command     = 'Show-AuditLogAvalonia'
        Title       = Get-PSGPOText 'Audit Log'
        Description = Get-PSGPOText 'What the consoles and the commands changed in the domain: who, when, from where, on which GPO'
        Icon        = 'book'
    }
}
