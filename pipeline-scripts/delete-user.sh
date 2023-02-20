#!/bin/bash
set -e

branch=$1

delete_user() {

  if [[ $branch == "master" ]]; then
    echo "Not deleting"
      echo "Deleting user ${3} with the mail address of ${2} and object ID of ${1}"
     # TODO https://github.com/Azure/azure-cli/issues/12946#issuecomment-737196942
     # az ad user delete --id ${1}
     az rest --method DELETE --uri "https://graph.microsoft.com/v1.0/users/${1}"
  else
    echo "Plan: user ${3}, mail address ${2}, object ID ${1}"
  fi
}
