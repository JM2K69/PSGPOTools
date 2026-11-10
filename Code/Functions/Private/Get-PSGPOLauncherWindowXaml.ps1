<#
    XAML of the Start-HGPM window (Start-PSGPOLauncherWindow): a tile for each console of HGPM,
    added to toolsPanel by the code, and About: the version of HGPM installed, the Hardenad
    community it comes from. Its texts are set by the code, in the language of the launcher.
#>

function Get-PSGPOLauncherWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='HGPM'
        Width='1240' Height='340'
        MinWidth='420' MinHeight='300'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='LauncherWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*,Auto'>

        <!-- Header: logo, title, language of the consoles, theme, About -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*,Auto,Auto,Auto'>
                <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                       RenderOptions.BitmapInterpolationMode='HighQuality'/>
                <StackPanel Grid.Column='1' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <TextBlock Text='HGPM' FontSize='22' FontWeight='Bold' Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Name='subtitleTextBlock' Text='Choose a console' FontSize='12' TextTrimming='CharacterEllipsis'
                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>
                <!-- The language of the launcher and of the consoles it opens, kept for the next time: an item
                     for each language of Resources/Strings, added by the code -->
                <ComboBox Grid.Column='2' Name='languageComboBox' Height='36' Width='130' Margin='0,0,12,0' VerticalAlignment='Center'
                          ToolTip.Tip='Language of the consoles'/>
                <Button Grid.Column='3' Name='themeToggleButton' Height='36' Width='140' VerticalAlignment='Center'>
                    <StackPanel Orientation='Horizontal' Spacing='8'>
                        <PathIcon Name='themeToggleIcon' Data='{StaticResource Icon.weather-moon}'/>
                        <TextBlock Name='themeToggleText' Text='Dark mode' VerticalAlignment='Center'/>
                    </StackPanel>
                </Button>
                <Button Grid.Column='4' Name='aboutButton' Height='36' Margin='12,0,0,0' VerticalAlignment='Center'>
                    <StackPanel Orientation='Horizontal' Spacing='8'>
                        <PathIcon Data='{StaticResource Icon.info}'/>
                        <TextBlock Name='aboutButtonText' Text='About' VerticalAlignment='Center'/>
                    </StackPanel>
                </Button>
            </Grid>
        </Border>

        <!-- The tiles of the consoles -->
        <ScrollViewer Grid.Row='1'>
            <WrapPanel Name='toolsPanel' Margin='14' HorizontalAlignment='Center'/>
        </ScrollViewer>

        <!-- Why a console did not open -->
        <TextBlock Grid.Row='2' Name='statusTextBlock' IsVisible='False' TextWrapping='Wrap' Margin='20,0,20,14'
                   Foreground='#D13438'/>

        <!-- About HGPM, over the tiles: its version and where it is installed, the Hardenad community -->
        <Border Grid.Row='0' Grid.RowSpan='3' Name='aboutPanel' IsVisible='False' Background='#99000000'>
            <Border Background='{DynamicResource BackgroundBrush}' BorderBrush='{DynamicResource BorderBrush}' BorderThickness='1'
                    CornerRadius='8' Padding='24,20' MaxWidth='560' Margin='16' HorizontalAlignment='Center' VerticalAlignment='Center'>
                <StackPanel Spacing='10'>
                    <StackPanel Orientation='Horizontal' Spacing='14'>
                        <Image Name='aboutLogoImage' Width='52' Height='52' VerticalAlignment='Center'
                               RenderOptions.BitmapInterpolationMode='HighQuality'/>
                        <StackPanel VerticalAlignment='Center'>
                            <TextBlock Text='HGPM' FontSize='22' FontWeight='Bold' Foreground='{DynamicResource TextBrush}'/>
                            <SelectableTextBlock Name='aboutVersionTextBlock' FontSize='13' Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </StackPanel>
                    </StackPanel>
                    <TextBlock Name='aboutDescriptionTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                    <StackPanel Orientation='Horizontal' Spacing='6'>
                        <TextBlock Name='aboutCommunityTextBlock' TextWrapping='Wrap' FontWeight='SemiBold' VerticalAlignment='Center'
                                   Foreground='{DynamicResource TextBrush}'/>
                        <HyperlinkButton Name='aboutHardenadLink' NavigateUri='https://hardenad.net/'
                                         Padding='0' VerticalAlignment='Center'/>
                    </StackPanel>
                    <SelectableTextBlock Name='aboutPathTextBlock' TextWrapping='Wrap' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                    <!-- An add-on installed and not loaded, and why (Get-PSGPOAddOnState). -->
                    <SelectableTextBlock Name='aboutAddOnTextBlock' TextWrapping='Wrap' FontSize='12' Foreground='#CA5010' IsVisible='False'/>
                    <SelectableTextBlock Name='aboutRuntimeTextBlock' TextWrapping='Wrap' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                    <StackPanel Orientation='Horizontal' Spacing='16'>
                        <HyperlinkButton Name='aboutDocsLink' Padding='0'/>
                        <HyperlinkButton Name='aboutSourceLink' NavigateUri='https://github.com/JM2K69/PSGPOTools' Padding='0'/>
                        <TextBlock Name='aboutLicenseTextBlock' VerticalAlignment='Center' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                    </StackPanel>
                    <Button Name='aboutCloseButton' HorizontalAlignment='Right' Margin='0,6,0,0' MinWidth='96'
                            HorizontalContentAlignment='Center'/>
                </StackPanel>
            </Border>
        </Border>
    </Grid>
</Window>
"@
}
