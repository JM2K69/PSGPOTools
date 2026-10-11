# Icons

Icons of `Show-GPOManagerAvalonia`: [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons),
the Windows 11 icons published by Microsoft under the MIT license (see `LICENSE`), size 20, regular style,
taken at commit `a347af95478f989038cccbf085978865264c048a`.

Each file is renamed after the icon (`assets/Folder Prohibited/SVG/ic_fluent_folder_prohibited_20_regular.svg`
is `folder-prohibited.svg`). The window reads the paths of every SVG of this folder as an Avalonia geometry,
available in XAML as `{StaticResource Icon.<name>}`; adding an icon means adding its SVG here.
