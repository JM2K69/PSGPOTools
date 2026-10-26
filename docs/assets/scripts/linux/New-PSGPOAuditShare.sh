#!/usr/bin/env bash
# Creates the share of the central audit log of HGPM on a Samba server (an AD domain controller
# or a member server): a folder, and a section of smb.conf whose permissions are the NT ACLs that
# Initialize-PSGPOAuditShare writes (acl_xattr), not those of the file system.
#
#   sudo ./New-PSGPOAuditShare.sh                       # share gpo-audit, folder /srv/gpo-audit
#   sudo ./New-PSGPOAuditShare.sh gpo-audit /srv/gpo-audit
#
# Then, from a console with the Kerberos ticket of a domain administrator (kinit administrator):
#
#   Initialize-PSGPOAuditShare -Path //<server>/gpo-audit -Server <domain controller>
#
# and Audit.Path = \\<server>\gpo-audit in the Settings of the console (the configuration of the
# domain). What is there is kept: the script can run again.
#
# https://jm2k69.github.io/PSGPOTools/en/features/audit-log/
set -euo pipefail

share="${1:-gpo-audit}"
folder="${2:-/srv/gpo-audit}"
config="$(smbd -b | awk '/CONFIGFILE:/ { print $2 }')"
config="${config:-/etc/samba/smb.conf}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run it as root: sudo $0 $*" >&2
    exit 1
fi

# The folder: every account of the domain reaches it, the NT ACLs decide what each does there.
# The sticky bit: an account cannot delete the file of another one, even from the server.
mkdir -p "$folder"
chmod 1777 "$folder"

# The share: NT ACLs kept in extended attributes, the POSIX ACLs left aside.
if grep -q "^\[$share\]" "$config"; then
    echo "[$share] is already in $config: kept."
else
    cp "$config" "$config.$(date +%Y%m%d-%H%M%S).bak"
    cat >> "$config" <<EOF

[$share]
	path = $folder
	read only = no
	vfs objects = acl_xattr
	acl_xattr:ignore system acls = yes
	map acl inherit = yes
	store dos attributes = yes
	comment = Central audit log of HGPM
EOF
    echo "[$share] added to $config."
fi

testparm -s "$config" > /dev/null
smbcontrol all reload-config
echo "Share //$(hostname -f)/$share ready: $folder"
echo "Next: Initialize-PSGPOAuditShare -Path //$(hostname -f)/$share"
