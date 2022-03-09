#!/bin/bash
set -e

branch=$1

delete_user() {
  echo "Branch is $branch"
  if [[ $branch == "master" ]]; then
    echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
    # az ad user delete --id
  else
    echo "Plan: user ${3}, mail address ${2}, object ID ${1}"
  fi
}