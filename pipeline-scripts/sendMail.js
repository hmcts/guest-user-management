const commandArgs = process.argv.slice(2)
const emailAddress = commandArgs[0]
const name = commandArgs[1]
const apiKey = commandArgs[2]

const NotifyClient = require('notifications-node-client').NotifyClient;
const notifyClient = new NotifyClient(apiKey);

const templateId = "b0c88c5b-76c3-4c17-9db4-63017e0f9a21"
const azurePortalURL = "https://portal.azure.com/hmcts.net"

let personalisation = {
        'name': name,
        'url': azurePortalURL,
        'email': emailAddress
}


console.log(name, azurePortalURL, emailAddress)
notifyClient
    .sendEmail(templateId, "matt.slater@justice.gov.uk", {
        personalisation: personalisation,
        reference: null,
        emailReplyToId: "7bb0ab72-86ca-4f88-88f9-e9293dd37cb2"
    })
    .then(response => console.log(response))
    .catch(err => console.error(err))