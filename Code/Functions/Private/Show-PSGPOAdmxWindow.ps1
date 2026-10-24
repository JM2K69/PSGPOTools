<#
    Window asking where the ADMX files are, shown by Show-GPOManagerAvalonia when none is loaded:
    a PolicyDefinitions folder (found on this computer, typed, or picked) and the language of its
    ADML files, detected from the names of its language folders and chosen in the window when
    several fit. Load runs Initialize-PSGPOAdmx and remembers the choice for the next time; the
    console needs them: Cancel (or closing the window) does not open it.

    Returns $true when the ADMX files were loaded. -OnShown exists for the GUI tests, as for
    Start-PSGPOManagerWindow: it gets the named controls, then the window closes.
#>

function Show-PSGPOAdmxWindow {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime

    $xaml = @'
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='GPO Policy Manager - Administrative Templates' Width='680' SizeToContent='Height'
        WindowStartupLocation='CenterScreen' CanResize='False'>
    <StackPanel Margin='24' Spacing='10'>
        <TextBlock Text='Administrative Templates (ADMX)' FontSize='20' FontWeight='SemiBold'/>
        <TextBlock TextWrapping='Wrap'
                   Text='No ADMX policy is loaded. Choose the PolicyDefinitions folder to load: its .admx files, and one folder per language (en-US, fr-FR...) with the .adml files.'/>

        <TextBlock Text='Found on this computer' FontWeight='SemiBold' Margin='0,8,0,0'/>
        <ComboBox Name='candidateComboBox' HorizontalAlignment='Stretch' PlaceholderText='No PolicyDefinitions folder found'/>

        <TextBlock Text='PolicyDefinitions folder' FontWeight='SemiBold' Margin='0,8,0,0'/>
        <Grid ColumnDefinitions='*,Auto'>
            <TextBox Name='pathTextBox' Watermark='Path of a PolicyDefinitions folder'/>
            <Button Grid.Column='1' Name='browseButton' Content='Browse...' Margin='8,0,0,0'/>
        </Grid>

        <TextBlock Text='Language of the ADML files' FontWeight='SemiBold' Margin='0,8,0,0'/>
        <ComboBox Name='cultureComboBox' HorizontalAlignment='Stretch' PlaceholderText='Choose a folder first'/>

        <TextBlock Name='statusTextBlock' TextWrapping='Wrap' Margin='0,8,0,0'/>

        <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Spacing='8' Margin='0,8,0,0'>
            <Button Name='cancelButton' Content='Cancel' Width='110'/>
            <Button Name='loadButton' Content='Load' Width='110' IsDefault='True' Classes='accent'/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml $xaml))
    Set-PSGPOWindowIcon -Window $window
    $controls = @{ Window = $window }
    foreach ($name in 'candidateComboBox', 'pathTextBox', 'browseButton', 'cultureComboBox', 'statusTextBlock', 'cancelButton', 'loadButton') {
        $controls[$name] = Get-PSGPOAvaloniaControl $window $name
    }
    $candidateComboBox = $controls.candidateComboBox
    $pathTextBox = $controls.pathTextBox
    $browseButton = $controls.browseButton
    $cultureComboBox = $controls.cultureComboBox
    $statusTextBlock = $controls.statusTextBlock
    $cancelButton = $controls.cancelButton
    $loadButton = $controls.loadButton
    $state = @{ Loaded = $false; Busy = $false }
    $settings = Get-PSGPOUserSetting
    $red = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))

    function Set-Status {
        param([string]$Text, [switch]$Problem)
        $statusTextBlock.Text = $Text
        if ($Problem) { $statusTextBlock.Foreground = $red } else { $statusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # The languages of the folder typed or chosen; the detected one (or the one chosen last) selected.
    function Update-Culture {
        $path = "$($pathTextBox.Text)".Trim()
        $cultureComboBox.ItemsSource = $null
        $loadButton.IsEnabled = $false
        if (-not $path) { Set-Status (Get-PSGPOText 'Choose a PolicyDefinitions folder.'); return }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { Set-Status (Get-PSGPOText "The folder '{0}' does not exist." $path) -Problem; return }
        $admx = @(Get-ChildItem -LiteralPath $path -File -Filter '*.admx' -ErrorAction SilentlyContinue).Count
        if (-not $admx) { Set-Status (Get-PSGPOText "No .admx file in '{0}': choose the PolicyDefinitions folder itself." $path) -Problem; return }
        try {
            $language = Resolve-PSGPOAdmxCulture -Path $path
        } catch {
            Set-Status $_.Exception.Message -Problem
            return
        }
        $cultureComboBox.ItemsSource = $language.Available
        $chosen = $language.Culture
        if ($settings.UICulture -and $language.Available -contains $settings.UICulture -and
            [string]::Equals("$($settings.PolicyDefinitions)", $path, [System.StringComparison]::OrdinalIgnoreCase)) { $chosen = $settings.UICulture }
        if ($chosen) { $cultureComboBox.SelectedItem = $chosen }
        $count = "$admx ADMX files, $($language.Available.Count) language$(if ($language.Available.Count -gt 1) { 's' })"
        if ($chosen) { Set-Status "$count." } else { Set-Status "$count`: choose the language of the ADML files." }
        $loadButton.IsEnabled = [bool]$chosen
    }

    $candidates = @(Get-PSGPOAdmxCandidate)
    $candidateComboBox.ItemsSource = $candidates
    $candidateComboBox.IsEnabled = $candidates.Count -gt 0
    $candidateComboBox.add_SelectionChanged({ if ($candidateComboBox.SelectedItem) { $pathTextBox.Text = "$($candidateComboBox.SelectedItem)" } })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $pathTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-Culture }
    })
    $cultureComboBox.add_SelectionChanged({ $loadButton.IsEnabled = -not $state.Busy -and $null -ne $cultureComboBox.SelectedItem })

    # The folder chosen last, else the first one found.
    $initial = if ($settings.PolicyDefinitions -and (Test-Path -LiteralPath $settings.PolicyDefinitions -PathType Container)) { $settings.PolicyDefinitions }
        elseif ($candidates.Count) { $candidates[0] }
    if ($initial -and $candidates -contains $initial) { $candidateComboBox.SelectedItem = $initial }
    elseif ($initial) { $pathTextBox.Text = $initial }
    else { Update-Culture }

    # Folder picker of the system (xdg-desktop-portal on Linux), when there is one: the result is
    # awaited by a timer, as the UI thread cannot block on it.
    $browseButton.IsVisible = $null -ne $window.StorageProvider -and $window.StorageProvider.CanPickFolder
    $browseButton.Add_Click({
        $options = [Avalonia.Platform.Storage.FolderPickerOpenOptions]::new()
        $options.Title = Get-PSGPOText 'PolicyDefinitions folder'
        $options.AllowMultiple = $false
        # In $state: the handlers run once this one has returned.
        $state.Picking = $window.StorageProvider.OpenFolderPickerAsync($options)
        $state.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $state.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $state.Timer.Add_Tick({
            if (-not $state.Picking.IsCompleted) { return }
            $state.Timer.Stop()
            if ($state.Picking.IsCompletedSuccessfully -and $state.Picking.Result.Count) {
                $pathTextBox.Text = $state.Picking.Result[0].Path.LocalPath
            }
        })
        $state.Timer.Start()
    })

    $cancelButton.Add_Click({ $window.Close() })
    $loadButton.Add_Click({
        # In $state: the posted action runs once this handler has returned.
        $state.Path = "$($pathTextBox.Text)".Trim()
        $state.Culture = "$($cultureComboBox.SelectedItem)"
        if (-not $state.Path -or -not $state.Culture) { return }
        $state.Busy = $true
        $loadButton.IsEnabled = $false
        $cancelButton.IsEnabled = $false
        Set-Status (Get-PSGPOText 'Loading the ADMX files of {0} in {1}...' $state.Path $state.Culture)
        # Posted after the rendering, so that the message shows while the files load.
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try {
                Initialize-PSGPOAdmx -Path $state.Path -UICulture $state.Culture -WarningAction SilentlyContinue
                Set-PSGPOUserSetting -Values @{ PolicyDefinitions = $state.Path; UICulture = $state.Culture }
                $state.Loaded = $true
                $window.Close()
            } catch {
                Set-Status (Get-PSGPOText 'The ADMX files cannot be loaded: {0}' $_.Exception.GetBaseException().Message) -Problem
                $state.Busy = $false
                $loadButton.IsEnabled = $true
                $cancelButton.IsEnabled = $true
            }
        }, [Avalonia.Threading.DispatcherPriority]::Background)
    })

    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $cts.Cancel() }, [Avalonia.Threading.DispatcherPriority]::Background)
    })
    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { if ($window.IsVisible) { $window.Close() } }
        })
    }
    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        # Expected: the loop exits by cancellation once the window is closed.
        Write-Verbose 'The window is closed.'
    }
    if ($onShownState.Error) { throw $onShownState.Error }
    $state.Loaded
}
