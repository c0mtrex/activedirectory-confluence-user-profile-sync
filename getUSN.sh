#!/bin/bash -eu
# See http://wiki.magicleap.ds/display/JIRACONF/Confluence+Profile+Synchronizer+info

if [[ "$(uname -n)" != ml-confluence-01 ]]
then
	# We're probably running a cloned VM on the staging server. Exit with an error code but otherwise silently
	exit 1
fi

ldapsearch -h magicleap.ds -p 389 -D "CN=Service Account for LDAP search and Bind,OU=SERVICE ACCOUNTS,OU=ADMIN,DC=magicleap,DC=ds" -w 47g9GXvP -b "" -s base "objectclass=*" highestCommittedUSN
#    --ldaphost "magicleap.ds" \
#    --binddn="CN=Service Account for LDAP search and Bind,OU=SERVICE ACCOUNTS,OU=ADMIN,DC=magicleap,DC=ds" \
#    --bindpassword="47g9GXvP" \
#    --basedn="OU=ADMIN,DC=magicleap,dc=ds" \
