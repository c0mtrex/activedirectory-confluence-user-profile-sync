#!/bin/bash -eu
# 

if [[ "$(uname -n)" != ml-confluence-01 ]]
then
	# We're probably running a cloned VM on the staging server. Exit with an error code but otherwise silently
	exit 1
fi

/usr/local/rvm/wrappers/default/ruby /opt/atlassian/activedirectory-confluence-user-profile-sync/sync_ad_confluence.rb \
    --ldaphost "AD server" \
    --binddn="CN=Service Account for LDAP search and Bind,OU=SERVICE ACCOUNTS,OU=ADMIN,DC=domain,DC=ds" \
    --bindpassword="password" \
    --basedn="OU=ADMIN,DC=domain,dc=ds" \
    --confbaseurl="http://" \
    --confuser="_profilesyncer" \
    --confpassword="password"  \
    $*
