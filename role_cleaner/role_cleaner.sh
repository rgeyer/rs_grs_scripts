#!/usr/bin/env bash

access_token=$(rsc -r $REFRESH_TOKEN -a $ACCOUNT_ID -h $SHARD --x1 .access_token cm15 create oauth2 grant_type=refresh_token refresh_token=$REFRESH_TOKEN)
rsc="rsc -s $access_token -a $ACCOUNT_ID -h $SHARD"

declare -a org_hrefs
declare -a org_choices
is_em=0
is_admin=0

print_org_list() {
  for ((org_choice_idx=1; org_choice_idx < ${#org_choices[@]}; org_choice_idx++))
  do
    echo ${org_choices[$org_choice_idx]}
  done
  echo "Which org would you like to act on?"
  read chosen_org_idx

  org_href=${org_hrefs[$chosen_org_idx]}
  org=$(echo $org_list | jq -r ".[] | select(.href==\"$org_href\")")
  org_name=$(echo $org | jq -r '.name')

  role_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' https://$SHARD$org_href/roles)
  em_role=$(echo $role_list | jq -r '.[] | select(.name=="enterprise_manager")')
  em_role_href=$(echo $em_role | jq -r '.href')
  admin_role=$(echo $role_list | jq -r '.[] | select(.name=="admin")')
  admin_role_href=$(echo $admin_role | jq -r '.href')

  project_index_href="https://$SHARD$org_href/projects"
  project_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' $project_index_href)
  echo "$org_href - $org_name -- Project Count: $(echo $project_list | jq -r '.[].href' | grep -ch "^")"

  org_access_rule_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' "https://$SHARD$org_href/access_rules?filter=subject_href=/grs/users/$USER_ID")
  em_role_assignment=$(echo $org_access_rule_list | jq -r ".[] | select(.links.role.href==\"$em_role_href\")")

  if [[ -z "$em_role_assignment" ]]; then
    is_em=0
    echo "You don't have the enterprise manager role in this org. Removing roles from projects will be permanent if you continue. Would you prefer to act on a different org? (y/n)"
    read continue
    if [[ "$continue" == "y" || "$continue" == "Y" ]];
    then
      print_org_list
    fi
  else
    is_em=1
    echo "You're an enterprise manager in this org. You may remove roles from projects, but still restore your access unless you destroy your enterprise manager role"
  fi

  print_org_menu
}

print_org_menu() {
  echo "Acting on ($org_href - $org_name -- Project Count: $(echo $project_list | jq -r '.[].href' | grep -ch "^"))"
  echo "1) Destroy all project roles"
  echo "2) Destroy enterprise manager role on org (Dangerous! Irreversible!)"
  echo "3) Choose a different org"

  read project_action
  if [ "$project_action" == "1" ];
  then
    revoke_all_roles_on_project
    print_org_menu
  elif [ "$project_action" == "2" ];
  then
    revoke_em_role_on_org
    print_org_menu
  elif [ "$project_action" == "3" ];
  then
    refresh_org_list
    print_org_list
  fi
}

revoke_em_role_on_org() {
  if [[ $is_em == 0 ]];
  then
    echo "You lack the enterprise manager role, so you may not revoke the enterprise manager role."
  else
    echo "Are you absolutely sure that you wish to destroy enterprise manager role on the org ($org_name). This is irreversible, this is your last chance to bail out y/n"
    read really_sure
    if [[ "$really_sure" == "y" ]];
    then
      curl -X PUT -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' "https://$SHARD$org_href/access_rules/revoke" -d "{\"subject\": {\"href\": \"/grs/users/$USER_ID\"},\"role\":{\"href\": \"$em_role_href\"}}"
    fi
  fi

}

revoke_all_roles_on_project() {
  for proj_href in $(echo $project_list | jq -r '.[].href')
  do
    proj=$(echo $project_list | jq -r ".[] | select(.href==\"$proj_href\")")
    name=$(echo $proj | jq -r '.name')
    href=$(echo $proj | jq -r '.href')
    id=$(echo $proj | jq -r '.id')
    access_rule_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' "https://$SHARD$org_href/projects/$id/access_rules?filter=subject_href=/grs/users/$USER_ID")
    admin_role_assignment=$(echo $access_rule_list | jq -r ".[] | select(.links.role.href==\"$admin_role_href\")")
    is_admin=0
    if [[ -z "$admin_role_assignment" ]];
    then
      is_admin=0
    else
      is_admin=1
    fi
    echo "  $id - $name -- Access Rule Count: $(echo $access_rule_list | jq -r '.[].links.role.href' | grep -ch "^")"

    if [[ $is_em == 0 && $is_admin == 0 ]];
    then
      echo "    You do not have the admin role in this project, or the enterprise manager role in the org. No roles will be destroyed."
      echo "    Roles not destroyed"
      for role_href in $(echo $access_rule_list | jq -r '.[].links.role.href')
      do
        role_name=$(echo $role_list | jq -r ".[] | select(.href==\"$role_href\") | .name")
        echo "      $role_href ($role_name)"
      done
    else
      for role_href in $(echo $access_rule_list | jq -r '.[].links.role.href')
      do
        if [[ "$role_href" == "$admin_role_href" ]];
        then
          echo "    Skipping role 'admin'"
        else
          role_name=$(echo $role_list | jq -r ".[] | select(.href==\"$role_href\") | .name")
          echo "    Revoking role $role_href ($role_name) for /grs/users/$USER_ID"
          curl -X PUT -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' "https://$SHARD$org_href/projects/$id/access_rules/revoke" -d "{\"subject\": {\"href\": \"/grs/users/$USER_ID\"},\"role\":{\"href\": \"$role_href\"}}"
        fi
      done
      if [[ $is_admin == 1 ]];
      then
        echo "    Revoking role $admin_role_href (admin) for /grs/users/$USER_ID"
        curl -X PUT -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' "https://$SHARD$org_href/projects/$id/access_rules/revoke" -d "{\"subject\": {\"href\": \"/grs/users/$USER_ID\"},\"role\":{\"href\": \"$admin_role_href\"}}"
      fi
    fi
  done
}

refresh_org_list() {
  echo "Refreshing list of orgs you have access to..."
  org_list=$(curl -s -H 'X-API-Version:2.0' -H "Authorization: Bearer $access_token" -H 'Content-Type: application/json' https://$SHARD/grs/users/$USER_ID/orgs)

  echo "You are a member of $(echo $org_list | jq -r '.[].href' | grep -ch "^") orgs. Enumerating them now..."
  org_idx=1
  for org_href in $(echo $org_list | jq -r '.[].href')
  do
    org=$(echo $org_list | jq -r ".[] | select(.href==\"$org_href\")")
    name=$(echo $org | jq -r '.name')
    org_choices[$org_idx]="$org_idx) $org_href - $name"
    org_hrefs[$org_idx]=$org_href
    org_idx=$((org_idx+1))
  done
}

refresh_org_list
print_org_list
