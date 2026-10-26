<#
    Private implementation of Show-WmiFilterCreatorAvalonia: builds the window, wires its handlers
    and runs the Avalonia loop until the window closes.

    The filter is written on the right: its name, description and queries, each query checked as
    it is typed (Test-PSGPOWqlSyntax). The queries come from the library on the left, the
    ready-made queries of Resources/WmiFilters.json with their parameters, or the query builder (a
    class, its properties, conditions), or are written. The test runs the queries on this computer
    (Windows) in a runspace of its own, so that the window stays responsive; the export writes a
    .mof file in the format of GPMC; the domain is read on the first creation, when the window got
    none.

    -OnShown exists for the GUI tests, as for Start-PSGPOManagerWindow: the scriptblock receives a
    hashtable of the named controls, runs inside the loop once the window is shown, and the window
    is then closed. Event handlers keep resolving the local variables below because this function
    scope stays alive for the whole loop.
#>

function Start-PSGPOWmiFilterCreatorWindow {
    [CmdletBinding()]
    param(
        # The filter shown at start: an object with Name, Description and Queries (Namespace,
        # Query), as ConvertFrom-PSGPOWmiFilterMof gives it.
        [AllowNull()] $Filter,

        # The domain the filters are created in; read with -DomainParameters on the first creation
        # when not given.
        [AllowNull()] [GPOToolsDirectory]$Directory,

        # Parameters of Get-PSGPODirectory (Server, Credential, UseSsl).
        [hashtable]$DomainParameters = @{},

        # Language of the interface; English by default, so that the tests do not depend on the
        # language of the computer: Show-WmiFilterCreatorAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml (Get-PSGPOWmiFilterCreatorWindowXaml)))
    Set-PSGPOWindowIcon -Window $window
    $names = 'logoImage', 'newFilterButton', 'openFilterButton', 'themeToggleButton', 'themeToggleIcon', 'themeToggleText',
    'openPanel', 'openPathTextBox', 'openBrowseButton', 'openConfirmButton', 'openCancelButton', 'openErrorTextBlock',
    'libraryTabControl', 'templateSearchTextBox', 'templateCategoryComboBox', 'templatesList', 'templateEmptyTextBlock', 'templateNoteTextBlock',
    'templateParametersPanel', 'templateQueryTextBlock', 'templateErrorTextBlock', 'addTemplateButton',
    'builderClassComboBox', 'builderClassTextBlock', 'builderPropertyComboBox', 'builderOperatorComboBox', 'builderPropertyTextBlock',
    'builderValueTextBox', 'builderKnownValueComboBox', 'builderJoinComboBox', 'builderAddConditionButton', 'builderRemoveConditionButton',
    'builderConditionsList', 'builderQueryTextBlock', 'builderErrorTextBlock', 'builderAddQueryButton',
    'filterNameTextBox', 'filterDescriptionTextBox', 'queriesHeaderTextBlock', 'newQueryButton', 'removeQueryButton', 'queriesList', 'queriesEmptyTextBlock',
    'queryEditorPanel', 'queryNamespaceTextBox', 'queryKnownNamespaceComboBox', 'queryTextBox', 'querySyntaxTextBlock', 'filterStatusTextBlock',
    'testHintTextBlock', 'testButton', 'testSummaryTextBlock', 'testResultsList',
    'exportPathTextBox', 'exportBrowseButton', 'exportButton', 'exportButtonTextBlock', 'domainHintTextBlock', 'createInDomainButton', 'resultTextBlock'
    $ui = @{}
    foreach ($name in $names) { $ui[$name] = Get-PSGPOAvaloniaControl $window $name }
    $ui.logoImage.Source = New-PSGPOLogoBitmap
    $red = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
    $green = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#107C10'))
    $catalog = Get-PSGPOWmiCatalog

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1).
    Register-PSGPOThemeWindow -Window $window -ToggleText $ui.themeToggleText -ToggleIcon $ui.themeToggleIcon
    $ui.themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # The filter being written: its queries, and what a .mof file opened gave (Id, author, dates,
    # domain), kept by the export.
    $rows = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    $ui.queriesList.ItemsSource = $rows
    $state = @{ Updating = $false; Id = [guid]::NewGuid(); Author = $null; CreationDate = $null; Domain = $null; ExportPathAuto = $true; ExportReplace = $null; ConfirmNew = $false }
    $domain = @{ Directory = $Directory; Parameters = $DomainParameters }

    function Show-Result {
        param([string]$Text, [switch]$Problem)
        if ($Problem) { Write-PSGPOLogEntry -Level Error -Source 'WMI creator' -Message $Text }
        $ui.resultTextBlock.Text = $Text
        $ui.resultTextBlock.IsVisible = [bool]$Text
        $ui.resultTextBlock.Foreground = if ($Problem) { $red } else { $green }
    }

    # A row of the queries, checked.
    function New-QueryRow {
        param([string]$Namespace, [string]$Query)
        $row = [AvaloniaWmiQueryRow]::new()
        $row.Namespace = if ("$Namespace".Trim()) { "$Namespace".Trim() } else { 'root\CIMv2' }
        $row.Query = "$Query".Trim()
        $check = Test-PSGPOWqlSyntax -Query $row.Query -Namespace $row.Namespace
        if (-not $check.IsValid) {
            $row.Status = Get-PSGPOText 'Not valid: {0}' $check.Error
            $row.StatusBrush = '#D13438'
        } elseif ($check.Warning) {
            $row.Status = $check.Warning
            $row.StatusBrush = '#8A6100'
        } else {
            $row.Status = Get-PSGPOText 'Valid WQL'
        }
        $row
    }

    # What the filter lacks before it is tested, exported or created; the buttons follow.
    function Update-Filter {
        $ui.queriesEmptyTextBlock.IsVisible = $rows.Count -eq 0
        $ui.queriesHeaderTextBlock.Text = Get-PSGPOText 'Queries ({0})' $rows.Count
        $problems = [System.Collections.Generic.List[string]]::new()
        if (-not "$($ui.filterNameTextBox.Text)".Trim()) { $problems.Add((Get-PSGPOText 'Give the filter a name.')) }
        if (-not $rows.Count) { $problems.Add((Get-PSGPOText 'Add at least one query.')) }
        $invalid = @($rows | Where-Object StatusBrush -EQ '#D13438').Count
        if ($invalid) { $problems.Add((Get-PSGPOText '{0} query(ies) not valid: correct or remove them.' $invalid)) }
        $ui.filterStatusTextBlock.Text = $problems -join ' '
        $ui.filterStatusTextBlock.IsVisible = $problems.Count -gt 0
        $queriesReady = $rows.Count -gt 0 -and -not $invalid
        $ui.testButton.IsEnabled = $IsWindows -and $queriesReady -and -not $test.PowerShell
        $ui.exportButton.IsEnabled = -not $problems.Count
        $ui.createInDomainButton.IsEnabled = -not $problems.Count -and ($domain.Directory -or $domain.Parameters.Server -or (Get-PSGPOPlatform).DomainName)
        $ui.removeQueryButton.IsEnabled = $null -ne $ui.queriesList.SelectedItem
        if ($state.ExportPathAuto) {
            $state.Updating = $true
            # No Documents folder on a Linux account without one: its home.
            $documents = [Environment]::GetFolderPath('MyDocuments')
            if (-not $documents) { $documents = $HOME }
            $ui.exportPathTextBox.Text = Join-Path $documents (Get-PSGPOWmiFilterFileName -Name $(if ("$($ui.filterNameTextBox.Text)".Trim()) { $ui.filterNameTextBox.Text } else { 'WMI filter' }))
            $state.Updating = $false
        }
        $state.ConfirmNew = $false
    }

    function Add-FilterQuery {
        param([string]$Namespace, [string]$Query)
        $rows.Add((New-QueryRow -Namespace $Namespace -Query $Query))
        $ui.queriesList.SelectedIndex = $rows.Count - 1
        Clear-TestResult
        Update-Filter
    }

    # The selected query in the editor.
    function Show-SelectedQuery {
        $row = $ui.queriesList.SelectedItem
        $ui.queryEditorPanel.IsVisible = $null -ne $row
        $ui.removeQueryButton.IsEnabled = $null -ne $row
        if (-not $row) { return }
        $state.Updating = $true
        $ui.queryNamespaceTextBox.Text = $row.Namespace
        $ui.queryTextBox.Text = $row.Query
        Show-QuerySyntax -Row $row
        $state.Updating = $false
    }

    function Show-QuerySyntax {
        param($Row)
        $ui.querySyntaxTextBlock.Text = $Row.Status
        $ui.querySyntaxTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse($Row.StatusBrush))
    }

    # The query typed replaces the selected row, checked again.
    function Update-SelectedQuery {
        if ($state.Updating) { return }
        $index = $ui.queriesList.SelectedIndex
        if ($index -lt 0) { return }
        $row = New-QueryRow -Namespace $ui.queryNamespaceTextBox.Text -Query $ui.queryTextBox.Text
        $state.Updating = $true
        $rows[$index] = $row
        $ui.queriesList.SelectedIndex = $index
        $state.Updating = $false
        Show-QuerySyntax -Row $row
        Clear-TestResult
        Update-Filter
    }

    $ui.queriesList.add_SelectionChanged({ if (-not $state.Updating) { Show-SelectedQuery } })
    foreach ($box in $ui.queryNamespaceTextBox, $ui.queryTextBox) {
        # The property, not TextChanged: it is raised at once, whoever sets the text.
        $box.add_PropertyChanged({
            param($control, $e)
            if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-SelectedQuery }
        })
    }
    $ui.queryKnownNamespaceComboBox.ItemsSource = [string[]]@($catalog.Namespaces)
    $ui.queryKnownNamespaceComboBox.add_SelectionChanged({
        $chosen = $ui.queryKnownNamespaceComboBox.SelectedItem
        if (-not $chosen) { return }
        $ui.queryNamespaceTextBox.Text = $chosen
        $ui.queryKnownNamespaceComboBox.SelectedIndex = -1
    })
    $ui.newQueryButton.Add_Click({
        $rows.Add((New-QueryRow -Namespace 'root\CIMv2' -Query 'SELECT * FROM Win32_OperatingSystem WHERE '))
        $ui.queriesList.SelectedIndex = $rows.Count - 1
        Update-Filter
        $ui.queryTextBox.Focus()
        $ui.queryTextBox.CaretIndex = $ui.queryTextBox.Text.Length
    })
    $ui.removeQueryButton.Add_Click({
        $index = $ui.queriesList.SelectedIndex
        if ($index -lt 0) { return }
        $rows.RemoveAt($index)
        if ($rows.Count) { $ui.queriesList.SelectedIndex = [math]::Min($index, $rows.Count - 1) } else { Show-SelectedQuery }
        Clear-TestResult
        Update-Filter
    })
    foreach ($box in $ui.filterNameTextBox, $ui.filterDescriptionTextBox) {
        $box.add_PropertyChanged({
            param($control, $e)
            if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty -and -not $state.Updating) { Update-Filter }
        })
    }

    # ---- Ready-made queries ----------------------------------------------------------------
    $templateItems = @(foreach ($template in @($catalog.Templates)) {
            $item = [AvaloniaWmiTemplateItem]::new()
            $item.Name = Get-PSGPOText $template.Name
            $item.Category = Get-PSGPOText $template.Category
            $item.Description = Get-PSGPOText $template.Description
            $item.Template = $template
            $item
        })
    $categories = @($catalog.Templates.Category | Select-Object -Unique)
    $ui.templateCategoryComboBox.ItemsSource = [string[]](@(Get-PSGPOText 'All categories') + @($categories | ForEach-Object { Get-PSGPOText $_ }))
    $ui.templateCategoryComboBox.SelectedIndex = 0
    $templateState = @{ Item = $null; Inputs = @{} }

    function Update-TemplateList {
        $search = "$($ui.templateSearchTextBox.Text)".Trim()
        $category = if ($ui.templateCategoryComboBox.SelectedIndex -gt 0) { $categories[$ui.templateCategoryComboBox.SelectedIndex - 1] }
        # Typed: the pipeline wraps the items in PSObjects, which the bindings do not read.
        $ui.templatesList.ItemsSource = [AvaloniaWmiTemplateItem[]]@($templateItems | Where-Object {
                (-not $category -or $_.Template.Category -eq $category) -and
                (-not $search -or $_.Name -like "*$search*" -or $_.Description -like "*$search*" -or $_.Template.Query -like "*$search*" -or $_.Template.Name -like "*$search*")
            })
    }

    # The parameters of a query, and its text once they are given.
    function Show-Template {
        $item = $ui.templatesList.SelectedItem
        $templateState.Item = $item
        $templateState.Inputs = @{}
        $ui.templateParametersPanel.Children.Clear()
        $ui.templateEmptyTextBlock.IsVisible = -not $item
        $ui.templateNoteTextBlock.Text = ''
        $ui.templateQueryTextBlock.Text = ''
        $ui.templateErrorTextBlock.Text = ''
        $ui.addTemplateButton.IsEnabled = $false
        if (-not $item) { return }
        $template = $item.Template
        $ui.templateNoteTextBlock.Text = (@($(if ($template.Note) { Get-PSGPOText $template.Note }), $(if ($template.Source) { Get-PSGPOText 'Source: {0}' $template.Source })) | Where-Object { $_ }) -join [Environment]::NewLine
        $ui.templateNoteTextBlock.IsVisible = [bool]$ui.templateNoteTextBlock.Text
        foreach ($parameter in @($template.Parameters)) {
            if (-not $parameter) { continue }
            $label = [Avalonia.Controls.TextBlock]::new()
            $label.Text = Get-PSGPOText $parameter.Label
            $label.FontSize = 12
            $ui.templateParametersPanel.Children.Add($label)
            if ($parameter.Kind -eq 'Choice') {
                $field = [Avalonia.Controls.ComboBox]::new()
                $field.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Stretch
                $field.ItemsSource = [string[]]@($parameter.Choices | ForEach-Object { Get-PSGPOText $_.Text })
                $default = [array]::IndexOf([string[]]@($parameter.Choices.Value), "$($parameter.Default)")
                $field.SelectedIndex = [math]::Max(0, $default)
                $field.add_SelectionChanged({ Update-TemplatePreview })
            } else {
                $field = [Avalonia.Controls.TextBox]::new()
                $field.Text = "$($parameter.Default)"
                if ($parameter.Hint) { $field.Watermark = Get-PSGPOText $parameter.Hint }
                $field.add_PropertyChanged({
                    param($control, $e)
                    if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-TemplatePreview }
                })
            }
            $field.FontSize = 12
            $field.Tag = $parameter
            $templateState.Inputs[$parameter.Name] = $field
            $ui.templateParametersPanel.Children.Add($field)
        }
        Update-TemplatePreview
    }

    function Get-TemplateQuery {
        $values = @{}
        foreach ($name in $templateState.Inputs.Keys) {
            $field = $templateState.Inputs[$name]
            # A choice by its index: its text is translated.
            $values[$name] = if ($field -is [Avalonia.Controls.ComboBox]) { if ($field.SelectedIndex -ge 0) { @($field.Tag.Choices)[$field.SelectedIndex].Value } } else { $field.Text }
        }
        New-PSGPOWmiTemplateQuery -Template $templateState.Item.Template -Values $values
    }

    function Update-TemplatePreview {
        if (-not $templateState.Item) { return }
        try {
            $ui.templateQueryTextBlock.Text = Get-TemplateQuery
            $ui.templateErrorTextBlock.Text = ''
            $ui.addTemplateButton.IsEnabled = $true
        } catch {
            $ui.templateQueryTextBlock.Text = $templateState.Item.Template.Query
            $ui.templateErrorTextBlock.Text = $_.Exception.Message
            $ui.addTemplateButton.IsEnabled = $false
        }
    }

    $ui.templateSearchTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-TemplateList }
    })
    $ui.templateCategoryComboBox.add_SelectionChanged({ Update-TemplateList })
    $ui.templatesList.add_SelectionChanged({ Show-Template })
    $ui.addTemplateButton.Add_Click({
        if (-not $templateState.Item) { return }
        try { $query = Get-TemplateQuery } catch { $ui.templateErrorTextBlock.Text = $_.Exception.Message; return }
        Add-FilterQuery -Namespace $templateState.Item.Template.Namespace -Query $query
        if (-not "$($ui.filterNameTextBox.Text)".Trim()) { $ui.filterNameTextBox.Text = $templateState.Item.Name }
        Show-Result -Text (Get-PSGPOText "'{0}' added to the filter." $templateState.Item.Name)
    })
    $ui.templatesList.add_DoubleTapped({ if ($ui.addTemplateButton.IsEnabled) { $ui.addTemplateButton.RaiseEvent([Avalonia.Interactivity.RoutedEventArgs]::new([Avalonia.Controls.Button]::ClickEvent)) } })
    Update-TemplateList
    Show-Template

    # ---- Query builder ---------------------------------------------------------------------
    $classes = @($catalog.Classes)
    $builder = @{ Conditions = [System.Collections.Generic.List[object]]::new() }
    $ui.builderClassComboBox.ItemsSource = [string[]]@($classes | ForEach-Object { "$($_.Name)  ($($_.Namespace))" })
    $ui.builderJoinComboBox.ItemsSource = [string[]]@('AND', 'OR')
    $ui.builderJoinComboBox.SelectedIndex = 0

    function Get-BuilderClass { if ($ui.builderClassComboBox.SelectedIndex -ge 0) { $classes[$ui.builderClassComboBox.SelectedIndex] } }
    function Get-BuilderProperty {
        $class = Get-BuilderClass
        if ($class -and $ui.builderPropertyComboBox.SelectedIndex -ge 0) { @($class.Properties)[$ui.builderPropertyComboBox.SelectedIndex] }
    }

    function Show-BuilderClass {
        $class = Get-BuilderClass
        $builder.Conditions.Clear()
        $ui.builderClassTextBlock.Text = if ($class) {
            $text = Get-PSGPOText $class.Description
            if ($class.Warning) { $text += ' ' + (Get-PSGPOText $class.Warning) }
            $text
        } else { '' }
        $ui.builderPropertyComboBox.ItemsSource = [string[]]@(if ($class) { $class.Properties.Name })
        $ui.builderPropertyComboBox.SelectedIndex = if ($class) { 0 } else { -1 }
        Update-BuilderQuery
    }

    function Show-BuilderProperty {
        $property = Get-BuilderProperty
        # The type by its name in the interface: a String is a Text.
        $ui.builderPropertyTextBlock.Text = if ($property) { "$(Get-PSGPOText $(if ($property.Type -eq 'String') { 'Text' } else { $property.Type })) - $(Get-PSGPOText $property.Description)" } else { '' }
        $operators = switch ($property.Type) {
            'Number' { '=', '<>', '>=', '<=', '>', '<', 'IS NULL', 'IS NOT NULL' }
            'Boolean' { '=', '<>' }
            default { '=', '<>', 'LIKE', 'NOT LIKE', '>=', '<=', 'IS NULL', 'IS NOT NULL' }
        }
        $ui.builderOperatorComboBox.ItemsSource = [string[]]@($operators)
        $ui.builderOperatorComboBox.SelectedIndex = 0
        $known = @($property.Values | Where-Object { $_ })
        $ui.builderKnownValueComboBox.ItemsSource = [string[]]@($known | ForEach-Object { "$($_.Value) - $(Get-PSGPOText $_.Text)" })
        $ui.builderKnownValueComboBox.IsVisible = $known.Count -gt 0
        $ui.builderValueTextBox.Text = if ($property.Type -eq 'Boolean') { 'TRUE' } else { '' }
    }

    function Update-BuilderQuery {
        $class = Get-BuilderClass
        # The first condition alone, the others after their AND / OR.
        $conditions = @($builder.Conditions)
        $ui.builderConditionsList.ItemsSource = [string[]]@(for ($index = 0; $index -lt $conditions.Count; $index++) {
                if ($index -eq 0) { $conditions[$index].Text } else { "$($conditions[$index].Join) $($conditions[$index].Text)" }
            })
        $ui.builderRemoveConditionButton.IsEnabled = $false
        if (-not $class) { $ui.builderQueryTextBlock.Text = ''; $ui.builderAddQueryButton.IsEnabled = $false; return }
        $query = "SELECT * FROM $($class.Name)"
        if ($builder.Conditions.Count) { $query += ' WHERE ' + (@($ui.builderConditionsList.ItemsSource) -join ' ') }
        $ui.builderQueryTextBlock.Text = $query
        $ui.builderAddQueryButton.IsEnabled = $true
    }

    $ui.builderClassComboBox.add_SelectionChanged({ Show-BuilderClass })
    $ui.builderPropertyComboBox.add_SelectionChanged({ Show-BuilderProperty })
    $ui.builderOperatorComboBox.add_SelectionChanged({ $ui.builderValueTextBox.IsEnabled = "$($ui.builderOperatorComboBox.SelectedItem)" -notlike 'IS*' })
    $ui.builderKnownValueComboBox.add_SelectionChanged({
        $property = Get-BuilderProperty
        $index = $ui.builderKnownValueComboBox.SelectedIndex
        if (-not $property -or $index -lt 0) { return }
        $ui.builderValueTextBox.Text = "$(@($property.Values)[$index].Value)"
    })
    $ui.builderAddConditionButton.Add_Click({
        $property = Get-BuilderProperty
        if (-not $property) { return }
        try {
            $text = New-PSGPOWqlCondition -Property $property.Name -Type $property.Type -Operator $ui.builderOperatorComboBox.SelectedItem -Value $ui.builderValueTextBox.Text
        } catch {
            $ui.builderErrorTextBlock.Text = $_.Exception.Message
            return
        }
        $ui.builderErrorTextBlock.Text = ''
        $builder.Conditions.Add([pscustomobject]@{ Join = $ui.builderJoinComboBox.SelectedItem; Text = $text })
        Update-BuilderQuery
    })
    $ui.builderConditionsList.add_SelectionChanged({ $ui.builderRemoveConditionButton.IsEnabled = $ui.builderConditionsList.SelectedIndex -ge 0 })
    $ui.builderRemoveConditionButton.Add_Click({
        $index = $ui.builderConditionsList.SelectedIndex
        if ($index -lt 0) { return }
        $builder.Conditions.RemoveAt($index)
        Update-BuilderQuery
    })
    $ui.builderAddQueryButton.Add_Click({
        $class = Get-BuilderClass
        if (-not $class) { return }
        Add-FilterQuery -Namespace $class.Namespace -Query $ui.builderQueryTextBlock.Text
        Show-Result -Text (Get-PSGPOText 'Query added to the filter: {0}' $ui.builderQueryTextBlock.Text)
    })
    $ui.builderClassComboBox.SelectedIndex = 0

    # ---- Test on this computer -------------------------------------------------------------
    $test = @{ PowerShell = $null; Handle = $null; Timer = $null }
    if (-not $IsWindows) {
        $ui.testHintTextBlock.Text = Get-PSGPOText 'WMI is a service of Windows: test the filter on a Windows computer, with Test-PSGPOWmiFilter.'
    }

    function Clear-TestResult {
        $ui.testSummaryTextBlock.IsVisible = $false
        $ui.testResultsList.ItemsSource = @()
    }

    function Start-FilterTest {
        if ($test.PowerShell -or -not $rows.Count) { return }
        $queries = @($rows | ForEach-Object { [pscustomobject]@{ Namespace = $_.Namespace; Query = $_.Query } })
        $script = "param(`$Query)`nfunction Invoke-PSGPOWmiQueryTest {`n$(${function:Invoke-PSGPOWmiQueryTest})`n}`nInvoke-PSGPOWmiQueryTest -Query `$Query"
        $test.PowerShell = [powershell]::Create()
        [void]$test.PowerShell.AddScript($script).AddArgument($queries)
        $test.Handle = $test.PowerShell.BeginInvoke()
        $ui.testButton.IsEnabled = $false
        $ui.testSummaryTextBlock.Text = Get-PSGPOText 'Test running on {0}...' ([Environment]::MachineName)
        $ui.testSummaryTextBlock.Foreground = $ui.testHintTextBlock.Foreground
        $ui.testSummaryTextBlock.IsVisible = $true
        $ui.testResultsList.ItemsSource = @()
        $test.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $test.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $test.Timer.Add_Tick({ if ($test.Handle.IsCompleted) { Complete-FilterTest } })
        $test.Timer.Start()
    }

    function Complete-FilterTest {
        $test.Timer.Stop()
        try {
            $results = @($test.PowerShell.EndInvoke($test.Handle))
            $failure = if ($test.PowerShell.Streams.Error.Count) { $test.PowerShell.Streams.Error[0].Exception.Message }
        } catch {
            $results = @()
            $failure = $_.Exception.GetBaseException().Message
        } finally {
            $test.PowerShell.Dispose()
            $test.PowerShell = $null
        }
        $ui.testResultsList.ItemsSource = [AvaloniaWmiTestRow[]]@(foreach ($result in $results) {
                $row = [AvaloniaWmiTestRow]::new()
                $row.Query = $result.Query
                switch ($result.Result) {
                    'Match' { $row.ResultText = Get-PSGPOText 'True: the query returns something'; $row.ResultBrush = '#107C10' }
                    'NoMatch' { $row.ResultText = Get-PSGPOText 'False: the query returns nothing'; $row.ResultBrush = '#D13438' }
                    default { $row.ResultText = Get-PSGPOText 'False: the query fails'; $row.ResultBrush = '#D13438'; $row.Error = $result.Error }
                }
                $row
            })
        $applies = $results.Count -gt 0 -and -not @($results | Where-Object Result -NE 'Match').Count
        $ui.testSummaryTextBlock.Text = if (-not $results.Count) { Get-PSGPOText 'The test did not run: {0}' $failure }
        elseif ($applies) { Get-PSGPOText 'The filter is True on {0}: this computer applies the GPOs linked to it.' ([Environment]::MachineName) }
        else { Get-PSGPOText 'The filter is False on {0}: this computer does not apply the GPOs linked to it.' ([Environment]::MachineName) }
        $ui.testSummaryTextBlock.Foreground = if ($applies) { $green } else { $red }
        Update-Filter
    }
    $ui.testButton.Add_Click({ Start-FilterTest })

    # ---- .mof files --------------------------------------------------------------------------
    # File pickers of the system (xdg-desktop-portal on Linux), when there is one: the result is
    # awaited by a timer, as the UI thread cannot block on it; $Done gets the path chosen.
    $filePicker = @{ Task = $null; Timer = $null; Done = $null }
    function Start-MofFilePicker {
        param([switch]$Save, [string]$Title, [string]$Path, [Parameter(Mandatory)] [scriptblock]$Done)
        $type = [Avalonia.Platform.Storage.FilePickerFileType]::new((Get-PSGPOText 'WMI filter (.mof)'))
        $type.Patterns = [string[]]@('*.mof')
        if ($Save) {
            $options = [Avalonia.Platform.Storage.FilePickerSaveOptions]::new()
            $options.SuggestedFileName = [System.IO.Path]::GetFileName($Path)
            $options.DefaultExtension = 'mof'
            $options.FileTypeChoices = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
        } else {
            $options = [Avalonia.Platform.Storage.FilePickerOpenOptions]::new()
            $options.AllowMultiple = $false
            $options.FileTypeFilter = [Avalonia.Platform.Storage.FilePickerFileType[]]@($type)
        }
        $options.Title = $Title
        $filePicker.Done = $Done
        $filePicker.Task = if ($Save) { $window.StorageProvider.SaveFilePickerAsync($options) } else { $window.StorageProvider.OpenFilePickerAsync($options) }
        $filePicker.Timer = [Avalonia.Threading.DispatcherTimer]::new()
        $filePicker.Timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $filePicker.Timer.Add_Tick({
            if (-not $filePicker.Task.IsCompleted) { return }
            $filePicker.Timer.Stop()
            if (-not $filePicker.Task.IsCompletedSuccessfully) { return }
            $chosen = $filePicker.Task.Result
            if ($chosen -isnot [Avalonia.Platform.Storage.IStorageFile]) { $chosen = @($chosen) | Select-Object -First 1 }
            if ($chosen) { & $filePicker.Done $chosen.Path.LocalPath }
        })
        $filePicker.Timer.Start()
    }
    $canPick = $null -ne $window.StorageProvider
    $ui.exportBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanSave
    $ui.openBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanOpen

    # The filter shown: a .mof file opened, or nothing (New).
    function Set-Filter {
        param($Value)
        $state.Updating = $true
        $ui.filterNameTextBox.Text = if ($Value) { $Value.Name } else { '' }
        $ui.filterDescriptionTextBox.Text = if ($Value) { $Value.Description } else { '' }
        $state.Updating = $false
        $rows.Clear()
        foreach ($query in @(if ($Value) { $Value.Queries })) { $rows.Add((New-QueryRow -Namespace $query.Namespace -Query $query.Query)) }
        $state.Id = if ($Value -and $Value.Id -and $Value.Id -ne [guid]::Empty) { $Value.Id } else { [guid]::NewGuid() }
        $state.Author = if ($Value) { $Value.Author }
        $state.CreationDate = if ($Value) { $Value.CreationDate }
        $state.Domain = if ($Value) { $Value.Domain }
        $state.ExportPathAuto = $true
        $state.ExportReplace = $null
        $ui.exportButtonTextBlock.Text = Get-PSGPOText 'Export .mof'
        if ($rows.Count) { $ui.queriesList.SelectedIndex = 0 } else { Show-SelectedQuery }
        Clear-TestResult
        Update-Filter
    }

    function Read-MofFile {
        $file = "$($ui.openPathTextBox.Text)".Trim().Trim('"')
        if (-not $file) { $ui.openErrorTextBlock.Text = Get-PSGPOText 'Give the .mof file to open.'; return }
        try {
            $filters = @(ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($file)))
        } catch {
            $ui.openErrorTextBlock.Text = Get-PSGPOText '{0} cannot be opened: {1}' $file $_.Exception.GetBaseException().Message
            return
        }
        $ui.openErrorTextBlock.Text = ''
        $ui.openPanel.IsVisible = $false
        Set-Filter -Value $filters[0]
        Show-Result -Text $(if ($filters.Count -gt 1) { Get-PSGPOText "{0} holds {1} WMI filters: the first one, '{2}', is opened." $file $filters.Count $filters[0].Name }
            else { Get-PSGPOText "WMI filter '{0}' opened from {1}." $filters[0].Name $file })
    }

    $ui.openFilterButton.Add_Click({
        $ui.openPanel.IsVisible = $true
        $ui.openErrorTextBlock.Text = ''
        $ui.openPathTextBox.Focus()
    })
    $ui.openBrowseButton.Add_Click({ Start-MofFilePicker -Title (Get-PSGPOText 'Open a WMI filter') -Done { param($Path) $ui.openPathTextBox.Text = $Path; Read-MofFile } })
    $ui.openConfirmButton.Add_Click({ Read-MofFile })
    $ui.openCancelButton.Add_Click({ $ui.openPanel.IsVisible = $false })
    $ui.openPathTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-MofFile }
    })
    $ui.newFilterButton.Add_Click({
        # A filter with queries is cleared once confirmed.
        if ($rows.Count -and -not $state.ConfirmNew) {
            Show-Result -Problem -Text (Get-PSGPOText 'Click New again to clear the filter: its queries are not kept.')
            $state.ConfirmNew = $true
            return
        }
        Set-Filter -Value $null
        Show-Result -Text ''
    })

    # The filter as GPOToolsWmiFilter, for the .mof file and the domain.
    function New-FilterObject {
        $value = [GPOToolsWmiFilter]::new()
        $value.Id = $state.Id
        $value.Name = "$($ui.filterNameTextBox.Text)".Trim()
        $value.Description = "$($ui.filterDescriptionTextBox.Text)".Trim()
        $value.Queries = @($rows | ForEach-Object { [pscustomobject]@{ Namespace = $_.Namespace; Query = $_.Query } })
        $value.Author = if ($state.Author) { $state.Author } else { "$([Environment]::UserDomainName)\$([Environment]::UserName)" }
        $value.CreationDate = if ($state.CreationDate) { $state.CreationDate } else { [GPOToolsWmiFilter]::GetDate() }
        $value.ChangeDate = [GPOToolsWmiFilter]::GetDate()
        $value
    }

    function Get-FilterDomainName {
        if ($state.Domain) { return $state.Domain }
        if ($domain.Directory) { return $domain.Directory.DomainName }
        $platform = Get-PSGPOPlatform
        if ($platform.DomainName) { return $platform.DomainName }
        if ($env:USERDNSDOMAIN) { return $env:USERDNSDOMAIN.ToLowerInvariant() }
        [Environment]::UserDomainName
    }

    function Submit-Export {
        $file = "$($ui.exportPathTextBox.Text)".Trim().Trim('"')
        if (-not $file) { Show-Result -Problem -Text (Get-PSGPOText 'Give the file of the export.'); return }
        if (-not $file.EndsWith('.mof', [System.StringComparison]::OrdinalIgnoreCase)) { $file += '.mof' }
        if ((Test-Path -LiteralPath $file) -and $state.ExportReplace -ne $file) {
            $state.ExportReplace = $file
            $ui.exportButtonTextBlock.Text = Get-PSGPOText 'Replace'
            Show-Result -Problem -Text (Get-PSGPOText '{0} exists: Replace writes the filter over it.' $file)
            return
        }
        try {
            $folder = [System.IO.Path]::GetDirectoryName($file)
            if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
            [System.IO.File]::WriteAllBytes($file, (ConvertTo-PSGPOWmiFilterMofByte -Filter (New-FilterObject) -Domain (Get-FilterDomainName)))
        } catch {
            Show-Result -Problem -Text (Get-PSGPOText 'The WMI filter is not exported: {0}' $_.Exception.GetBaseException().Message)
            return
        }
        $state.ExportReplace = $null
        $ui.exportButtonTextBlock.Text = Get-PSGPOText 'Export .mof'
        Show-Result -Text (Get-PSGPOText "WMI filter '{0}' exported to {1}: GPMC imports it in another domain, as Import... in the context menu of WMI Filters does." "$($ui.filterNameTextBox.Text)".Trim() $file)
    }
    $ui.exportPathTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property -ne [Avalonia.Controls.TextBox]::TextProperty -or $state.Updating) { return }
        # A path typed is kept; another file is confirmed again before it is replaced.
        $state.ExportPathAuto = $false
        if ($state.ExportReplace) {
            $state.ExportReplace = $null
            $ui.exportButtonTextBlock.Text = Get-PSGPOText 'Export .mof'
        }
    })
    $ui.exportBrowseButton.Add_Click({ Start-MofFilePicker -Save -Title (Get-PSGPOText 'Export the WMI filter') -Path $ui.exportPathTextBox.Text -Done { param($Path) $ui.exportPathTextBox.Text = $Path } })
    $ui.exportButton.Add_Click({ Submit-Export })

    # ---- Domain ------------------------------------------------------------------------------
    function Update-DomainHint {
        $name = if ($domain.Directory) { $domain.Directory.DomainName } elseif ($domain.Parameters.Server) { $domain.Parameters.Server } else { (Get-PSGPOPlatform).DomainName }
        $ui.domainHintTextBlock.Text = if ($name) { Get-PSGPOText 'Creates the filter in {0}, with the rights of the account, as New... on WMI Filters.' $name }
        else { Get-PSGPOText 'No domain discovered: give -Server to Show-WmiFilterCreatorAvalonia to create the filter in a domain, or export it.' }
    }

    function Submit-CreateInDomain {
        try {
            if (-not $domain.Directory) {
                $parameters = $domain.Parameters
                $domain.Directory = Get-PSGPODirectory @parameters -ErrorAction Stop
                Update-DomainHint
            }
            $directory = $domain.Directory
            if ($directory.IsReadOnly -or -not $directory.CanCreateWmiFilter) { throw (Get-PSGPOText 'The account {0} cannot create WMI filters in {1}.' $directory.Account $directory.DomainName) }
            Use-PSGPODomainConfiguration -Directory $directory
            $created = $directory.NewWmiFilter("$($ui.filterNameTextBox.Text)".Trim(), "$($ui.filterDescriptionTextBox.Text)".Trim(), @($rows | ForEach-Object { [pscustomobject]@{ Namespace = $_.Namespace; Query = $_.Query } }))
        } catch {
            Show-Result -Problem -Text (Get-PSGPOText 'The WMI filter is not created: {0}' $_.Exception.GetBaseException().Message)
            return
        }
        $state.Id = $created.Id
        Show-Result -Text (Get-PSGPOText "WMI filter '{0}' created in {1}: link a GPO to it in Group Policy Management." $created.Name $domain.Directory.DomainName)
    }
    $ui.createInDomainButton.Add_Click({ Submit-CreateInDomain })
    Update-DomainHint

    Set-Filter -Value $Filter

    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        if ($test.PowerShell) { $test.Timer.Stop(); $test.PowerShell.Stop(); $test.PowerShell.Dispose(); $test.PowerShell = $null }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $cts.Cancel() }, [Avalonia.Threading.DispatcherPriority]::Background)
    })
    Show-PSGPOWindow -Window $window

    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Rows = $rows } + $ui
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
