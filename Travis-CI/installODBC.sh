#!/bin/bash

sudo curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -

#Download appropriate package for the OS version
#Choose only ONE of the following, corresponding to your OS version

#Ubuntu 16.04
sudo curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list > /etc/apt/sources.list.d/mssql-release.list

#Update and install 
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install msodbcsql17

# optional: for bcp and sqlcmd
sudo ACCEPT_EULA=Y apt-get install mssql-tools
