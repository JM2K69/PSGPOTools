<#
    XAML of the Show-PSOManagerAvalonia window (Start-PSGPOPasswordPolicyWindow): the fine-grained
    password policies of the domain (Password Settings view), and the ones a user or a group gets
    (Resultant Password Settings view).
#>

function Get-PSGPOPasswordPolicyWindowXaml {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @"
<Window xmlns='https://github.com/avaloniaui'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='PSO Manager'
        Width='1200' Height='720'
        MinWidth='800' MinHeight='500'
        WindowStartupLocation='CenterScreen'
        Background='{DynamicResource BackgroundBrush}'
        Name='PasswordPolicyWindow'>

$(Get-PSGPOWindowResourceXaml)

    <Grid RowDefinitions='Auto,*,Auto'>

        <!-- Header: logo, title, views, refresh, theme -->
        <Border Grid.Row='0' Background='{DynamicResource BackgroundBrush}' BorderThickness='0,0,0,1'
                BorderBrush='{DynamicResource BorderBrush}' Padding='20,16'>
            <Grid ColumnDefinitions='*,Auto'>
                <Grid Grid.Column='0' ColumnDefinitions='Auto,*' VerticalAlignment='Center' Margin='0,0,16,0'>
                    <Image Grid.Column='0' Name='logoImage' Width='44' Height='44' VerticalAlignment='Center' Margin='0,0,12,0'
                           RenderOptions.BitmapInterpolationMode='HighQuality'/>
                    <StackPanel Grid.Column='1' VerticalAlignment='Center'>
                        <TextBlock Text='PSO Manager' FontSize='22' FontWeight='Bold' TextTrimming='CharacterEllipsis'
                                   Foreground='{DynamicResource TextBrush}'/>
                        <TextBlock Name='subtitleTextBlock' Text='Fine-grained password policies' FontSize='12'
                                   TextTrimming='CharacterEllipsis' ToolTip.Tip='{Binding Text, RelativeSource={RelativeSource Self}}'
                                   Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,2,0,0'/>
                    </StackPanel>
                </Grid>
                <StackPanel Grid.Column='1' Orientation='Horizontal' HorizontalAlignment='Right' VerticalAlignment='Center' Spacing='12'>
                    <Button Name='policiesButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.key}'/>
                            <TextBlock Text='Password Settings' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='resultantButton' Height='36'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.people}'/>
                            <TextBlock Text='Resultant Password Settings' VerticalAlignment='Center'/>
                        </StackPanel>
                    </Button>
                    <Button Name='refreshButton' Height='36' ToolTip.Tip='Read the domain again (F5)'>
                        <StackPanel Orientation='Horizontal' Spacing='8'>
                            <PathIcon Data='{StaticResource Icon.arrow-sync}'/>
                            <TextBlock Text='Refresh' VerticalAlignment='Center'/>
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

        <Grid Grid.Row='1' RowDefinitions='Auto,Auto,*'>
            <!-- Shown when no domain was discovered and the sample policies are displayed -->
            <Border Grid.Row='0' Name='demoBanner' IsVisible='False' Margin='16,16,16,0' Padding='12,8'
                    CornerRadius='6' Background='#FFF4CE' BorderThickness='1' BorderBrush='#F2C94C'>
                <StackPanel Orientation='Horizontal' Spacing='8'>
                    <PathIcon Data='{StaticResource Icon.info}' Foreground='#8A6100'/>
                    <StackPanel>
                        <TextBlock FontWeight='SemiBold' TextWrapping='Wrap' Foreground='#3D2C00'
                                   Text='Demonstration environment: no Active Directory or Samba AD domain discovered'/>
                        <TextBlock FontSize='11' TextWrapping='Wrap' Foreground='#3D2C00'
                                   Text='The password settings shown are sample data and their changes stay in memory. Read a domain with Show-PSOManagerAvalonia -Server, or from a computer of the domain.'/>
                    </StackPanel>
                </StackPanel>
            </Border>
            <!-- Why the domain could not be read -->
            <Border Grid.Row='1' Name='errorBanner' IsVisible='False' Margin='16,16,16,0' Padding='12,8'
                    CornerRadius='6' BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                <TextBlock Name='errorBannerTextBlock' TextWrapping='Wrap' Foreground='#D13438'/>
            </Border>

            <!-- Password Settings view: the PSOs of the Password Settings Container | the selected one -->
            <Grid Grid.Row='2' Name='policiesView' ColumnDefinitions='3*,Auto,2*'>
                <Border Grid.Column='0' Background='{DynamicResource BackgroundBrush}' Margin='16,16,8,16' CornerRadius='8'
                        BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                    <Grid RowDefinitions='Auto,Auto,*,Auto'>
                        <Border Grid.Row='0' Background='{DynamicResource HeaderBackgroundBrush}' Padding='16,12' CornerRadius='8,8,0,0'>
                            <StackPanel>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.key}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                    <TextBlock Text='Password Settings Container' FontSize='15' FontWeight='SemiBold' Foreground='{DynamicResource HeaderTextBrush}'/>
                                </StackPanel>
                                <TextBlock Name='policiesHeaderTextBlock' FontSize='12' Margin='24,2,0,0' TextWrapping='Wrap'
                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                            </StackPanel>
                        </Border>
                        <StackPanel Grid.Row='1' Orientation='Horizontal' Spacing='8' Margin='12,10,12,4'>
                            <Button Name='newPolicyButton'>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.add}'/>
                                    <TextBlock Text='New...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='editPolicyButton'>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.edit}'/>
                                    <TextBlock Text='Properties...' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                            <Button Name='deletePolicyButton'>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.delete}'/>
                                    <TextBlock Text='Delete' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                        </StackPanel>
                        <Panel Grid.Row='2'>
                            <ListBox Name='policiesList' Margin='8,4,8,8' Background='Transparent'>
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Grid ColumnDefinitions='56,*,Auto' Margin='0,4'>
                                            <StackPanel Grid.Column='0' VerticalAlignment='Center'>
                                                <TextBlock Text='{Binding Precedence}' FontSize='18' FontWeight='SemiBold' HorizontalAlignment='Center'
                                                           Foreground='{DynamicResource PrimaryBrush}'/>
                                            </StackPanel>
                                            <StackPanel Grid.Column='1' Spacing='2'>
                                                <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextTrimming='CharacterEllipsis'/>
                                                <TextBlock Text='{Binding Summary}' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <TextBlock Text='{Binding Description}' FontSize='11' TextTrimming='CharacterEllipsis' Foreground='{DynamicResource SecondaryTextBrush}'
                                                           IsVisible='{Binding Description, Converter={x:Static StringConverters.IsNotNullOrEmpty}}'/>
                                            </StackPanel>
                                            <StackPanel Grid.Column='2' Orientation='Horizontal' Spacing='8' VerticalAlignment='Center' Margin='12,0,4,0'>
                                                <PathIcon Data='{StaticResource Icon.lock-closed}' Width='14' Height='14' Foreground='#CA5010' IsVisible='{Binding IsProtected}'/>
                                                <PathIcon Data='{StaticResource Icon.people}' Width='14' Height='14' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                <TextBlock Text='{Binding AppliesTo}' FontSize='12' VerticalAlignment='Center'/>
                                            </StackPanel>
                                        </Grid>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>
                            <TextBlock Name='policiesEmptyTextBlock' IsVisible='False' TextWrapping='Wrap' Margin='20' VerticalAlignment='Top'
                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                        </Panel>
                        <!-- The password policy of the domain: what applies without PSO -->
                        <Border Grid.Row='3' Margin='12,0,12,12' Padding='12,8' CornerRadius='6' Background='{DynamicResource SecondaryBackgroundBrush}'>
                            <StackPanel Spacing='2'>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.globe}' Width='14' Height='14' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                    <TextBlock Text='Default domain password policy' FontWeight='SemiBold' FontSize='12'/>
                                </StackPanel>
                                <TextBlock Name='domainPolicyTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <GridSplitter Grid.Column='1' Width='4' Background='Transparent' ResizeDirection='Columns'/>

                <Border Grid.Column='2' Background='{DynamicResource BackgroundBrush}' Margin='8,16,16,16' CornerRadius='8'
                        BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                    <ScrollViewer>
                        <StackPanel Margin='20,16' Spacing='4'>
                            <TextBlock Name='policyTitleTextBlock' FontSize='18' FontWeight='SemiBold' TextWrapping='Wrap'/>
                            <TextBlock Name='policyDescriptionTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBlock Name='policyResultTextBlock' TextWrapping='Wrap' Margin='0,8,0,0' IsVisible='False'/>

                            <Border Name='deletePolicyPanel' IsVisible='False' Margin='0,8,0,8' Padding='12' CornerRadius='4'
                                    BorderThickness='1' BorderBrush='#D13438' Background='{DynamicResource SecondaryBackgroundBrush}'>
                                <StackPanel Spacing='8'>
                                    <TextBlock Name='deletePolicyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource TextBrush}'/>
                                    <StackPanel Orientation='Horizontal' Spacing='8' HorizontalAlignment='Right'>
                                        <Button Name='deletePolicyConfirmButton' Content='Delete' Width='120'/>
                                        <Button Name='deletePolicyCancelButton' Content='Cancel' Width='100'/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <TextBlock Name='policyEmptyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                       Text='Select a password settings object to see its settings and the users and groups it applies to.'/>
                            <ItemsControl Name='policySettingsList' Margin='0,8,0,0'>
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Grid ColumnDefinitions='220,*' Margin='0,3'>
                                            <TextBlock Grid.Column='0' Text='{Binding Key}' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,0,12,0'/>
                                            <SelectableTextBlock Grid.Column='1' Text='{Binding Value}' TextWrapping='Wrap'/>
                                        </Grid>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                            <TextBlock Name='appliesToHeaderTextBlock' FontSize='12' FontWeight='SemiBold' Margin='0,16,0,4'
                                       Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <ItemsControl Name='appliesToList'>
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate>
                                        <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,6'>
                                            <Grid ColumnDefinitions='Auto,*'>
                                                <PathIcon Grid.Column='0' Data='{Binding IconData}' Margin='0,0,10,0' VerticalAlignment='Top' Foreground='{DynamicResource PrimaryBrush}'/>
                                                <StackPanel Grid.Column='1' Spacing='1'>
                                                    <StackPanel Orientation='Horizontal' Spacing='8'>
                                                        <TextBlock Text='{Binding Name}' FontWeight='SemiBold'/>
                                                        <TextBlock Text='{Binding Kind}' FontSize='12' VerticalAlignment='Center' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    </StackPanel>
                                                    <SelectableTextBlock Text='{Binding DistinguishedName}' FontSize='11' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                </StackPanel>
                                            </Grid>
                                        </Border>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </Grid>

            <!-- Resultant Password Settings view: users and groups | what applies to the selected one -->
            <Grid Grid.Row='2' Name='resultantView' ColumnDefinitions='2*,Auto,3*' IsVisible='False'>
                <Border Grid.Column='0' Background='{DynamicResource BackgroundBrush}' Margin='16,16,8,16' CornerRadius='8'
                        BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                    <Grid RowDefinitions='Auto,Auto,Auto,*'>
                        <Border Grid.Row='0' Background='{DynamicResource HeaderBackgroundBrush}' Padding='16,12' CornerRadius='8,8,0,0'>
                            <StackPanel Orientation='Horizontal' Spacing='8'>
                                <PathIcon Data='{StaticResource Icon.people}' Foreground='{DynamicResource HeaderTextBrush}'/>
                                <TextBlock Text='Users and groups' FontSize='15' FontWeight='SemiBold' Foreground='{DynamicResource HeaderTextBrush}'/>
                            </StackPanel>
                        </Border>
                        <Grid Grid.Row='1' ColumnDefinitions='*,Auto' Margin='12,12,12,4'>
                            <TextBox Grid.Column='0' Name='identitySearchTextBox' Watermark='Search a user or a group...' Height='34' VerticalContentAlignment='Center'/>
                            <Button Grid.Column='1' Name='identitySearchButton' Height='34' Margin='8,0,0,0'>
                                <StackPanel Orientation='Horizontal' Spacing='8'>
                                    <PathIcon Data='{StaticResource Icon.search}'/>
                                    <TextBlock Text='Search' VerticalAlignment='Center'/>
                                </StackPanel>
                            </Button>
                        </Grid>
                        <TextBlock Grid.Row='2' Name='identityStatusTextBlock' FontSize='12' TextWrapping='Wrap' Margin='14,4,12,4'
                                   Foreground='{DynamicResource SecondaryTextBrush}'/>
                        <ListBox Grid.Row='3' Name='identitiesList' Margin='8,4,8,8' Background='Transparent'>
                            <ListBox.ItemTemplate>
                                <DataTemplate>
                                    <Grid ColumnDefinitions='Auto,*' Margin='0,3'>
                                        <PathIcon Grid.Column='0' Data='{Binding IconData}' Margin='0,0,10,0' Foreground='{DynamicResource PrimaryBrush}'/>
                                        <StackPanel Grid.Column='1'>
                                            <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextTrimming='CharacterEllipsis'/>
                                            <TextBlock Text='{Binding Kind}' FontSize='11' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        </StackPanel>
                                    </Grid>
                                </DataTemplate>
                            </ListBox.ItemTemplate>
                        </ListBox>
                    </Grid>
                </Border>

                <GridSplitter Grid.Column='1' Width='4' Background='Transparent' ResizeDirection='Columns'/>

                <Border Grid.Column='2' Background='{DynamicResource BackgroundBrush}' Margin='8,16,16,16' CornerRadius='8'
                        BorderThickness='1' BorderBrush='{DynamicResource BorderBrush}' BoxShadow='0 2 10 0 #1A000000'>
                    <ScrollViewer>
                        <StackPanel Margin='20,16' Spacing='4'>
                            <TextBlock Name='resultEmptyTextBlock' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'
                                       Text='Search a user or a group, then select it: the password settings objects that concern it show by order of priority, and the one that applies.'/>
                            <StackPanel Name='resultPanel' IsVisible='False' Spacing='4'>
                                <TextBlock Name='resultTitleTextBlock' FontSize='18' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                <SelectableTextBlock Name='resultSubtitleTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>

                                <!-- What applies -->
                                <Border Margin='0,12,0,4' Padding='14,10' CornerRadius='6' BorderThickness='1' BorderBrush='{DynamicResource PrimaryBrush}'
                                        Background='{DynamicResource SecondaryBackgroundBrush}'>
                                    <StackPanel Spacing='2'>
                                        <TextBlock Name='appliedCaptionTextBlock' Text='Resultant password settings' FontSize='12' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        <StackPanel Orientation='Horizontal' Spacing='8'>
                                            <PathIcon Data='{StaticResource Icon.key}' Foreground='{DynamicResource PrimaryBrush}'/>
                                            <TextBlock Name='appliedNameTextBlock' FontSize='16' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                        </StackPanel>
                                        <TextBlock Name='appliedSourceTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                        <TextBlock Name='differsTextBlock' FontSize='12' TextWrapping='Wrap' Foreground='#CA5010' IsVisible='False'/>
                                    </StackPanel>
                                </Border>
                                <!-- Every PSO that concerns it, by order of priority -->
                                <TextBlock Text='Password settings by order of priority' FontSize='12' FontWeight='SemiBold' Margin='0,16,0,4'
                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <ItemsControl Name='candidatesList'>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Border BorderThickness='0,0,0,1' BorderBrush='{DynamicResource BorderBrush}' Padding='0,8'>
                                                <Grid ColumnDefinitions='32,*,Auto'>
                                                    <TextBlock Grid.Column='0' Text='{Binding Order}' FontWeight='SemiBold' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                    <StackPanel Grid.Column='1' Spacing='2'>
                                                        <StackPanel Orientation='Horizontal' Spacing='10'>
                                                            <TextBlock Text='{Binding Name}' FontWeight='SemiBold' TextWrapping='Wrap'/>
                                                            <TextBlock Text='{Binding Precedence}' FontSize='12' VerticalAlignment='Center' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        </StackPanel>
                                                        <TextBlock Text='{Binding Through}' FontSize='12' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}'/>
                                                        <TextBlock Text='{Binding Reason}' FontSize='12' TextWrapping='Wrap'/>
                                                    </StackPanel>
                                                    <Border Grid.Column='2' Background='{Binding StatusBrush}' CornerRadius='3' Padding='8,2' VerticalAlignment='Top' Margin='12,0,0,0'>
                                                        <TextBlock Text='{Binding Status}' Foreground='White' FontSize='11' FontWeight='SemiBold'/>
                                                    </Border>
                                                </Grid>
                                            </Border>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                                <!-- The settings that apply -->
                                <TextBlock Name='resultSettingsHeaderTextBlock' Text='Settings that apply' FontSize='12' FontWeight='SemiBold' Margin='0,16,0,4'
                                           Foreground='{DynamicResource SecondaryTextBrush}'/>
                                <ItemsControl Name='resultSettingsList' >
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <Grid ColumnDefinitions='220,*' Margin='0,2'>
                                                <TextBlock Grid.Column='0' Text='{Binding Key}' TextWrapping='Wrap' Foreground='{DynamicResource SecondaryTextBrush}' Margin='0,0,12,0'/>
                                                <SelectableTextBlock Grid.Column='1' Text='{Binding Value}' TextWrapping='Wrap'/>
                                            </Grid>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>

                                <TextBlock Name='groupRuleTextBlock' FontSize='11' TextWrapping='Wrap' Margin='0,8,0,0' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            </StackPanel>
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </Grid>
        </Grid>

        <!-- Status bar: this computer, its addresses, the domain and the domain controller read -->
        <Border Grid.Row='2' Name='statusBar' Background='{DynamicResource HeaderBackgroundBrush}'
                BorderThickness='0,1,0,0' BorderBrush='{DynamicResource BorderBrush}' Padding='16,6'>
            <ItemsControl Name='statusBarList'>
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <WrapPanel Orientation='Horizontal'/>
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <StackPanel Orientation='Horizontal' Spacing='6' Margin='0,0,24,0' ToolTip.Tip='{Binding ToolTip}'>
                            <PathIcon Data='{Binding IconData}' Width='14' Height='14' Foreground='{DynamicResource SecondaryTextBrush}'/>
                            <TextBlock Text='{Binding Text}' FontSize='12' VerticalAlignment='Center' Foreground='{DynamicResource TextBrush}'/>
                        </StackPanel>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </Border>
    </Grid>
</Window>
"@
}
