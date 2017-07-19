#!/usr/bin/env bash

access_token=$(rsc -r $REFRESH_TOKEN -a $ACCOUNT_ID -h $SHARD --x1 .access_token cm15 create oauth2 grant_type=refresh_token refresh_token=$REFRESH_TOKEN)
rsc="rsc -s $access_token -a $ACCOUNT_ID -h $SHARD"

org_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' https://$SHARD/grs/users/$USER_ID/orgs)

echo "You are a member of $(echo $org_list | jq -r '.[].href' | grep -ch "^") orgs. Enumerating them now..."
org_idx=1
for org_href in $(echo $org_list | jq -r '.[].href')
do
  org=$(echo $org_list | jq -r ".[] | select(.href==\"$org_href\")")
  org_name=$(echo $org | jq -r '.name')

  project_index_href="https://$SHARD$org_href/projects"
  project_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' $project_index_href)
  for project_href in $(echo $project_list | jq -r '.[].href')
  do
    project=$(echo $project_list | jq -r ".[] | select(.href==\"$project_href\")")
    project_name=$(echo $project | jq -r '.name')
    echo "Org: $org_name Project: $project_name Project Href: $project_href"
  done
done
