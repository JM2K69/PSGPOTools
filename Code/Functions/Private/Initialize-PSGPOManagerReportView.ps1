<#
    The Settings tab of the GPO selected: the settings of its folder read once per version, in the
    language of the interface, and its report saved as an HTML page.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerReportView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerReportView {
    # Settings tab of the selected GPO: the files of its folder read once per version of the GPO
    # (Get-PSGPOFolderSetting), what the console does not interpret below its settings.
    $settingsCache = @{}
    function Update-SettingsTab {
        $gpo = Get-SelectedGpo
        $settingsTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $settingsTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $settingsTab) { return }
        # The policies named by the ADMX files: the tab once they are loaded.
        if (Wait-ConsoleAdmx -Then ${function:Update-SettingsTab}) {
            $settingsStatusTextBlock.Text = Get-PSGPOText 'Loading the administrative templates (ADMX)...'
            return
        }

        $cached = $settingsCache["$($gpo.Id)"]
        if (-not $cached -or $cached.Version -ne $gpo.Version) {
            $cached = @{ Version = $gpo.Version; Machine = @(); User = @(); Uninterpreted = @(); Error = $null }
            try {
                # Windows Settings first (scripts, security settings), then the policies of
                # Registry.pol, then the preferences, as GPMC lists them.
                $settings = Get-PSGPOFolderSetting -Files $Directory.ReadGpoFolder($gpo) -MachineExtensionNames $gpo.MachineExtensionNames -UserExtensionNames $gpo.UserExtensionNames
                foreach ($part in 'Machine', 'User', 'Uninterpreted') { $cached[$part] = $settings.$part }
            } catch {
                $cached.Error = Get-PSGPOText 'The settings of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message
            }
            # In the language of the interface: the rows come from functions the commands share.
            foreach ($part in 'Machine', 'User', 'Uninterpreted') { $cached[$part] = @(foreach ($row in $cached[$part]) { ConvertTo-DisplaySettingRow $row }) }
            $settingsCache["$($gpo.Id)"] = $cached
        }
        $settingsStatusTextBlock.Text = if ($cached.Error) { $cached.Error }
            elseif ([GPOToolsUtility]::Policies.Count -eq 0) { Get-PSGPOText 'No ADMX loaded (Initialize-PSGPOAdmx): the values are shown as Extra Registry Settings.' }
            else { Get-PSGPOText 'Settings of {0} (version: computer {1}, user {2})' $gpo.DisplayName $gpo.GetComputerVersion() $gpo.GetUserVersion() }
        $computerState = Get-PSGPOText $(if ($gpo.Flags -band 2) { 'Disabled' } else { 'Enabled' })
        $userState = Get-PSGPOText $(if ($gpo.Flags -band 1) { 'Disabled' } else { 'Enabled' })
        $computerSettingsHeader.Text = Get-PSGPOText $(if ($cached.Machine.Count) { 'Computer Configuration ({0})' } else { 'Computer Configuration ({0}): no settings defined' }) $computerState
        $userSettingsHeader.Text = Get-PSGPOText $(if ($cached.User.Count) { 'User Configuration ({0})' } else { 'User Configuration ({0}): no settings defined' }) $userState
        $computerSettingsList.ItemsSource = $cached.Machine
        $userSettingsList.ItemsSource = $cached.User
        $uninterpretedSettingsBorder.IsVisible = $cached.Uninterpreted.Count -gt 0
        $uninterpretedSettingsHeader.Text = Get-PSGPOText 'Settings the console does not interpret ({0})' $cached.Uninterpreted.Count
        $uninterpretedSettingsList.ItemsSource = $cached.Uninterpreted
    }
    # Save report... of the Settings tab and of the context menu, as GPMC: the report of the GPO as
    # an HTML page or an XML document (Get-PSGPOReport), or in a format an add-on gives, by the
    # extension of the file; in the language of the interface; its result under the button, or in
    # the Details tab from the context menu (FromMenu).
    $gpoReport = @{ Gpo = $null; FromMenu = $false; Path = $null }
    function Save-GpoReport {
        param([Parameter(Mandatory)] [string]$Path)
        $gpo = $gpoReport.Gpo
        if (-not $gpo) { return }
        if (Wait-ConsoleAdmx -Then ${function:Save-GpoReport} -ArgumentList $Path) { return }
        # In the background: it reads the folder of the GPO, and an add-on may print it.
        $gpoReport.Path = $Path
        $null = Start-ConsoleOperation -Text (Get-PSGPOText 'Saving the report of {0}...' $gpo.DisplayName) -ScriptBlock {
            param($Directory, $Gpo, $Path)
            $report = @(Get-PSGPOReportData -Directory $Directory -Gpo $Gpo)
            if ([System.IO.Path]::GetExtension($Path) -eq '.xml') {
                [System.IO.File]::WriteAllText($Path, (ConvertTo-PSGPOReportXml -Report $report), [System.Text.UTF8Encoding]::new($false))
            } else {
                $null = Write-PSGPOReportHtmlFile -Html (ConvertTo-PSGPOReportHtml -Report $report) -Path $Path
            }
        } -ArgumentList $Directory, $gpo, $Path -Done {
            Show-GpoReportResult -Text (Get-PSGPOText 'Report saved: {0}' $gpoReport.Path)
        } -Failed {
            param($ErrorRecord)
            Show-GpoReportResult -Text (Get-PSGPOText 'The report is not saved: {0}' $ErrorRecord.Exception.GetBaseException().Message) -Problem
        } -Cancelled {
            Show-GpoReportResult -Text (Get-PSGPOText 'The report is not saved: cancelled.') -Problem
        }
    }

    # Where the report saved says it: the details of the domain (from the menu), else the Settings tab.
    function Show-GpoReportResult {
        param([string]$Text, [switch]$Problem)
        if ($gpoReport.FromMenu) {
            Show-DirectoryDetailsTab
            Show-DirectoryResult -Text $Text -Problem:$Problem
            return
        }
        if ($Problem) { $settingsReportStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $settingsReportStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
        $settingsReportStatusTextBlock.Text = $Text
    }
    function Start-GpoReportSave {
        param([switch]$FromMenu)
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        $gpoReport.Gpo = $gpo
        $gpoReport.FromMenu = [bool]$FromMenu
        $settingsReportStatusTextBlock.Text = ''
        # A name of file: the name of the GPO without the characters a file name cannot have.
        $invalid = [System.IO.Path]::GetInvalidFileNameChars()
        $file = (-join @($gpo.DisplayName.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })) + '.html'
        Start-FilePicker -Save -Title (Get-PSGPOText 'Save the report of the GPO') -Path $file -Types (Get-GpoReportFileType) -Done { param($Path) Save-GpoReport -Path $Path }
    }
    # The types of file of a report, as GPMC: an HTML page, an XML document, then those of the
    # add-ons loaded.
    function Get-GpoReportFileType {
        @{ Name = Get-PSGPOText 'HTML page'; Patterns = @('*.html') }
        @{ Name = Get-PSGPOText 'XML file'; Patterns = @('*.xml') }
        foreach ($format in @(Get-PSGPOAddOnReportFormat)) { @{ Name = $format.TypeName; Patterns = @("*.$($format.Extension)") } }
    }
    $settingsReportButton.IsVisible = $null -ne $window.StorageProvider -and $window.StorageProvider.CanSave
    $settingsReportButton.Add_Click({ Start-GpoReportSave })
    $saveReportGpoMenuItem.Add_Click({ Start-GpoReportSave -FromMenu })

    # A row of the Settings tab in the language of the interface (a copy: the row of the report
    # stays in English).
    function ConvertTo-DisplaySettingRow {
        param([AvaloniaSettingRow]$Row)
        $copy = [AvaloniaSettingRow]::new()
        $copy.Path = ConvertTo-PSGPODisplayText $Row.Path
        $copy.Name = ConvertTo-PSGPODisplayText $Row.Name
        $copy.State = ConvertTo-PSGPODisplayText $Row.State
        # A preference: its attributes (hive = HKEY_LOCAL_MACHINE) by the labels of its type, as
        # its form shows them (Hive: HKEY_LOCAL_MACHINE).
        $labels = @{}
        if ($Row.Path -like 'Policies > Preferences > *') {
            $extensionName = @($Row.Path -split ' > ')[3]
            foreach ($property in @(Get-PSGPOPreferenceCatalog | Where-Object Name -EQ $extensionName | ForEach-Object { $_.Items.Properties })) {
                if ($property.Name -and -not $labels.ContainsKey($property.Name)) { $labels[$property.Name] = $property.Label }
            }
        }
        $copy.Options = @("$($Row.Options)" -split '\r?\n' | ForEach-Object {
                if ($_ -match '^(\w+) = (.*)$' -and $labels.ContainsKey($Matches[1])) { Get-PSGPOText '{0}: {1}' (Get-PSGPOText $labels[$Matches[1]]) $Matches[2] }
                else { ConvertTo-PSGPODisplayText $_ }
            }) -join [Environment]::NewLine
        $copy.IsExtra = $Row.IsExtra
        $copy
    }
}
