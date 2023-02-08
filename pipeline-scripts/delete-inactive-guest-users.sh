#!/bin/bash
#set -e

cd "$(dirname "$0")" || exit 1

if [[ $(uname) == "Darwin" ]]; then
  shopt -s expand_aliases
  alias date="gdate"
fi

branch=$1
notify_api_key=$2

pipeline_scheduled_run_time="02:00"

# Number of days before deletion date that a user will start getting notified about being deleted
warn_inactive_days=7

# Number of days a user can be inactive before being deleted
delete_inactive_days=31

# Number of days old that an account has to be before being processed for activity
min_user_age_days=7

max_inactive_days=$((${delete_inactive_days} - ${warn_inactive_days}))
max_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${max_inactive_days} days ago")

delete_inactive_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${delete_inactive_days} days ago")

min_user_age_date=$(date +%Y-%m-%dT%H:%m:%SZ -d "${min_user_age_days} days ago")

echo "warning_date=${max_inactive_date}"
echo "delete_inactive_date=${delete_inactive_date}"
echo "min_user_age_date=${min_user_age_date}"

users_file=guests.json

. delete-user.sh "${branch}"

most_recent_login() {
  local most_recent_login_date

  # Take both login times check which one is the most recent and work with that
  if [[ $1 == "null" ]] && [[ $2 == "null" ]]; then
    most_recent_login_date="null"
  elif [[ $1 == "null" ]]; then
    most_recent_login_date=$2
  elif [[ $2 == "null" ]]; then
    most_recent_login_date=$1
  else
    most_recent_login_date=$([[ "$1" > "$2" ]] && echo "$1" || echo "$2")
  fi

  echo "${most_recent_login_date}"
}

set_full_name() {
  local display_name=$1
  local given_name=$2
  local surname=$3
  local full_name=
  # Use display name if given and surname aren't set
  if [[ ${given_name} == "null" ]] || [[ ${surname} == "null" ]]; then
    given_name=$(echo "$display_name" | cut -d "," -f2 )
    surname=$(echo "$display_name" | cut -d "," -f1)
    # Remove the leading whitespace from given name
    full_name=$(printf "%s %s" "${given_name## }" "$surname")
  else
    full_name=$(printf "%s %s" "$given_name" "$surname")
  fi

  echo "${full_name}"
}

get_user_sign_in_activity() {
  local sign_in_activity
  local last_non_interactive_sign_in_date_time_retry
  local last_sign_in_date_time_retry
  local most_recent_login_date_retry

  sign_in_activity=$(az rest --method get --uri "https://graph.microsoft.com/beta/users/${object_id}?select=signInActivity")

  last_non_interactive_sign_in_date_time_retry=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${sign_in_activity}")
  last_sign_in_date_time_retry=$(jq -r .signInActivity.lastSignInDateTime <<< "${sign_in_activity}")

  most_recent_login_date_retry=$(most_recent_login "${last_sign_in_date_time_retry}" "${last_non_interactive_sign_in_date_time_retry}")

  echo "${most_recent_login_date_retry}"
}

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

if [[ "${inactive_users_count}" == 0 ]]; then
  echo "No inactive users found"
  exit 0
fi

####
# Loop through users
# Delete inactive users
# Send notifications to users close to being deleted
####

jq -c '.[] | select(.signInActivity.lastSignInDateTime < "'${max_inactive_date}'" and .signInActivity.lastNonInteractiveSignInDateTime < "'${max_inactive_date}'")' ${users_file} | while read -r user; do

  object_id=$(jq -r ".id" <<< "${user}")
  display_name=$(jq -r ".displayName" <<< "${user}")
  given_name=$(jq -r ".givenName" <<< "${user}")
  surname=$(jq -r ".surname" <<< "${user}")
  mail=$(jq -r ".mail" <<< "${user}")

  # Set full name of user given_name adn surname will be used if neither are null
  formatted_name=$(set_full_name "${display_name}" "${given_name}" "${surname}")

  last_sign_in_date_time=$(jq -r .signInActivity.lastSignInDateTime <<< "${user}")
  last_non_interactive_sign_in_date_time=$(jq -r .signInActivity.lastNonInteractiveSignInDateTime <<< "${user}")

  most_recent_login_date=$(most_recent_login "${last_sign_in_date_time}" "${last_non_interactive_sign_in_date_time}")


  if [[ "${most_recent_login_date}" == "null" ]] || [[ "${most_recent_login_date}" == "" ]]; then
    days_until_deletion="-100"
  else
    days_until_deletion=$(( ${delete_inactive_days} - (( $(date +%s) - $(date +%s -d "${most_recent_login_date}")) / 86400 + 1) ))
  fi

  if [[ "${days_until_deletion}" -lt "0"  ]]; then
    sign_in_activity_counter=0
    most_recent_login_date_retry=

    until [[ ${sign_in_activity_counter} == 2 ]] ||  [[ ( "${most_recent_login_date_retry}" != "null" && "${most_recent_login_date_retry}" > "${most_recent_login_date}")  ]]  ; do

      most_recent_login_date_retry=$(get_user_sign_in_activity "${object_id}")

      if [[ "${most_recent_login_date_retry}" == "" ]]; then
        most_recent_login_date="0001-01-01T00:00:00Z"
        break
      fi

      if [[ "${most_recent_login_date_retry}" != "null" ]] && [[ "${most_recent_login_date_retry}" != "" ]] && [[ "${most_recent_login_date_retry}" > "${most_recent_login_date}"  ]]; then
        most_recent_login_date="${most_recent_login_date_retry}"
        days_until_deletion=$(( "${delete_inactive_days}" - (( $(date +%s) - $(date +%s -d "${most_recent_login_date_retry}")) / 86400 + 1) ))
        break
      fi

      sign_in_activity_counter=$(( sign_in_activity_counter + 1 ))
      sleep 2
    done
  fi

  if [[ "${most_recent_login_date}" == "null" ]]; then
    printf "Sign in activity is null for user %s with Object ID of %s. Please re-run the pipeline or manually check user.\n" "${formatted_name}" "${object_id}"
    continue
  fi

  if [[ "${days_until_deletion}" -lt "0"  ]]; then

    if [[ "${branch}" =~ ^(main|master)$ ]]; then
      if [[ "${most_recent_login_date}" == "0001-01-01T00:00:00Z" ]]; then
        printf "Deleting user %s as it looks like the user hasn't logged in and their account is older than %s days\n" "${formatted_name}" "${min_user_age_days}"
      else
        printf "Deleting user %s as the last login recorded was %s and that is more than %s days ago. Object ID %s\n" "${formatted_name}" "${most_recent_login_date}"  "${delete_inactive_days}" "${object_id}"
      fi

      role_assignments=$(az rest --method get --uri "https://graph.microsoft.com/beta/roleManagement/directory/transitiveRoleAssignments?\$count=true&\$filter=principalId eq '$object_id'" --headers='{"ConsistencyLevel": "eventual"}')

      echo "$role_assignments"

      echo "Deleting roles assigned to user"
      jq -c '.value[]' | while read -r ra; do
        role_assignment_id=$(jq -r ".id" <<< "${ra}")
        principal_id=$(jq -r ".principalId" <<< "${ra}")

        echo "role_assignment_id: $role_assignment_id"
        echo "principal_id: $principal_id"

        if [[ ${principal_id} == "${object_id}" ]]; then
          # Delete role assignment if it's a direct assignment
          az rest --method delete --uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments/$role_assignment_id"

        else
          # Remove user from group if assignment isn't a direct one
          printf "Removing user %s from group %s\n" "${object_id}" "${principal_id}"
          az ad group member remove --group "${principal_id}" --member-id "${object_id}"
        fi

      done

      sleep 5
      # Delete user
      echo "Deleting user"
      az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/users/${object_id}" || echo "Error deleting user ${display_name}"

    else
      if [[ "${most_recent_login_date}" == "0001-01-01T00:00:00Z" ]]; then
        printf "Deleting user %s as it looks like the user hasn't logged in and their account is older than %s days\n" "${formatted_name}" "${min_user_age_days}"
      else
        printf "Plan: User %s hasn't logged in for %s days and will be deleted. The last login recorded was %s\n" "${formatted_name}" "${delete_inactive_days}" "${most_recent_login_date}"
      fi
    fi
  elif [[ "${days_until_deletion}" =~ ^(1|3|5|7)$ ]]; then
    # Set log in by date
    log_in_by_date=$(date "+%d-%m-%Y ${pipeline_scheduled_run_time}" -d "${most_recent_login_date} + ${delete_inactive_days} days")

    # Check email isn't null
    if [[ "${mail}" == "null" ]]; then
      printf "No email address found for user %s. PLease re-run the pipeline or check the user manually\n" "${formatted_name}"
      continue
    fi

    if [[ "${branch}" =~ ^(main|master)$ ]]; then
      printf "Sending warning notification %s: last_login=%s, days_until_deletion=%s, log_in_by_date=%s\n" "${formatted_name}" "${most_recent_login_date}" "${days_until_deletion}" "${log_in_by_date}"

      # Send warning notification
      node sendMail.js "${mail}" "${formatted_name}" "${notify_api_key}" "${days_until_deletion}" "${delete_inactive_days}" "${log_in_by_date}" > /dev/null
    else
      printf "Plan: Warning notification will be sent to %s when this pipeline runs on the default branch: last_login=%s, days_until_deletion=%s, log_in_by_date=%s\n" "${formatted_name}" "${most_recent_login_date}" "${days_until_deletion}" "${log_in_by_date}"
    fi

  elif [[ "${days_until_deletion}" =~ ^(2|4|6)$ ]]; then
    # Set log in by date
    log_in_by_date=$(date "+%d-%m-%Y ${pipeline_scheduled_run_time}" -d "${most_recent_login_date} + ${delete_inactive_days} days")

    printf "Plan: Will not send warning as notifications are sent 1,3,5 and 7 days before deletion. %s has %s days to log in: last_login=%s, log_in_by_date=%s\n" "${formatted_name}" "${days_until_deletion}" "${most_recent_login_date}" "${log_in_by_date}"

  fi

  # mitigate issues with request limits and throttling
  sleep 3
done
