<#
    The comment of the GPO selected, in its Details tab, as GPMC: the file GPO.cmt of its folder in
    SYSVOL, read once after the click (the selection shows at once) and until the domain is read
    again; saved by an account that edits the GPO, without changing its version.

    Dot-sourced by Start-PSGPOManagerWindow (. Initialize-PSGPOManagerCommentView): its state and
    functions live in the scope of the window, which stays alive while the window is open: its
    handlers find them there, with the controls of the window (a variable per control) and the
    other views.
#>

function Initialize-PSGPOManagerCommentView {
    # Gpo: the one shown; Saved: its comment as the domain has it; Cache: the comments read, by GPO
    # (emptied when the domain is read again); Reading: the comment is being read.
    $gpoComment = @{ Gpo = $null; Saved = ''; Cache = @{}; Reading = $false }

    # A comment as the box shows it and compares it: the line ends as LF.
    function ConvertTo-GpoCommentText {
        param([AllowNull()] [string]$Text)
        "$Text" -replace '\r\n', "`n"
    }

    function Set-GpoCommentStatus {
        param([string]$Text, [switch]$Problem)
        if ($Problem) { $gpoCommentStatusTextBlock.Foreground = [Avalonia.Media.SolidColorBrush]::new([Avalonia.Media.Color]::Parse('#D13438')) }
        else { $gpoCommentStatusTextBlock.ClearValue([Avalonia.Controls.TextBlock]::ForegroundProperty) }
        $gpoCommentStatusTextBlock.Text = $Text
    }

    function Show-GpoComment {
        param([AllowNull()] [string]$Text)
        $gpoComment.Reading = $false
        $gpoComment.Saved = ConvertTo-GpoCommentText $Text
        $gpoCommentTextBox.Text = $gpoComment.Saved
        $gpoCommentTextBox.Watermark = Get-PSGPOText 'No comment'
        $gpoCommentSaveButton.IsEnabled = $false
    }

    # The comment of $Gpo ($null: the panel hidden), from the cache or read after the click.
    function Update-GpoComment {
        param([AllowNull()] [GPOToolsGpo]$Gpo)
        $gpoComment.Gpo = $Gpo
        $gpoCommentPanel.IsVisible = $null -ne $Gpo
        Set-GpoCommentStatus ''
        if (-not $Gpo) { return }
        $editable = $Gpo.CanEdit -and -not $Directory.IsReadOnly
        $gpoCommentTextBox.IsReadOnly = -not $editable
        $gpoCommentSaveButton.IsVisible = $editable
        if ($gpoComment.Cache.ContainsKey($Gpo.Id)) { Show-GpoComment $gpoComment.Cache[$Gpo.Id]; return }
        $gpoComment.Reading = $true
        $gpoCommentTextBox.Text = ''
        $gpoCommentTextBox.Watermark = Get-PSGPOText 'Reading the comment...'
        $gpoCommentSaveButton.IsEnabled = $false
        # Posted: the selection shows first, then the folder of the GPO is read.
        [Avalonia.Threading.Dispatcher]::UIThread.Post([System.Action] {
                $gpo = $gpoComment.Gpo
                if (-not $gpo -or -not $gpoComment.Reading) { return }
                try {
                    $gpoComment.Cache[$gpo.Id] = $Directory.ReadGpoComment($gpo)
                } catch {
                    if ([object]::ReferenceEquals($gpoComment.Gpo, $gpo)) {
                        Show-GpoComment ''
                        Set-GpoCommentStatus (Get-PSGPOText 'The comment is not read: {0}' $_.Exception.GetBaseException().Message) -Problem
                    }
                    return
                }
                # Another GPO selected meanwhile: it is read on its own.
                if ([object]::ReferenceEquals($gpoComment.Gpo, $gpo)) { Show-GpoComment $gpoComment.Cache[$gpo.Id] }
            }, [Avalonia.Threading.DispatcherPriority]::Background)
    }

    function Save-GpoComment {
        $gpo = $gpoComment.Gpo
        if (-not $gpo -or $gpoComment.Reading) { return }
        $text = ConvertTo-GpoCommentText $gpoCommentTextBox.Text
        try {
            $Directory.WriteGpoComment($gpo, $text)
        } catch {
            Set-GpoCommentStatus (Get-PSGPOText 'The comment is not saved: {0}' $_.Exception.GetBaseException().Message) -Problem
            return
        }
        $gpoComment.Cache[$gpo.Id] = $text
        Show-GpoComment $text
        Set-GpoCommentStatus (Get-PSGPOText 'Comment saved.')
    }

    # The property, not TextChanged: it is raised at once, whoever sets the text.
    $gpoCommentTextBox.add_PropertyChanged({
            param($control, $e)
            if ($e.Property -ne [Avalonia.Controls.TextBox]::TextProperty -or $gpoComment.Reading) { return }
            $gpoCommentSaveButton.IsEnabled = (ConvertTo-GpoCommentText $gpoCommentTextBox.Text) -cne $gpoComment.Saved
        })
    $gpoCommentSaveButton.Add_Click({ Save-GpoComment })
}
