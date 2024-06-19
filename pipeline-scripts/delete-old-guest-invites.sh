#!/bin/bash
# set -e

if [[ $(uname) == "Darwin" ]]; then
  shopt -s expand_aliases
  alias date="gdate"
fi

branch=$1

min_user_age_days=31
min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")
echo "min_user_age_date=${min_user_age_date}"

users_file=unaccepted_invites.json

. pipeline-scripts/delete-user.sh $branch

# Remove guest users in Azure AAD that haven't accepted their invite after 31 days
delete_old_invites() {
  # Create file with users that haven't accepted invite within a week
  # az ad user list --query="[?userType=='Guest' && userState=='PendingAcceptance' && createdDateTime<'${min_user_age_date}' ].{DisplayName: displayName, ObjectId:objectId, Mail:mail}" -o json > ${users_file}
  az rest --method get --uri "https://graph.microsoft.com/beta/users?top=999&filter=externalUserState eq 'PendingAcceptance' and createdDateTime le ${min_user_age_date}&select=id,createdDateTime,mail,givenName,surname,displayName" -o json > ${users_file}

  unaccepted_invite_count=$(jq -r .value[].id ${users_file} | wc -l )

  if [[ ${unaccepted_invite_count} -gt 0 ]]; then
    echo "Number of users to be deleted: ${unaccepted_invite_count}"
    while IFS=" " read -r object_id mail display_name
    do

      delete_user "$object_id" "$mail" "$display_name" &
    
    done <<< "$(jq -r '.value[] | "\(.id) \(.mail) \(.displayName)"' ${users_file})"
    wait
  else
    echo "No unaccepted invites found, nothing to do."
  fi
}

if [[ $branch == "master" ]]; then
  echo "Deleting users that haven't accepted their invite within ${min_user_age_days} days"
  delete_old_invites
  echo "Guest users deleted"
else
  echo "Creating list of users that will be deleted when this script runs on the default branch"
  delete_old_invites
fi
