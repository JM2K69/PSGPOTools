<#
    Private implementation of Start-HGPM: a tile for each console, a click on a tile runs its
    command. The command of a console runs its own Avalonia loop inside the click handler (a nested
    frame of the dispatcher, as a dialog), so the launcher stays responsive and several consoles can
    be open at once; the tile of an open console is disabled until it is closed.

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
    $null = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOLauncherWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $ui = @{}
    foreach ($name in 'logoImage', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText', 'toolsPanel', 'statusTextBlock') {
        $ui[$name] = Get-PSGPOAvaloniaControl $window $name
    }
    $ui.logoImage.Source = New-PSGPOLogoBitmap

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $window -ToggleText $ui.themeToggleText -ToggleIcon $ui.themeToggleIcon
    $ui.themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # The tiles: an icon, the title and what the console does; the tool is the Tag of the button.
    $tiles = [System.Collections.Generic.List[object]]::new()
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

    # A click on a tile runs its console, until the window of the console is closed. Once the click
    # is over: the tile keeps the pointer during its click, and every click in the console would go
    # to the launcher (which comes back in front) until the console is closed.
    $launch = @{ Tile = $null; Tool = $null }
    function Invoke-LauncherTool {
        $tile = $launch.Tile
        $tool = $launch.Tool
        try {
            & $tool.Command -Language $Language
        } catch {
            $ui.statusTextBlock.Text = Get-PSGPOText '{0} did not open: {1}' $tool.Command $_.Exception.GetBaseException().Message
            $ui.statusTextBlock.IsVisible = $true
        } finally {
            $tile.IsEnabled = $true
            # The consoles share the language of the session: the launcher keeps its own.
            $null = Set-PSGPOLanguage -Language $Language
        }
    }
    $ui.toolsPanel.AddHandler([Avalonia.Controls.Button]::ClickEvent, [EventHandler[Avalonia.Interactivity.RoutedEventArgs]] {
            param($source, $e)
            $tile = $e.Source
            $tool = $tile.Tag
            if ($tool -isnot [hashtable]) { return }
            $e.Handled = $true
            $ui.statusTextBlock.IsVisible = $false
            $tile.IsEnabled = $false
            $launch.Tile = $tile
            $launch.Tool = $tool
            [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { Invoke-LauncherTool }, [Avalonia.Threading.DispatcherPriority]::Background)
        })

    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $cts.Cancel() }, [Avalonia.Threading.DispatcherPriority]::Background)
    })
    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Tiles = $tiles } + $ui
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
            })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        Write-Verbose 'The window is closed.'
    }

    if ($onShownState.Error) { throw $onShownState.Error }
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
}
