<#
    XAML of the Show-WmiFilterCreatorAvalonia window (Start-PSGPOWmiFilterCreatorWindow): the
    library of queries (the ready-made queries of Resources/WmiFilters.json and the query builder)
    | the WMI filter being written, its queries checked, tested on the computer, exported to a .mof
    file or created in the domain.
#>

function Get-PSGPOWmiFilterCreatorWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='WMI Filter Creator'
        Width='1280' Height='820'
        MinWidth='900' MinHeight='560'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='WmiFilterCreatorWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,Auto,*,Auto'>

        <!-- Header: logo, title, new, open, theme -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*,Auto'>
                <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                       RenderOptions.BitmapInterpolationMode='HighQuality'/>
                <StackPanel Grid.Column='1' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <TextBlock Text='WMI Filter Creator' FontSize='22' FontWeight='Bold' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Text='Build, check and test the WMI filters of the GPOs, then export them to .mof or create them in the domain' FontSize='12'
                               TextTrimming='CharacterEllipsis' Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>
                <StackPanel Grid.Column='2' Orientation='Horizontal' Spacing='12' VerticalAlignment='Center'>
                    <Button Name='newFilterButton' Height='36' ToolTip.Tip='Start a new WMI filter'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.add}'/>
                            <TextBlock Text='New' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='openFilterButton' Height='36' ToolTip.Tip='Open a .mof file exported by GPMC or HGPM'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.arrow-import}'/>
                            <TextBlock Text='Open .mof...' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='themeToggleButton' Height='36' Width='140'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Name='themeToggleIcon' Data='{StaticResource Icon.weather-moon}'/>
                            <TextBlock Name='themeToggleText' Text='Dark mode' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Open a .mof file: its path, read on Open -->
        <Border Grid.Row='1' Name='openPanel' IsVisible='False' Margin='16,12,16,0' Padding='12' CornerRadius='6' BorderThickness='1'
                BorderBrush='{DynamicResource BorderBrush}' Background='{DynamicResource SecondaryBackgroundBrush}'>
            <StackPanel Spacing='6'>
                <TextBlock Text='Open a WMI filter from a .mof file' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                <Grid ColumnDefinitions='*,Auto,Auto,Auto'>
                    <TextBox Grid.Column='0' Name='openPathTextBox' Watermark='Path of the .mof file'/>
                    <Button Grid.Column='1' Name='openBrowseButton' Content='Browse...' Margin='6,0,0,0'/>
                    <Button Grid.Column='2' Name='openConfirmButton' Content='Open' Margin='6,0,0,0' Classes='accent'/>
                    <Button Grid.Column='3' Name='openCancelButton' Content='Cancel' Margin='6,0,0,0'/>
                </Grid>
                <TextBlock Name='openErrorTextBlock' TextWrapping='Wrap' Foreground='#D13438'/>
            </StackPanel>
        </Border>

        <Grid Grid.Row='2' ColumnDefinitions='5*,Auto,6*'>

            <!-- Library of queries: the ready-made ones and the builder -->
            <Border Grid.Column='0' Background='{DynamicResource BackgroundBrush}' Margin='16,16,4,16' CornerRadius='8'
                    BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0' Background='{DynamicResource HeaderBackgroundBrush}' Padding='16,12' CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.library}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                <TextBlock Text='Query library' FontSize='15' FontWeight='SemiBold' Foreground='{DynamicResource HeaderTextBrush}'/>
                            </StackPanel>
                            <TextBlock Text='Pick a ready-made query or build one, then add it to the filter' FontSize='11' Margin='24,2,0,0' TextWrapping='Wrap'
                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                    </Border>
                    <TabControl Grid.Row='1' Name='libraryTabControl' Margin='8,4,8,8'>
                        <TabItem Header='Ready-made queries' FontSize='14'>
                            <Grid RowDefinitions='Auto,*,Auto' Margin='0,8,0,0'>
                                <Grid Grid.Row='0' ColumnDefinitions='*,Auto'>
                                    <TextBox Grid.Column='0' Name='templateSearchTextBox' Watermark='Search a query' FontSize='12'/>
                                    <ComboBox Grid.Column='1' Name='templateCategoryComboBox' MinWidth='170' Margin='6,0,0,0' FontSize='12'/>
                                </Grid>
                                <ListBox Grid.Row='1' Name='templatesList' Margin='0,8,0,8' MinHeight='140' ScrollViewer.HorizontalScrollBarVisibility='Disabled'>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel Spacing='2' Margin='0,2'>
                                                <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource TextBrush}'/>
                                                <TextBlock Text='{Binding Category}' FontSize='11' Foreground='{DynamicResource PrimaryBrush}'/>
                                                <TextBlock Text='{Binding Description}' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <!-- The selected query: at most half of the card, the list keeps the rest -->
                                <Border Grid.Row='2' Padding='10,10,0,10' CornerRadius='6' Background='{DynamicResource SecondaryBackgroundBrush}' MaxHeight='320'>
                                    <ScrollViewer HorizontalScrollBarVisibility='Disabled'>
                                        <StackPanel Spacing='6' Margin='0,0,12,0'>
                                            <TextBlock Name='templateEmptyTextBlock' Text='Select a query of the list.' FontSize='12' TextWrapping='Wrap'
                                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <TextBlock Name='templateNoteTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <StackPanel Name='templateParametersPanel' Spacing='6'/>
                                            <TextBlock Name='templateQueryTextBlock' FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace' FontSize='12'
                                                       TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Name='templateErrorTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='#D13438'/>
                                            <Button Name='addTemplateButton' HorizontalAlignment='Right' Classes='accent' IsEnabled='False'>
                                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                                    <PathIcon Data='{StaticResource Icon.add}'/>
                                                    <TextBlock Text='Add to the filter' VerticalAlignment='Center'/>
                                                </StackPanel>
                                            </Button>
                                        </StackPanel>
                                    </ScrollViewer>
                                </Border>
                            </Grid>
                        </TabItem>
                        <TabItem Header='Query builder' FontSize='14'>
                            <ScrollViewer HorizontalScrollBarVisibility='Disabled'>
                                <StackPanel Spacing='6' Margin='0,8,12,0'>
                                    <TextBlock Text='Class' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <ComboBox Name='builderClassComboBox' HorizontalAlignment='Stretch' FontSize='12'/>
                                    <TextBlock Name='builderClassTextBlock' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <Grid ColumnDefinitions='3*,2*' Margin='0,6,0,0'>
                                        <StackPanel Grid.Column='0' Spacing='4' Margin='0,0,6,0'>
                                            <TextBlock Text='Property' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <ComboBox Name='builderPropertyComboBox' HorizontalAlignment='Stretch' FontSize='12'/>
                                        </StackPanel>
                                        <StackPanel Grid.Column='1' Spacing='4'>
                                            <TextBlock Text='Operator' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                            <ComboBox Name='builderOperatorComboBox' HorizontalAlignment='Stretch' FontSize='12'/>
                                        </StackPanel>
                                    </Grid>
                                    <TextBlock Name='builderPropertyTextBlock' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <TextBlock Text='Value' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <Grid ColumnDefinitions='*,Auto'>
                                        <TextBox Grid.Column='0' Name='builderValueTextBox' FontSize='12' Watermark='% stands for any text with LIKE'/>
                                        <ComboBox Grid.Column='1' Name='builderKnownValueComboBox' MinWidth='170' Margin='6,0,0,0' FontSize='12'
                                                  PlaceholderText='Known values' IsVisible='False'/>
                                    </Grid>
                                    <StackPanel Orientation='Horizontal' Spacing='6'>
                                        <ComboBox Name='builderJoinComboBox' MinWidth='80' FontSize='12'/>
                                        <Button Name='builderAddConditionButton'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.add}'/>
                                                <TextBlock Text='Add the condition' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                        <Button Name='builderRemoveConditionButton' IsEnabled='False' ToolTip.Tip='Remove the selected condition'>
                                            <PathIcon Data='{StaticResource Icon.delete}'/>
                                        </Button>
                                    </StackPanel>
                                    <ListBox Name='builderConditionsList' MinHeight='60' MaxHeight='160' FontSize='12'
                                             FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace'/>
                                    <TextBlock Text='Query' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <TextBlock Name='builderQueryTextBlock' FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace' FontSize='12'
                                               TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                    <TextBlock Name='builderErrorTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='#D13438'/>
                                    <Button Name='builderAddQueryButton' HorizontalAlignment='Right' Classes='accent' Margin='0,0,0,8'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.add}'/>
                                            <TextBlock Text='Add to the filter' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                </StackPanel>
                            </ScrollViewer>
                        </TabItem>
                    </TabControl>
                </Grid>
            </Border>

            <GridSplitter Grid.Column='1' Width='6' Background='Transparent' ResizeDirection='Columns'/>

            <!-- The WMI filter: its name, description and queries; test, export, create -->
            <Border Grid.Column='2' Background='{DynamicResource BackgroundBrush}' Margin='4,16,16,16' CornerRadius='8'
                    BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                <Grid RowDefinitions='Auto,*'>
                    <Border Grid.Row='0' Background='{DynamicResource HeaderBackgroundBrush}' Padding='16,12' CornerRadius='8,8,0,0'>
                        <StackPanel>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.filter}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                <TextBlock Text='WMI filter' FontSize='15' FontWeight='SemiBold' Foreground='{DynamicResource HeaderTextBrush}'/>
                            </StackPanel>
                            <TextBlock Text='A computer applies the GPOs linked to the filter only when each of its queries returns something' FontSize='11'
                                       Margin='24,2,0,0' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                    </Border>
                    <ScrollViewer Grid.Row='1' HorizontalScrollBarVisibility='Disabled'>
                        <StackPanel Spacing='6' Margin='16,12,20,16'>
                            <TextBlock Text='Name' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBox Name='filterNameTextBox' Watermark='Name of the filter, unique in the domain'/>
                            <TextBlock Text='Description' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBox Name='filterDescriptionTextBox' Watermark='What the filter is for'/>
                            <Grid ColumnDefinitions='*,Auto' Margin='0,8,0,0'>
                                <TextBlock Grid.Column='0' Name='queriesHeaderTextBlock' Text='Queries' FontWeight='SemiBold' VerticalAlignment='Center'
                                           Foreground='{DynamicResource TextBrush}'/>
                                <StackPanel Grid.Column='1' Orientation='Horizontal' Spacing='6'>
                                    <Button Name='newQueryButton' ToolTip.Tip='Add an empty query, to write'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.edit}'/>
                                            <TextBlock Text='Write a query' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                    <Button Name='removeQueryButton' IsEnabled='False' ToolTip.Tip='Remove the selected query'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.delete}'/>
                                            <TextBlock Text='Remove' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                </StackPanel>
                            </Grid>
                            <Panel>
                                <ListBox Name='queriesList' MinHeight='90' MaxHeight='220' ScrollViewer.HorizontalScrollBarVisibility='Disabled'>
                                    <ListBox.ItemTemplate>
                                        <DataTemplate>
                                            <StackPanel Spacing='2' Margin='0,2'>
                                                <TextBlock Text='{Binding Query}' FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace' FontSize='12'
                                                           TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                                    <TextBlock Text='{Binding Namespace}' FontSize='11' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    <TextBlock Text='{Binding Status}' FontSize='11' Foreground='{Binding StatusBrush}' TextWrapping='Wrap'/>
                                                </StackPanel>
                                            </StackPanel>
                                        </DataTemplate>
                                    </ListBox.ItemTemplate>
                                </ListBox>
                                <TextBlock Name='queriesEmptyTextBlock' Margin='12' TextWrapping='Wrap' VerticalAlignment='Center' HorizontalAlignment='Center'
                                           Foreground='{DynamicResource SecondaryTextBrush}' IsHitTestVisible='False'
                                           Text='No query yet: add one from the library, or write it.'/>
                            </Panel>
                            <!-- The selected query, as it is written -->
                            <StackPanel Name='queryEditorPanel' Spacing='4' IsVisible='False'>
                                <TextBlock Text='Namespace' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <Grid ColumnDefinitions='*,Auto'>
                                    <TextBox Grid.Column='0' Name='queryNamespaceTextBox' FontSize='12'/>
                                    <ComboBox Grid.Column='1' Name='queryKnownNamespaceComboBox' MinWidth='150' Margin='6,0,0,0' FontSize='12' PlaceholderText='Known namespaces'/>
                                </Grid>
                                <TextBlock Text='WQL query' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <TextBox Name='queryTextBox' TextWrapping='Wrap' MinHeight='60' FontSize='12'
                                         FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace'/>
                                <TextBlock Name='querySyntaxTextBlock' FontSize='12' TextWrapping='Wrap'/>
                            </StackPanel>

                            <TextBlock Name='filterStatusTextBlock' FontSize='12' TextWrapping='Wrap' Margin='0,6,0,0' Foreground='#D13438'/>

                            <!-- Test of the queries on this computer -->
                            <Border Padding='10' CornerRadius='6' Background='{DynamicResource SecondaryBackgroundBrush}' Margin='0,6,0,0'>
                                <StackPanel Spacing='6'>
                                    <Grid ColumnDefinitions='*,Auto'>
                                        <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                                            <TextBlock Text='Test' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                                            <TextBlock Name='testHintTextBlock' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                                       Text='Runs each query on this computer, as Windows evaluates the filter before it applies a GPO'/>
                                        </StackPanel>
                                        <Button Grid.Column='1' Name='testButton' Margin='8,0,0,0' IsEnabled='False'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.desktop}'/>
                                                <TextBlock Text='Test on this computer' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                    </Grid>
                                    <TextBlock Name='testSummaryTextBlock' FontWeight='SemiBold' TextWrapping='Wrap' IsVisible='False'/>
                                    <ItemsControl Name='testResultsList'>
                                        <ItemsControl.ItemTemplate>
                                            <DataTemplate>
                                                <StackPanel Spacing='1' Margin='0,3'>
                                                    <TextBlock Text='{Binding ResultText}' FontSize='12' FontWeight='SemiBold' Foreground='{Binding ResultBrush}'/>
                                                    <TextBlock Text='{Binding Query}' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                                               FontFamily='Cascadia Mono,Consolas,Menlo,DejaVu Sans Mono,monospace'/>
                                                    <TextBlock Text='{Binding Error}' FontSize='11' TextWrapping='Wrap' Foreground='#D13438'
                                                               IsVisible='{Binding Error, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                                </StackPanel>
                                            </DataTemplate>
                                        </ItemsControl.ItemTemplate>
                                    </ItemsControl>
                                </StackPanel>
                            </Border>

                            <!-- Export to a .mof file, as GPMC exports a filter -->
                            <Border Padding='10' CornerRadius='6' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                <StackPanel Spacing='6'>
                                    <TextBlock Text='Export' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                                    <TextBlock Text='A .mof file in the format of GPMC: Import... on WMI Filters in GPMC or HGPM creates the filter in a domain'
                                               FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <Grid ColumnDefinitions='*,Auto,Auto'>
                                        <TextBox Grid.Column='0' Name='exportPathTextBox' FontSize='12' Watermark='Path of the .mof file'/>
                                        <Button Grid.Column='1' Name='exportBrowseButton' Content='Browse...' Margin='6,0,0,0'/>
                                        <Button Grid.Column='2' Name='exportButton' Margin='6,0,0,0' Classes='accent' IsEnabled='False'>
                                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                                <PathIcon Data='{StaticResource Icon.arrow-export}'/>
                                                <TextBlock Name='exportButtonTextBlock' Text='Export .mof' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Button>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <!-- Create in the domain, as New... on WMI Filters -->
                            <Border Padding='10' CornerRadius='6' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                <Grid ColumnDefinitions='*,Auto'>
                                    <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                                        <TextBlock Text='Domain' FontWeight='SemiBold' Foreground='{DynamicResource TextBrush}'/>
                                        <TextBlock Name='domainHintTextBlock' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    </StackPanel>
                                    <Button Grid.Column='1' Name='createInDomainButton' Margin='8,0,0,0' IsEnabled='False'>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.organization}'/>
                                            <TextBlock Text='Create in the domain' VerticalAlignment='Center'/>
                                        </StackPanel>
                                    </Button>
                                </Grid>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Border>
        </Grid>

        <!-- What the last action did -->
        <TextBlock Grid.Row='3' Name='resultTextBlock' IsVisible='False' TextWrapping='Wrap' Margin='20,0,20,14'/>
    </Grid>
</Window>
"@
}
