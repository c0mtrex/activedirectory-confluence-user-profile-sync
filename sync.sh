#!/bin/bash -eu
# See http://wiki.magicleap.ds/display/JIRACONF/Confluence+Profile+Synchronizer+info

if [[ "$(uname -n)" != ml-confluence-01 ]]
then
	# We're probably running a cloned VM on the staging server. Exit with an error code but otherwise silently
	exit 1
fi

/usr/local/rvm/wrappers/default/ruby /opt/atlassian/activedirectory-confluence-user-profile-sync/sync_ad_confluence.rb \
    --ldaphost "magicleap.ds" \
    --binddn="CN=Service Account for LDAP search and Bind,OU=SERVICE ACCOUNTS,OU=ADMIN,DC=magicleap,DC=ds" \
    --bindpassword="47g9GXvP" \
    --basedn="OU=ADMIN,DC=magicleap,dc=ds" \
    --confbaseurl="http://wiki.magicleap.ds" \
    --confuser="_profilesyncer" \
    --confpassword="xnIxQcPt4mu0SvORLNo9"  \
    $*
