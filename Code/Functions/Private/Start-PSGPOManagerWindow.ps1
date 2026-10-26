<#
    Private implementation of Show-GPOManagerAvalonia: builds the window, wires its
    handlers and runs the Avalonia loop until the window closes.

    -OnShown exists for the GUI tests: the scriptblock receives a hashtable of the named
    controls, runs inside the loop once the window is shown, and the window is then
    closed. Event handlers keep resolving the local variables below because this
    function scope stays alive for the whole loop.
#>

function Start-PSGPOManagerWindow {
    [CmdletBinding()]
    Param(
        # Domain of the Group Policy Management view; without it the window opens on the ADMX policies.
        [GPOToolsDirectory]$Directory,

        # Why the domain could not be read: shown in the Group Policy Management view.
        [string]$DirectoryError,

        # View shown at launch: the Group Policy Management view, or the policy editor.
        [ValidateSet('Management', 'Editor')]
        [string]$StartView = 'Management',

        # Language of the interface (Resources/Strings); English by default, so that the tests do
        # not depend on the language of the computer: Show-GPOManagerAvalonia gives the one of the session.
        [string]$Language = 'en-US',

        [scriptblock]$OnShown
    )

    Initialize-PSGPOAvaloniaRuntime
    $null = Set-PSGPOLanguage -Language $Language

    $xaml = Get-PSGPOManagerWindowXaml

    # The configuration of HGPM for the domain shown (SYSVOL of its domain controller).
    Use-PSGPODomainConfiguration -Directory $Directory -Force
    $window = [Avalonia.Markup.Xaml.AvaloniaRuntimeXamlLoader]::Parse((ConvertTo-PSGPOLocalizedXaml -Xaml $xaml))
    # The logo of HGPM: the icon of the window and the image of its header.
    Set-PSGPOWindowIcon -Window $window
    $logoImage = Get-PSGPOAvaloniaControl $window 'logoImage'
    $logoImage.Source = New-PSGPOLogoBitmap

    $treeView = Get-PSGPOAvaloniaControl $window 'treeView'
    $themeToggleButton = Get-PSGPOAvaloniaControl $window 'themeToggleButton'
    $configurationButton = Get-PSGPOAvaloniaControl $window 'configurationButton'
    $breadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'breadcrumbTextBlock'
    $searchTextBox = Get-PSGPOAvaloniaControl $window 'searchTextBox'
    $searchButton = Get-PSGPOAvaloniaControl $window 'searchButton'
    $configuredOnlyCheckBox = Get-PSGPOAvaloniaControl $window 'configuredOnlyCheckBox'
    $displayNameTextBox = Get-PSGPOAvaloniaControl $window 'displayNameTextBox'
    $descriptionTextBox = Get-PSGPOAvaloniaControl $window 'descriptionTextBox'
    $scopeTextBox = Get-PSGPOAvaloniaControl $window 'scopeTextBox'
    $registryPathTextBox = Get-PSGPOAvaloniaControl $window 'registryPathTextBox'
    $registryKeyTextBox = Get-PSGPOAvaloniaControl $window 'registryKeyTextBox'
    $registryValuesList = Get-PSGPOAvaloniaControl $window 'registryValuesList'
    $settingTitleTextBlock = Get-PSGPOAvaloniaControl $window 'settingTitleTextBlock'
    $previewEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'previewEmptyTextBlock'
    $copyNameMenuItem = Get-PSGPOAvaloniaControl $window 'copyNameMenuItem'
    $copyRegistryMenuItem = Get-PSGPOAvaloniaControl $window 'copyRegistryMenuItem'
    $copyCommandMenuItem = Get-PSGPOAvaloniaControl $window 'copyCommandMenuItem'
    $notConfiguredRadio = Get-PSGPOAvaloniaControl $window 'notConfiguredRadio'
    $enabledRadio = Get-PSGPOAvaloniaControl $window 'enabledRadio'
    $disabledRadio = Get-PSGPOAvaloniaControl $window 'disabledRadio'
    $optionsHost = Get-PSGPOAvaloniaControl $window 'optionsHost'
    $settingErrorTextBlock = Get-PSGPOAvaloniaControl $window 'settingErrorTextBlock'
    $registryPreviewList = Get-PSGPOAvaloniaControl $window 'registryPreviewList'

    $subtitleTextBlock = Get-PSGPOAvaloniaControl $window 'subtitleTextBlock'
    $managementButton = Get-PSGPOAvaloniaControl $window 'managementButton'
    $browseAdmxButton = Get-PSGPOAvaloniaControl $window 'browseAdmxButton'
    $refreshButton = Get-PSGPOAvaloniaControl $window 'refreshButton'
    $searchPanel = Get-PSGPOAvaloniaControl $window 'searchPanel'
    $managementView = Get-PSGPOAvaloniaControl $window 'managementView'
    $editorView = Get-PSGPOAvaloniaControl $window 'editorView'
    $editingBanner = Get-PSGPOAvaloniaControl $window 'editingBanner'
    $editingGpoTextBlock = Get-PSGPOAvaloniaControl $window 'editingGpoTextBlock'
    $domainTreeView = Get-PSGPOAvaloniaControl $window 'domainTreeView'
    $directoryEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'directoryEmptyTextBlock'
    $demoBanner = Get-PSGPOAvaloniaControl $window 'demoBanner'
    $statusBarList = Get-PSGPOAvaloniaControl $window 'statusBarList'
    $directoryBreadcrumbTextBlock = Get-PSGPOAvaloniaControl $window 'directoryBreadcrumbTextBlock'
    $directoryTitleTextBlock = Get-PSGPOAvaloniaControl $window 'directoryTitleTextBlock'
    $directoryPropertiesList = Get-PSGPOAvaloniaControl $window 'directoryPropertiesList'
    $linksHeaderTextBlock = Get-PSGPOAvaloniaControl $window 'linksHeaderTextBlock'
    $linksList = Get-PSGPOAvaloniaControl $window 'linksList'
    $createLinkedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'createLinkedGpoMenuItem'
    $newGpoMenuItem = Get-PSGPOAvaloniaControl $window 'newGpoMenuItem'
    $editGpoMenuItem = Get-PSGPOAvaloniaControl $window 'editGpoMenuItem'
    $editGpoButton = Get-PSGPOAvaloniaControl $window 'editGpoButton'
    $newGpoPanel = Get-PSGPOAvaloniaControl $window 'newGpoPanel'
    $newGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoTitleTextBlock'
    $newGpoNameTextBox = Get-PSGPOAvaloniaControl $window 'newGpoNameTextBox'
    $newGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoErrorTextBlock'
    $newGpoCreateButton = Get-PSGPOAvaloniaControl $window 'newGpoCreateButton'
    $newGpoCancelButton = Get-PSGPOAvaloniaControl $window 'newGpoCancelButton'
    $newGpoStatusComboBox = Get-PSGPOAvaloniaControl $window 'newGpoStatusComboBox'
    $newGpoGroupsCheckBox = Get-PSGPOAvaloniaControl $window 'newGpoGroupsCheckBox'
    $newGpoGroupsPanel = Get-PSGPOAvaloniaControl $window 'newGpoGroupsPanel'
    $newGpoGroupsTextBlock = Get-PSGPOAvaloniaControl $window 'newGpoGroupsTextBlock'
    $newGpoGroupsContainerComboBox = Get-PSGPOAvaloniaControl $window 'newGpoGroupsContainerComboBox'
    $directoryResultTextBlock = Get-PSGPOAvaloniaControl $window 'directoryResultTextBlock'
    $deleteLinkMenuItem = Get-PSGPOAvaloniaControl $window 'deleteLinkMenuItem'
    $enforcedLinkMenuItem = Get-PSGPOAvaloniaControl $window 'enforcedLinkMenuItem'
    $enabledLinkMenuItem = Get-PSGPOAvaloniaControl $window 'enabledLinkMenuItem'
    $moveLinkUpMenuItem = Get-PSGPOAvaloniaControl $window 'moveLinkUpMenuItem'
    $moveLinkDownMenuItem = Get-PSGPOAvaloniaControl $window 'moveLinkDownMenuItem'
    $blockInheritanceMenuItem = Get-PSGPOAvaloniaControl $window 'blockInheritanceMenuItem'
    $gpoStatusMenuItem = Get-PSGPOAvaloniaControl $window 'gpoStatusMenuItem'
    $wmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'wmiFilterMenuItem'
    $newWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'newWmiFilterMenuItem'
    $editWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'editWmiFilterMenuItem'
    $deleteWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'deleteWmiFilterMenuItem'
    $newWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'newWmiFilterPanel'
    $newWmiFilterTitleTextBlock = Get-PSGPOAvaloniaControl $window 'newWmiFilterTitleTextBlock'
    $newWmiFilterNameTextBox = Get-PSGPOAvaloniaControl $window 'newWmiFilterNameTextBox'
    $newWmiFilterDescriptionTextBox = Get-PSGPOAvaloniaControl $window 'newWmiFilterDescriptionTextBox'
    $newWmiFilterNamespaceTextBox = Get-PSGPOAvaloniaControl $window 'newWmiFilterNamespaceTextBox'
    $newWmiFilterQueryTextBox = Get-PSGPOAvaloniaControl $window 'newWmiFilterQueryTextBox'
    $newWmiFilterErrorTextBlock = Get-PSGPOAvaloniaControl $window 'newWmiFilterErrorTextBlock'
    $newWmiFilterCreateButton = Get-PSGPOAvaloniaControl $window 'newWmiFilterCreateButton'
    $newWmiFilterCancelButton = Get-PSGPOAvaloniaControl $window 'newWmiFilterCancelButton'
    $deleteWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'deleteWmiFilterPanel'
    $deleteWmiFilterTextBlock = Get-PSGPOAvaloniaControl $window 'deleteWmiFilterTextBlock'
    $deleteWmiFilterConfirmButton = Get-PSGPOAvaloniaControl $window 'deleteWmiFilterConfirmButton'
    $deleteWmiFilterCancelButton = Get-PSGPOAvaloniaControl $window 'deleteWmiFilterCancelButton'
    $gpoStatusEnabledMenuItem = Get-PSGPOAvaloniaControl $window 'gpoStatusEnabledMenuItem'
    $gpoStatusUserDisabledMenuItem = Get-PSGPOAvaloniaControl $window 'gpoStatusUserDisabledMenuItem'
    $gpoStatusComputerDisabledMenuItem = Get-PSGPOAvaloniaControl $window 'gpoStatusComputerDisabledMenuItem'
    $gpoStatusAllDisabledMenuItem = Get-PSGPOAvaloniaControl $window 'gpoStatusAllDisabledMenuItem'
    $deleteLinkPanel = Get-PSGPOAvaloniaControl $window 'deleteLinkPanel'
    $deleteLinkTextBlock = Get-PSGPOAvaloniaControl $window 'deleteLinkTextBlock'
    $deleteLinkConfirmButton = Get-PSGPOAvaloniaControl $window 'deleteLinkConfirmButton'
    $deleteLinkCancelButton = Get-PSGPOAvaloniaControl $window 'deleteLinkCancelButton'
    $linkGpoMenuItem = Get-PSGPOAvaloniaControl $window 'linkGpoMenuItem'
    $deleteGpoMenuItem = Get-PSGPOAvaloniaControl $window 'deleteGpoMenuItem'
    $approveGpoMenuItem = Get-PSGPOAvaloniaControl $window 'approveGpoMenuItem'
    $approveGpoPanel = Get-PSGPOAvaloniaControl $window 'approveGpoPanel'
    $approveGpoTextBlock = Get-PSGPOAvaloniaControl $window 'approveGpoTextBlock'
    $approveGpoRightsComboBox = Get-PSGPOAvaloniaControl $window 'approveGpoRightsComboBox'
    $approveGpoApplyToTextBox = Get-PSGPOAvaloniaControl $window 'approveGpoApplyToTextBox'
    $approveGpoDenyToTextBox = Get-PSGPOAvaloniaControl $window 'approveGpoDenyToTextBox'
    $approveGpoGroupsCheckBox = Get-PSGPOAvaloniaControl $window 'approveGpoGroupsCheckBox'
    $approveGpoGroupsTextBlock = Get-PSGPOAvaloniaControl $window 'approveGpoGroupsTextBlock'
    $approveGpoFilteringGrid = Get-PSGPOAvaloniaControl $window 'approveGpoFilteringGrid'
    $approveGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'approveGpoErrorTextBlock'
    $approveGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'approveGpoConfirmButton'
    $approveGpoCancelButton = Get-PSGPOAvaloniaControl $window 'approveGpoCancelButton'
    $deleteGpoPanel = Get-PSGPOAvaloniaControl $window 'deleteGpoPanel'
    $deleteGpoTextBlock = Get-PSGPOAvaloniaControl $window 'deleteGpoTextBlock'
    $deleteGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'deleteGpoConfirmButton'
    $deleteGpoCancelButton = Get-PSGPOAvaloniaControl $window 'deleteGpoCancelButton'
    $restoreDeletedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'restoreDeletedGpoMenuItem'
    $restoreDeletedGpoButton = Get-PSGPOAvaloniaControl $window 'restoreDeletedGpoButton'
    $restoreGpoPanel = Get-PSGPOAvaloniaControl $window 'restoreGpoPanel'
    $restoreGpoTextBlock = Get-PSGPOAvaloniaControl $window 'restoreGpoTextBlock'
    $restoreGpoLinkCheckBox = Get-PSGPOAvaloniaControl $window 'restoreGpoLinkCheckBox'
    $restoreGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'restoreGpoConfirmButton'
    $restoreGpoCancelButton = Get-PSGPOAvaloniaControl $window 'restoreGpoCancelButton'
    $purgeDeletedGpoMenuItem = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoMenuItem'
    $purgeDeletedGpoButton = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoButton'
    $purgeDeletedGpoPanel = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoPanel'
    $purgeDeletedGpoTextBlock = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoTextBlock'
    $purgeDeletedGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoConfirmButton'
    $purgeDeletedGpoCancelButton = Get-PSGPOAvaloniaControl $window 'purgeDeletedGpoCancelButton'
    $renameMenuItem = Get-PSGPOAvaloniaControl $window 'renameMenuItem'
    $renamePanel = Get-PSGPOAvaloniaControl $window 'renamePanel'
    $renameTitleTextBlock = Get-PSGPOAvaloniaControl $window 'renameTitleTextBlock'
    $renameTextBox = Get-PSGPOAvaloniaControl $window 'renameTextBox'
    $renameErrorTextBlock = Get-PSGPOAvaloniaControl $window 'renameErrorTextBlock'
    $renameConfirmButton = Get-PSGPOAvaloniaControl $window 'renameConfirmButton'
    $renameCancelButton = Get-PSGPOAvaloniaControl $window 'renameCancelButton'
    $editWmiFilterButton = Get-PSGPOAvaloniaControl $window 'editWmiFilterButton'
    $editingStatusTextBlock = Get-PSGPOAvaloniaControl $window 'editingStatusTextBlock'
    $useWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'useWmiFilterMenuItem'
    $exportWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'exportWmiFilterMenuItem'
    $importWmiFilterMenuItem = Get-PSGPOAvaloniaControl $window 'importWmiFilterMenuItem'
    $exportWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'exportWmiFilterPanel'
    $exportWmiFilterTitleTextBlock = Get-PSGPOAvaloniaControl $window 'exportWmiFilterTitleTextBlock'
    $exportWmiFilterPathTextBox = Get-PSGPOAvaloniaControl $window 'exportWmiFilterPathTextBox'
    $exportWmiFilterBrowseButton = Get-PSGPOAvaloniaControl $window 'exportWmiFilterBrowseButton'
    $exportWmiFilterErrorTextBlock = Get-PSGPOAvaloniaControl $window 'exportWmiFilterErrorTextBlock'
    $exportWmiFilterConfirmButton = Get-PSGPOAvaloniaControl $window 'exportWmiFilterConfirmButton'
    $exportWmiFilterCancelButton = Get-PSGPOAvaloniaControl $window 'exportWmiFilterCancelButton'
    $importWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'importWmiFilterPanel'
    $importWmiFilterTitleTextBlock = Get-PSGPOAvaloniaControl $window 'importWmiFilterTitleTextBlock'
    $importWmiFilterPathTextBox = Get-PSGPOAvaloniaControl $window 'importWmiFilterPathTextBox'
    $importWmiFilterBrowseButton = Get-PSGPOAvaloniaControl $window 'importWmiFilterBrowseButton'
    $importWmiFilterReadButton = Get-PSGPOAvaloniaControl $window 'importWmiFilterReadButton'
    $importWmiFilterInfoTextBlock = Get-PSGPOAvaloniaControl $window 'importWmiFilterInfoTextBlock'
    $importWmiFilterNameTextBox = Get-PSGPOAvaloniaControl $window 'importWmiFilterNameTextBox'
    $importWmiFilterErrorTextBlock = Get-PSGPOAvaloniaControl $window 'importWmiFilterErrorTextBlock'
    $importWmiFilterConfirmButton = Get-PSGPOAvaloniaControl $window 'importWmiFilterConfirmButton'
    $importWmiFilterCancelButton = Get-PSGPOAvaloniaControl $window 'importWmiFilterCancelButton'
    $useWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'useWmiFilterPanel'
    $useWmiFilterTitleTextBlock = Get-PSGPOAvaloniaControl $window 'useWmiFilterTitleTextBlock'
    $useWmiFilterSearchTextBox = Get-PSGPOAvaloniaControl $window 'useWmiFilterSearchTextBox'
    $useWmiFilterList = Get-PSGPOAvaloniaControl $window 'useWmiFilterList'
    $useWmiFilterErrorTextBlock = Get-PSGPOAvaloniaControl $window 'useWmiFilterErrorTextBlock'
    $useWmiFilterConfirmButton = Get-PSGPOAvaloniaControl $window 'useWmiFilterConfirmButton'
    $useWmiFilterCancelButton = Get-PSGPOAvaloniaControl $window 'useWmiFilterCancelButton'
    $gpoWmiFilterPanel = Get-PSGPOAvaloniaControl $window 'gpoWmiFilterPanel'
    $gpoWmiFilterComboBox = Get-PSGPOAvaloniaControl $window 'gpoWmiFilterComboBox'
    $wmiDelegationTab = Get-PSGPOAvaloniaControl $window 'wmiDelegationTab'
    $wmiDelegationTitleTextBlock = Get-PSGPOAvaloniaControl $window 'wmiDelegationTitleTextBlock'
    $wmiDelegationInfoTextBlock = Get-PSGPOAvaloniaControl $window 'wmiDelegationInfoTextBlock'
    $wmiDelegationList = Get-PSGPOAvaloniaControl $window 'wmiDelegationList'
    $wmiDelegationNameTextBox = Get-PSGPOAvaloniaControl $window 'wmiDelegationNameTextBox'
    $wmiDelegationPermissionComboBox = Get-PSGPOAvaloniaControl $window 'wmiDelegationPermissionComboBox'
    $wmiDelegationSetButton = Get-PSGPOAvaloniaControl $window 'wmiDelegationSetButton'
    $wmiDelegationRemoveButton = Get-PSGPOAvaloniaControl $window 'wmiDelegationRemoveButton'
    $wmiDelegationStatusTextBlock = Get-PSGPOAvaloniaControl $window 'wmiDelegationStatusTextBlock'
    $newGpoTemplateComboBox = Get-PSGPOAvaloniaControl $window 'newGpoTemplateComboBox'
    $historyNotesTemplateCheckBox = Get-PSGPOAvaloniaControl $window 'historyNotesTemplateCheckBox'
    $linkGpoPanel = Get-PSGPOAvaloniaControl $window 'linkGpoPanel'
    $linkGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'linkGpoTitleTextBlock'
    $linkGpoFilterTextBox = Get-PSGPOAvaloniaControl $window 'linkGpoFilterTextBox'
    $linkGpoList = Get-PSGPOAvaloniaControl $window 'linkGpoList'
    $linkGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'linkGpoErrorTextBlock'
    $linkGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'linkGpoConfirmButton'
    $linkGpoCancelButton = Get-PSGPOAvaloniaControl $window 'linkGpoCancelButton'

    $applyPanel = Get-PSGPOAvaloniaControl $window 'applyPanel'
    $directoryTabs = Get-PSGPOAvaloniaControl $window 'directoryTabs'
    $settingsTab = Get-PSGPOAvaloniaControl $window 'settingsTab'
    $historyTab = Get-PSGPOAvaloniaControl $window 'historyTab'
    $delegationTab = Get-PSGPOAvaloniaControl $window 'delegationTab'
    $importGpoMenuItem = Get-PSGPOAvaloniaControl $window 'importGpoMenuItem'
    $importGpoPanel = Get-PSGPOAvaloniaControl $window 'importGpoPanel'
    $importGpoTitleTextBlock = Get-PSGPOAvaloniaControl $window 'importGpoTitleTextBlock'
    $importGpoPathTextBox = Get-PSGPOAvaloniaControl $window 'importGpoPathTextBox'
    $importGpoReadButton = Get-PSGPOAvaloniaControl $window 'importGpoReadButton'
    $importGpoSourceComboBox = Get-PSGPOAvaloniaControl $window 'importGpoSourceComboBox'
    $importGpoTableTextBox = Get-PSGPOAvaloniaControl $window 'importGpoTableTextBox'
    $importGpoExclusiveCheckBox = Get-PSGPOAvaloniaControl $window 'importGpoExclusiveCheckBox'
    $importGpoTextBlock = Get-PSGPOAvaloniaControl $window 'importGpoTextBlock'
    $importGpoErrorTextBlock = Get-PSGPOAvaloniaControl $window 'importGpoErrorTextBlock'
    $importGpoConfirmButton = Get-PSGPOAvaloniaControl $window 'importGpoConfirmButton'
    $importGpoCancelButton = Get-PSGPOAvaloniaControl $window 'importGpoCancelButton'
    $filteringList = Get-PSGPOAvaloniaControl $window 'filteringList'
    $filteringNameTextBox = Get-PSGPOAvaloniaControl $window 'filteringNameTextBox'
    $filteringAddButton = Get-PSGPOAvaloniaControl $window 'filteringAddButton'
    $filteringRemoveButton = Get-PSGPOAvaloniaControl $window 'filteringRemoveButton'
    $delegationList = Get-PSGPOAvaloniaControl $window 'delegationList'
    $delegationNameTextBox = Get-PSGPOAvaloniaControl $window 'delegationNameTextBox'
    $delegationPermissionComboBox = Get-PSGPOAvaloniaControl $window 'delegationPermissionComboBox'
    $delegationSetButton = Get-PSGPOAvaloniaControl $window 'delegationSetButton'
    $delegationRemoveButton = Get-PSGPOAvaloniaControl $window 'delegationRemoveButton'
    $delegationStatusTextBlock = Get-PSGPOAvaloniaControl $window 'delegationStatusTextBlock'
    $historyPathTextBox = Get-PSGPOAvaloniaControl $window 'historyPathTextBox'
    $historyBackupButton = Get-PSGPOAvaloniaControl $window 'historyBackupButton'
    $historyBackupAllButton = Get-PSGPOAvaloniaControl $window 'historyBackupAllButton'
    $historyStatusTextBlock = Get-PSGPOAvaloniaControl $window 'historyStatusTextBlock'
    $historyTimelineScrollViewer = Get-PSGPOAvaloniaControl $window 'historyTimelineScrollViewer'
    $historyTimelineList = Get-PSGPOAvaloniaControl $window 'historyTimelineList'
    $historyCompareTextBlock = Get-PSGPOAvaloniaControl $window 'historyCompareTextBlock'
    $historyChangesList = Get-PSGPOAvaloniaControl $window 'historyChangesList'
    $historyRestoreButton = Get-PSGPOAvaloniaControl $window 'historyRestoreButton'
    $historyRestorePanel = Get-PSGPOAvaloniaControl $window 'historyRestorePanel'
    $historyRestoreTextBlock = Get-PSGPOAvaloniaControl $window 'historyRestoreTextBlock'
    $historyRestoreConfirmButton = Get-PSGPOAvaloniaControl $window 'historyRestoreConfirmButton'
    $historyRestoreCancelButton = Get-PSGPOAvaloniaControl $window 'historyRestoreCancelButton'
    $historyCommentTextBox = Get-PSGPOAvaloniaControl $window 'historyCommentTextBox'
    $historyDriftBorder = Get-PSGPOAvaloniaControl $window 'historyDriftBorder'
    $historyDriftTextBlock = Get-PSGPOAvaloniaControl $window 'historyDriftTextBlock'
    $historyDriftButton = Get-PSGPOAvaloniaControl $window 'historyDriftButton'
    $historyNotesPanel = Get-PSGPOAvaloniaControl $window 'historyNotesPanel'
    $historyNotesInfoTextBlock = Get-PSGPOAvaloniaControl $window 'historyNotesInfoTextBlock'
    $historyNotesCommentTextBox = Get-PSGPOAvaloniaControl $window 'historyNotesCommentTextBox'
    $historyNotesLabelsTextBox = Get-PSGPOAvaloniaControl $window 'historyNotesLabelsTextBox'
    $historyNotesApprovedCheckBox = Get-PSGPOAvaloniaControl $window 'historyNotesApprovedCheckBox'
    $historyNotesSaveButton = Get-PSGPOAvaloniaControl $window 'historyNotesSaveButton'
    $settingsStatusTextBlock = Get-PSGPOAvaloniaControl $window 'settingsStatusTextBlock'
    $computerSettingsHeader = Get-PSGPOAvaloniaControl $window 'computerSettingsHeader'
    $computerSettingsList = Get-PSGPOAvaloniaControl $window 'computerSettingsList'
    $userSettingsHeader = Get-PSGPOAvaloniaControl $window 'userSettingsHeader'
    $userSettingsList = Get-PSGPOAvaloniaControl $window 'userSettingsList'
    $applySettingButton = Get-PSGPOAvaloniaControl $window 'applySettingButton'
    $applyStatusTextBlock = Get-PSGPOAvaloniaControl $window 'applyStatusTextBlock'

    $detailsTabs = Get-PSGPOAvaloniaControl $window 'detailsTabs'
    $detailsTitleTextBlock = Get-PSGPOAvaloniaControl $window 'detailsTitleTextBlock'
    $preferencesPanel = Get-PSGPOAvaloniaControl $window 'preferencesPanel'
    $preferencesTitleTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesTitleTextBlock'
    $preferencesInfoTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesInfoTextBlock'
    $preferencesNewTypeComboBox = Get-PSGPOAvaloniaControl $window 'preferencesNewTypeComboBox'
    $preferencesNewButton = Get-PSGPOAvaloniaControl $window 'preferencesNewButton'
    $preferencesEditButton = Get-PSGPOAvaloniaControl $window 'preferencesEditButton'
    $preferencesDeleteButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteButton'
    $preferencesUpButton = Get-PSGPOAvaloniaControl $window 'preferencesUpButton'
    $preferencesDownButton = Get-PSGPOAvaloniaControl $window 'preferencesDownButton'
    $preferencesStatusTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesStatusTextBlock'
    $preferencesEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesEmptyTextBlock'
    $preferencesList = Get-PSGPOAvaloniaControl $window 'preferencesList'
    $preferencesDeletePanel = Get-PSGPOAvaloniaControl $window 'preferencesDeletePanel'
    $preferencesDeleteTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesDeleteTextBlock'
    $preferencesDeleteConfirmButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteConfirmButton'
    $preferencesDeleteCancelButton = Get-PSGPOAvaloniaControl $window 'preferencesDeleteCancelButton'
    $preferencesFormBorder = Get-PSGPOAvaloniaControl $window 'preferencesFormBorder'
    $preferencesFormTitleTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesFormTitleTextBlock'
    $preferencesFormHost = Get-PSGPOAvaloniaControl $window 'preferencesFormHost'
    $preferencesFormErrorTextBlock = Get-PSGPOAvaloniaControl $window 'preferencesFormErrorTextBlock'
    $preferencesSaveButton = Get-PSGPOAvaloniaControl $window 'preferencesSaveButton'
    $preferencesCancelButton = Get-PSGPOAvaloniaControl $window 'preferencesCancelButton'
    $certificatesPanel = Get-PSGPOAvaloniaControl $window 'certificatesPanel'
    $certificatesTitleTextBlock = Get-PSGPOAvaloniaControl $window 'certificatesTitleTextBlock'
    $certificatesInfoTextBlock = Get-PSGPOAvaloniaControl $window 'certificatesInfoTextBlock'
    $certificatesPathTextBox = Get-PSGPOAvaloniaControl $window 'certificatesPathTextBox'
    $certificatesImportButton = Get-PSGPOAvaloniaControl $window 'certificatesImportButton'
    $certificatesDeleteButton = Get-PSGPOAvaloniaControl $window 'certificatesDeleteButton'
    $certificatesStatusTextBlock = Get-PSGPOAvaloniaControl $window 'certificatesStatusTextBlock'
    $certificatesEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'certificatesEmptyTextBlock'
    $certificatesList = Get-PSGPOAvaloniaControl $window 'certificatesList'
    $certificatesDeletePanel = Get-PSGPOAvaloniaControl $window 'certificatesDeletePanel'
    $certificatesDeleteTextBlock = Get-PSGPOAvaloniaControl $window 'certificatesDeleteTextBlock'
    $certificatesDeleteConfirmButton = Get-PSGPOAvaloniaControl $window 'certificatesDeleteConfirmButton'
    $certificatesDeleteCancelButton = Get-PSGPOAvaloniaControl $window 'certificatesDeleteCancelButton'
    $restrictedGroupsPanel = Get-PSGPOAvaloniaControl $window 'restrictedGroupsPanel'
    $restrictedGroupsAddButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsAddButton'
    $restrictedGroupsEditButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsEditButton'
    $restrictedGroupsDeleteButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsDeleteButton'
    $restrictedGroupsStatusTextBlock = Get-PSGPOAvaloniaControl $window 'restrictedGroupsStatusTextBlock'
    $restrictedGroupsEmptyTextBlock = Get-PSGPOAvaloniaControl $window 'restrictedGroupsEmptyTextBlock'
    $restrictedGroupsList = Get-PSGPOAvaloniaControl $window 'restrictedGroupsList'
    $restrictedGroupsDeletePanel = Get-PSGPOAvaloniaControl $window 'restrictedGroupsDeletePanel'
    $restrictedGroupsDeleteTextBlock = Get-PSGPOAvaloniaControl $window 'restrictedGroupsDeleteTextBlock'
    $restrictedGroupsDeleteConfirmButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsDeleteConfirmButton'
    $restrictedGroupsDeleteCancelButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsDeleteCancelButton'
    $restrictedGroupsFormBorder = Get-PSGPOAvaloniaControl $window 'restrictedGroupsFormBorder'
    $restrictedGroupsFormTitleTextBlock = Get-PSGPOAvaloniaControl $window 'restrictedGroupsFormTitleTextBlock'
    $restrictedGroupNameTextBox = Get-PSGPOAvaloniaControl $window 'restrictedGroupNameTextBox'
    $restrictedGroupMembersCheckBox = Get-PSGPOAvaloniaControl $window 'restrictedGroupMembersCheckBox'
    $restrictedGroupMembersTextBox = Get-PSGPOAvaloniaControl $window 'restrictedGroupMembersTextBox'
    $restrictedGroupMemberOfTextBox = Get-PSGPOAvaloniaControl $window 'restrictedGroupMemberOfTextBox'
    $restrictedGroupsFormErrorTextBlock = Get-PSGPOAvaloniaControl $window 'restrictedGroupsFormErrorTextBlock'
    $restrictedGroupsSaveButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsSaveButton'
    $restrictedGroupsCancelButton = Get-PSGPOAvaloniaControl $window 'restrictedGroupsCancelButton'

    # Options form of the selected policy (New-PSGPOPolicyEditor), the policy it edits and the
    # GPO opened from the Group Policy Management view ($null: browsing the ADMX policies).
    # Pol: the Registry.pol of the GPO by scope; Saved: the registry values of the setting of the
    # selected policy in it, compared with the form to know whether there is something to apply.
    # Security: the selected security setting, Template: the GptTmpl.inf of the GPO (security
    # settings), Audit: its audit.csv (advanced audit policy); Saved is then the raw value of the
    # setting in it.
    $editing = @{ Policy = $null; Security = $null; Editor = $null; Gpo = $null; Pol = @{}; PolError = $null; Template = $null; Audit = $null; Saved = $null; Preferences = @{} }
    $previewHeaderTextBlock = Get-PSGPOAvaloniaControl $window 'previewHeaderTextBlock'
    $notDefinedMark = '(not defined)'

    # The file of a security setting in the GPO: audit.csv for the advanced audit policy, else
    # GptTmpl.inf; $null when the GPO is not read.
    function Get-SecurityStore {
        param([GPOToolsSecuritySetting]$Setting)
        if ($Setting.Section -eq [GPOToolsAuditPolicyFile]::Section) { $editing.Audit } else { $editing.Template }
    }
    function Get-SecurityFileName {
        param([GPOToolsSecuritySetting]$Setting)
        if ($Setting.Section -eq [GPOToolsAuditPolicyFile]::Section) { 'audit.csv' } else { 'GptTmpl.inf' }
    }

    # Raw GptTmpl.inf value of the security setting of the form, or the not defined mark.
    function Get-SecuritySignature {
        if ($enabledRadio.IsChecked) { $editing.Security.ConvertToRaw((& $editing.Editor.GetValue)) } else { $notDefinedMark }
    }

    function Get-SettingState {
        if ($enabledRadio.IsChecked) { 'Enabled' } elseif ($disabledRadio.IsChecked) { 'Disabled' } else { 'NotConfigured' }
    }

    # Registry values of a setting as one text, to compare two settings.
    function Get-SettingSignature {
        param([GPOToolsPolicy]$Policy, [string]$State, [hashtable]$Value)
        (@(Get-PSGPOPolicyRegistryChange -Policy $Policy -State $State -Value $Value) | ForEach-Object { Format-PSGPORegistryValue $_ }) -join "`n"
    }

    # Apply is offered when the form differs from the Registry.pol of the GPO and is valid.
    function Update-ApplyButton {
        $policy = $editing.Policy
        $applyPanel.IsVisible = [bool]$editing.Gpo
        $pol = if ($policy) { $editing.Pol["$($policy.Scope)"] }
        $changed = $false
        if (-not $settingErrorTextBlock.Text) {
            try {
                if ($policy -and $pol) { $changed = (Get-SettingSignature $policy (Get-SettingState) (& $editing.Editor.GetValue)) -ne $editing.Saved }
                elseif ($editing.Security -and (Get-SecurityStore $editing.Security)) { $changed = (Get-SecuritySignature) -ne $editing.Saved }
            } catch { $changed = $false }
        }
        $applySettingButton.IsEnabled = $changed
    }

    # Registry values the current setting writes (what Registry.pol will contain).
    function Update-RegistryPreview {
        $policy = $editing.Policy
        $state = if ($enabledRadio.IsChecked) { 'Enabled' } elseif ($disabledRadio.IsChecked) { 'Disabled' } else { 'NotConfigured' }
        # Like the Group Policy editor, options can only be edited when the policy is enabled.
        $optionsHost.IsEnabled = $state -eq 'Enabled'
        $settingErrorTextBlock.Text = ''
        if ($editing.Security) {
            # A security setting: its line of GptTmpl.inf.
            $rows = @()
            if ($state -eq 'Enabled') {
                try {
                    $row = [AvaloniaPreviewRow]::new()
                    $audit = $editing.Security.Section -eq [GPOToolsAuditPolicyFile]::Section
                    $row.Title = Get-PSGPOText $(if ($audit) { 'Set in audit.csv' } else { 'Set in GptTmpl.inf' })
                    $row.Key = if ($audit) { $editing.Security.Name } else { "[$($editing.Security.Section)]" }
                    $row.ValueName = $editing.Security.Key
                    $row.Data = $editing.Security.ConvertToRaw((& $editing.Editor.GetValue))
                    $rows = @($row)
                } catch {
                    $settingErrorTextBlock.Text = $_.Exception.Message
                }
            }
            $registryPreviewList.ItemsSource = $rows
            $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
            $previewEmptyTextBlock.Text = Get-PSGPOText $(if ($settingErrorTextBlock.Text) { 'Fix the value above to see the line of {0}.' } else { 'Not defined: nothing is written to {0}.' }) (Get-SecurityFileName $editing.Security)
            Update-ApplyButton
            return
        }
        $rows = @()
        if ($policy) {
            try {
                $changes = @(Get-PSGPOPolicyRegistryChange -Policy $policy -State $state -Value (& $editing.Editor.GetValue))
                $rows = @(foreach ($change in $changes) { ConvertTo-PSGPOPreviewRow -Change $change -Scope $policy.Scope })
            } catch {
                $settingErrorTextBlock.Text = $_.Exception.Message
            }
        }
        $registryPreviewList.ItemsSource = $rows
        $previewEmptyTextBlock.IsVisible = $rows.Count -eq 0
        $previewEmptyTextBlock.Text = Get-PSGPOText $(if (-not $policy) { 'Select a policy in the tree.' }
            elseif ($settingErrorTextBlock.Text) { 'Fix the options above to see the registry values.' }
            else { 'Not configured: nothing is written to the registry.' })
        Update-ApplyButton
    }

    # Saves the setting of the selected policy in the Registry.pol of the GPO. The file is
    # changed on a copy: if the domain refuses it, the setting read before stays.
    $applySettingButton.Add_Click({
        if ($editing.Security) {
            # A security setting: written to a copy of GptTmpl.inf (audit.csv for the advanced
            # audit policy), saved, then kept.
            $setting = $editing.Security
            $store = Get-SecurityStore $setting
            if (-not $editing.Gpo -or -not $store) { return }
            $value = if ($enabledRadio.IsChecked) { & $editing.Editor.GetValue } else { $null }
            $copy = if ($store -is [GPOToolsAuditPolicyFile]) { [GPOToolsAuditPolicyFile]::Parse($store.ToBytes()) } else { [GPOToolsSecurityTemplate]::Parse($store.ToBytes()) }
            try {
                Set-PSGPOSecurityValue -Template $copy -Setting $setting -Value $value
                if ($copy -is [GPOToolsAuditPolicyFile]) {
                    $Directory.WriteAuditPolicyFile($editing.Gpo, $copy.ToBytes())
                    $editing.Audit = $copy
                } else {
                    $Directory.WriteSecurityTemplate($editing.Gpo, $copy.ToBytes())
                    $editing.Template = $copy
                }
                $editing.Saved = Get-SecuritySignature
                $applyStatusTextBlock.Text = Get-PSGPOText 'Saved: {0} in {1} (version {2}).' (ConvertTo-PSGPODisplayText $setting.FormatValue($value)) (Get-SecurityFileName $setting) $editing.Gpo.GetComputerVersion()
            } catch {
                $applyStatusTextBlock.Text = Get-PSGPOText 'Not saved: {0}' $_.Exception.GetBaseException().Message
            }
            Update-ApplyButton
            return
        }
        $policy = $editing.Policy
        $scope = "$($policy.Scope)"
        if (-not $policy -or -not $editing.Gpo -or -not $editing.Pol[$scope]) { return }
        $state = Get-SettingState
        $value = & $editing.Editor.GetValue
        $copy = [GPOToolsRegistryPol]::Parse($editing.Pol[$scope].ToBytes())
        try {
            Set-PSGPOPolicyState -Policy $policy -Pol $copy -State $state -Value $value
            $Directory.WritePolicyFile($editing.Gpo, $scope, $copy.ToBytes())
            $editing.Pol[$scope] = $copy
            $editing.Saved = Get-SettingSignature $policy $state $value
            $version = if ($scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
            $applyStatusTextBlock.Text = Get-PSGPOText 'Saved: {0} in {1}\Registry.pol (version {2}).' (Get-PSGPOText $state) $scope $version
        } catch {
            $applyStatusTextBlock.Text = Get-PSGPOText 'Not saved: {0}' $_.Exception.GetBaseException().Message
        }
        Update-ApplyButton
    })
    foreach ($radio in $notConfiguredRadio, $enabledRadio, $disabledRadio) {
        $radio.add_IsCheckedChanged({ Update-RegistryPreview })
    }

    # Theme: the one of the session, the same in every window (PSGPOTheme.ps1); FluentTheme and
    # our ThemeDictionaries swap when RequestedThemeVariant changes.
    $themeToggleIcon = Get-PSGPOAvaloniaControl $window 'themeToggleIcon'
    $themeToggleText = Get-PSGPOAvaloniaControl $window 'themeToggleText'
    Register-PSGPOThemeWindow -Window $window -ToggleText $themeToggleText -ToggleIcon $themeToggleIcon
    $themeToggleButton.Add_Click({ Switch-PSGPOTheme })

    # Context menu actions copy information about the selected policy to the clipboard.
    # The last copy task is kept: a failed copy (no clipboard on a Linux session...) is reported
    # instead of being lost, and the tests can wait for it.
    $clipboard = @{ Task = $null; Error = $null; Text = $null }
    function Copy-SelectedPolicyText {
        param([scriptblock]$Text)

        $selected = $treeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsPolicy]) {
            $value = & $Text $selected.Tag
            if ($value) {
                $clipboard.Error = $null
                $clipboard.Text = $value
                try {
                    $clipboard.Task = $window.Clipboard.SetTextAsync($value)
                } catch {
                    $clipboard.Task = $null
                    $clipboard.Error = $_.Exception
                    Write-Warning "Copy to the clipboard failed: $($_.Exception.Message)"
                }
            }
        }
    }
    $copyNameMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.DisplayName } })
    $copyRegistryMenuItem.Add_Click({ Copy-SelectedPolicyText { param($p) $p.Registry.Path } })
    $copyCommandMenuItem.Add_Click({
        Copy-SelectedPolicyText {
            param($p)
            if ($p.Registry.Key) {
                "Get-ItemProperty -Path '{0}' -Name '{1}'" -f $p.Registry.Path, $p.Registry.Key
            } elseif ($p.Registry.Path) {
                "Get-ItemProperty -Path '{0}'" -f $p.Registry.Path
            }
        }
    })

    # A security setting in the form: Not Defined / Define this policy setting, its value read
    # from the GptTmpl.inf of the edited GPO.
    function Show-SecuritySetting {
        param([GPOToolsSecuritySetting]$Setting)
        $read = [pscustomobject]@{ Defined = $false; Value = $null; Problem = $null; Raw = $null }
        $store = Get-SecurityStore $Setting
        $fileName = Get-SecurityFileName $Setting
        if ($store) { $read = Get-PSGPOSecurityValue -Template $store -Setting $Setting }
        $editing.Policy = $null
        $editing.Saved = if ($read.Defined) { $read.Raw } else { $notDefinedMark }
        $notConfiguredRadio.Content = Get-PSGPOText 'Not Defined'
        $enabledRadio.Content = Get-PSGPOText 'Define this policy setting'
        $disabledRadio.IsVisible = $false
        $previewHeaderTextBlock.Text = Get-PSGPOText '{0} Preview' $fileName
        if ($read.Defined -and -not $read.Problem) { $enabledRadio.IsChecked = $true } else { $notConfiguredRadio.IsChecked = $true }
        $applyStatusTextBlock.Text = if ($read.Problem) { $read.Problem }
            elseif ($store) { Get-PSGPOText $(if ($read.Defined) { 'Defined in {0}' } else { 'Not defined in {0}' }) $fileName }
            elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }

        $editing.Security = $Setting
        $settingTitleTextBlock.Text = Get-PSGPOText $Setting.Name
        $editing.Editor = New-PSGPOSecurityEditor -Setting $Setting -Value $read.Value -OnChange { Update-RegistryPreview }
        $optionsHost.Content = $editing.Editor.Panel

        $displayNameTextBox.Text = Get-PSGPOText $Setting.Name
        $descriptionTextBox.Text = (Get-PSGPOText $(if ($fileName -eq 'audit.csv') { 'Advanced audit policy of the computer, in audit.csv (Machine\Microsoft\Windows NT\Audit): the events of this subcategory the computers audit.' } else { 'Security setting of the computer, in GptTmpl.inf (Machine\Microsoft\Windows NT\SecEdit).' })) + $(if ($Setting.Reference) { "`n`n" + (Get-PSGPOText 'Reference: {0}' $Setting.Reference) })
        $scopeTextBox.Text = Get-PSGPOText 'Machine'
        $registryPathTextBox.Text = if ($fileName -eq 'audit.csv') { [GPOToolsDirectory]::AuditPolicyPath } else { "GptTmpl.inf [$($Setting.Section)]" }
        $registryKeyTextBox.Text = $Setting.Key
        $registryValuesList.ItemsSource = @(
            foreach ($pair in @(
                    @('Category', (@($Setting.Path | ForEach-Object { Get-PSGPOText $_ }) -join ' > '))
                    @('Value', $(if ($Setting.Kind -eq 'RegistryValue') { Get-PSGPOText '{0}, registry type {1}' (Get-PSGPOText "$($Setting.Display)") $Setting.RegistryType } else { Get-PSGPOText "$($Setting.Kind)" }))
                    @('Range', $(if ($null -ne $Setting.Min -or $null -ne $Setting.Max) { (Get-PSGPOText '{0} to {1} {2}' $Setting.Min $Setting.Max (Get-PSGPOText "$($Setting.Unit)")).Trim() }))
                    @('Values', (@($Setting.Choices | ForEach-Object { "$($_.Value): $(Get-PSGPOText "$($_.Text)")" }) -join '; ')))) {
                if (-not $pair[1]) { continue }
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = Get-PSGPOText $pair[0]
                $row.Value = $pair[1]
                $row
            })
        Update-RegistryPreview
    }

    # --- Preferences ([MS-GPPREF]) of the edited GPO --------------------------------------------

    # The type shown, the item edited and its form; the files read once per GPO edited.
    $preferences = @{ Node = $null; File = $null; Item = $null; Type = $null; Form = $null }

    function Set-PreferenceStatus {
        param([string]$Text, [switch]$Problem)
        $preferencesStatusTextBlock.Text = $Text
        if ($Problem) { $preferencesStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $preferencesStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # The file of a preference type of the GPO: read once; an empty one when the GPO has none.
    function Get-PreferenceFile {
        param([GPOToolsPreferenceNode]$Node)
        $key = "$($Node.Scope)|$($Node.Extension.Id)"
        if (-not $editing.Preferences.ContainsKey($key)) {
            $bytes = $Directory.ReadPreferenceFile($editing.Gpo, $Node.Scope, $Node.Extension.Path)
            $editing.Preferences[$key] = if ($bytes) { [GPOToolsPreferenceFile]::Parse($bytes) } else { [GPOToolsPreferenceFile]::Create($Node.Extension.Root, $Node.Extension.RootClsid) }
        }
        $editing.Preferences[$key]
    }

    function Test-PreferenceEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $preferences.File
    }

    function Update-PreferenceToolbar {
        $row = $preferencesList.SelectedItem
        $editable = Test-PreferenceEditable
        $preferencesNewButton.IsEnabled = $editable -and $null -ne $preferencesNewTypeComboBox.SelectedItem
        $preferencesEditButton.IsEnabled = $editable -and $row -and $row.Item.Editable
        $preferencesDeleteButton.IsEnabled = $editable -and $row
        $preferencesUpButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
        $preferencesDownButton.IsEnabled = $editable -and $row -and -not $row.Item.Collection
    }

    # The items of the type selected in the tree, for the edited GPO.
    function Show-PreferenceType {
        param([GPOToolsPreferenceNode]$Node, [string]$Status, [string]$SelectUid)
        $preferences.Node = $Node
        $preferences.File = $null
        $extension = $Node.Extension
        $scopeLabel = Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' })
        $preferencesTitleTextBlock.Text = "$(Get-PSGPOText $extension.Name) ($scopeLabel)"
        $types = @($extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })
        $preferencesInfoTextBlock.Text = (Get-PSGPOText 'Preferences > {0} > {1}: Preferences\{2} in the {3} folder of the GPO, client-side extension {4}.' (Get-PSGPOText $extension.Group) (Get-PSGPOText $extension.Name) $extension.Path (Get-PSGPOText $Node.Scope) $extension.Cse) +
            $(if (-not $types.Count) { Get-PSGPOText ' Its items are created with GPMC: the console shows them, keeps them as they are and deletes them.' })
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $false
        $preferencesNewTypeComboBox.ItemsSource = @($types | ForEach-Object { Get-PSGPOText $_.Label })
        $preferencesNewTypeComboBox.SelectedIndex = if ($types.Count) { 0 } else { -1 }
        $preferencesNewTypeComboBox.IsVisible = $types.Count -gt 0
        $preferencesNewButton.IsVisible = $types.Count -gt 0
        $rows = @()
        $problem = $null
        if (-not $editing.Gpo) {
            $preferencesEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its preferences.'
        } else {
            try {
                $preferences.File = Get-PreferenceFile $Node
                $rows = @(foreach ($item in @(Get-PSGPOPreferenceItem -File $preferences.File -Extension $extension)) {
                        $row = [AvaloniaPreferenceRow]::new()
                        $row.Name = "$(if ($item.Collection) { "$($item.Collection) > " })$(if ($item.Name) { $item.Name } else { Get-PSGPOText $item.Label })"
                        $row.Summary = Get-PSGPOPreferenceSummary -Item $item
                        $row.Flags = (@(
                                if ($item.Disabled) { Get-PSGPOText 'Disabled' }
                                if ($item.FilterCount) { Get-PSGPOText '{0} targeting filter(s)' $item.FilterCount }
                                if ($item.HasPassword) { Get-PSGPOText 'Stores a password readable by any user of the domain (MS14-025)' }
                                if (-not $item.Editable) { Get-PSGPOText 'Edited with GPMC' }) -join ' - ')
                        $row.Item = $item
                        $row
                    })
                $preferencesEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'This GPO has no {0} item for the computers.' } else { 'This GPO has no {0} item for the users.' }) (Get-PSGPOText $extension.Name) }
            } catch {
                $problem = Get-PSGPOText 'The preferences cannot be read: {0}' $_.Exception.GetBaseException().Message
                $preferencesEmptyTextBlock.Text = ''
            }
        }
        $preferencesEmptyTextBlock.IsVisible = [bool]$preferencesEmptyTextBlock.Text
        $preferencesList.ItemsSource = $rows
        if ($SelectUid) { $preferencesList.SelectedItem = $rows | Where-Object { $_.Item.Uid -eq $SelectUid } | Select-Object -First 1 }
        if ($problem) { Set-PreferenceStatus $problem -Problem } else { Set-PreferenceStatus $Status }
        Update-PreferenceToolbar
    }

    # Applies a change to a copy of the file, writes it to the GPO, then shows the items again;
    # returns the error message when the change or the write failed (nothing is kept then).
    function Save-PreferenceFile {
        param([scriptblock]$Change, [string]$Done, [string]$SelectUid)
        $node = $preferences.Node
        $copy = [GPOToolsPreferenceFile]::Parse($preferences.File.ToBytes())
        try {
            $uid = & $Change $copy
            $Directory.WritePreferenceFile($editing.Gpo, $node.Scope, $node.Extension.Path, $copy.ToBytes(), $node.Extension.Cse, $node.Extension.Tool)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Preferences["$($node.Scope)|$($node.Extension.Id)"] = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($node.Scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-PreferenceType -Node $node -Status (Get-PSGPOText '{0} in Preferences\{1} ({2} version {3}).' $Done $node.Extension.Path (Get-PSGPOText $node.Scope) $version) -SelectUid $(if ($uid) { $uid } else { $SelectUid })
        $null
    }

    function Find-PreferenceElement {
        param([GPOToolsPreferenceFile]$File, [string]$Uid)
        $File.Document.SelectSingleNode("//*[@uid='$Uid']")
    }

    function Open-PreferenceForm {
        param($Type, $Item)
        $preferences.Type = $Type
        $preferences.Item = $Item
        $preferences.Form = New-PSGPOPreferenceForm -Type $Type -Scope $preferences.Node.Scope -Item $Item
        $preferencesFormHost.Content = $preferences.Form.Panel
        $preferencesFormTitleTextBlock.Text = if ($Item) { "$(Get-PSGPOText $Type.Label): $($Item.Name)" } else { Get-PSGPOText 'New {0}' (Get-PSGPOText $Type.Label) }
        $preferencesFormErrorTextBlock.Text = ''
        $preferencesDeletePanel.IsVisible = $false
        $preferencesFormBorder.IsVisible = $true
    }

    $preferencesList.add_SelectionChanged({ Update-PreferenceToolbar })
    $preferencesNewTypeComboBox.add_SelectionChanged({ Update-PreferenceToolbar })
    $preferencesNewButton.Add_Click({
        $type = @($preferences.Node.Extension.Items | Where-Object { $_.Properties -and -not $_.IsCollection })[$preferencesNewTypeComboBox.SelectedIndex]
        if ($type) { Open-PreferenceForm -Type $type -Item $null }
    })
    $preferencesEditButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesList.add_DoubleTapped({
        $row = $preferencesList.SelectedItem
        if ($row -and $row.Item.Editable -and (Test-PreferenceEditable)) { Open-PreferenceForm -Type $row.Item.Type -Item $row.Item }
    })
    $preferencesCancelButton.Add_Click({ $preferencesFormBorder.IsVisible = $false })
    $preferencesSaveButton.Add_Click({
        $type = $preferences.Type
        $item = $preferences.Item
        try {
            $values = & $preferences.Form.GetValues
            $common = & $preferences.Form.GetCommon
        } catch {
            $preferencesFormErrorTextBlock.Text = $_.Exception.Message
            return
        }
        $problem = if ($item) {
            Save-PreferenceFile -Done (Get-PSGPOText '{0} saved' (Get-PSGPOText $type.Label)) -SelectUid $item.Uid -Change {
                param($Copy)
                Set-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $item.Uid) -Type $type -Values $values -Common $common
            }
        } else {
            Save-PreferenceFile -Done (Get-PSGPOText '{0} created' (Get-PSGPOText $type.Label)) -Change {
                param($Copy)
                (New-PSGPOPreferenceItem -File $Copy -Type $type -Values $values -Common $common).GetAttribute('uid')
            }
        }
        if ($problem) { $preferencesFormErrorTextBlock.Text = $problem } else { $preferencesFormBorder.IsVisible = $false }
    })
    $preferencesDeleteButton.Add_Click({
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $preferencesDeleteTextBlock.Text = Get-PSGPOText "Delete the item '{0}' from the GPO? The computers and users stop applying it; what it already changed stays, unless it removes itself (Remove this item when it is no longer applied)." $row.Name
        $preferencesFormBorder.IsVisible = $false
        $preferencesDeletePanel.IsVisible = $true
    })
    $preferencesDeleteCancelButton.Add_Click({ $preferencesDeletePanel.IsVisible = $false })
    $preferencesDeleteConfirmButton.Add_Click({
        $row = $preferencesList.SelectedItem
        $preferencesDeletePanel.IsVisible = $false
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done (Get-PSGPOText "'{0}' deleted" $row.Name) -Change {
            param($Copy)
            Remove-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid)
            $null
        }
        if ($problem) { Set-PreferenceStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })
    # Not GetNewClosure for the handlers: the functions of this window would not be found.
    function Move-PreferenceItem {
        param([string]$Direction)
        $row = $preferencesList.SelectedItem
        if (-not $row) { return }
        $problem = Save-PreferenceFile -Done (Get-PSGPOText $(if ($Direction -eq 'Up') { "'{0}' moved up" } else { "'{0}' moved down" }) $row.Name) -SelectUid $row.Item.Uid -Change {
            param($Copy)
            Move-PSGPOPreferenceElement -Element (Find-PreferenceElement $Copy $row.Item.Uid) -Direction $Direction
            $null
        }
        if ($problem) { Set-PreferenceStatus (Get-PSGPOText 'Not moved: {0}' $problem) -Problem }
    }
    $preferencesUpButton.Add_Click({ Move-PreferenceItem -Direction Up })
    $preferencesDownButton.Add_Click({ Move-PreferenceItem -Direction Down })

    # --- Restricted Groups: the groups of [Group Membership] in the GptTmpl.inf of the edited GPO ---

    $restrictedGroups = @{ Group = $null }
    function Set-RestrictedGroupStatus {
        param([string]$Text, [switch]$Problem)
        $restrictedGroupsStatusTextBlock.Text = $Text
        if ($Problem) { $restrictedGroupsStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $restrictedGroupsStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Test-RestrictedGroupEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $editing.Template
    }

    function Update-RestrictedGroupToolbar {
        $editable = Test-RestrictedGroupEditable
        $restrictedGroupsAddButton.IsEnabled = [bool]$editable
        $restrictedGroupsEditButton.IsEnabled = $editable -and $restrictedGroupsList.SelectedItem
        $restrictedGroupsDeleteButton.IsEnabled = $editable -and $restrictedGroupsList.SelectedItem
    }

    # The restricted groups of the edited GPO, the group $Select selected.
    function Show-RestrictedGroupList {
        param([string]$Status, [string]$Select)
        $restrictedGroupsFormBorder.IsVisible = $false
        $restrictedGroupsDeletePanel.IsVisible = $false
        $rows = @()
        if (-not $editing.Gpo) {
            $restrictedGroupsEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its restricted groups.'
        } elseif (-not $editing.Template) {
            $restrictedGroupsEmptyTextBlock.Text = ''
            if (-not $Status) { $Status = $editing.PolError }
        } else {
            $rows = @(foreach ($group in @(Get-PSGPORestrictedGroup -Template $editing.Template)) {
                    $row = [AvaloniaPreferenceRow]::new()
                    $row.Name = Format-PSGPORestrictedAccount $group.Group
                    $row.Summary = (@(
                            if ($null -eq $group.Members) { Get-PSGPOText 'Members: not defined' }
                            elseif ($group.Members.Count) { Get-PSGPOText 'Members: {0}' (@($group.Members | ForEach-Object { Format-PSGPORestrictedAccount $_ }) -join ', ') }
                            if ($group.MemberOf.Count) { Get-PSGPOText 'Member of: {0}' (@($group.MemberOf | ForEach-Object { Format-PSGPORestrictedAccount $_ }) -join ', ') }) -join ' - ')
                    $row.Flags = if ($null -ne $group.Members -and -not $group.Members.Count) { Get-PSGPOText 'No member: the computers remove every member of this group' }
                    $row.Item = $group
                    $row
                })
            $restrictedGroupsEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText 'This GPO has no restricted group.' }
        }
        $restrictedGroupsEmptyTextBlock.IsVisible = [bool]$restrictedGroupsEmptyTextBlock.Text
        $restrictedGroupsList.ItemsSource = $rows
        if ($Select) { $restrictedGroupsList.SelectedItem = $rows | Where-Object { $_.Item.Group -ieq $Select } | Select-Object -First 1 }
        Set-RestrictedGroupStatus $Status
        Update-RestrictedGroupToolbar
    }

    function Open-RestrictedGroupForm {
        param($Group)
        $restrictedGroups.Group = $Group
        $restrictedGroupsFormTitleTextBlock.Text = if ($Group) { Get-PSGPOText 'Restricted group: {0}' (Format-PSGPORestrictedAccount $Group.Group) } else { Get-PSGPOText 'New restricted group' }
        $restrictedGroupNameTextBox.Text = if ($Group) { $Group.Group } else { '' }
        $restrictedGroupMembersCheckBox.IsChecked = -not $Group -or $null -ne $Group.Members
        $restrictedGroupMembersTextBox.Text = if ($Group) { @($Group.Members) -join [Environment]::NewLine } else { '' }
        $restrictedGroupMemberOfTextBox.Text = if ($Group) { @($Group.MemberOf) -join [Environment]::NewLine } else { '' }
        $restrictedGroupsFormErrorTextBlock.Text = ''
        $restrictedGroupsDeletePanel.IsVisible = $false
        $restrictedGroupsFormBorder.IsVisible = $true
    }

    # A change of the restricted groups: on a copy of GptTmpl.inf, written, then kept.
    function Save-RestrictedGroupChange {
        param([scriptblock]$Change, [string]$Done, [string]$Select)
        $copy = [GPOToolsSecurityTemplate]::Parse($editing.Template.ToBytes())
        try {
            & $Change $copy
            $Directory.WriteSecurityTemplate($editing.Gpo, $copy.ToBytes())
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Template = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        Show-RestrictedGroupList -Status (Get-PSGPOText '{0} in GptTmpl.inf (version {1}).' $Done $editing.Gpo.GetComputerVersion()) -Select $Select
        $null
    }

    $restrictedGroupsList.add_SelectionChanged({ Update-RestrictedGroupToolbar })
    $restrictedGroupsAddButton.Add_Click({ Open-RestrictedGroupForm $null })
    $restrictedGroupsEditButton.Add_Click({ if ($restrictedGroupsList.SelectedItem) { Open-RestrictedGroupForm $restrictedGroupsList.SelectedItem.Item } })
    $restrictedGroupsList.add_DoubleTapped({ if ($restrictedGroupsList.SelectedItem -and (Test-RestrictedGroupEditable)) { Open-RestrictedGroupForm $restrictedGroupsList.SelectedItem.Item } })
    $restrictedGroupsCancelButton.Add_Click({ $restrictedGroupsFormBorder.IsVisible = $false })
    $restrictedGroupMembersCheckBox.add_IsCheckedChanged({ $restrictedGroupMembersTextBox.IsEnabled = [bool]$restrictedGroupMembersCheckBox.IsChecked })
    $restrictedGroupsSaveButton.Add_Click({
        $name = "$($restrictedGroupNameTextBox.Text)".Trim()
        $lines = { param($Text) @("$Text" -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        $members = if ($restrictedGroupMembersCheckBox.IsChecked) { [string[]](& $lines $restrictedGroupMembersTextBox.Text) } else { $null }
        $memberOf = [string[]](& $lines $restrictedGroupMemberOfTextBox.Text)
        $old = $restrictedGroups.Group
        $problem = Save-RestrictedGroupChange -Select $name -Done (Get-PSGPOText $(if ($old) { "Restricted group '{0}' saved" } else { "Restricted group '{0}' added" }) $name) -Change {
            param($Copy)
            if ($old -and $old.Group -ine $name) { Remove-PSGPORestrictedGroup -Template $Copy -Group $old.Group }
            if (-not $old -and @(Get-PSGPORestrictedGroup -Template $Copy | Where-Object { $_.Group -ieq $name }).Count) { throw (Get-PSGPOText "'{0}' is already a restricted group of this GPO: edit it." $name) }
            Set-PSGPORestrictedGroup -Template $Copy -Group $name -Members $members -MemberOf $memberOf
        }
        if ($problem) { $restrictedGroupsFormErrorTextBlock.Text = $problem }
    })
    $restrictedGroupsDeleteButton.Add_Click({
        $row = $restrictedGroupsList.SelectedItem
        if (-not $row) { return }
        $restrictedGroupsDeleteTextBlock.Text = Get-PSGPOText "Delete the restricted group '{0}' from the GPO? The computers stop changing its members; the members it already has stay." $row.Name
        $restrictedGroupsFormBorder.IsVisible = $false
        $restrictedGroupsDeletePanel.IsVisible = $true
    })
    $restrictedGroupsDeleteCancelButton.Add_Click({ $restrictedGroupsDeletePanel.IsVisible = $false })
    $restrictedGroupsDeleteConfirmButton.Add_Click({
        $row = $restrictedGroupsList.SelectedItem
        if (-not $row) { return }
        $group = $row.Item.Group
        $problem = Save-RestrictedGroupChange -Done (Get-PSGPOText "Restricted group '{0}' deleted" $row.Name) -Change { param($Copy) Remove-PSGPORestrictedGroup -Template $Copy -Group $group }
        if ($problem) { Set-RestrictedGroupStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })

    # --- Public Key Policies: the certificates of a store in the Registry.pol of the edited GPO ---

    $certificates = @{ Node = $null }
    function Set-CertificateStatus {
        param([string]$Text, [switch]$Problem)
        $certificatesStatusTextBlock.Text = $Text
        if ($Problem) { $certificatesStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $certificatesStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Test-CertificateEditable {
        $editing.Gpo -and $editing.Gpo.CanEdit -and -not $Directory.IsReadOnly -and $certificates.Node -and $editing.Pol[$certificates.Node.Scope]
    }

    function Update-CertificateToolbar {
        $editable = Test-CertificateEditable
        $certificatesImportButton.IsEnabled = [bool]$editable
        $certificatesPathTextBox.IsEnabled = [bool]$editable
        $certificatesDeleteButton.IsEnabled = $editable -and $certificatesList.SelectedItem
    }

    # The certificates of the store selected in the tree, for the edited GPO.
    function Show-CertificateStore {
        param([GPOToolsCertificateStoreNode]$Node, [string]$Status, [string]$Select)
        $certificates.Node = $Node
        $certificatesDeletePanel.IsVisible = $false
        $scopeLabel = Get-PSGPOText $(if ($Node.Scope -eq 'Machine') { 'Computer Configuration' } else { 'User Configuration' })
        $certificatesTitleTextBlock.Text = "$(Get-PSGPOText $Node.Name) ($scopeLabel)"
        $certificatesInfoTextBlock.Text = (Get-PSGPOText 'In {0}\Registry.pol of the GPO: Software\Policies\Microsoft\SystemCertificates\{1}\Certificates, applied by the Registry extension.' $Node.Scope $Node.Store) +
            $(switch ($Node.Store) {
                    'EFS' { Get-PSGPOText ' The recovery agents of EFS: their certificates also make the EFSBlob, rebuilt at each change.' }
                    'FVE' { Get-PSGPOText ' The data recovery agents of BitLocker (with the policy that gives the identifiers of the organization).' }
                    'FVE_NKP' { Get-PSGPOText ' The certificate of BitLocker Network Unlock.' }
                    'Disallowed' { Get-PSGPOText ' The computers distrust these certificates.' }
                })
        $rows = @()
        $pol = if ($editing.Gpo) { $editing.Pol[$Node.Scope] }
        if (-not $editing.Gpo) {
            $certificatesEmptyTextBlock.Text = Get-PSGPOText 'Edit a GPO (Group Policy Management view) to see and configure its public key policies.'
        } elseif (-not $pol) {
            $certificatesEmptyTextBlock.Text = ''
            if (-not $Status) { $Status = $editing.PolError }
        } else {
            $now = [datetime]::Now
            $rows = @(foreach ($certificate in @(Get-PSGPOPolicyCertificate -Pol $pol -Store $Node.Store)) {
                    $row = [AvaloniaPreferenceRow]::new()
                    $row.Name = $certificate.Subject
                    $row.Summary = if ($certificate.Certificate) {
                        Get-PSGPOText 'Issued by {0} - expires {1} - thumbprint {2}' $certificate.Issuer $certificate.NotAfter.ToString('yyyy-MM-dd') $certificate.Thumbprint
                    } else { Get-PSGPOText 'Thumbprint {0}' $certificate.Thumbprint }
                    $row.Flags = if (-not $certificate.Certificate) { Get-PSGPOText 'This value is not a certificate the console can read.' }
                        elseif ($certificate.NotAfter -lt $now) { Get-PSGPOText 'Expired' }
                    $row.Item = $certificate
                    $row
                })
            $certificatesEmptyTextBlock.Text = if ($rows.Count) { '' } else { Get-PSGPOText 'This GPO has no certificate in this store.' }
        }
        $certificatesEmptyTextBlock.IsVisible = [bool]$certificatesEmptyTextBlock.Text
        $certificatesList.ItemsSource = $rows
        if ($Select) { $certificatesList.SelectedItem = $rows | Where-Object { $_.Item.Thumbprint -eq $Select } | Select-Object -First 1 }
        Set-CertificateStatus $Status
        Update-CertificateToolbar
    }

    # A change of a store: on a copy of the Registry.pol of the scope, written, then kept.
    function Save-CertificateChange {
        param([scriptblock]$Change, [string]$Done, [string]$Select)
        $node = $certificates.Node
        $copy = [GPOToolsRegistryPol]::Parse($editing.Pol[$node.Scope].ToBytes())
        try {
            & $Change $copy
            $efs = @(Get-PSGPOPolicyCertificate -Pol $copy -Store 'EFS').Count -gt 0
            $Directory.WritePublicKeyPolicyFile($editing.Gpo, $node.Scope, $copy.ToBytes(), $efs)
        } catch {
            return $_.Exception.GetBaseException().Message
        }
        $editing.Pol[$node.Scope] = $copy
        $settingsCache.Remove("$($editing.Gpo.Id)")
        $version = if ($node.Scope -eq 'Machine') { $editing.Gpo.GetComputerVersion() } else { $editing.Gpo.GetUserVersion() }
        Show-CertificateStore -Node $node -Status (Get-PSGPOText '{0} in {1}\Registry.pol (version {2}).' $Done $node.Scope $version) -Select $Select
        $null
    }

    $certificatesList.add_SelectionChanged({ Update-CertificateToolbar })
    $certificatesImportButton.Add_Click({
        $path = "$($certificatesPathTextBox.Text)".Trim().Trim('"')
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Set-CertificateStatus (Get-PSGPOText 'Give the path of a certificate file (.cer, .crt or .pem).') -Problem; return }
        try { $der = Read-PSGPOCertificateFile -Path $path } catch { Set-CertificateStatus $_.Exception.Message -Problem; return }
        $store = $certificates.Node.Store
        $added = @{ Info = $null }
        $problem = Save-CertificateChange -Done (Get-PSGPOText 'Certificate imported') -Change {
            param($Copy)
            $added.Info = Add-PSGPOPolicyCertificate -Pol $Copy -Store $store -Certificate $der
        }
        if ($problem) { Set-CertificateStatus (Get-PSGPOText 'Not imported: {0}' $problem) -Problem; return }
        $certificatesPathTextBox.Text = ''
        Show-CertificateStore -Node $certificates.Node -Status $certificatesStatusTextBlock.Text -Select $added.Info.Thumbprint
    })
    $certificatesDeleteButton.Add_Click({
        $row = $certificatesList.SelectedItem
        if (-not $row) { return }
        $certificatesDeleteTextBlock.Text = Get-PSGPOText "Delete the certificate '{0}' from the GPO? The computers remove it from their Group Policy store at the next refresh." $row.Name
        $certificatesDeletePanel.IsVisible = $true
    })
    $certificatesDeleteCancelButton.Add_Click({ $certificatesDeletePanel.IsVisible = $false })
    $certificatesDeleteConfirmButton.Add_Click({
        $row = $certificatesList.SelectedItem
        if (-not $row) { return }
        $store = $certificates.Node.Store
        $thumbprint = $row.Item.Thumbprint
        $problem = Save-CertificateChange -Done (Get-PSGPOText "Certificate '{0}' deleted" $row.Name) -Change { param($Copy) Remove-PSGPOPolicyCertificate -Pol $Copy -Store $store -Thumbprint $thumbprint }
        if ($problem) { Set-CertificateStatus (Get-PSGPOText 'Not deleted: {0}' $problem) -Problem }
    })

    $treeView.add_SelectionChanged({
        $selected = $treeView.SelectedItem

        # Breadcrumb: walk the node's own Parent chain (built while populating the tree).
        $pathParts = [System.Collections.Generic.List[string]]::new()
        $current = $selected
        while ($null -ne $current) {
            $pathParts.Insert(0, $current.Header)
            $current = $current.Parent
        }
        $breadcrumbTextBlock.Text = if ($pathParts.Count -gt 0) { $pathParts -join ' > ' } else { Get-PSGPOText 'Select a policy to see its path' }

        $policy = if ($selected) { $selected.Tag } else { $null }
        $editing.Security = $null
        # A preference type: its items instead of the form of a policy; Restricted Groups: its groups.
        $isPreference = $policy -is [GPOToolsPreferenceNode]
        $isRestricted = $policy -is [string] -and $policy -eq 'RestrictedGroups'
        $isStore = $policy -is [GPOToolsCertificateStoreNode]
        $preferencesPanel.IsVisible = $isPreference
        $restrictedGroupsPanel.IsVisible = $isRestricted
        $certificatesPanel.IsVisible = $isStore
        $detailsTabs.IsVisible = -not $isPreference -and -not $isRestricted -and -not $isStore
        $detailsTitleTextBlock.Text = Get-PSGPOText $(if ($isPreference) { 'Preference Items' } elseif ($isRestricted) { 'Restricted Groups' } elseif ($isStore) { 'Public Key Policies' } else { 'Policy Details' })
        if ($isStore) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-CertificateStore -Node $policy
            return
        }
        if ($isRestricted) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-RestrictedGroupList
            return
        }
        if ($isPreference) {
            $editing.Policy = $null
            $editing.Editor = $null
            Show-PreferenceType -Node $policy
            return
        }
        if ($policy -is [GPOToolsSecuritySetting]) {
            Show-SecuritySetting -Setting $policy
            return
        }
        # A policy: Not Configured / Enabled / Disabled.
        $notConfiguredRadio.Content = Get-PSGPOText 'Not Configured'
        $enabledRadio.Content = Get-PSGPOText 'Enabled'
        $disabledRadio.IsVisible = $true
        $previewHeaderTextBlock.Text = Get-PSGPOText 'Registry Preview'
        # The setting of the policy in the Registry.pol of the edited GPO, else not configured.
        $read = [pscustomobject]@{ State = 'NotConfigured'; Value = @{} }
        $pol = if ($policy -is [GPOToolsPolicy]) { $editing.Pol["$($policy.Scope)"] }
        if ($pol) {
            try { $read = Get-PSGPOPolicyState -Policy $policy -Pol $pol } catch { Write-Warning "Setting of $($policy.DisplayName) not read: $($_.Exception.Message)" }
        }
        $editing.Policy = $null
        $editing.Saved = if ($pol) { Get-SettingSignature $policy $read.State $read.Value } else { $null }
        switch ($read.State) {
            'Enabled' { $enabledRadio.IsChecked = $true }
            'Disabled' { $disabledRadio.IsChecked = $true }
            default { $notConfiguredRadio.IsChecked = $true }
        }
        $applyStatusTextBlock.Text = if ($pol) { Get-PSGPOText '{0} in {1}\Registry.pol' (Get-PSGPOText $read.State) $policy.Scope } elseif ($editing.Gpo -and $editing.PolError) { $editing.PolError } else { '' }
        if ($policy -is [GPOToolsPolicy]) {
            $editing.Policy = $policy
            $settingTitleTextBlock.Text = $policy.DisplayName
            $editing.Editor = New-PSGPOPolicyEditor -Policy $policy -Value $read.Value -OnChange { Update-RegistryPreview }
            $optionsHost.Content = $editing.Editor.Panel

            $displayNameTextBox.Text = $policy.DisplayName
            $descriptionTextBox.Text = if ($policy.Description) { $policy.Description } else { Get-PSGPOText '(No description available)' }
            $scopeTextBox.Text = Get-PSGPOText $policy.Scope.ToString()

            if ($policy.Registry) {
                $registryPathTextBox.Text = if ($policy.Registry.Path) { $policy.Registry.Path } else { Get-PSGPOText '(No registry path defined)' }
                $registryKeyTextBox.Text = if ($policy.Registry.Key) { $policy.Registry.Key } else { Get-PSGPOText '(No registry value name defined)' }

                $rows = @(Get-PSGPOPolicyRegistryRow -Policy $policy)
                if ($rows.Count -gt 0) {
                    $registryValuesList.ItemsSource = $rows
                } else {
                    $row = [AvaloniaRegistryRow]::new()
                    $row.Key = Get-PSGPOText 'Information'
                    $row.Value = Get-PSGPOText '(No registry value available for this policy)'
                    $registryValuesList.ItemsSource = @($row)
                }
            } else {
                $registryPathTextBox.Text = Get-PSGPOText '(This policy does not use the registry)'
                $registryKeyTextBox.Text = Get-PSGPOText '(No registry value name)'
                $row = [AvaloniaRegistryRow]::new()
                $row.Key = Get-PSGPOText 'Information'
                $row.Value = Get-PSGPOText '(This policy does not store data in the registry)'
                $registryValuesList.ItemsSource = @($row)
            }
        } else {
            $displayNameTextBox.Text = ''
            $descriptionTextBox.Text = ''
            $scopeTextBox.Text = ''
            $registryPathTextBox.Text = ''
            $registryKeyTextBox.Text = ''
            $registryValuesList.ItemsSource = $null
            $editing.Policy = $null
            $editing.Editor = $null
            $optionsHost.Content = $null
            $settingTitleTextBlock.Text = Get-PSGPOText 'Select a policy in the tree'
        }
        Update-RegistryPreview
    })

    # The tree of the policies matching the search; editing a GPO with "Configured settings
    # only", the policies its Registry.pol files configure and the security settings its
    # GptTmpl.inf defines.
    function Update-PolicyTree {
        $only = $null
        if ($configuredOnlyCheckBox.IsChecked -and $editing.Gpo) {
            $only = [System.Collections.Generic.HashSet[object]]::new()
            foreach ($scope in 'Machine', 'User') {
                if (-not $editing.Pol[$scope]) { continue }
                foreach ($configured in @(Get-PSGPOConfiguredPolicy -Pol $editing.Pol[$scope] -Scope $scope)) { [void]$only.Add($configured.Policy) }
            }
            foreach ($setting in Get-PSGPOSecuritySetting) {
                $store = Get-SecurityStore $setting
                if ($store -and $store.HasValue($setting.Section, $setting.Key)) { [void]$only.Add($setting) }
            }
            if ($editing.Template -and @(Get-PSGPORestrictedGroup -Template $editing.Template).Count) { [void]$only.Add('RestrictedGroups') }
            # The certificate stores with a certificate.
            foreach ($scope in 'Machine', 'User') {
                if (-not $editing.Pol[$scope]) { continue }
                foreach ($store in @(Get-PSGPOCertificateStore -Scope $scope)) {
                    if (@(Get-PSGPOPolicyCertificate -Pol $editing.Pol[$scope] -Store $store.Store).Count) { [void]$only.Add("Certificates:$scope|$($store.Store)") }
                }
            }
            # The preference types the GPO declares (its client-side extensions).
            foreach ($scope in 'Machine', 'User') {
                $names = if ($scope -eq 'Machine') { "$($editing.Gpo.MachineExtensionNames)" } else { "$($editing.Gpo.UserExtensionNames)" }
                foreach ($extension in @(Get-PSGPOPreferenceExtension -Scope $scope)) {
                    if ($names.IndexOf($extension.Cse, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { [void]$only.Add("Preference:$scope|$($extension.Id)") }
                }
            }
        }
        $treeView.ItemsSource = New-PSGPOPolicyTree -Filter $searchTextBox.Text -Only $only
        if ($only -and -not @($treeView.ItemsSource).Count) {
            $breadcrumbTextBlock.Text = Get-PSGPOText $(if ($searchTextBox.Text) { 'No configured setting matches the search' } else { 'This GPO configures no setting' })
        }
    }
    $configuredOnlyCheckBox.add_IsCheckedChanged({ Update-PolicyTree })

    # The security settings do not come from the ADMX files: the tree always has them.
    Update-PolicyTree
    if ([GPOToolsUtility]::Policies.Count -eq 0) {
        Write-Warning 'No ADMX policy loaded: run Initialize-PSGPOAdmx before Show-GPOManagerAvalonia for the Administrative Templates.'
        $breadcrumbTextBlock.Text = Get-PSGPOText 'No ADMX policy loaded (Initialize-PSGPOAdmx): only the security settings are shown'
    }

    $searchButton.Add_Click({ Update-PolicyTree })
    $searchTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            Update-PolicyTree
        }
    })

    # --- Group Policy Management view --------------------------------------------------------

    function Show-View {
        param([ValidateSet('Management', 'Editor')][string]$View)
        $managementView.IsVisible = $View -eq 'Management'
        $editorView.IsVisible = $View -eq 'Editor'
        $managementButton.IsVisible = $View -eq 'Editor'
        $browseAdmxButton.IsVisible = $View -eq 'Management'
        # A domain read over LDAP is read again; a description in memory has nothing to read.
        $refreshButton.IsVisible = $View -eq 'Management' -and $Directory -is [GPOToolsLdapDirectory]
        $searchPanel.IsVisible = $View -eq 'Editor'
        $subtitleTextBlock.Text = if ($View -eq 'Management') {
            if (-not $Directory) { Get-PSGPOText 'Group Policy Management' }
            elseif ($Directory.IsDemonstration) { Get-PSGPOText 'Group Policy Management - {0} (demonstration)' $Directory.DomainName }
            elseif ($Directory -is [GPOToolsLdapDirectory]) {
                if ($Directory.Account) { Get-PSGPOText 'Group Policy Management - {0} ({1}) - connected as {2}' $Directory.DomainName $Directory.ServerType $Directory.Account }
                else { Get-PSGPOText 'Group Policy Management - {0} ({1})' $Directory.DomainName $Directory.ServerType }
            }
            elseif ($Directory.IsReadOnly) { Get-PSGPOText 'Group Policy Management - {0} (read-only)' $Directory.DomainName }
            else { Get-PSGPOText 'Group Policy Management - {0}' $Directory.DomainName }
        } elseif ($editing.Gpo) { Get-PSGPOText 'Editing the GPO {0}' $editing.Gpo.DisplayName } else { Get-PSGPOText 'Explore and manage Group Policy Objects' }
    }

    # Opens the policy editor on a GPO ($null: browse the ADMX policies, outside any GPO).
    function Open-GpoEditor {
        param([GPOToolsGpo]$Gpo)
        $editing.Gpo = $Gpo
        # The settings of the GPO: its Registry.pol for each scope (empty when it has none).
        $editing.Pol = @{}
        $editing.Template = $null
        $editing.Audit = $null
        $editing.Preferences = @{}
        $editing.PolError = $null
        if ($Gpo) {
            try {
                foreach ($scope in 'Machine', 'User') {
                    $editing.Pol[$scope] = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($Gpo, $scope))
                }
                # Its security settings: GptTmpl.inf, a new empty template when the GPO has none.
                $editing.Template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($Gpo))
                # Its advanced audit policy: audit.csv, empty when the GPO has none.
                $editing.Audit = [GPOToolsAuditPolicyFile]::Parse($Directory.ReadAuditPolicyFile($Gpo))
            } catch {
                $editing.PolError = Get-PSGPOText 'The settings of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message
                $editing.Pol = @{}
                $editing.Template = $null
                $editing.Audit = $null
            }
        }
        $treeView.SelectedItem = $null
        # The filter on the configured settings only applies to a GPO; rebuilt for this one.
        $configuredOnlyCheckBox.IsVisible = $null -ne $Gpo
        if (-not $Gpo -and $configuredOnlyCheckBox.IsChecked) { $configuredOnlyCheckBox.IsChecked = $false }
        elseif ($configuredOnlyCheckBox.IsChecked) { Update-PolicyTree }
        $editingBanner.IsVisible = $null -ne $Gpo
        $editingGpoTextBlock.Text = if (-not $Gpo) { '' }
            elseif ($editing.PolError) { Get-PSGPOText "Editing the GPO '{0}' [{1}]: {2}" $Gpo.DisplayName $Directory.DomainName $editing.PolError }
            else { Get-PSGPOText "Editing the GPO '{0}' [{1}]" $Gpo.DisplayName $Directory.DomainName }
        # Its status may disable a part: it can be edited, as in GPMC, but does not apply.
        $editingStatusTextBlock.Text = if ($Gpo) {
            switch ($Gpo.Flags -band 3) {
                1 { Get-PSGPOText 'The GPO status disables its User Configuration: its settings are saved, but the users do not apply them.' }
                2 { Get-PSGPOText 'The GPO status disables its Computer Configuration: its settings are saved, but the computers do not apply them.' }
                3 { Get-PSGPOText 'The GPO status disables all its settings: they are saved, but nobody applies them.' }
            }
        }
        Update-ApplyButton
        Show-View 'Editor'
    }

    # Keys of the expanded nodes, to keep them expanded when the tree is rebuilt.
    function Get-ExpandedKey {
        $keys = [System.Collections.Generic.HashSet[string]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($root in @($domainTreeView.ItemsSource)) { if ($root) { $stack.Push($root) } }
        while ($stack.Count) {
            $node = $stack.Pop()
            if ($node.IsExpanded) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $node)") }
            foreach ($child in $node.Children) { $stack.Push($child) }
        }
        , $keys
    }

    # The recycle bin and the templates: from the backups of the folder of the History tab, read
    # again when that folder changes or with -Force (after a deletion, a restore, new notes).
    $backupLists = @{ Root = $null; Deleted = @(); Templates = @(); RootProblem = $null }
    function Update-BackupList {
        param([switch]$Force)
        # Central backups, for Tier 0 only: no Deleted GPOs for the others, nor where the share is
        # not reached (not mounted on Linux).
        if (-not (Test-PSGPOBackupAllowed -Directory $Directory)) {
            $backupLists.Deleted = $null
            $backupLists.Templates = @()
            return
        }
        $root = Get-HistoryRoot
        if (-not $Force -and $backupLists.Root -eq $root) { return }
        $backupLists.Root = $root
        if (-not $root) {
            $backupLists.Deleted = $null
            $backupLists.Templates = @()
            return
        }
        try {
            $backupLists.Deleted = @(Get-PSGPODeletedGpoBackup -Directory $Directory -Path $root)
            $backupLists.Templates = @(Get-PSGPOTemplateBackup -Path $root)
        } catch {
            $backupLists.Deleted = @()
            $backupLists.Templates = @()
        }
    }

    # Rebuilds the tree and selects the first node whose Tag is $Select, its parents expanded.
    function Update-DirectoryTree {
        param($Select)
        Update-BackupList
        $keys = Get-ExpandedKey
        if ($null -ne $Select) {
            $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
            $target = $null
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count -and -not $target) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select) -or ($Select -is [string] -and $node.Tag -is [string] -and $node.Tag -eq $Select)) { $target = $node }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
            for ($parent = $target.Parent; $parent; $parent = $parent.Parent) { [void]$keys.Add("$(Get-PSGPODirectoryNodeKey $parent)") }
        }
        $roots = New-PSGPODirectoryTree -Directory $Directory -Expanded $keys -DeletedGpo $backupLists.Deleted
        $domainTreeView.ItemsSource = $roots
        if ($null -ne $Select) {
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($root in $roots) { $stack.Push($root) }
            while ($stack.Count) {
                $node = $stack.Pop()
                if ([object]::ReferenceEquals($node.Tag, $Select) -or ($Select -is [string] -and $node.Tag -is [string] -and $node.Tag -eq $Select)) { $domainTreeView.SelectedItem = $node; break }
                foreach ($child in $node.Children) { $stack.Push($child) }
            }
        }
    }

    # New GPO form: linked to $Som, or only created in the domain when $Som is $null.
    $newGpo = @{ Som = $null; Groups = $null; Templates = @() }
    function Open-NewGpoForm {
        param([GPOToolsSom]$Som)
        $newGpo.Som = $Som
        $newGpoTitleTextBlock.Text = if ($Som) { Get-PSGPOText 'New GPO in {0}, linked to {1}' $Directory.DomainName $Som.Name } else { Get-PSGPOText 'New GPO in {0}' $Directory.DomainName }
        # What the configuration proposes (Get-PSGPOConfiguration): name, status, groups.
        $configuration = (Get-PSGPOConfigurationData).NewGpo
        $newGpo.Groups = $configuration.SecurityFilteringGroups
        $newGpoNameTextBox.Text = $configuration.DefaultName
        $newGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        # The templates: the backups with the template label, newest first.
        Update-BackupList -Force
        $newGpo.Templates = @($backupLists.Templates)
        $newGpoTemplateComboBox.ItemsSource = @(Get-PSGPOText 'Empty GPO') + @(foreach ($template in $newGpo.Templates) {
                (Get-PSGPOText '{0}, backup of {1}' $template.DisplayName (Format-HistoryDate $template.BackedUp)) + $(if ($template.Domain -and $template.Domain -ne $Directory.DomainName) { " ($($template.Domain))" })
            })
        $newGpoTemplateComboBox.SelectedIndex = 0
        $newGpoStatusComboBox.SelectedIndex = [array]::IndexOf(@('Enabled', 'ComputerOnly', 'UserOnly'), $configuration.Status)
        # A GPO of a creator waits for its approval: its security filtering is set then.
        $creator = $Directory.IsWorkflowCreator()
        $newGpoGroupsCheckBox.IsVisible = -not $creator
        $newGpoGroupsCheckBox.IsChecked = [bool]$newGpo.Groups.Create -and -not $creator
        $newGpoGroupsPanel.IsVisible = [bool]$newGpoGroupsCheckBox.IsChecked
        if ($creator) { $newGpoTitleTextBlock.Text += Get-PSGPOText ': it waits for the approval of an approver, and applies to nobody until then' }
        # The groups go to the container of the configuration, else the users container, or to an OU.
        $configured = Resolve-PSGPOGroupContainer -Directory $Directory -Container $newGpo.Groups.Container
        $containers = [System.Collections.Generic.List[string]]::new()
        $containers.Add($configured)
        if ($configured -ne $Directory.GetUsersContainer()) { $containers.Add($Directory.GetUsersContainer()) }
        $stack = [System.Collections.Generic.Stack[GPOToolsSom]]::new()
        foreach ($child in @($Directory.Domain.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        while ($stack.Count) {
            $som = $stack.Pop()
            if ($som.DistinguishedName -ne $configured) { $containers.Add($som.DistinguishedName) }
            foreach ($child in @($som.Children | Sort-Object Name -Descending)) { $stack.Push($child) }
        }
        $newGpoGroupsContainerComboBox.ItemsSource = $containers
        $newGpoGroupsContainerComboBox.SelectedIndex = 0
        Update-NewGpoGroupText
        $newGpoPanel.IsVisible = $true
        [void]$newGpoNameTextBox.Focus()
        $newGpoNameTextBox.SelectAll()
    }

    # What the security filtering groups of the new GPO will be.
    function Update-NewGpoGroupText {
        try {
            $settings = if ($newGpo.Groups) { $newGpo.Groups } else { (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups }
            $apply = Get-PSGPOFilteringGroupName -Role Apply -GpoName $newGpoNameTextBox.Text -Settings $settings
            $deny = Get-PSGPOFilteringGroupName -Role Deny -GpoName $newGpoNameTextBox.Text -Settings $settings
            $newGpoGroupsTextBlock.Text = Get-PSGPOText '{0}: only its members apply the GPO (add the computers or users to it). {1}: its members never apply it. Authenticated Users keep reading the GPO.' $apply $deny
        } catch {
            $newGpoGroupsTextBlock.Text = $_.Exception.Message
        }
    }

    # Creates the GPO, then sets its status and its security filtering groups, then links it.
    # It is not linked when its security filtering failed: it would apply to every computer and
    # user. What failed after the creation is said under the details of the GPO.
    function Submit-NewGpo {
        $template = if ($newGpoTemplateComboBox.SelectedIndex -gt 0) { $newGpo.Templates[$newGpoTemplateComboBox.SelectedIndex - 1] }
        try {
            # A template checked before the GPO is created.
            if ($template) { $null = Get-PSGPOVerifiedBackupFile -Backup $template }
            $gpo = $Directory.NewGpo($newGpoNameTextBox.Text)
        } catch {
            $newGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $done = [System.Collections.Generic.List[string]]::new()
        $problems = [System.Collections.Generic.List[string]]::new()
        $done.Add((Get-PSGPOText "GPO '{0}' created." $gpo.DisplayName))
        if ($gpo.ApprovalState -eq 'Pending') { $done.Add((Get-PSGPOText 'It waits for the approval of {0}: it applies to nobody until then.' ($Directory.Workflow.Approvers -join ', '))) }
        if ($template) {
            try {
                Copy-PSGPOBackupSetting -Directory $Directory -Gpo $gpo -Backup $template
                $done.Add((Get-PSGPOText "Settings of the template '{0}' copied." $template.DisplayName))
            } catch {
                $problems.Add((Get-PSGPOText 'The settings of the template are not copied: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $flags = [int]"$($newGpoStatusComboBox.SelectedItem.Tag)"
        if ($flags) {
            try {
                $Directory.SetGpoStatus($gpo, $flags)
                $done.Add((Get-PSGPOText 'GPO status: {0}.' (Get-PSGPOText $gpo.GetStatus())))
            } catch {
                $problems.Add((Get-PSGPOText 'Its status is not set: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $filtered = $true
        if ($newGpoGroupsCheckBox.IsChecked) {
            try {
                $container = "$($newGpoGroupsContainerComboBox.SelectedItem)"
                $groups = $Directory.NewFilteringGroups($gpo, $container)
                $done.Add((Get-PSGPOText 'Security filtering groups {0} created in {1}.' (@($groups.Name) -join (Get-PSGPOText ' and ')) $container))
            } catch {
                $filtered = $false
                $problems.Add((Get-PSGPOText 'Its security filtering groups are not set: {0}' $_.Exception.GetBaseException().Message))
            }
        }
        $select = $gpo
        if ($newGpo.Som) {
            if (-not $filtered) {
                $problems.Add((Get-PSGPOText 'It is not linked to {0}, so that it does not apply to everyone: link it once its security filtering is set.' $newGpo.Som.Name))
            } else {
                try {
                    $select = $Directory.NewLink($newGpo.Som, $gpo)
                    $done.Add((Get-PSGPOText 'Linked to {0}.' $newGpo.Som.Name))
                } catch {
                    $problems.Add((Get-PSGPOText 'It is not linked to {0}: {1}' $newGpo.Som.Name $_.Exception.GetBaseException().Message))
                }
            }
        }
        $newGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $select
        Show-DirectoryResult -Text ((@($done) + @($problems)) -join [Environment]::NewLine) -Problem:($problems.Count -gt 0)
    }

    # What a change of the directory did, under the details; in red when something failed.
    function Show-DirectoryResult {
        param([string]$Text, [switch]$Problem)
        $directoryResultTextBlock.Text = $Text
        if ($Problem) {
            $directoryResultTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
        } else {
            $directoryResultTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty)
        }
    }

    # Deletion of the selected link, once confirmed, as GPMC: the GPO itself is kept.
    $deleteLink = @{ Som = $null; Link = $null }
    function Open-DeleteLinkForm {
        $node = $domainTreeView.SelectedItem
        if (-not $node -or $node.Tag -isnot [GPOToolsGpoLink] -or $node.Parent.Tag -isnot [GPOToolsSom]) { return }
        $deleteLink.Link = $node.Tag
        $deleteLink.Som = $node.Parent.Tag
        $deleteLinkTextBlock.Text = Get-PSGPOText "Delete the link of the GPO '{0}' to {1}? The GPO itself is not deleted: it stays in Group Policy Objects, with its other links." $node.Tag.GetDisplayName() $node.Parent.Tag.Name
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteLinkPanel.IsVisible = $true
    }

    # The forms of the details, one at a time.
    function Hide-DirectoryForm {
        foreach ($panel in $newGpoPanel, $deleteLinkPanel, $linkGpoPanel, $deleteGpoPanel, $restoreGpoPanel, $purgeDeletedGpoPanel, $renamePanel, $approveGpoPanel, $newWmiFilterPanel, $deleteWmiFilterPanel,
            $exportWmiFilterPanel, $importWmiFilterPanel, $useWmiFilterPanel, $importGpoPanel) { $panel.IsVisible = $false }
    }

    # Approval of the selected GPO (approval workflow): what the creators may still do, who
    # applies it; backed up with the approved label in the folder of the History tab.
    $approveGpo = @{ Gpo = $null; Groups = $null }
    function Open-ApproveGpoForm {
        $gpo = Get-SelectedGpo
        if (-not $gpo -or $gpo.ApprovalState -ne 'Pending') { return }
        $approveGpo.Gpo = $gpo
        # What the approver approves: where it is linked, and whether someone made it apply already.
        $links = @($Directory.GetLinksOf($gpo))
        $approveGpoTextBlock.Text = $(if ($gpo.Owner) { Get-PSGPOText "Approve the GPO '{0}', created by {1}? " $gpo.DisplayName $gpo.Owner } else { Get-PSGPOText "Approve the GPO '{0}'? " $gpo.DisplayName }) +
            (Get-PSGPOText 'Its owner becomes {0}, in the directory and in SYSVOL, and its permissions are rebuilt: its creator cannot give itself its rights back. ' $Directory.Workflow.ApprovedOwner) +
            (Get-PSGPOText 'It applies to the group below from then on, and is backed up as its approved version. ') +
            $(if ($links.Count) { Get-PSGPOText 'It is linked to {0}.' (@($links | ForEach-Object { $_.Som.Name }) -join ', ') } else { Get-PSGPOText 'It is not linked.' }) +
            $(if ($gpo.AppliesWhilePending()) { Get-PSGPOText " Warning: it applies already, to {0}: someone gave 'Apply Group Policy' back while it was pending." ($gpo.SecurityFiltering -join ', ') })
        $approveGpoRightsComboBox.SelectedIndex = if ($Directory.Workflow.CreatorRights -eq 'EditSettings') { 1 } else { 0 }
        # Its own groups when they exist; else the approver may create them, as the New GPO form.
        $existing = Find-PSGPOFilteringGroup -Directory $Directory -Gpo $gpo
        $approveGpo.Groups = (Get-PSGPOConfigurationData).NewGpo.SecurityFilteringGroups
        $approveGpoApplyToTextBox.Text = if ($existing.Apply) { $existing.Apply.Name } else { 'Authenticated Users' }
        $approveGpoDenyToTextBox.Text = if ($existing.Deny) { $existing.Deny.Name } else { '' }
        $approveGpoGroupsCheckBox.IsVisible = -not ($existing.Apply -or $existing.Deny)
        $approveGpoGroupsCheckBox.IsChecked = $approveGpoGroupsCheckBox.IsVisible -and [bool]$approveGpo.Groups.Create
        $approveGpoGroupsTextBlock.Text = if ($approveGpoGroupsCheckBox.IsVisible) {
            Get-PSGPOText '{0} applies it, {1} is denied it; created in {2} ({3}).' (Get-PSGPOFilteringGroupName -Role Apply -GpoName $gpo.DisplayName -Settings $approveGpo.Groups) (Get-PSGPOFilteringGroupName -Role Deny -GpoName $gpo.DisplayName -Settings $approveGpo.Groups) (Resolve-PSGPOGroupContainer -Directory $Directory -Container $approveGpo.Groups.Container) $approveGpo.Groups.Scope
        } else { Get-PSGPOText 'Its groups exist: {0}.' (@($existing.Apply, $existing.Deny | Where-Object { $_ } | ForEach-Object Name) -join ', ') }
        Update-ApproveGpoGroupState
        $approveGpoErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $approveGpoPanel.IsVisible = $true
    }

    # The groups to create replace who applies it and who is denied it.
    function Update-ApproveGpoGroupState {
        $create = [bool]($approveGpoGroupsCheckBox.IsVisible -and $approveGpoGroupsCheckBox.IsChecked)
        $approveGpoFilteringGrid.IsEnabled = -not $create
        $approveGpoGroupsTextBlock.Opacity = if ($create -or -not $approveGpoGroupsCheckBox.IsVisible) { 1 } else { 0.6 }
    }

    function Submit-ApproveGpo {
        $gpo = $approveGpo.Gpo
        if (-not $gpo) { return }
        $rights = "$($approveGpoRightsComboBox.SelectedItem.Tag)"
        $create = [bool]($approveGpoGroupsCheckBox.IsVisible -and $approveGpoGroupsCheckBox.IsChecked)
        try {
            $approval = @{ Directory = $Directory; Gpo = $gpo; CreatorRights = $rights; BackupPath = (Get-HistoryRoot) }
            if ($create) {
                $approval.CreateFilteringGroups = $true
            } else {
                $approval.ApplyTo = Resolve-PSGPOApplyTo -Directory $Directory -Name "$($approveGpoApplyToTextBox.Text)"
                if ("$($approveGpoDenyToTextBox.Text)".Trim()) { $approval.DenyTo = Resolve-PSGPOApplyTo -Directory $Directory -Name "$($approveGpoDenyToTextBox.Text)" }
            }
            $result = Invoke-PSGPOApproval @approval
        } catch {
            $approveGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $approveGpoPanel.IsVisible = $false
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-DirectoryTree -Select $gpo
        $creators = Get-PSGPOText $(if ($rights -eq 'EditSettings') { 'the creators edit its settings' } else { 'the creators read it' })
        $lines = @($(if ($result.DeniedTo) { Get-PSGPOText "GPO '{0}' approved: owned by {1}, applied by {2}, denied to {3}, {4}." $gpo.DisplayName $result.Owner $result.AppliedBy $result.DeniedTo $creators }
                else { Get-PSGPOText "GPO '{0}' approved: owned by {1}, applied by {2}, {3}." $gpo.DisplayName $result.Owner $result.AppliedBy $creators }))
        if ($result.GroupsCreated.Count) { $lines += Get-PSGPOText 'Security filtering groups created: {0}.' ($result.GroupsCreated -join '; ') }
        if ($result.RemovedPermissions.Count) { $lines += Get-PSGPOText 'Permissions added while it was pending, removed: {0}. Find out who added them.' ($result.RemovedPermissions -join ' ') }
        if ($result.Backup) { $lines += Get-PSGPOText 'Backed up as its approved version.' }
        if ($result.Problem) { $lines += $result.Problem }
        Show-DirectoryResult -Text ($lines -join [Environment]::NewLine) -Problem:([bool]($result.Problem -or $result.RemovedPermissions.Count))
    }

    # Import Settings... of a GPO, as GPMC: the settings of a backup of GPMC or of HGPM, of this
    # domain or another, with a migration table; the GPO backed up first in the folder of the History tab.
    $importGpo = @{ Gpo = $null; Sources = @() }
    function Open-ImportGpoForm {
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        $importGpo.Gpo = $gpo
        $importGpoTitleTextBlock.Text = Get-PSGPOText "Import settings into the GPO '{0}'" $gpo.DisplayName
        if (-not "$($importGpoPathTextBox.Text)".Trim()) { $importGpoPathTextBox.Text = Get-HistoryRoot }
        $importGpoTextBlock.Text = Get-PSGPOText 'Its settings are replaced by those of the backup, with the migration table applied; it is backed up first in {0}. Its links, permissions, status and WMI filter do not change.' (Get-HistoryRoot)
        $importGpoErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $importGpoPanel.IsVisible = $true
        Read-ImportSource
    }

    # The backups of the folder typed, to choose the one to import.
    function Read-ImportSource {
        $importGpo.Sources = @()
        $importGpoErrorTextBlock.Text = ''
        try {
            $importGpo.Sources = @(Get-PSGPOImportSource -Path "$($importGpoPathTextBox.Text)".Trim() 3>$null)
        } catch {
            $importGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
        }
        $importGpoSourceComboBox.ItemsSource = @(foreach ($source in $importGpo.Sources) {
                Get-PSGPOText '{0} - {1} backup of {2} ({3})' $source.DisplayName $source.Kind (Format-HistoryDate $source.BackedUp) $source.Domain
            })
        $importGpoSourceComboBox.SelectedIndex = if ($importGpo.Sources.Count) { 0 } else { -1 }
        $importGpoConfirmButton.IsEnabled = $importGpo.Sources.Count -gt 0
        if (-not $importGpo.Sources.Count -and -not $importGpoErrorTextBlock.Text) { $importGpoErrorTextBlock.Text = Get-PSGPOText 'No backup of GPMC or of HGPM in this folder.' }
    }

    function Submit-ImportGpo {
        $gpo = $importGpo.Gpo
        $source = if ($importGpoSourceComboBox.SelectedIndex -ge 0) { $importGpo.Sources[$importGpoSourceComboBox.SelectedIndex] }
        if (-not $gpo -or -not $source) { return }
        $table = "$($importGpoTableTextBox.Text)".Trim()
        try {
            $import = @{ Directory = $Directory; Source = $source; Gpo = $gpo; Exclusive = [bool]$importGpoExclusiveCheckBox.IsChecked; BackupPath = (Get-HistoryRoot) }
            if ($table) { $import.MigrationTable = $table }
            $result = Invoke-PSGPOImport @import
        } catch {
            $importGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $importGpoPanel.IsVisible = $false
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-BackupList -Force
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add((Get-PSGPOText "Settings of '{0}' imported into '{1}' (version {2})." $source.DisplayName $gpo.DisplayName $gpo.Version))
        foreach ($item in @($result.Migration | Where-Object Mode -In 'ByRelativeName', 'Explicit')) { $lines.Add((Get-PSGPOText '{0} -> {1}' $item.Source $item.Destination.QualifiedName)) }
        foreach ($item in @($result.Migration | Where-Object Mode -EQ 'None')) { $lines.Add((Get-PSGPOText '{0}: removed' $item.Source)) }
        $kept = @($result.Migration | Where-Object Mode -EQ 'NotInTable' | ForEach-Object Source)
        if ($kept.Count) { $lines.Add((Get-PSGPOText 'Kept as they are (not in the migration table): {0}' ($kept -join ', '))) }
        Show-DirectoryResult -Text ($lines -join [Environment]::NewLine)
    }

    # Deletion of the selected GPO, once confirmed, as GPMC: its links too; backed up first in
    # the folder of the History tab, so that Deleted GPOs keeps it.
    $deleteGpo = @{ Gpo = $null }
    function Open-DeleteGpoForm {
        $gpo = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($gpo -isnot [GPOToolsGpo]) { return }
        $deleteGpo.Gpo = $gpo
        $links = @($Directory.GetLinksOf($gpo))
        $linkNames = @($links | ForEach-Object { $_.Som.Name }) -join ', '
        $deleteGpoTextBlock.Text = (Get-PSGPOText "Delete the GPO '{0}'? " $gpo.DisplayName) +
            $(if ($links.Count -gt 1) { Get-PSGPOText 'Its {0} links ({1}) are deleted too. ' $links.Count $linkNames } elseif ($links.Count) { Get-PSGPOText 'Its 1 link ({0}) is deleted too. ' $linkNames } else { Get-PSGPOText 'It is not linked. ' }) +
            (Get-PSGPOText 'It is backed up first in {0}: Deleted GPOs keeps it, to restore it.' (Get-HistoryRoot))
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteGpoPanel.IsVisible = $true
    }

    function Submit-DeleteGpo {
        $gpo = $deleteGpo.Gpo
        $deleteGpoPanel.IsVisible = $false
        if (-not $gpo) { return }
        try {
            $removed = Remove-PSGPOWithBackup -Directory $Directory -Gpo $gpo -Path (Get-HistoryRoot)
        } catch {
            # Some links may be gone already.
            Update-DirectoryTree -Select $gpo
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not deleted: {1}" $gpo.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $settingsCache.Remove("$($gpo.Id)")
        Update-BackupList -Force
        Update-DirectoryTree -Select $Directory.Domain
        $count = @($removed.Links).Count
        Show-DirectoryResult -Text $(if ($count -gt 1) { Get-PSGPOText "GPO '{0}' deleted, with its {1} links. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName $count }
            elseif ($count) { Get-PSGPOText "GPO '{0}' deleted, with its 1 link. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName }
            else { Get-PSGPOText "GPO '{0}' deleted. Its backup is in Deleted GPOs, to restore it." $gpo.DisplayName })
    }

    # A deleted GPO created again from its newest backup; linked again where it was, when its
    # security filtering allows it.
    $restoreGpo = @{ Backup = $null }
    function Open-RestoreGpoForm {
        $backup = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $backup -or $backup.PSObject.TypeNames -notcontains 'PSGPOTools.Backup') { return }
        $restoreGpo.Backup = $backup
        $restoreGpoTextBlock.Text = Get-PSGPOText "Create the deleted GPO '{0}' again from its backup of {1}? It gets a new unique ID from the domain, and the settings, status and client-side extensions of the backup. Its security filtering is not restored: it applies to Authenticated Users." $backup.DisplayName (Format-HistoryDate $backup.BackedUp)
        $links = @($backup.Links).Count
        $filtering = (@($backup.SecurityFiltering) -join '|') -eq 'Authenticated Users' -and -not @($backup.DeniedTo | Where-Object { $_ }).Count
        $restoreGpoLinkCheckBox.IsVisible = $links -gt 0
        $restoreGpoLinkCheckBox.IsEnabled = $filtering
        $restoreGpoLinkCheckBox.IsChecked = $filtering
        $restoreGpoLinkCheckBox.Content = if ($filtering) { Get-PSGPOText $(if ($links -gt 1) { 'Link it again where it was ({0} links)' } else { 'Link it again where it was ({0} link)' }) $links }
            else { Get-PSGPOText 'Not linked again: its security filtering was {0}, set it first' (@($backup.SecurityFiltering) -join ', ') }
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $restoreGpoPanel.IsVisible = $true
    }

    function Submit-RestoreGpo {
        $backup = $restoreGpo.Backup
        $restoreGpoPanel.IsVisible = $false
        if (-not $backup) { return }
        try {
            $files = Get-PSGPOVerifiedBackupFile -Backup $backup
            $result = Restore-PSGPODeletedGpo -Directory $Directory -Backup $backup -Files $files -RestoreLink:([bool]($restoreGpoLinkCheckBox.IsVisible -and $restoreGpoLinkCheckBox.IsChecked))
        } catch {
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not restored: {1}" $backup.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $gpo = $Directory.Gpos | Where-Object Id -EQ $result.Id | Select-Object -First 1
        Update-BackupList -Force
        Update-DirectoryTree -Select $gpo
        $lines = @(Get-PSGPOText "GPO '{0}' restored from its backup of {1}, as {2}." $result.DisplayName (Format-HistoryDate $backup.BackedUp) "{$($result.Id.ToString().ToUpperInvariant())}")
        if ($result.Linked.Count) { $lines += Get-PSGPOText 'Linked again to {0}.' (@($result.Linked | ForEach-Object { $Directory.FindSom($_).Name }) -join ', ') }
        Show-DirectoryResult -Text ((@($lines) + @($result.Problems)) -join [Environment]::NewLine) -Problem:($result.Problems.Count -gt 0)
    }

    # A deleted GPO deleted for good, once confirmed: all its backups in the folder of the History
    # tab, its templates too; it leaves Deleted GPOs and cannot be restored anymore.
    $purgeDeletedGpo = @{ Backup = $null }
    function Open-PurgeDeletedGpoForm {
        $backup = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if (-not $backup -or $backup.PSObject.TypeNames -notcontains 'PSGPOTools.Backup') { return }
        $purgeDeletedGpo.Backup = $backup
        $backups = @(Get-PSGPOBackupEntry -Path (Get-HistoryRoot) -Id $backup.Id 3>$null)
        $label = Get-PSGPOTemplateLabel
        $templates = @($backups | Where-Object { $_.Labels -contains $label }).Count
        $purgeDeletedGpoTextBlock.Text = (Get-PSGPOText $(if ($backups.Count -gt 1) { "Delete the GPO '{0}' for good? Its {1} backups in {2} are deleted: it cannot be restored afterwards." } else { "Delete the GPO '{0}' for good? Its backup in {2} is deleted: it cannot be restored afterwards." }) $backup.DisplayName $backups.Count (Get-HistoryRoot)) +
            $(if ($templates) { ' ' + (Get-PSGPOText 'Templates of new GPOs made from it: {0}, deleted too.' $templates) })
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $purgeDeletedGpoPanel.IsVisible = $true
    }

    function Submit-PurgeDeletedGpo {
        $backup = $purgeDeletedGpo.Backup
        $purgeDeletedGpoPanel.IsVisible = $false
        if (-not $backup) { return }
        try {
            $removed = Remove-PSGPODeletedGpoBackup -Directory $Directory -Path (Get-HistoryRoot) -Id $backup.Id
        } catch {
            Update-BackupList -Force
            Update-DirectoryTree -Select 'DeletedGpos'
            Show-DirectoryResult -Text (Get-PSGPOText "The GPO '{0}' is not deleted for good: {1}" $backup.DisplayName $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-BackupList -Force
        Update-DirectoryTree -Select 'DeletedGpos'
        Show-DirectoryResult -Text (Get-PSGPOText $(if ($removed.Backups -gt 1) { "GPO '{0}' deleted for good: its {1} backups are deleted." } else { "GPO '{0}' deleted for good: its backup is deleted." }) $removed.DisplayName $removed.Backups)
    }

    # Rename... on a GPO (or a link to it) or on a WMI filter, as GPMC: its name only.
    $rename = @{ Target = $null; Select = $null }
    function Open-RenameForm {
        if (-not $renameMenuItem.IsVisible) { return }
        $item = $domainTreeView.SelectedItem.Tag
        $target = if ($item -is [GPOToolsWmiFilter]) { $item } else { Get-SelectedGpo }
        if (-not $target) { return }
        $rename.Target = $target
        $rename.Select = $item
        $renameTitleTextBlock.Text = if ($target -is [GPOToolsWmiFilter]) { Get-PSGPOText "Rename the WMI filter '{0}'" $target.Name } else { Get-PSGPOText "Rename the GPO '{0}'" $target.DisplayName }
        $renameTextBox.Text = "$target"
        $renameErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $renamePanel.IsVisible = $true
        $renameTextBox.Focus()
        $renameTextBox.SelectAll()
    }

    function Submit-Rename {
        $target = $rename.Target
        if (-not $target) { return }
        $old = "$target"
        $name = "$($renameTextBox.Text)".Trim()
        try {
            if ($target -is [GPOToolsWmiFilter]) { $Directory.EditWmiFilter($target, $name, $target.Description, $target.Queries) }
            else { $Directory.RenameGpo($target, $name) }
        } catch {
            $renameErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $renamePanel.IsVisible = $false
        if ("$target" -ceq $old) { return }
        Update-DirectoryTree -Select $rename.Select
        Show-DirectoryResult -Text (Get-PSGPOText $(if ($target -is [GPOToolsWmiFilter]) { "WMI filter '{0}' renamed '{1}'." } else { "GPO '{0}' renamed '{1}': its links, its settings and its history are kept." }) $old "$target")
    }

    function Submit-DeleteLink {
        $som = $deleteLink.Som
        $link = $deleteLink.Link
        if (-not $som -or -not $link) { return }
        try {
            $Directory.RemoveLink($som, $link)
        } catch {
            $deleteLinkPanel.IsVisible = $false
            Show-DirectoryResult -Text (Get-PSGPOText "The link of the GPO '{0}' to {1} is not deleted: {2}" $link.GetDisplayName() $som.Name $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $deleteLinkPanel.IsVisible = $false
        Update-DirectoryTree -Select $som
        Show-DirectoryResult -Text (Get-PSGPOText "Link of the GPO '{0}' to {1} deleted." $link.GetDisplayName() $som.Name)
    }

    # Link of an existing GPO to the selected domain or OU, as GPMC "Link an Existing GPO...": the
    # GPOs of the domain not linked there yet, by name.
    $linkGpo = @{ Som = $null }
    function Open-LinkGpoForm {
        param([GPOToolsSom]$Som)
        $linkGpo.Som = $Som
        $linkGpoTitleTextBlock.Text = Get-PSGPOText 'Link an existing GPO of {0} to {1}' $Directory.DomainName $Som.Name
        $linkGpoErrorTextBlock.Text = ''
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $linkGpoFilterTextBox.Text = ''
        Update-LinkGpoList
        $linkGpoPanel.IsVisible = $true
        [void]$linkGpoFilterTextBox.Focus()
    }

    function Update-LinkGpoList {
        $som = $linkGpo.Som
        if (-not $som) { return }
        $filter = "$($linkGpoFilterTextBox.Text)".Trim()
        $linked = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($link in $som.Links) { if ($link.Gpo) { [void]$linked.Add($link.Gpo) } }
        $gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        foreach ($gpo in @($Directory.Gpos | Sort-Object DisplayName)) {
            if ($linked.Contains($gpo)) { continue }
            if ($filter -and $gpo.DisplayName.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $gpos.Add($gpo)
        }
        $linkGpoList.ItemsSource = $gpos
        $linkGpoList.SelectedIndex = if ($gpos.Count -eq 1) { 0 } else { -1 }
        $linkGpoConfirmButton.IsEnabled = $null -ne $linkGpoList.SelectedItem
        $linkGpoErrorTextBlock.Text = if ($gpos.Count) { '' }
            elseif ($filter) { Get-PSGPOText "No GPO named like '{0}' can be linked to {1}." $filter $som.Name }
            else { Get-PSGPOText 'Every GPO of {0} is already linked to {1}.' $Directory.DomainName $som.Name }
    }

    function Submit-LinkGpo {
        $som = $linkGpo.Som
        $gpo = $linkGpoList.SelectedItem
        if (-not $som -or $gpo -isnot [GPOToolsGpo]) { return }
        try {
            $link = $Directory.NewLink($som, $gpo)
        } catch {
            $linkGpoErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $linkGpoPanel.IsVisible = $false
        Update-DirectoryTree -Select $link
        Show-DirectoryResult -Text (Get-PSGPOText "GPO '{0}' linked to {1}, link order {2}." $gpo.DisplayName $som.Name $link.Order)
    }

    # Settings tab of the selected GPO: its Registry.pol files read once per version of the GPO.
    $settingsCache = @{}
    function Update-SettingsTab {
        $gpo = Get-SelectedGpo
        $settingsTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $settingsTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $settingsTab) { return }

        $cached = $settingsCache["$($gpo.Id)"]
        if (-not $cached -or $cached.Version -ne $gpo.Version) {
            $cached = @{ Version = $gpo.Version; Machine = @(); User = @(); Error = $null }
            try {
                foreach ($scope in 'Machine', 'User') {
                    $pol = [GPOToolsRegistryPol]::Parse($Directory.ReadPolicyFile($gpo, $scope))
                    $cached[$scope] = @(Get-PSGPOConfiguredSetting -Pol $pol -Scope $scope)
                }
                # Security settings first, as GPMC lists Windows Settings before Administrative Templates.
                $template = [GPOToolsSecurityTemplate]::Parse($Directory.ReadSecurityTemplate($gpo))
                $audit = [GPOToolsAuditPolicyFile]::Parse($Directory.ReadAuditPolicyFile($gpo))
                $cached['Machine'] = @(Get-PSGPOConfiguredSecuritySetting -Template $template) + @(Get-PSGPOConfiguredAuditSetting -AuditFile $audit) + $cached['Machine']
                # Preferences last, as GPMC lists them after the policies: their files, read in one
                # copy of the folder, only when the GPO declares a preference type.
                $declared = "$($gpo.MachineExtensionNames)$($gpo.UserExtensionNames)"
                if (@(Get-PSGPOPreferenceCatalog | Where-Object { $declared.IndexOf($_.Cse, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
                    $files = $Directory.ReadGpoFolder($gpo)
                    foreach ($scope in 'Machine', 'User') {
                        # Not through the pipeline: it wraps the rows in PSObjects, which Avalonia cannot bind.
                        $rows = [System.Collections.Generic.List[object]]::new()
                        foreach ($row in @($cached[$scope])) { $rows.Add($row) }
                        foreach ($preference in @(Get-PSGPOConfiguredPreference -Files $files -Scope $scope)) { if ($preference.Row) { $rows.Add($preference.Row) } }
                        $cached[$scope] = $rows.ToArray()
                    }
                }
            } catch {
                $cached.Error = Get-PSGPOText 'The settings of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message
            }
            # In the language of the interface: the rows come from functions the commands share.
            foreach ($scope in 'Machine', 'User') { $cached[$scope] = @(foreach ($row in $cached[$scope]) { ConvertTo-DisplaySettingRow $row }) }
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
    }
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

    # --- History tab: the backups of the GPO as a timeline, and what changed at each one ---------

    # Reports of the backups read once (by folder), and of the current state of each GPO (by its
    # version and last change); the GPO compared to its approved version (Get-PSGPODriftState).
    $history = @{ Reports = @{}; Current = @{}; Drift = $null }
    # The central backups of the domain: their folder, not another one.
    $historyPathTextBox.IsReadOnly = [bool]"$((Get-PSGPOConfigurationData).Backup.Path)".Trim()

    # The folder of the backups; empty when the central backups are not reached (the share not
    # mounted on Linux): $backupLists.RootProblem says why.
    function Get-HistoryRoot {
        $path = "$($historyPathTextBox.Text)".Trim()
        if (-not $path) {
            try {
                $path = Get-PSGPODefaultBackupPath
                $backupLists.RootProblem = $null
            } catch {
                $backupLists.RootProblem = $_.Exception.Message
                return ''
            }
            $historyPathTextBox.Text = $path
        }
        $path
    }

    function Set-HistoryStatus {
        param([string]$Text, [switch]$Problem)
        $historyStatusTextBlock.Text = $Text
        if ($Problem) { $historyStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $historyStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    function Format-HistoryDate {
        param($Date)
        if ($null -eq $Date) { return Get-PSGPOText 'unknown date' }
        ([datetime]$Date).ToLocalTime().ToString('g')
    }

    function Get-ChangeSummary {
        param([object[]]$Changes)
        $count = { param($Kind) @($Changes | Where-Object Change -EQ $Kind).Count }
        if (-not $Changes.Count) { return Get-PSGPOText 'no setting changed' }
        '+{0}  ~{1}  -{2}' -f (& $count 'Added'), (& $count 'Changed'), (& $count 'Removed')
    }

    # The timeline of the selected GPO; the backup in $SelectPath selected, else the newest node.
    function Update-HistoryTab {
        param([string]$SelectPath)
        $gpo = Get-SelectedGpo
        # Central backups, for Tier 0 only.
        $historyTab.IsVisible = [bool]$gpo -and (Test-PSGPOBackupAllowed -Directory $Directory)
        if (-not $historyTab.IsVisible) {
            if ($directoryTabs.SelectedItem -eq $historyTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $historyTab) { return }

        $root = Get-HistoryRoot
        if (-not $root) {
            $historyTimelineList.ItemsSource = @()
            Set-HistoryStatus $backupLists.RootProblem -Problem
            return
        }
        $nodes = [System.Collections.Generic.List[AvaloniaHistoryNode]]::new()
        $problem = $null
        $history.Drift = $null
        $approvedLabel = Get-PSGPOApprovedLabel
        try {
            # Oldest first, as the branch of a git graph.
            $backups = @(Get-PSGPOBackupEntry -Path $root -Id $gpo.Id)
            [array]::Reverse($backups)
            $previous = @()
            $previousDate = $null
            foreach ($backup in $backups) {
                if (-not $history.Reports.ContainsKey($backup.Path)) { $history.Reports[$backup.Path] = @(Get-PSGPOBackupSetting -Backup $backup) }
                $report = $history.Reports[$backup.Path]
                $node = [AvaloniaHistoryNode]::new()
                $node.Backup = $backup
                $node.Title = Format-HistoryDate $(if ($backup.Modified) { $backup.Modified } else { $backup.BackedUp })
                $node.Subtitle = Get-PSGPOText 'computer {0}, user {1}' $backup.ComputerVersion $backup.UserVersion
                $node.Changes = @(Compare-PSGPOSettingReport -Reference $previous -Difference $report)
                $node.Summary = if ($nodes.Count) { Get-ChangeSummary $node.Changes } else { Get-PSGPOText 'first backup' }
                $node.Previous = $previousDate
                # The approved version in green, its labels under it, its comment as its tool tip.
                $node.IsApproved = $backup.Labels -contains $approvedLabel
                $node.NodeFill = if ($node.IsApproved) { '#107C10' } else { '#0078D4' }
                $node.NodeStroke = $node.NodeFill
                $node.LineBrush = '#8A8886'
                $node.LabelsText = @($backup.Labels) -join ', '
                $node.HasLabels = [bool]@($backup.Labels).Count
                $node.LabelBrush = if ($node.IsApproved) { '#3BA55C' } else { '#3A96DD' }
                if ($backup.Comment) { $node.Comment = $backup.Comment }
                $nodes.Add($node)
                $previous = $report
                $previousDate = $node.Title
            }

            # The GPO as it is now, when it changed since its last backup.
            $Directory.RefreshGpo($gpo)
            $key = "$($gpo.Id)|$($gpo.Version)|$($gpo.Modified)|$($gpo.Flags)"
            if (-not $history.Current.ContainsKey($key)) {
                $files = $Directory.ReadGpoFolder($gpo)
                $history.Current[$key] = @(Get-PSGPOSettingReport -Files $files -Property (Get-PSGPOBackupProperty -Directory $Directory -Gpo $gpo))
            }
            $changes = @(Compare-PSGPOSettingReport -Reference $previous -Difference $history.Current[$key])
            # Its approved version: the newest backup with the label.
            $approvedNode = @($nodes | Where-Object IsApproved) | Select-Object -Last 1
            $history.Drift = if ($approvedNode) {
                Get-PSGPODriftState -Directory $Directory -Gpo $gpo -Backups @($approvedNode.Backup) -Current $history.Current[$key] `
                    -ApprovedSetting $history.Reports[$approvedNode.Backup.Path] -Label $approvedLabel
            }
            if ($changes.Count -or -not $nodes.Count) {
                $node = [AvaloniaHistoryNode]::new()
                $node.IsCurrent = $true
                $node.Title = Get-PSGPOText 'Now'
                $node.Subtitle = Get-PSGPOText 'computer {0}, user {1}' $gpo.GetComputerVersion() $gpo.GetUserVersion()
                $node.Changes = $changes
                $node.Summary = if ($nodes.Count) { Get-PSGPOText '{0}, not backed up' (Get-ChangeSummary $changes) } else { Get-PSGPOText 'not backed up' }
                $node.Previous = $previousDate
                $node.NodeFill = 'Transparent'
                $node.NodeStroke = '#CA5010'
                $node.LineBrush = '#8A8886'
                $nodes.Add($node)
            }
        } catch {
            $problem = Get-PSGPOText 'The history cannot be read: {0}' $_.Exception.GetBaseException().Message
        }

        $historyTimelineList.ItemsSource = $nodes
        $backed = @($nodes | Where-Object { -not $_.IsCurrent }).Count
        if ($problem) { Set-HistoryStatus $problem -Problem }
        elseif (-not $backed) { Set-HistoryStatus (Get-PSGPOText 'No backup of this GPO in {0} yet: Back up now keeps its settings as they are.' $root) }
        else {
            $count = Get-PSGPOText $(if ($backed -gt 1) { '{0} backups in {1}.' } else { '{0} backup in {1}.' }) $backed $root
            Set-HistoryStatus ($count + ' ' + (Get-PSGPOText $(if ($nodes[-1].IsCurrent) { 'The GPO changed since the last one (Now).' } else { 'The last one is up to date.' })))
        }
        Update-HistoryDrift -Backed $backed -Label $approvedLabel
        # The node asked for, else the newest one; the branch scrolled to it.
        $index = $nodes.Count - 1
        if ($SelectPath) {
            for ($i = 0; $i -lt $nodes.Count; $i++) { if ($nodes[$i].Backup -and $nodes[$i].Backup.Path -eq $SelectPath) { $index = $i } }
        }
        if ($nodes.Count) {
            # Selecting the node it is already on would not show it again.
            if ($historyTimelineList.SelectedIndex -eq $index) { Show-HistoryChange $nodes[$index] } else { $historyTimelineList.SelectedIndex = $index }
        } else { Show-HistoryChange $null }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] { $historyTimelineScrollViewer.ScrollToEnd() }, [Avalonia.Threading.DispatcherPriority]::Background)
    }

    # The GPO compared to its approved version, over the timeline: in orange when it changed since.
    function Update-HistoryDrift {
        param([int]$Backed, [string]$Label)
        $drift = $history.Drift
        $historyDriftButton.IsVisible = $drift -and $drift.State -eq 'Drifted'
        $historyDriftBorder.IsVisible = $Backed -gt 0
        if (-not $Backed) { return }
        $brush = '#8A8886'
        $historyDriftTextBlock.Text = if (-not $drift) {
            Get-PSGPOText "No approved version yet: check '{0}' in the notes of a backup to see what changes after it." $Label
        } else {
            $approved = if ($drift.ApprovedBy) { Get-PSGPOText '{0}, by {1}' (Format-HistoryDate $drift.Approved) $drift.ApprovedBy } else { Format-HistoryDate $drift.Approved }
            if ($drift.State -eq 'Drifted') {
                $brush = '#CA5010'
                Get-PSGPOText 'Changed since its approved version of {0} ({1}).' $approved (Get-ChangeSummary $drift.Changes)
            } else {
                $brush = '#107C10'
                Get-PSGPOText 'The GPO is its approved version of {0}.' $approved
            }
        }
        $historyDriftBorder.BorderBrush = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse($brush))
    }

    # What changed at the selected node, from the node before it; or what $Title says, for the
    # changes since the approved version.
    function Show-HistoryChange {
        param([AvaloniaHistoryNode]$Node, [string]$Title)
        # A backup can be restored, by an account that may edit the GPO.
        $gpo = Get-SelectedGpo
        $historyRestorePanel.IsVisible = $false
        $historyRestoreButton.IsVisible = $Node -and -not $Node.IsCurrent -and -not $Title -and $gpo -and $gpo.CanEdit -and -not $Directory.IsReadOnly
        Show-HistoryNote $(if (-not $Title) { $Node })
        if (-not $Node) {
            $historyCompareTextBlock.Text = ''
            $historyChangesList.ItemsSource = $null
            return
        }
        $historyCompareTextBlock.Text = if ($Title) { $Title }
            elseif ($Node.IsCurrent -and $Node.Previous) { Get-PSGPOText 'Changes since the backup of {0}, not backed up yet' $Node.Previous }
            elseif ($Node.IsCurrent) { Get-PSGPOText 'The settings of the GPO now, never backed up' }
            elseif ($Node.Previous) { Get-PSGPOText 'Changes from {0} to {1}' $Node.Previous $Node.Title }
            else { Get-PSGPOText 'First backup, {0}: the settings of the GPO then' $Node.Title }
        if (-not $Node.Changes.Count) { $historyCompareTextBlock.Text += Get-PSGPOText ': no setting changed (the version or the files did)' }
        $scopes = @{ GPO = 'GPO'; Computer = Get-PSGPOText 'Computer Configuration'; User = Get-PSGPOText 'User Configuration'; Files = Get-PSGPOText 'Files' }
        $brushes = @{ Added = '#107C10'; Removed = '#D13438'; Changed = '#CA5010' }
        $historyChangesList.ItemsSource = @(foreach ($change in $Node.Changes) {
                $row = [AvaloniaChangeRow]::new()
                $row.Change = Get-PSGPOText $change.Change
                $row.ChangeBrush = $brushes[$change.Change]
                # The report of the changes is in English (Compare-PSGPOBackup shares it).
                $row.Location = "$($scopes[$change.Scope]) > $(ConvertTo-PSGPODisplayText $change.Path)"
                $row.Name = ConvertTo-PSGPODisplayText $change.Name
                $row.Before = ConvertTo-PSGPODisplayText $change.Before
                $row.After = ConvertTo-PSGPODisplayText $change.After
                $row.HasBefore = [bool]$change.Before
                $row.HasAfter = [bool]$change.After
                $row
            })
    }

    # The notes of the backup of a node, to change them; hidden for the GPO now.
    $historyNote = @{ Backup = $null }
    function Show-HistoryNote {
        param([AvaloniaHistoryNode]$Node)
        $backup = if ($Node -and -not $Node.IsCurrent) { $Node.Backup }
        $historyNote.Backup = $backup
        $historyNotesPanel.IsVisible = [bool]$backup
        if (-not $backup) { return }
        $label = Get-PSGPOApprovedLabel
        $info = if ($backup.BackedUpBy) { Get-PSGPOText 'Backed up by {0} on {1}.' $backup.BackedUpBy (Format-HistoryDate $backup.BackedUp) } else { Get-PSGPOText 'Backed up on {0}.' (Format-HistoryDate $backup.BackedUp) }
        if ($backup.NotesUpdated) {
            $info += ' ' + $(if ($backup.NotesUpdatedBy) { Get-PSGPOText 'Notes changed by {0} on {1}.' $backup.NotesUpdatedBy (Format-HistoryDate $backup.NotesUpdated) } else { Get-PSGPOText 'Notes changed on {0}.' (Format-HistoryDate $backup.NotesUpdated) })
        }
        $historyNotesInfoTextBlock.Text = $info
        $historyNotesCommentTextBox.Text = $backup.Comment
        $template = Get-PSGPOTemplateLabel
        $historyNotesLabelsTextBox.Text = @($backup.Labels | Where-Object { $_ -ne $label -and $_ -ne $template }) -join ', '
        $historyNotesApprovedCheckBox.Content = Get-PSGPOText '{0} version' $label
        $historyNotesApprovedCheckBox.IsChecked = $backup.Labels -contains $label
        $historyNotesTemplateCheckBox.Content = $template
        $historyNotesTemplateCheckBox.IsChecked = $backup.Labels -contains $template
    }

    function Save-HistoryNote {
        $backup = $historyNote.Backup
        if (-not $backup) { return }
        $label = Get-PSGPOApprovedLabel
        $template = Get-PSGPOTemplateLabel
        $labels = @("$($historyNotesLabelsTextBox.Text)" -split ',' | Where-Object { $_.Trim() -and $_.Trim() -ne $label -and $_.Trim() -ne $template })
        if ($historyNotesApprovedCheckBox.IsChecked) { $labels += $label }
        if ($historyNotesTemplateCheckBox.IsChecked) { $labels += $template }
        try {
            $saved = Save-PSGPOBackupNote -Backup $backup -Comment $historyNotesCommentTextBox.Text -Label $labels -Account $Directory.Account
        } catch {
            Set-HistoryStatus (Get-PSGPOText 'The notes are not saved: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        Update-HistoryTab -SelectPath $saved.Path
        Set-HistoryStatus (Get-PSGPOText 'Notes of the backup of {0} saved.' (Format-HistoryDate $(if ($saved.Modified) { $saved.Modified } else { $saved.BackedUp })))
    }

    # Backs up GPOs in the folder of the history, with the comment typed; what was done in the status.
    function Invoke-HistoryBackup {
        param([GPOToolsGpo[]]$Gpos)
        $root = Get-HistoryRoot
        $comment = "$($historyCommentTextBox.Text)".Trim()
        $counts = @{ Created = 0; Unchanged = 0 }
        $errors = [System.Collections.Generic.List[string]]::new()
        try { $null = New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop }
        catch { Set-HistoryStatus (Get-PSGPOText 'The folder of the backups cannot be created: {0}' $_.Exception.GetBaseException().Message) -Problem; return }
        # The folder of the account, kept for the next time; not the central backups of the domain.
        if (-not "$((Get-PSGPOConfigurationData).Backup.Path)".Trim()) { Set-PSGPOUserSetting -Values @{ BackupPath = $root } }
        foreach ($gpo in $Gpos) {
            try {
                $result = Save-PSGPOBackup -Directory $Directory -Gpo $gpo -Path $root -Comment $comment
                $counts[$result.Result]++
            } catch {
                $errors.Add("$($gpo.DisplayName): $($_.Exception.GetBaseException().Message)")
            }
        }
        $history.Current = @{}
        Update-HistoryTab
        # The comment went with the new backups.
        if ($counts.Created) { $historyCommentTextBox.Text = '' }
        $text = if ($Gpos.Count -eq 1 -and -not $errors.Count) {
            if ($counts.Created) { Get-PSGPOText 'Backed up in {0}.' $root }
            elseif ($comment) { Get-PSGPOText 'Not backed up again: the GPO did not change since its last backup. Its comment is in the notes of that backup.' }
            else { Get-PSGPOText 'Not backed up again: the GPO did not change since its last backup.' }
        } else {
            Get-PSGPOText '{0} GPO(s) backed up, {1} unchanged since their last backup, in {2}.' $counts.Created $counts.Unchanged $root
        }
        if ($errors.Count) { Set-HistoryStatus ($text + ' ' + (Get-PSGPOText 'Not backed up: {0}' ($errors -join '; '))) -Problem } else { Set-HistoryStatus $text }
    }

    # Restore of the selected backup, once confirmed; the GPO as it is now is backed up first.
    $historyRestoreButton.Add_Click({
        $node = $historyTimelineList.SelectedItem
        $gpo = Get-SelectedGpo
        if (-not $node -or $node.IsCurrent -or -not $gpo) { return }
        $historyRestoreTextBlock.Text = Get-PSGPOText "Restore the GPO '{0}' as it was on {1}? Its files, status and client-side extensions are replaced, and its version increases so that the computers apply it again. Its links and security filtering do not change. The GPO as it is now is backed up first." $gpo.DisplayName $node.Title
        $historyRestorePanel.IsVisible = $true
    })
    $historyRestoreCancelButton.Add_Click({ $historyRestorePanel.IsVisible = $false })
    $historyRestoreConfirmButton.Add_Click({
        $node = $historyTimelineList.SelectedItem
        $gpo = Get-SelectedGpo
        $historyRestorePanel.IsVisible = $false
        if (-not $node -or $node.IsCurrent -or -not $gpo) { return }
        try {
            $result = Restore-PSGPO -Backup $node.Backup -Directory $Directory -Confirm:$false
        } catch {
            Set-HistoryStatus (Get-PSGPOText 'The GPO is not restored: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        # Its settings, details and history as they are now.
        $settingsCache.Remove("$($gpo.Id)")
        $history.Current = @{}
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $directoryTabs.SelectedItem = $historyTab
        Update-HistoryTab
        Set-HistoryStatus (Get-PSGPOText 'GPO restored as it was on {0} (version {1}); its state before was backed up.' $node.Title $result.Version)
    })
    $historyTimelineList.add_SelectionChanged({ Show-HistoryChange $historyTimelineList.SelectedItem })
    $historyNotesSaveButton.Add_Click({ Save-HistoryNote })
    # The changes from the approved version to the GPO now, under the timeline.
    $historyDriftButton.Add_Click({
        $drift = $history.Drift
        if (-not $drift) { return }
        $node = [AvaloniaHistoryNode]::new()
        $node.IsCurrent = $true
        $node.Changes = $drift.Changes
        Show-HistoryChange $node -Title (Get-PSGPOText 'Changes since the approved version of {0}' (Format-HistoryDate $drift.Approved))
    })
    $historyBackupButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Invoke-HistoryBackup -Gpos @($gpo) } })
    $historyBackupAllButton.Add_Click({ Invoke-HistoryBackup -Gpos @($Directory.GetVisibleGpos()) })
    # Another folder: its backups, remembered for the next time.
    $historyPathTextBox.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) {
            if (-not $historyPathTextBox.IsReadOnly) { Set-PSGPOUserSetting -Values @{ BackupPath = (Get-HistoryRoot) } }
            Update-HistoryTab
            # Its deleted GPOs in the tree.
            Update-BackupList -Force
            $tag = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
            if ($tag -is [GPOToolsGpo] -or $tag -is [GPOToolsSom]) { Update-DirectoryTree -Select $tag } else { Update-DirectoryTree -Select $Directory.Domain }
        }
    })

    # --- Delegation tab: the permissions of the GPO, as the Scope and Delegation tabs of GPMC --------

    $delegation = @{ Gpo = $null; Editable = $false }
    function Update-DelegationTab {
        param([string]$Status, [switch]$Problem)
        $gpo = Get-SelectedGpo
        $delegationTab.IsVisible = [bool]$gpo
        if (-not $gpo) {
            if ($directoryTabs.SelectedItem -eq $delegationTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $delegationTab) { return }
        $delegation.Gpo = $gpo
        $delegation.Editable = $gpo.CanEdit -and -not $Directory.IsReadOnly -and $gpo.ApprovalState -ne 'Pending'
        $rows = @()
        $lines = [System.Collections.Generic.List[string]]::new()
        try {
            $rows = @($Directory.GetGpoPermissions($gpo))
        } catch {
            $lines.Add((Get-PSGPOText 'The permissions of the GPO cannot be read: {0}' $_.Exception.GetBaseException().Message))
            $Problem = $true
        }
        $permissionRows = @(foreach ($row in $rows) {
                $item = [AvaloniaPermissionRow]::new()
                $item.Name = $row.Name
                $item.Sid = $row.Sid
                $item.Permission = $row.Permission
                $item.PermissionText = Get-PSGPOText (Get-PSGPOPermissionText -Permission $row.Permission)
                $item.Applies = $row.Applies -and -not $row.Denied
                $item.Inherited = $row.Inherited
                $item.InheritedText = Get-PSGPOText $(if ($row.Inherited) { 'Yes' } else { 'No' })
                $item
            })
        $delegationList.ItemsSource = $permissionRows
        # The security filtering: who applies the GPO (an inherited right counts too). Not through
        # the pipeline: it wraps the rows in PSObjects, which Avalonia cannot show.
        $filtering = [System.Collections.Generic.List[AvaloniaPermissionRow]]::new()
        foreach ($item in $permissionRows) {
            $applies = @($rows | Where-Object { $_.Sid -eq $item.Sid -and $_.Applies -and -not $_.Denied }).Count
            if ($applies -and -not @($filtering | Where-Object Sid -EQ $item.Sid).Count) { $filtering.Add($item) }
        }
        $filteringList.ItemsSource = $filtering
        foreach ($control in $filteringNameTextBox, $filteringAddButton, $delegationNameTextBox, $delegationPermissionComboBox, $delegationSetButton) { $control.IsEnabled = $delegation.Editable }
        Update-DelegationButton
        if ($gpo.ApprovalState -eq 'Pending') { $lines.Add((Get-PSGPOText 'The GPO waits for its approval: its permissions are set when it is approved.')) }
        elseif (-not $delegation.Editable) { $lines.Add((Get-PSGPOText 'Read only: the account cannot change the permissions of this GPO.')) }
        if ($rows.Count -and -not (Test-PSGPOComputerReadable -Permission $rows)) {
            $lines.Add((Get-PSGPOText 'Warning: neither Authenticated Users nor Domain Computers read this GPO, so no computer applies it (MS16-072). Give one of them Read in the delegation.'))
            $Problem = $true
        }
        if ($Status) { $lines.Insert(0, $Status) }
        $delegationStatusTextBlock.Text = $lines -join [Environment]::NewLine
        if ($Problem) { $delegationStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $delegationStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # Remove is for an account of the GPO itself: the inherited permissions come from CN=Policies.
    function Update-DelegationButton {
        $filteringRemoveButton.IsEnabled = $delegation.Editable -and $null -ne $filteringList.SelectedItem
        $delegationRemoveButton.IsEnabled = $delegation.Editable -and $delegationList.SelectedItem -and -not $delegationList.SelectedItem.Inherited
    }

    # One change of the permissions of the GPO: an account by its name (or its row), then the tab and
    # the details shown again, with what was done or why not.
    function Invoke-PermissionChange {
        param([string]$Account, [AvaloniaPermissionRow]$Row, [ValidateSet('Permission', 'Filtering')] [string]$Operation, [string]$Value)
        $gpo = $delegation.Gpo
        if (-not $gpo) { return }
        try {
            $principal = if ($Row) { [pscustomobject]@{ Name = $Row.Name; Sid = $Row.Sid } }
                elseif ("$Account".Trim()) { Resolve-PSGPOApplyTo -Directory $Directory -Name $Account }
                else { throw (Get-PSGPOText 'Give a group, a user or a computer.') }
            if ($Operation -eq 'Filtering') { $Directory.SetGpoSecurityFiltering($gpo, $principal.Sid, $Value -eq 'True') }
            else { $Directory.SetGpoPermission($gpo, $principal.Sid, $Value) }
        } catch {
            Update-DelegationTab -Status (Get-PSGPOText 'Not changed: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $done = if ($Operation -eq 'Filtering') { Get-PSGPOText $(if ($Value -eq 'True') { "'{0}' applies the GPO now." } else { "'{0}' no longer applies the GPO." }) $principal.Name }
            elseif ($Value -eq 'None') { Get-PSGPOText "The permissions of '{0}' are removed." $principal.Name }
            else { Get-PSGPOText "'{0}' has the permission {1} now." $principal.Name (Get-PSGPOText (Get-PSGPOPermissionText -Permission $Value)) }
        # The details (security filtering) and the history (the GPO now) show the change.
        $history.Current = @{}
        $filteringNameTextBox.Text = ''
        $delegationNameTextBox.Text = ''
        Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag
        $directoryTabs.SelectedItem = $delegationTab
        Update-DelegationTab -Status $done
    }

    $filteringList.add_SelectionChanged({ Update-DelegationButton })
    $delegationList.add_SelectionChanged({
        $row = $delegationList.SelectedItem
        if ($row) {
            # The account and its level, to change them.
            $delegationNameTextBox.Text = $row.Name
            $index = @('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity').IndexOf($row.Permission)
            if ($index -ge 0) { $delegationPermissionComboBox.SelectedIndex = $index }
        }
        Update-DelegationButton
    })
    $filteringAddButton.Add_Click({ Invoke-PermissionChange -Account $filteringNameTextBox.Text -Operation Filtering -Value 'True' })
    $filteringRemoveButton.Add_Click({ if ($filteringList.SelectedItem) { Invoke-PermissionChange -Row $filteringList.SelectedItem -Operation Filtering -Value 'False' } })
    $delegationSetButton.Add_Click({
        $level = "$($delegationPermissionComboBox.SelectedItem.Tag)"
        $row = $delegationList.SelectedItem
        # The selected account when its name is the one typed (its SID, a name may not resolve).
        if ($row -and $row.Name -eq "$($delegationNameTextBox.Text)".Trim() -and -not $row.Inherited) { Invoke-PermissionChange -Row $row -Operation Permission -Value $level }
        else { Invoke-PermissionChange -Account $delegationNameTextBox.Text -Operation Permission -Value $level }
    })
    $delegationRemoveButton.Add_Click({ if ($delegationList.SelectedItem) { Invoke-PermissionChange -Row $delegationList.SelectedItem -Operation Permission -Value 'None' } })

    # --- Delegation of the WMI filters, as GPMC: on WMI Filters who creates filters, on a filter
    # who changes it ----------------------------------------------------------------------------

    $wmiDelegation = @{ Target = $null; Filter = $null; Editable = $false }
    function Update-WmiDelegationTab {
        param([string]$Status, [switch]$Problem)
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        $onContainer = $item -is [string] -and $item -eq 'WmiFilters'
        $wmiDelegationTab.IsVisible = $onContainer -or $item -is [GPOToolsWmiFilter]
        if (-not $wmiDelegationTab.IsVisible) {
            if ($directoryTabs.SelectedItem -eq $wmiDelegationTab) { $directoryTabs.SelectedIndex = 0 }
            return
        }
        if ($directoryTabs.SelectedItem -ne $wmiDelegationTab) { return }
        $filter = if ($onContainer) { $null } else { $item }
        $wmiDelegation.Filter = $filter
        $wmiDelegation.Editable = -not $Directory.IsReadOnly -and $(if ($filter) { $filter.CanEdit } else { $Directory.IsDomainAdministrator })
        $wmiDelegationTitleTextBlock.Text = if ($filter) { Get-PSGPOText "Delegation of the WMI filter '{0}'" $filter.Name } else { Get-PSGPOText 'Delegation of the WMI filters of {0}' $Directory.DomainName }
        $wmiDelegationInfoTextBlock.Text = if ($filter) { Get-PSGPOText 'These groups and users have the specified permission for this WMI filter: Edit changes its name, description and queries; Full control also deletes it and changes its permissions.' }
            else { Get-PSGPOText 'These groups and users create WMI filters: Creator owner creates filters and changes those it created; Full control creates filters and changes all of them.' }
        # The levels of the target, the one chosen kept when it is one of them.
        $levels = if ($filter) { 'WmiEdit', 'WmiFullControl' } else { 'WmiCreate', 'WmiFullControl' }
        $chosen = if ($wmiDelegationPermissionComboBox.SelectedItem) { "$($wmiDelegationPermissionComboBox.SelectedItem.Tag)" }
        $choices = foreach ($level in $levels) {
            $choice = [Avalonia.Controls.ComboBoxItem]::new()
            $choice.Content = Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $level)
            $choice.Tag = $level
            $choice
        }
        $wmiDelegationPermissionComboBox.ItemsSource = @($choices)
        $wmiDelegationPermissionComboBox.SelectedIndex = [Math]::Max(0, [array]::IndexOf($levels, $chosen))
        $rows = @()
        $lines = [System.Collections.Generic.List[string]]::new()
        try {
            $rows = @($Directory.GetWmiFilterPermissions($filter))
        } catch {
            $lines.Add((Get-PSGPOText 'The permissions cannot be read: {0}' $_.Exception.GetBaseException().Message))
            $Problem = $true
        }
        $wmiDelegationList.ItemsSource = @(foreach ($row in $rows) {
                $entry = [AvaloniaPermissionRow]::new()
                $entry.Name = $row.Name
                $entry.Sid = $row.Sid
                $entry.Permission = $row.Permission
                $entry.PermissionText = Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $row.Permission)
                $entry.Inherited = $row.Inherited
                $entry.InheritedText = Get-PSGPOText $(if ($row.Inherited) { 'Yes' } else { 'No' })
                $entry
            })
        foreach ($control in $wmiDelegationNameTextBox, $wmiDelegationPermissionComboBox, $wmiDelegationSetButton) { $control.IsEnabled = $wmiDelegation.Editable }
        Update-WmiDelegationButton
        if (-not $wmiDelegation.Editable) { $lines.Add((Get-PSGPOText $(if ($filter) { 'Read only: the account cannot change the permissions of this WMI filter.' } else { 'Read only: only the administrators of the domain change who creates WMI filters.' }))) }
        if ($Status) { $lines.Insert(0, $Status) }
        $wmiDelegationStatusTextBlock.Text = $lines -join [Environment]::NewLine
        if ($Problem) { $wmiDelegationStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $wmiDelegationStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
    }

    # Remove is for an account of the filter or the container itself, not an inherited one.
    function Update-WmiDelegationButton {
        $wmiDelegationRemoveButton.IsEnabled = $wmiDelegation.Editable -and $wmiDelegationList.SelectedItem -and -not $wmiDelegationList.SelectedItem.Inherited
    }

    function Invoke-WmiPermissionChange {
        param([string]$Account, [AvaloniaPermissionRow]$Row, [string]$Value)
        $filter = $wmiDelegation.Filter
        try {
            $principal = if ($Row) { [pscustomobject]@{ Name = $Row.Name; Sid = $Row.Sid } }
                elseif ("$Account".Trim()) { Resolve-PSGPOApplyTo -Directory $Directory -Name $Account }
                else { throw (Get-PSGPOText 'Give a group or a user.') }
            $Directory.SetWmiFilterPermission($filter, $principal.Sid, $Value)
        } catch {
            Update-WmiDelegationTab -Status (Get-PSGPOText 'Not changed: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $done = if ($Value -eq 'None') { Get-PSGPOText "The permissions of '{0}' are removed." $principal.Name }
            else { Get-PSGPOText "'{0}' has the permission {1} now." $principal.Name (Get-PSGPOText (Get-PSGPOWmiFilterPermissionText -Permission $Value)) }
        $wmiDelegationNameTextBox.Text = ''
        Update-WmiDelegationTab -Status $done
    }

    $wmiDelegationList.add_SelectionChanged({
        $row = $wmiDelegationList.SelectedItem
        if ($row) {
            $wmiDelegationNameTextBox.Text = $row.Name
            $index = [array]::IndexOf(@($wmiDelegationPermissionComboBox.ItemsSource | ForEach-Object { "$($_.Tag)" }), $row.Permission)
            if ($index -ge 0) { $wmiDelegationPermissionComboBox.SelectedIndex = $index }
        }
        Update-WmiDelegationButton
    })
    $wmiDelegationSetButton.Add_Click({
        $level = "$($wmiDelegationPermissionComboBox.SelectedItem.Tag)"
        $row = $wmiDelegationList.SelectedItem
        # The selected account when its name is the one typed (its SID, a name may not resolve).
        if ($row -and $row.Name -eq "$($wmiDelegationNameTextBox.Text)".Trim() -and -not $row.Inherited) { Invoke-WmiPermissionChange -Row $row -Value $level }
        else { Invoke-WmiPermissionChange -Account $wmiDelegationNameTextBox.Text -Value $level }
    })
    $wmiDelegationRemoveButton.Add_Click({ if ($wmiDelegationList.SelectedItem) { Invoke-WmiPermissionChange -Row $wmiDelegationList.SelectedItem -Value 'None' } })

    $directoryTabs.add_SelectionChanged({
        param($control, $e)
        # Only the selection of a tab, not of a control inside one.
        if ([object]::ReferenceEquals($e.Source, $directoryTabs)) { Update-SettingsTab; Update-DelegationTab; Update-WmiDelegationTab; Update-HistoryTab }
    })

    function Get-SelectedGpo {
        $item = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($item -is [GPOToolsGpoLink]) { $item.Gpo } elseif ($item -is [GPOToolsGpo]) { $item }
    }

    $domainTreeView.add_SelectionChanged({
        $selected = $domainTreeView.SelectedItem
        $item = if ($selected) { $selected.Tag }

        $pathParts = [System.Collections.Generic.List[string]]::new()
        for ($current = $selected; $current; $current = $current.Parent) { $pathParts.Insert(0, $current.Header) }
        $directoryBreadcrumbTextBlock.Text = if ($pathParts.Count) { $pathParts -join ' > ' } else { $directoryHint }

        $detail = Get-PSGPODirectoryDetail -Directory $Directory -Item $item -DeletedGpo $backupLists.Deleted
        $directoryTitleTextBlock.Text = $detail.Title
        $directoryPropertiesList.ItemsSource = $detail.Properties
        $linksHeaderTextBlock.Text = $detail.LinksHeader
        $linksHeaderTextBlock.IsVisible = [bool]$detail.LinksHeader
        $linksList.ItemsSource = $detail.Links
        $editGpoButton.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $directoryResultTextBlock.Text = ''
        Hide-DirectoryForm
        $canRestore = $null -ne $detail.Deleted -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $restoreDeletedGpoButton.IsVisible = $canRestore
        $purgeDeletedGpoButton.IsVisible = $canRestore

        # Context menu of the selected node, as in GPMC.
        # A read-only directory (read over LDAP) cannot create GPOs yet.
        # And what the account may do there (its delegations).
        $createLinkedGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo -and $item.CanLink
        $linkGpoMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $item.CanLink -and $Directory.Gpos.Count -gt 0
        $newGpoMenuItem.IsVisible = $item -eq 'GroupPolicyObjects' -and -not $Directory.IsReadOnly -and $Directory.CanCreateGpo
        $editGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit
        $deleteLinkMenuItem.IsVisible = $item -is [GPOToolsGpoLink] -and -not $Directory.IsReadOnly -and $selected.Parent.Tag.CanLink
        # A link: Enforced, Link Enabled and its order, as GPMC; a SOM: Block Inheritance.
        $onLink = $deleteLinkMenuItem.IsVisible
        $enforcedLinkMenuItem.IsVisible = $onLink
        $enforcedLinkMenuItem.IsChecked = $onLink -and $item.Enforced
        $enabledLinkMenuItem.IsVisible = $onLink
        $enabledLinkMenuItem.IsChecked = $onLink -and $item.Enabled
        $moveLinkUpMenuItem.IsVisible = $onLink -and $item.Order -gt 1
        $moveLinkDownMenuItem.IsVisible = $onLink -and $item.Order -lt $selected.Parent.Tag.Links.Count
        $blockInheritanceMenuItem.IsVisible = $item -is [GPOToolsSom] -and -not $Directory.IsReadOnly -and $item.CanLink
        $blockInheritanceMenuItem.IsChecked = $item -is [GPOToolsSom] -and $item.BlockInheritance
        $gpoStatusMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit -and -not $Directory.IsReadOnly
        foreach ($statusItem in $gpoStatusEnabledMenuItem, $gpoStatusUserDisabledMenuItem, $gpoStatusComputerDisabledMenuItem, $gpoStatusAllDisabledMenuItem) {
            $statusItem.IsChecked = $null -ne $detail.Gpo -and [int]$statusItem.Tag -eq ($detail.Gpo.Flags -band 3)
        }
        # WMI Filters: a new filter, the change or the deletion of one.
        $newWmiFilterMenuItem.IsVisible = $item -eq 'WmiFilters' -and -not $Directory.IsReadOnly -and $Directory.CanCreateWmiFilter
        $editWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter] -and -not $Directory.IsReadOnly -and $item.CanEdit
        $editWmiFilterButton.IsVisible = $editWmiFilterMenuItem.IsVisible
        $deleteWmiFilterMenuItem.IsVisible = $editWmiFilterMenuItem.IsVisible
        # Rename a GPO (its node or a link to it) or a WMI filter, as GPMC.
        $renameMenuItem.IsVisible = $editWmiFilterMenuItem.IsVisible -or $gpoStatusMenuItem.IsVisible
        # WMI Filter: the filters of the domain, as the WMI Filtering of the Scope tab of GPMC.
        $wmiFilterMenuItem.IsVisible = $gpoStatusMenuItem.IsVisible -and ($Directory.WmiFilters.Count -or $null -ne $detail.Gpo.WmiFilterId)
        if ($wmiFilterMenuItem.IsVisible) { Update-WmiFilterMenu -Gpo $detail.Gpo }
        # And in the details of the GPO.
        $gpoWmiFilterPanel.IsVisible = $wmiFilterMenuItem.IsVisible
        if ($gpoWmiFilterPanel.IsVisible) { Update-GpoWmiFilterComboBox -Gpo $detail.Gpo }
        # A filter: exported by anyone who reads it, used in the GPOs the account edits; WMI
        # Filters: a filter imported where the account creates them.
        $exportWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter]
        $useWmiFilterMenuItem.IsVisible = $item -is [GPOToolsWmiFilter] -and -not $Directory.IsReadOnly -and @($Directory.Gpos | Where-Object CanEdit).Count -gt 0
        $importWmiFilterMenuItem.IsVisible = $newWmiFilterMenuItem.IsVisible
        # Delete a GPO from Group Policy Objects, as GPMC; never a default GPO of the domain.
        $importGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.CanEdit -and -not $Directory.IsReadOnly
        $deleteGpoMenuItem.IsVisible = $item -is [GPOToolsGpo] -and -not $Directory.IsReadOnly -and $item.CanEdit -and [GPOToolsDirectory]::DefaultGpoIds -notcontains $item.Id
        $restoreDeletedGpoMenuItem.IsVisible = $canRestore
        $purgeDeletedGpoMenuItem.IsVisible = $canRestore
        $approveGpoMenuItem.IsVisible = $null -ne $detail.Gpo -and $detail.Gpo.ApprovalState -eq 'Pending' -and -not $Directory.IsReadOnly -and
            $Directory.Workflow -and $Directory.Workflow.IsApprover
        Update-SettingsTab
        Update-DelegationTab
        Update-WmiDelegationTab
        Update-HistoryTab
    })
    # Nothing to offer on this node: do not open an empty menu.
    (Get-PSGPOAvaloniaControl $window 'domainContextMenu').add_Opening({
        param($control, $e)
        if (-not ($createLinkedGpoMenuItem.IsVisible -or $linkGpoMenuItem.IsVisible -or $newGpoMenuItem.IsVisible -or $editGpoMenuItem.IsVisible -or $renameMenuItem.IsVisible -or $purgeDeletedGpoMenuItem.IsVisible -or $deleteLinkMenuItem.IsVisible -or
                $exportWmiFilterMenuItem.IsVisible -or $importWmiFilterMenuItem.IsVisible -or $useWmiFilterMenuItem.IsVisible -or
                $blockInheritanceMenuItem.IsVisible -or $gpoStatusMenuItem.IsVisible -or $wmiFilterMenuItem.IsVisible -or $newWmiFilterMenuItem.IsVisible -or $editWmiFilterMenuItem.IsVisible -or $deleteWmiFilterMenuItem.IsVisible -or
                $deleteGpoMenuItem.IsVisible -or $restoreDeletedGpoMenuItem.IsVisible -or $approveGpoMenuItem.IsVisible -or $importGpoMenuItem.IsVisible) -or
            -not $domainTreeView.SelectedItem) { $e.Cancel = $true }
    })

    $createLinkedGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-NewGpoForm -Som $item } })
    $newGpoMenuItem.Add_Click({ Open-NewGpoForm -Som $null })
    $linkGpoMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsSom]) { Open-LinkGpoForm -Som $item } })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $linkGpoFilterTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text' -and $linkGpoPanel.IsVisible) { Update-LinkGpoList }
    })
    $linkGpoList.add_SelectionChanged({ $linkGpoConfirmButton.IsEnabled = $null -ne $linkGpoList.SelectedItem })
    $linkGpoList.add_DoubleTapped({ Submit-LinkGpo })
    $linkGpoConfirmButton.Add_Click({ Submit-LinkGpo })
    $linkGpoCancelButton.Add_Click({ $linkGpoPanel.IsVisible = $false })
    $editGpoMenuItem.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $editGpoButton.Add_Click({ $gpo = Get-SelectedGpo; if ($gpo) { Open-GpoEditor -Gpo $gpo } })
    $domainTreeView.add_DoubleTapped({ $gpo = Get-SelectedGpo; if ($gpo -and $gpo.CanEdit) { Open-GpoEditor -Gpo $gpo } })
    $newGpoCreateButton.Add_Click({ Submit-NewGpo })
    $newGpoCancelButton.Add_Click({ $newGpoPanel.IsVisible = $false })
    $deleteLinkMenuItem.Add_Click({ Open-DeleteLinkForm })

    # Links, inheritance and status, written to the domain at once, as GPMC does: the tree shows
    # them as the domain has them, and the result says what changed or why not.
    function Invoke-DirectoryChange {
        param([Parameter(Mandatory)] [scriptblock]$Change, [Parameter(Mandatory)] [string]$Done, $Select)
        try {
            & $Change
        } catch {
            Update-DirectoryTree -Select $Select
            Show-DirectoryResult -Text $_.Exception.GetBaseException().Message -Problem
            return
        }
        Update-DirectoryTree -Select $Select
        Show-DirectoryResult -Text $Done
    }
    # The items of WMI Filter: none, then each filter of the domain, the one of the GPO checked.
    function Update-WmiFilterMenu {
        param([GPOToolsGpo]$Gpo)
        $wmiFilterMenuItem.Items.Clear()
        foreach ($choice in @($null) + @($Directory.WmiFilters)) {
            $item = [Avalonia.Controls.MenuItem]::new()
            $item.Header = if ($choice) { $choice.Name } else { Get-PSGPOText '(none)' }
            $item.ToggleType = [Avalonia.Controls.MenuItemToggleType]::Radio
            $item.GroupName = 'wmiFilter'
            $item.IsChecked = if ($choice) { $Gpo.WmiFilterId -eq $choice.Id } else { $null -eq $Gpo.WmiFilterId }
            $item.Tag = $choice
            if ($choice) { [Avalonia.Controls.ToolTip]::SetTip($item, $choice.GetQueryText()) }
            $item.Add_Click({ param($control) Set-SelectedWmiFilter -Filter $control.Tag })
            [void]$wmiFilterMenuItem.Items.Add($item)
        }
    }
    function Set-SelectedWmiFilter {
        param([GPOToolsWmiFilter]$Filter)
        $gpo = Get-SelectedGpo
        if (-not $gpo) { return }
        if ("$($gpo.WmiFilterId)" -eq "$(if ($Filter) { $Filter.Id })") { return }
        $select = $domainTreeView.SelectedItem.Tag
        Invoke-DirectoryChange -Select $select -Done $(if ($Filter) { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}': the computers apply it only when each of its queries returns something ({2})." $gpo.DisplayName $Filter.Name $Filter.GetQueryText() } else { Get-PSGPOText "'{0}' is linked to no WMI filter." $gpo.DisplayName }) `
            -Change { $Directory.SetWmiFilter($gpo, $Filter) }
    }
    # New WMI Filter... on WMI Filters, as GPMC; Edit WMI filter... on a filter, in the same form.
    $wmiFilterForm = @{ Filter = $null }
    function Open-NewWmiFilterForm {
        param([GPOToolsWmiFilter]$Filter)
        $wmiFilterForm.Filter = $Filter
        $newWmiFilterTitleTextBlock.Text = if ($Filter) { Get-PSGPOText 'Edit WMI filter' } else { Get-PSGPOText 'New WMI filter' }
        $newWmiFilterCreateButton.Content = if ($Filter) { Get-PSGPOText 'Save' } else { Get-PSGPOText 'Create' }
        $newWmiFilterNameTextBox.Text = if ($Filter) { $Filter.Name } else { '' }
        $newWmiFilterDescriptionTextBox.Text = if ($Filter) { "$($Filter.Description)" } else { '' }
        # The namespace of the first query; a query of another namespace is a line namespace: query.
        $namespace = if ($Filter -and @($Filter.Queries).Count) { $Filter.Queries[0].Namespace } else { 'root\CIMv2' }
        $newWmiFilterNamespaceTextBox.Text = $namespace
        $newWmiFilterQueryTextBox.Text = if ($Filter) {
            @($Filter.Queries | ForEach-Object { if ($_.Namespace -eq $namespace) { $_.Query } else { "$($_.Namespace): $($_.Query)" } }) -join [Environment]::NewLine
        } else { '' }
        $newWmiFilterErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $newWmiFilterPanel.IsVisible = $true
        $newWmiFilterNameTextBox.Focus()
    }
    function Submit-NewWmiFilter {
        $namespace = "$($newWmiFilterNamespaceTextBox.Text)".Trim()
        if (-not $namespace) { $namespace = 'root\CIMv2' }
        $queries = @("$($newWmiFilterQueryTextBox.Text)" -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
                # A WQL query starts with its verb (SELECT): a line that starts with root names its namespace.
                if ($_ -match '^(root(\\[^\\:\s]+)*)\s*:\s*(\S.*)$') { [pscustomobject]@{ Namespace = $Matches[1]; Query = $Matches[3] } }
                else { [pscustomobject]@{ Namespace = $namespace; Query = $_ } }
            })
        $filter = $wmiFilterForm.Filter
        $users = @()
        try {
            if ($filter) {
                $users = @($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $filter.Id } | ForEach-Object DisplayName)
                $Directory.EditWmiFilter($filter, $newWmiFilterNameTextBox.Text, "$($newWmiFilterDescriptionTextBox.Text)".Trim(), $queries)
            } else {
                $filter = $Directory.NewWmiFilter($newWmiFilterNameTextBox.Text, "$($newWmiFilterDescriptionTextBox.Text)".Trim(), $queries)
            }
        } catch {
            $newWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $newWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text $(
            if (-not $wmiFilterForm.Filter) { Get-PSGPOText "WMI filter '{0}' created. Link a GPO to it with WMI Filter in the context menu of the GPO." $filter.Name }
            elseif ($users.Count) { Get-PSGPOText "WMI filter '{0}' saved: {1} apply it with its new queries." $filter.Name ($users -join ', ') }
            else { Get-PSGPOText "WMI filter '{0}' saved." $filter.Name })
    }
    # Delete WMI filter... on a filter, once confirmed; refused while a GPO uses it.
    $deleteWmiFilter = @{ Filter = $null }
    function Open-DeleteWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $deleteWmiFilter.Filter = $filter
        $users = @($Directory.Gpos | Where-Object { $_.WmiFilterId -eq $filter.Id } | ForEach-Object DisplayName)
        $deleteWmiFilterTextBlock.Text = (Get-PSGPOText "Delete the WMI filter '{0}'? " $filter.Name) +
            $(if ($users.Count) { Get-PSGPOText 'It is used by {0}: unlink them first (WMI Filter > (none)), it is not deleted otherwise.' ($users -join ', ') } else { Get-PSGPOText 'No GPO uses it.' })
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $deleteWmiFilterPanel.IsVisible = $true
    }
    function Submit-DeleteWmiFilter {
        $filter = $deleteWmiFilter.Filter
        if (-not $filter) { return }
        $deleteWmiFilterPanel.IsVisible = $false
        Invoke-DirectoryChange -Select 'WmiFilters' -Done (Get-PSGPOText "WMI filter '{0}' deleted." $filter.Name) -Change { $Directory.RemoveWmiFilter($filter) }
    }
    $newWmiFilterMenuItem.Add_Click({ Open-NewWmiFilterForm })
    $editWmiFilterMenuItem.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsWmiFilter]) { Open-NewWmiFilterForm -Filter $item } })
    $editWmiFilterButton.Add_Click({ $item = $domainTreeView.SelectedItem.Tag; if ($item -is [GPOToolsWmiFilter]) { Open-NewWmiFilterForm -Filter $item } })
    $newWmiFilterCreateButton.Add_Click({ Submit-NewWmiFilter })
    $newWmiFilterCancelButton.Add_Click({ $newWmiFilterPanel.IsVisible = $false })
    $deleteWmiFilterMenuItem.Add_Click({ Open-DeleteWmiFilterForm })
    $deleteWmiFilterConfirmButton.Add_Click({ Submit-DeleteWmiFilter })
    $deleteWmiFilterCancelButton.Add_Click({ $deleteWmiFilterPanel.IsVisible = $false })

    # File pickers of the system (xdg-desktop-portal on Linux), when there is one, for the .mof
    # files: the result is awaited by a timer, as the UI thread cannot block on it; $Done gets the
    # path chosen.
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
    $exportWmiFilterBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanSave
    $importWmiFilterBrowseButton.IsVisible = $canPick -and $window.StorageProvider.CanOpen

    # Export... on a WMI filter, as GPMC: a .mof file in the format of GPMC, by default in the
    # folder WMI filters of the folder of the backups. A file there is replaced once confirmed.
    $exportWmiFilter = @{ Filter = $null; Replace = $null }
    function Open-ExportWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $exportWmiFilter.Filter = $filter
        $exportWmiFilter.Replace = $null
        $exportWmiFilterTitleTextBlock.Text = Get-PSGPOText "Export the WMI filter '{0}'" $filter.Name
        # The folder of the account: the central backups are for Tier 0.
        $exportWmiFilterPathTextBox.Text = Join-Path (Join-Path (Get-PSGPOLocalBackupPath) 'WMI filters') (Get-PSGPOWmiFilterFileName -Name $filter.Name)
        $exportWmiFilterErrorTextBlock.Text = ''
        $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Export'
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $exportWmiFilterPanel.IsVisible = $true
    }
    function Submit-ExportWmiFilter {
        $filter = $exportWmiFilter.Filter
        if (-not $filter) { return }
        $file = "$($exportWmiFilterPathTextBox.Text)".Trim()
        if (-not $file) { $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText 'Give the file of the export.'; return }
        if (-not $file.EndsWith('.mof', [System.StringComparison]::OrdinalIgnoreCase)) { $file += '.mof' }
        if ((Test-Path -LiteralPath $file) -and $exportWmiFilter.Replace -ne $file) {
            $exportWmiFilter.Replace = $file
            $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText '{0} exists: Replace writes the filter over it.' $file
            $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Replace'
            return
        }
        try {
            $folder = [System.IO.Path]::GetDirectoryName($file)
            if ($folder) { $null = New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop }
            [System.IO.File]::WriteAllBytes($file, (ConvertTo-PSGPOWmiFilterMofByte -Filter $filter -Domain $Directory.DomainName))
        } catch {
            $exportWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The WMI filter is not exported: {0}' $_.Exception.GetBaseException().Message
            return
        }
        $exportWmiFilterPanel.IsVisible = $false
        Show-DirectoryResult -Text (Get-PSGPOText "WMI filter '{0}' exported to {1}: GPMC imports it in another domain, as Import... in the context menu of WMI Filters does." $filter.Name $file)
    }
    $exportWmiFilterPathTextBox.add_PropertyChanged({
        param($control, $e)
        # Another file: confirmed again before it is replaced.
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty -and $exportWmiFilter.Replace) {
            $exportWmiFilter.Replace = $null
            $exportWmiFilterErrorTextBlock.Text = ''
            $exportWmiFilterConfirmButton.Content = Get-PSGPOText 'Export'
        }
    })

    # Import... on WMI Filters, as GPMC: a .mof file of GPMC or HGPM read first, its filter shown,
    # then created in the domain with a new Id, under its name or the one given.
    $importWmiFilter = @{ Source = $null; File = $null }
    function Open-ImportWmiFilterForm {
        $importWmiFilter.Source = $null
        $importWmiFilter.File = $null
        $importWmiFilterTitleTextBlock.Text = Get-PSGPOText 'Import a WMI filter into {0}' $Directory.DomainName
        $importWmiFilterInfoTextBlock.Text = ''
        $importWmiFilterNameTextBox.Text = ''
        $importWmiFilterErrorTextBlock.Text = ''
        $importWmiFilterConfirmButton.IsEnabled = $false
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $importWmiFilterPanel.IsVisible = $true
        [void]$importWmiFilterPathTextBox.Focus()
    }
    function Read-ImportWmiFilterFile {
        $importWmiFilter.Source = $null
        $importWmiFilterConfirmButton.IsEnabled = $false
        $importWmiFilterInfoTextBlock.Text = ''
        $importWmiFilterErrorTextBlock.Text = ''
        $file = "$($importWmiFilterPathTextBox.Text)".Trim()
        if (-not $file) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'Give the .mof file to import.'; return }
        try {
            $read = @(ConvertFrom-PSGPOWmiFilterMof -Bytes ([System.IO.File]::ReadAllBytes($file)))
        } catch {
            $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The file cannot be imported: {0}' $_.Exception.GetBaseException().Message
            return
        }
        # As GPMC: one filter in a file; Import-PSGPOWmiFilter imports them all.
        if ($read.Count -gt 1) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText 'The file holds {0} WMI filters: the console imports a file of one, Import-PSGPOWmiFilter imports them all.' $read.Count; return }
        $source = $read[0]
        $importWmiFilter.Source = $source
        $importWmiFilter.File = $file
        $importWmiFilterInfoTextBlock.Text = ((@(
                    Get-PSGPOText "'{0}', exported from {1}" $source.Name $(if ($source.Domain) { $source.Domain } else { '?' })
                    if ($source.Description) { $source.Description }
                    @($source.Queries | ForEach-Object { "$($_.Namespace): $($_.Query)" })
                )) -join [Environment]::NewLine)
        $importWmiFilterNameTextBox.Text = $source.Name
        if ($Directory.FindWmiFilter($source.Name)) { $importWmiFilterErrorTextBlock.Text = Get-PSGPOText "A WMI filter named '{0}' exists in {1}: give the imported one another name." $source.Name $Directory.DomainName }
        $importWmiFilterConfirmButton.IsEnabled = $true
    }
    function Submit-ImportWmiFilter {
        $source = $importWmiFilter.Source
        if (-not $source) { return }
        try {
            $filter = $Directory.NewWmiFilter($importWmiFilterNameTextBox.Text, $source.Description, $source.Queries)
        } catch {
            $importWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $importWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text (Get-PSGPOText "WMI filter '{0}' imported from {1}. Link a GPO to it with WMI Filter in the context menu of the GPO, or Use it in a GPO... here." $filter.Name $importWmiFilter.File)
    }

    # Use it in a GPO... on a WMI filter: the GPOs the account edits that do not use it; the one
    # chosen is linked to the filter (its former filter replaced), as its Scope tab in GPMC.
    $useWmiFilter = @{ Filter = $null }
    function Open-UseWmiFilterForm {
        $filter = if ($domainTreeView.SelectedItem) { $domainTreeView.SelectedItem.Tag }
        if ($filter -isnot [GPOToolsWmiFilter]) { return }
        $useWmiFilter.Filter = $filter
        $useWmiFilterTitleTextBlock.Text = Get-PSGPOText "Use the WMI filter '{0}' in a GPO: the computers apply it only when each of its queries returns something ({1})" $filter.Name $filter.GetQueryText()
        $useWmiFilterErrorTextBlock.Text = ''
        Hide-DirectoryForm
        $directoryResultTextBlock.Text = ''
        $useWmiFilterSearchTextBox.Text = ''
        Update-UseWmiFilterList
        $useWmiFilterPanel.IsVisible = $true
        [void]$useWmiFilterSearchTextBox.Focus()
    }
    function Update-UseWmiFilterList {
        $filter = $useWmiFilter.Filter
        if (-not $filter) { return }
        $search = "$($useWmiFilterSearchTextBox.Text)".Trim()
        $gpos = [System.Collections.Generic.List[GPOToolsGpo]]::new()
        foreach ($gpo in @($Directory.Gpos | Sort-Object DisplayName)) {
            if (-not $gpo.CanEdit -or $gpo.WmiFilterId -eq $filter.Id) { continue }
            if ($search -and $gpo.DisplayName.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $gpos.Add($gpo)
        }
        $useWmiFilterList.ItemsSource = $gpos
        $useWmiFilterList.SelectedIndex = if ($gpos.Count -eq 1) { 0 } else { -1 }
        $useWmiFilterConfirmButton.IsEnabled = $null -ne $useWmiFilterList.SelectedItem
        $useWmiFilterErrorTextBlock.Text = if ($gpos.Count) { '' }
            elseif ($search) { Get-PSGPOText "No GPO named like '{0}' can use the WMI filter '{1}'." $search $filter.Name }
            else { Get-PSGPOText "Every GPO you edit uses the WMI filter '{0}' already." $filter.Name }
    }
    function Submit-UseWmiFilter {
        $filter = $useWmiFilter.Filter
        $gpo = $useWmiFilterList.SelectedItem
        if (-not $filter -or $gpo -isnot [GPOToolsGpo]) { return }
        $former = $Directory.GetWmiFilter($gpo)
        try {
            $Directory.SetWmiFilter($gpo, $filter)
        } catch {
            $useWmiFilterErrorTextBlock.Text = $_.Exception.GetBaseException().Message
            return
        }
        $useWmiFilterPanel.IsVisible = $false
        Update-DirectoryTree -Select $filter
        Show-DirectoryResult -Text $(if ($former) { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}', instead of '{2}'." $gpo.DisplayName $filter.Name $former.Name }
            else { Get-PSGPOText "'{0}' is linked to the WMI filter '{1}': the computers apply it only when each of its queries returns something ({2})." $gpo.DisplayName $filter.Name $filter.GetQueryText() })
    }

    # The WMI filter of the selected GPO in its details, as the Scope tab of GPMC: (none), the
    # filters of the domain, and a filter the domain does not have anymore.
    $gpoWmiFilter = @{ Updating = $false }
    function Update-GpoWmiFilterComboBox {
        param([GPOToolsGpo]$Gpo)
        $gpoWmiFilter.Updating = $true
        try {
            $items = [System.Collections.Generic.List[object]]::new()
            $selected = $null
            foreach ($choice in @($null) + @($Directory.WmiFilters)) {
                $item = [Avalonia.Controls.ComboBoxItem]::new()
                $item.Content = if ($choice) { $choice.Name } else { Get-PSGPOText '(none)' }
                $item.Tag = $choice
                if ($choice) { [Avalonia.Controls.ToolTip]::SetTip($item, $choice.GetQueryText()) }
                $items.Add($item)
                if (($choice -and $Gpo.WmiFilterId -eq $choice.Id) -or (-not $choice -and $null -eq $Gpo.WmiFilterId)) { $selected = $item }
            }
            if (-not $selected) {
                $selected = [Avalonia.Controls.ComboBoxItem]::new()
                $selected.Content = Get-PSGPOText '{0}: not in the domain anymore, the computers ignore the GPO' ('{' + $Gpo.WmiFilterId.ToString().ToUpperInvariant() + '}')
                $selected.Tag = 'Missing'
                $items.Add($selected)
            }
            $gpoWmiFilterComboBox.ItemsSource = $items
            $gpoWmiFilterComboBox.SelectedItem = $selected
        } finally {
            $gpoWmiFilter.Updating = $false
        }
    }
    $gpoWmiFilterComboBox.add_SelectionChanged({
        if ($gpoWmiFilter.Updating) { return }
        $item = $gpoWmiFilterComboBox.SelectedItem
        if (-not $item -or "$($item.Tag)" -eq 'Missing') { return }
        Set-SelectedWmiFilter -Filter $item.Tag
    })

    $exportWmiFilterMenuItem.Add_Click({ Open-ExportWmiFilterForm })
    $exportWmiFilterBrowseButton.Add_Click({ Start-MofFilePicker -Save -Title (Get-PSGPOText 'Export the WMI filter') -Path $exportWmiFilterPathTextBox.Text -Done { param($Path) $exportWmiFilterPathTextBox.Text = $Path } })
    $exportWmiFilterConfirmButton.Add_Click({ Submit-ExportWmiFilter })
    $exportWmiFilterCancelButton.Add_Click({ $exportWmiFilterPanel.IsVisible = $false })
    $importWmiFilterMenuItem.Add_Click({ Open-ImportWmiFilterForm })
    $importWmiFilterBrowseButton.Add_Click({ Start-MofFilePicker -Title (Get-PSGPOText 'Import a WMI filter') -Done { param($Path) $importWmiFilterPathTextBox.Text = $Path; Read-ImportWmiFilterFile } })
    $importWmiFilterReadButton.Add_Click({ Read-ImportWmiFilterFile })
    $importWmiFilterPathTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-ImportWmiFilterFile }
    })
    $importWmiFilterConfirmButton.Add_Click({ Submit-ImportWmiFilter })
    $importWmiFilterCancelButton.Add_Click({ $importWmiFilterPanel.IsVisible = $false })
    $useWmiFilterMenuItem.Add_Click({ Open-UseWmiFilterForm })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $useWmiFilterSearchTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property.Name -eq 'Text' -and $useWmiFilterPanel.IsVisible) { Update-UseWmiFilterList }
    })
    $useWmiFilterList.add_SelectionChanged({ $useWmiFilterConfirmButton.IsEnabled = $null -ne $useWmiFilterList.SelectedItem })
    $useWmiFilterList.add_DoubleTapped({ Submit-UseWmiFilter })
    $useWmiFilterConfirmButton.Add_Click({ Submit-UseWmiFilter })
    $useWmiFilterCancelButton.Add_Click({ $useWmiFilterPanel.IsVisible = $false })

    function Get-SelectedLink {
        $selected = $domainTreeView.SelectedItem
        if ($selected -and $selected.Tag -is [GPOToolsGpoLink] -and $selected.Parent.Tag -is [GPOToolsSom]) { [pscustomobject]@{ Som = $selected.Parent.Tag; Link = $selected.Tag } }
    }
    $enforcedLinkMenuItem.Add_Click({
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $enforced = -not $pair.Link.Enforced
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText $(if ($enforced) { "The link of '{0}' to {1} is enforced: it applies even where the inheritance is blocked." } else { "The link of '{0}' to {1} is no longer enforced." }) $pair.Link.GetDisplayName() $pair.Som.Name) `
            -Change { $Directory.SetLink($pair.Som, $pair.Link, $pair.Link.Enabled, $enforced) }
    })
    $enabledLinkMenuItem.Add_Click({
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $enabled = -not $pair.Link.Enabled
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText $(if ($enabled) { "The link of '{0}' to {1} is enabled." } else { "The link of '{0}' to {1} is disabled: the GPO no longer applies there." }) $pair.Link.GetDisplayName() $pair.Som.Name) `
            -Change { $Directory.SetLink($pair.Som, $pair.Link, $enabled, $pair.Link.Enforced) }
    })
    # Not GetNewClosure: the closure would not see the functions of the window.
    function Move-SelectedLink {
        param([int]$Step)
        $pair = Get-SelectedLink
        if (-not $pair) { return }
        $order = $pair.Link.Order + $Step
        Invoke-DirectoryChange -Select $pair.Link -Done (Get-PSGPOText "The link of '{0}' to {1} has the link order {2}." $pair.Link.GetDisplayName() $pair.Som.Name $order) `
            -Change { $Directory.MoveLink($pair.Som, $pair.Link, $order) }
    }
    $moveLinkUpMenuItem.Add_Click({ Move-SelectedLink -Step -1 })
    $moveLinkDownMenuItem.Add_Click({ Move-SelectedLink -Step 1 })
    $blockInheritanceMenuItem.Add_Click({
        $som = $domainTreeView.SelectedItem.Tag
        if ($som -isnot [GPOToolsSom]) { return }
        $blocked = -not $som.BlockInheritance
        Invoke-DirectoryChange -Select $som -Done (Get-PSGPOText $(if ($blocked) { 'The inheritance of {0} is blocked: the GPOs linked above apply there only when their link is enforced.' } else { 'The inheritance of {0} is no longer blocked.' }) $som.Name) `
            -Change { $Directory.SetBlockInheritance($som, $blocked) }
    })
    foreach ($statusItem in $gpoStatusEnabledMenuItem, $gpoStatusUserDisabledMenuItem, $gpoStatusComputerDisabledMenuItem, $gpoStatusAllDisabledMenuItem) {
        $statusItem.Add_Click({
            param($control)
            $gpo = Get-SelectedGpo
            if (-not $gpo) { return }
            $flags = [int]$control.Tag
            $select = $domainTreeView.SelectedItem.Tag
            if (($gpo.Flags -band 3) -eq $flags) { return }
            Invoke-DirectoryChange -Select $select -Done (Get-PSGPOText "The status of '{0}' is: {1}." $gpo.DisplayName (Get-PSGPOText @('Enabled', 'User configuration settings disabled', 'Computer configuration settings disabled', 'All settings disabled')[$flags])) `
                -Change { $Directory.SetGpoStatus($gpo, $flags) }
        })
    }
    $deleteGpoMenuItem.Add_Click({ Open-DeleteGpoForm })
    $importGpoMenuItem.Add_Click({ Open-ImportGpoForm })
    $importGpoReadButton.Add_Click({ Read-ImportSource })
    $importGpoPathTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Read-ImportSource }
    })
    $importGpoConfirmButton.Add_Click({ Submit-ImportGpo })
    $importGpoCancelButton.Add_Click({ $importGpoPanel.IsVisible = $false })
    $approveGpoMenuItem.Add_Click({ Open-ApproveGpoForm })
    $approveGpoConfirmButton.Add_Click({ Submit-ApproveGpo })
    $approveGpoGroupsCheckBox.add_IsCheckedChanged({ Update-ApproveGpoGroupState })
    $approveGpoCancelButton.Add_Click({ $approveGpoPanel.IsVisible = $false })
    $deleteGpoConfirmButton.Add_Click({ Submit-DeleteGpo })
    $deleteGpoCancelButton.Add_Click({ $deleteGpoPanel.IsVisible = $false })
    $restoreDeletedGpoMenuItem.Add_Click({ Open-RestoreGpoForm })
    $restoreDeletedGpoButton.Add_Click({ Open-RestoreGpoForm })
    $restoreGpoConfirmButton.Add_Click({ Submit-RestoreGpo })
    $restoreGpoCancelButton.Add_Click({ $restoreGpoPanel.IsVisible = $false })
    $purgeDeletedGpoMenuItem.Add_Click({ Open-PurgeDeletedGpoForm })
    $purgeDeletedGpoButton.Add_Click({ Open-PurgeDeletedGpoForm })
    $purgeDeletedGpoConfirmButton.Add_Click({ Submit-PurgeDeletedGpo })
    $purgeDeletedGpoCancelButton.Add_Click({ $purgeDeletedGpoPanel.IsVisible = $false })
    $renameMenuItem.Add_Click({ Open-RenameForm })
    $renameConfirmButton.Add_Click({ Submit-Rename })
    $renameCancelButton.Add_Click({ $renamePanel.IsVisible = $false })
    $renameTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-Rename }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $renamePanel.IsVisible = $false }
    })
    # F2 on the tree, as in GPMC and the file managers.
    $domainTreeView.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::F2 -and $renameMenuItem.IsVisible) { Open-RenameForm; $e.Handled = $true }
    })
    $deleteLinkConfirmButton.Add_Click({ Submit-DeleteLink })
    $deleteLinkCancelButton.Add_Click({ $deleteLinkPanel.IsVisible = $false })
    $newGpoGroupsCheckBox.add_IsCheckedChanged({ $newGpoGroupsPanel.IsVisible = [bool]$newGpoGroupsCheckBox.IsChecked })
    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $newGpoNameTextBox.add_PropertyChanged({
        param($control, $e)
        if ($e.Property -eq [Avalonia.Controls.TextBox]::TextProperty) { Update-NewGpoGroupText }
    })
    $newGpoNameTextBox.Add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::Enter) { Submit-NewGpo }
        elseif ($e.Key -eq [Avalonia.Input.Key]::Escape) { $newGpoPanel.IsVisible = $false }
    })
    $managementButton.Add_Click({ Show-View 'Management' })
    # The configuration window (New-PSGPOConfigurationWindow), one at a time, owned by the console;
    # for the administrators of the domain only, who change the configuration every console reads.
    $configurationWindow = @{ Ui = $null }
    $configurationButton.IsEnabled = $Directory -and -not $Directory.IsReadOnly -and $Directory.IsDomainAdministrator
    if (-not $configurationButton.IsEnabled) {
        [Avalonia.Controls.ToolTip]::SetTip($configurationButton, (Get-PSGPOText $(if ($Directory) { 'Only the administrators of the domain change the configuration of HGPM' } else { 'No domain: the defaults of the module apply.' })))
        [Avalonia.Controls.ToolTip]::SetShowOnDisabled($configurationButton, $true)
    }
    $configurationButton.Add_Click({
        if ($configurationWindow.Ui -and $configurationWindow.Ui.Window.IsVisible) { $configurationWindow.Ui.Window.Activate(); return }
        $configurationWindow.Ui = New-PSGPOConfigurationWindow -Directory $Directory
        # A configuration saved may change the view (View.ShowUnmanaged): the tree built again.
        $configurationWindow.Ui.Window.add_Closed({ if ($configurationWindow.Ui.State.Saved) { Update-DirectoryTree -Select $domainTreeView.SelectedItem.Tag } })
        $configurationWindow.Ui.Window.Show($window)
    })
    $browseAdmxButton.Add_Click({ Open-GpoEditor -Gpo $null })

    # Refresh (F5): the domain read again, as GPMC does; the tree keeps what is expanded and
    # selected. The changes of the other consoles and of GPMC show, and a GPO read again can be
    # saved again (its version is the one of the domain).
    # What was selected: the posted block runs once this function returned.
    $refresh = @{ Item = $null; LinkSom = $null }
    function Invoke-DirectoryRefresh {
        if ($Directory -isnot [GPOToolsLdapDirectory] -or -not $refreshButton.IsEnabled) { return }
        $selected = $domainTreeView.SelectedItem
        $refresh.Item = if ($selected) { $selected.Tag }
        $refresh.LinkSom = if ($refresh.Item -is [GPOToolsGpoLink] -and $selected.Parent.Tag -is [GPOToolsSom]) { $selected.Parent.Tag.DistinguishedName }
        $refreshButton.IsEnabled = $false
        Show-DirectoryResult -Text (Get-PSGPOText 'Reading the domain again from {0}...' $Directory.Server)
        # Posted: the text shows before the window waits for the domain.
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                try {
                    Update-PSGPODirectoryFromDomain -Directory $Directory
                } catch {
                    $refreshButton.IsEnabled = $true
                    Show-DirectoryResult -Text (Get-PSGPOText 'The domain is not read again: {0}' $_.Exception.GetBaseException().Message) -Problem
                    return
                }
                $settingsCache.Clear()
                $history.Current = @{}
                $backupLists.Root = $null
                Update-DirectoryTree -Select (Find-PSGPODirectoryItem -Directory $Directory -Item $refresh.Item -LinkSom $refresh.LinkSom)
                $refreshButton.IsEnabled = $true
                Show-DirectoryResult -Text (Get-PSGPOText 'The domain is read again from {0}, at {1}.' $Directory.Server (Get-Date).ToString('T'))
            }, [Avalonia.Threading.DispatcherPriority]::Background)
    }
    $refreshButton.Add_Click({ Invoke-DirectoryRefresh })
    $window.add_KeyDown({
        param($control, $e)
        if ($e.Key -eq [Avalonia.Input.Key]::F5 -and $managementView.IsVisible) { Invoke-DirectoryRefresh; $e.Handled = $true }
    })

    $directoryHint = if ($Directory.IsReadOnly) { Get-PSGPOText 'Read-only: {0}' $Directory.Source } else { Get-PSGPOText 'Right-click a domain or an OU to create a GPO' }
    $directoryBreadcrumbTextBlock.Text = $directoryHint
    $directoryEmptyTextBlock.IsVisible = -not $Directory
    $demoBanner.IsVisible = [bool]$Directory.IsDemonstration
    $domainTreeView.IsVisible = [bool]$Directory
    if ($DirectoryError) {
        $directoryEmptyTextBlock.Text = (Get-PSGPOText 'The domain could not be read.') + "`n`n$DirectoryError"
        $directoryEmptyTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438'))
        $directoryBreadcrumbTextBlock.Text = Get-PSGPOText 'Domain not read'
    }
    if ($Directory) { Update-DirectoryTree }
    Show-View $StartView

    # Then the version of HGPM, and whether a newer one is on the PowerShell Gallery.
    $statusBarList.ItemsSource = @(Get-PSGPOStatusBarItem -Platform (Get-PSGPOPlatform) -Directory $Directory -DirectoryError $DirectoryError) + @(Get-PSGPOVersionStatusItem)

    # Avalonia's SetupWithoutStarting() does not run a message loop by itself; drive one
    # manually and stop it when the window closes so the call blocks until then.
    $cts = [System.Threading.CancellationTokenSource]::new()
    $window.Add_Closed({
        [Avalonia.Threading.Dispatcher]::UIThread.Post(
            [System.Action] { $cts.Cancel() },
            [Avalonia.Threading.DispatcherPriority]::Background
        )
    })

    Show-PSGPOWindow -Window $window

    # A hashtable, because assigning a variable inside the posted action would only set a child-scope copy.
    $onShownState = @{ Error = $null }
    if ($OnShown) {
        $controls = @{ Window = $window; Editing = $editing; Clipboard = $clipboard; Directory = $Directory; Configuration = $configurationWindow }
        foreach ($name in 'treeView', 'logoImage', 'themeToggleButton', 'breadcrumbTextBlock', 'searchTextBox', 'searchButton', 'configuredOnlyCheckBox',
            'displayNameTextBox', 'descriptionTextBox', 'scopeTextBox', 'registryPathTextBox',
            'registryKeyTextBox', 'registryValuesList', 'settingTitleTextBlock', 'previewEmptyTextBlock', 'detailsTabs', 'copyNameMenuItem', 'copyRegistryMenuItem', 'copyCommandMenuItem',
            'notConfiguredRadio', 'enabledRadio', 'disabledRadio', 'optionsHost', 'settingErrorTextBlock', 'registryPreviewList',
            'themeToggleIcon', 'themeToggleText', 'subtitleTextBlock', 'managementButton', 'browseAdmxButton', 'searchPanel', 'managementView', 'editorView',
            'editingBanner', 'editingGpoTextBlock', 'applyPanel', 'applySettingButton', 'applyStatusTextBlock', 'previewHeaderTextBlock', 'directoryTabs', 'settingsTab', 'settingsStatusTextBlock', 'computerSettingsHeader', 'computerSettingsList', 'userSettingsHeader', 'userSettingsList', 'demoBanner', 'demoBannerTextBlock', 'statusBar', 'statusBarList', 'domainTreeView', 'domainContextMenu', 'directoryEmptyTextBlock', 'directoryBreadcrumbTextBlock',
            'directoryTitleTextBlock', 'directoryPropertiesList', 'linksHeaderTextBlock', 'linksList', 'createLinkedGpoMenuItem',
            'newGpoMenuItem', 'editGpoMenuItem', 'editGpoButton', 'newGpoPanel', 'newGpoTitleTextBlock', 'newGpoNameTextBox',
            'newGpoErrorTextBlock', 'newGpoCreateButton', 'newGpoCancelButton', 'newGpoStatusComboBox', 'newGpoGroupsCheckBox', 'newGpoGroupsPanel',
            'newGpoGroupsTextBlock', 'newGpoGroupsContainerComboBox', 'directoryResultTextBlock', 'deleteLinkMenuItem', 'deleteLinkPanel',
            'deleteLinkTextBlock', 'deleteLinkConfirmButton', 'deleteLinkCancelButton', 'linkGpoMenuItem', 'linkGpoPanel',
            'linkGpoTitleTextBlock', 'linkGpoFilterTextBox', 'linkGpoList', 'linkGpoErrorTextBlock', 'linkGpoConfirmButton', 'linkGpoCancelButton',
            'deleteGpoMenuItem', 'deleteGpoPanel', 'deleteGpoTextBlock', 'deleteGpoConfirmButton', 'deleteGpoCancelButton', 'restoreDeletedGpoMenuItem',
            'restoreDeletedGpoButton', 'restoreGpoPanel', 'restoreGpoTextBlock', 'restoreGpoLinkCheckBox', 'restoreGpoConfirmButton', 'restoreGpoCancelButton',
            'purgeDeletedGpoMenuItem', 'purgeDeletedGpoButton', 'purgeDeletedGpoPanel', 'purgeDeletedGpoTextBlock', 'purgeDeletedGpoConfirmButton', 'purgeDeletedGpoCancelButton',
            'renameMenuItem', 'renamePanel', 'renameTitleTextBlock', 'renameTextBox', 'renameErrorTextBlock', 'renameConfirmButton', 'renameCancelButton',
            'editWmiFilterButton', 'editingStatusTextBlock',
            'useWmiFilterMenuItem', 'exportWmiFilterMenuItem', 'importWmiFilterMenuItem', 'exportWmiFilterPanel', 'exportWmiFilterTitleTextBlock', 'exportWmiFilterPathTextBox', 'exportWmiFilterBrowseButton', 'exportWmiFilterErrorTextBlock', 'exportWmiFilterConfirmButton', 'exportWmiFilterCancelButton', 'importWmiFilterPanel', 'importWmiFilterTitleTextBlock', 'importWmiFilterPathTextBox', 'importWmiFilterBrowseButton', 'importWmiFilterReadButton', 'importWmiFilterInfoTextBlock', 'importWmiFilterNameTextBox', 'importWmiFilterErrorTextBlock', 'importWmiFilterConfirmButton', 'importWmiFilterCancelButton', 'useWmiFilterPanel', 'useWmiFilterTitleTextBlock', 'useWmiFilterSearchTextBox', 'useWmiFilterList', 'useWmiFilterErrorTextBlock', 'useWmiFilterConfirmButton', 'useWmiFilterCancelButton', 'gpoWmiFilterPanel', 'gpoWmiFilterComboBox',
            'wmiDelegationTab', 'wmiDelegationTitleTextBlock', 'wmiDelegationInfoTextBlock', 'wmiDelegationList', 'wmiDelegationNameTextBox', 'wmiDelegationPermissionComboBox', 'wmiDelegationSetButton', 'wmiDelegationRemoveButton', 'wmiDelegationStatusTextBlock',
            'newGpoTemplateComboBox', 'historyNotesTemplateCheckBox', 'approveGpoMenuItem', 'approveGpoPanel', 'approveGpoTextBlock',
            'approveGpoRightsComboBox', 'approveGpoApplyToTextBox', 'approveGpoErrorTextBlock', 'approveGpoConfirmButton', 'approveGpoCancelButton',
            'approveGpoDenyToTextBox', 'approveGpoGroupsCheckBox', 'approveGpoGroupsTextBlock', 'approveGpoFilteringGrid',
            'historyCommentTextBox', 'historyDriftBorder', 'historyDriftTextBlock', 'historyDriftButton', 'historyNotesPanel', 'historyNotesInfoTextBlock',
            'historyNotesCommentTextBox', 'historyNotesLabelsTextBox', 'historyNotesApprovedCheckBox', 'historyNotesSaveButton', 'historyTab', 'historyPathTextBox', 'historyBackupButton',
            'importGpoMenuItem', 'importGpoPanel', 'importGpoTitleTextBlock', 'importGpoPathTextBox', 'importGpoReadButton', 'importGpoSourceComboBox', 'importGpoTableTextBox',
            'importGpoExclusiveCheckBox', 'importGpoTextBlock', 'importGpoErrorTextBlock', 'importGpoConfirmButton', 'importGpoCancelButton',
            'delegationTab', 'filteringList', 'filteringNameTextBox', 'filteringAddButton', 'filteringRemoveButton', 'delegationList', 'delegationNameTextBox',
            'delegationPermissionComboBox', 'delegationSetButton', 'delegationRemoveButton', 'delegationStatusTextBlock',
            'historyBackupAllButton', 'historyStatusTextBlock', 'historyTimelineList', 'historyCompareTextBlock', 'historyChangesList',
            'historyRestoreButton', 'historyRestorePanel', 'historyRestoreTextBlock', 'historyRestoreConfirmButton', 'historyRestoreCancelButton',
            'detailsTitleTextBlock', 'configurationButton', 'preferencesPanel', 'preferencesTitleTextBlock', 'preferencesInfoTextBlock', 'preferencesNewTypeComboBox',
            'preferencesNewButton', 'preferencesEditButton', 'preferencesDeleteButton', 'preferencesUpButton', 'preferencesDownButton',
            'preferencesStatusTextBlock', 'preferencesEmptyTextBlock', 'preferencesList', 'preferencesDeletePanel', 'preferencesDeleteTextBlock',
            'preferencesDeleteConfirmButton', 'preferencesDeleteCancelButton', 'preferencesFormBorder', 'preferencesFormTitleTextBlock', 'refreshButton',
            'enforcedLinkMenuItem', 'enabledLinkMenuItem', 'moveLinkUpMenuItem', 'moveLinkDownMenuItem', 'blockInheritanceMenuItem', 'gpoStatusMenuItem', 'wmiFilterMenuItem', 'newWmiFilterMenuItem', 'editWmiFilterMenuItem', 'deleteWmiFilterMenuItem', 'newWmiFilterPanel', 'newWmiFilterTitleTextBlock', 'newWmiFilterNameTextBox', 'newWmiFilterDescriptionTextBox', 'newWmiFilterNamespaceTextBox', 'newWmiFilterQueryTextBox', 'newWmiFilterErrorTextBlock', 'newWmiFilterCreateButton', 'newWmiFilterCancelButton', 'deleteWmiFilterPanel', 'deleteWmiFilterTextBlock', 'deleteWmiFilterConfirmButton', 'deleteWmiFilterCancelButton', 'gpoStatusEnabledMenuItem', 'gpoStatusUserDisabledMenuItem', 'gpoStatusComputerDisabledMenuItem', 'gpoStatusAllDisabledMenuItem',
            'preferencesFormHost', 'preferencesFormErrorTextBlock', 'preferencesSaveButton', 'preferencesCancelButton',
            'certificatesPanel', 'certificatesTitleTextBlock', 'certificatesInfoTextBlock', 'certificatesPathTextBox', 'certificatesImportButton', 'certificatesDeleteButton', 'certificatesStatusTextBlock', 'certificatesEmptyTextBlock', 'certificatesList', 'certificatesDeletePanel', 'certificatesDeleteTextBlock', 'certificatesDeleteConfirmButton', 'certificatesDeleteCancelButton',
            'restrictedGroupsPanel', 'restrictedGroupsInfoTextBlock', 'restrictedGroupsAddButton', 'restrictedGroupsEditButton', 'restrictedGroupsDeleteButton', 'restrictedGroupsStatusTextBlock', 'restrictedGroupsEmptyTextBlock', 'restrictedGroupsList', 'restrictedGroupsDeletePanel', 'restrictedGroupsDeleteTextBlock', 'restrictedGroupsDeleteConfirmButton', 'restrictedGroupsDeleteCancelButton', 'restrictedGroupsFormBorder', 'restrictedGroupsFormTitleTextBlock', 'restrictedGroupNameTextBox', 'restrictedGroupMembersCheckBox', 'restrictedGroupMembersTextBox', 'restrictedGroupMemberOfTextBox', 'restrictedGroupsFormErrorTextBlock', 'restrictedGroupsSaveButton', 'restrictedGroupsCancelButton') {
            $controls[$name] = Get-PSGPOAvaloniaControl $window $name
        }
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
            try { & $OnShown $controls } catch { $onShownState.Error = $_ } finally { $window.Close() }
        })
    }

    try {
        [Avalonia.Threading.Dispatcher]::UIThread.MainLoop($cts.Token)
    } catch [System.OperationCanceledException] {
        # Expected: the loop exits by cancellation once the window is closed.
        Write-Verbose 'The window is closed.'
    }

    if ($onShownState.Error) { throw $onShownState.Error }
}
