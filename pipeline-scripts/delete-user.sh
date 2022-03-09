#!/bin/bash
set -e

branch=$1

delete_user() {

  if [[ $branch == "master" ]]; then
    echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
     az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/users/${1}"
  else
    echo "Plan: user ${3}, mail address ${2}, object ID ${1}"
  fi
}
