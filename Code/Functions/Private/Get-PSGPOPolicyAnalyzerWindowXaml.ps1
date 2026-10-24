<#
    XAML of the Show-PolicyAnalyzerAvalonia window (Start-PSGPOPolicyAnalyzerWindow): its header
    (logo, title, theme), then the Policy Analyzer (Get-PSGPOPolicyAnalyzerViewXaml): the rule
    sets | their comparison.
#>

function Get-PSGPOPolicyAnalyzerWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Policy Analyzer'
        Width='1400' Height='860'
        MinWidth='1000' MinHeight='600'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='PolicyAnalyzerWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*'>

        <!-- Header: logo, title, theme -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='Auto,*,Auto'>
                <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                       RenderOptions.BitmapInterpolationMode='HighQuality'/>
                <StackPanel Grid.Column='1' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <TextBlock Text='Policy Analyzer' FontSize='22' FontWeight='Bold' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource TextBrush}'/>
                    <TextBlock Name='subtitleTextBlock' Text='GPOs and security baselines compared setting by setting' FontSize='12'
                               TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Text, RelativeSource={RelativeSource Self}}'
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

$(Get-PSGPOPolicyAnalyzerViewXaml)
    </Grid>
</Window>
"@
}
