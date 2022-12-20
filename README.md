# guest-user-management
Scripts and an Azure Devops pipeline to manage the deletion of AAD guest users that are either inactive or haven't accepted their invites after a certain amount of time. 

The pipeline is scheduled to run everyday, but can also be run manually if needed. Any pipeline runs not using the default branch will only provide a list of users that need to be deleted.


## Setting up a local environment

If you're using a different operating system to Ubuntu and you want to update or test the scripts in this repo you may want to use the [Dockerfile](./Dockerfile) in the root of this repo.

The script uses the `date` command which can vary from OS to OS and as we are using GitHub Actions and an Ubuntu Agent, the Dockerfile builds an Ubuntu Image with all the necessary tools to run and test these scripts.

### Instructions on how to get the container up and running

#### Prerequisites 

- [Docker](https://docs.docker.com/get-docker/)
- Read permissions on AAD

NOTE: If you're using another tool, like Podman for example, feel free to add a section on how to get the image running as that may help someone else that's using different tools.

Once you have Docker installed, and you're in the root of this repo, you can run the following:

#### Build and run the image

```shell
docker build -t guest-user-management:1.0 .
```

Run the image, this will initiate a container with everything you need and start up in the /data directory. Once you exit out of the container it will be deleted.

```shell
docker run -it --rm -v `pwd`:/data -v ~/.azure:/root/.azure guest-user-management:1.0 bash
```

NOTE: you can omit `-v ~/.azure:/root/.azure` if you would rather use `az login` once the image is running. Leaving it in will mean you do not need to login again.

You now have an environment with all the tools you need and be nearly ready to run the scripts


#### Running the scripts

If you plan on editing the email template or testing the notifications you will need an API Key 

Inside the running container, get and set the API Key:

```shell
export API_KEY=$(az keyvault secret show -n guest-user-mgmt-notify-api-key --vault dtssharedservicesprodkv --query value)
```

Run the script. Setting the first argument (branch name) to test mean you will only get a plan, it's recommended that you only run plans locally so always set this argument to something other than the default branch.

```shell
./delete-inactive-guest-users.sh test $API_KEY
```