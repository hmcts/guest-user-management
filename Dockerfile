FROM ubuntu

RUN apt update && apt install ca-certificates curl apt-transport-https lsb-release gnupg curl jq vim nodejs npm -y
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

WORKDIR /data/pipeline-scripts