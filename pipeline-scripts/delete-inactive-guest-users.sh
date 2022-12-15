#!/bin/bash
set -e

branch=$1

# Number of days before deletion date that a user will start getting notified about being deleted
warn_inactive_days=7

# Number of days a user can be inactive before being deleted
delete_inactive_days=31

min_user_age_days=7
max_inactive_days=$(("${delete_inactive_days}" - "${warn_inactive_days}" ))
max_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${max_inactive_days} days ago")
delete_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${delete_inactive_days} days ago")

min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

echo "max_inactive_days=${max_inactive_days}"
echo "delete_inactive_date=${delete_inactive_date}"
echo "min_user_age_date=${min_user_age_date}"

users_file=guests.json

. pipeline-scripts/delete-user.sh "${branch}"

# Delete users that haven't logged in within set number of days and are over a week old
delete_inactive_guests() {

  # Create file with list of guest users that have accepted their invite
  NEXT_LINK=
  counter=0

  until [[ "${NEXT_LINK}" == "null" ]]; do

    if [[ ${counter} == 0 ]]; then
      az rest --method get --uri "https://graph.microsoft.com/beta/users?top=100&filter=externalUserState eq 'Accepted' and createdDateTime le ${min_user_age_date}&select=id,signInActivity,createdDateTime,mail,givenName,surname,displayName" > users-${counter}.json
    else
      az rest --method get --uri "${NEXT_LINK}" > users-${counter}.json
    fi

    NEXT_LINK=$(jq -r '."@odata.nextLink"' users-${counter}.json)

    counter=$(( counter + 1 ))

  done

  jq -s 'map(.value[])' users-?.json > ${users_file}
  

  inactive_users_count=$(jq -r '.[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | .id' ${users_file} | wc -l )
  jq -r '.[].id' ${users_file} | wc -l
  
  if [[ ${inactive_users_count} -gt 0 ]]; then

    while IFS=" " read -r object_id mail last_sign_in_date_time last_non_interactive_sign_in_date_time given_name surname display_name
    do

      # Use display name if given and surname aren't set
      if [[ ${given_name} == "null" ]] || [[ ${surname} == "null" ]]; then
        given_name=$(echo "$display_name" | cut -d "," -f2 )
        surname=$(echo "$display_name" | cut -d "," -f1)
        # Remove the leading whitespace from given name
        printf -v full_name "%s %s" "${given_name## }" "$surname"
      else
        printf -v full_name "%s %s" "$given_name" "$surname"
      fi

      if [[ ${delete_inactive_date} > ${last_sign_in_date_time} ]] && [[ ${delete_inactive_date} > ${last_non_interactive_sign_in_date_time} ]]; then
         echo "Deleted user $full_name, last_sign_in=${last_sign_in_date_time}, last_non_interactive_sign_in=${last_non_interactive_sign_in_date_time}, max_inactive_date=${delete_inactive_date}"
#        delete_user "$object_id" "$mail" "$display_name" "$last_Sign_in_date_time" "$last_non_interactive_sign_in_date_time" "given_name" "$surname"
      else

        if [[ $last_sign_in_date_time != "null" ]] && [[ $(date +%s -d "$last_sign_in_date_time") > $(date +%s -d "$last_non_interactive_sign_in_date_time") ]]; then
          days_until_deletion=$(( "$delete_inactive_days" - (( $(date +%s) - $(date +%s -d "$last_sign_in_date_time") ) / 86400 + 1) ))

          if [[ "$days_until_deletion" -lt ${warn_inactive_days} ]]; then
            echo "User $full_name will be deleted in $days_until_deletion days, last_sign_in=${last_sign_in_date_time}, last_non_interactive_sign_in=${last_non_interactive_sign_in_date_time}, max_inactive_date=${delete_inactive_date}"
          fi
        elif [[ $last_non_interactive_sign_in_date_time != "null" ]] && [[ $(date +%s -d "$last_non_interactive_sign_in_date_time") > $(date +%s -d "$last_sign_in_date_time") ]]; then
          days_until_deletion=$(( "$delete_inactive_days" - (( $(date +%s) - $(date +%s -d "$last_non_interactive_sign_in_date_time") ) / 86400 + 1) ))
          if [[ $days_until_deletion -lt ${warn_inactive_days} ]]; then
            echo "User $full_name will be deleted in $days_until_deletion days, last_sign_in=${last_sign_in_date_time}, last_non_interactive_sign_in=${last_non_interactive_sign_in_date_time}, delete_date=${delete_inactive_date}"
          fi
        else
          echo "Error: Both sign in times are null for user $full_name"
        fi
      fi

#      node pipeline-scripts/sendMail.js "${mail}" "${full_name}"

    done <<< "$(jq -r '.[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'") | "\(.id) \(.mail) \(.signInActivity.lastSignInDateTime) \(.signInActivity.lastNonInteractiveSignInDateTime) \(.givenName) \(.surname) \(.displayName)"' ${users_file})"
    wait
  else
    echo "No inactive users found, nothing to do"
  fi
}


if [[ $branch == "master" ]]; then
    echo "Not deleting users temporarily see DTSPO-11798"
#   echo "Deleting users that haven't logged in for ${max_inactive_days} days"
#   delete_inactive_guests
#   echo "Users deleted"
else
  echo "Creating list of user that will be deleted when this script runs on the default branch"
  delete_inactive_guests
fi
