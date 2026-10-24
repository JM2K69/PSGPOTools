<#
    XAML of the Start-HGPM window (Start-PSGPOLauncherWindow): a tile for each console of HGPM,
    added to toolsPanel by the code.
#>

function Get-PSGPOLauncherWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='HGPM'
        Width='1000' Height='340'
        MinWidth='420' MinHeight='300'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='LauncherWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*,Auto'>

        <!-- Header: logo, title, theme -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*,Auto'>
                <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                       RenderOptions.BitmapInterpolationMode='HighQuality'/>
                <StackPanel Grid.Column='1' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <TextBlock Text='HGPM' FontSize='22' FontWeight='Bold' Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Text='Choose a console' FontSize='12' TextTrimming='CharacterEllipsis'
                               Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                </StackPanel>
                <Button Grid.Column='2' Name='themeToggleButton' Height='36' Width='140' VerticalAlignment='Center'>
                    <StackPanel Orientation='Horizontal' Spacing='8'>
                        <PathIcon Name='themeToggleIcon' Data='{StaticResource Icon.weather-moon}'/>
                        <TextBlock Name='themeToggleText' Text='Dark mode' VerticalAlignment='Center'/>
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
    </Grid>
</Window>
"@
}
