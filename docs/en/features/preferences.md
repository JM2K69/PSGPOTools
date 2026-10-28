# Group Policy Preferences

The **Preferences** node of each scope has the 21 preference types of
[MS-GPPREF](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/),
under **Windows Settings** and **Control Panel Settings**, as the Windows editor shows them.

![The Registry preferences of a GPO](../assets/screenshots/11-editor-preferences.png)

| Windows Settings | Control Panel Settings |
|---|---|
| Applications (user), Drive Maps (user), Environment, Files, Folders, Ini Files, Registry, Network Shares (computer), Shortcuts | Data Sources, Devices, Folder Options, Internet Settings (user), Local Users and Groups, Network Options, Power Options, Printers, Regional Options (user), Scheduled Tasks, Services (computer), Start Menu (user) |

## Items

The items of a type are listed in their order. **New**, **Edit**, **Move up / down** and
**Delete** change them, with a form generated from the type ([MS-GPPREF] schema): the 35 item
types of the 21 preference types (a TCP/IP, shared or local printer; a group and its members; a
scheduled or an immediate task...).

The common options of every item are there too: description, stop processing on error, run in the
security context of the user, remove the item when it is no longer applied.

What an item holds as XML is edited as XML, and checked before it is written: the Task Scheduler
definition of a task (a valid task is proposed to start with), the registry values of Internet
Settings, the content of an application.

A **Registry Item** suggests while typing the keys of the loaded ADMX files for its hive
(`HKEY_LOCAL_MACHINE`: those of the computer policies, `HKEY_CURRENT_USER`: those of the user
policies), with the policies that write them, then the value names of the key chosen. When a policy
manages the key, the form says so: a preference writes the value on the computers for good, and it
stays when the GPO no longer applies (it tattoos them), where a policy is removed with its GPO. Set
the policy instead.

![The keys of the ADMX files suggested in a Registry item, and the warning of a key a policy manages](../assets/screenshots/86-registry-suggestions.png){ width="640" }

A **Local Group** suggests the groups of every computer, as GPMC names them
(`Administrators (built-in)`), and fills their SID; its members are added from the well-known
accounts and those of the domain, with their SID ([accounts and SIDs](policy-editor.md#accounts-and-sids)).

## How it is written

The XML file of the type (`Machine\Preferences\Registry\Registry.xml`...) is read and written with
`System.Xml`, as GPMC writes it: `clsid` of each element, `uid`, `changed` in UTC, the image of the
action. **What the console does not edit is kept**: item-level targeting (`Filters`), unknown
attributes.

Then the version of the scope increases, and the client-side extension of the type is declared
with its tool, and the tool under the null extension `{00000000-0000-0000-0000-000000000000}`, as
GPMC does.

!!! danger "Passwords are never written"
    Preferences can store a password (`cpassword`), encrypted with a key Microsoft published:
    any user of the domain can read it (MS14-025). The console never writes one; an item that
    stores one is reported, and its password kept as it is.

The Settings tab, the backups and the history show the preference items, compared item by item by
their `uid` (the XML they hold by its hash).
