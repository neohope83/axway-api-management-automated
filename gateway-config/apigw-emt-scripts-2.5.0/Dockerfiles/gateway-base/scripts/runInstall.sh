#!/bin/sh

if [ $# -eq 0 ]
then
  echo "No API Gateway installer provided"
  echo "Usage: ./opt/runInstall.sh /opt/APIGateway_Install.run"
  exit 1
fi

#Get installer version from .run file ($1)
installerInfo="$(./"$1" --version)"
echo 'Provided installer version:'
echo "$installerInfo"
#Strip out "." ie 7.7.0 = 770
installerVersion=$(( $(echo "$installerInfo" | cut -c 19-23 | tr -d .) ))
#Strip out year ie 2020-01-30 = 2020
installerDate=$(( $(echo "$installerInfo" | cut -c 37-41) ))

disabled_components="analytics,policystudio,configurationstudio,qstart,cassandra,agentsConfiguration"
#Only add apitester to components in versions earlier than 7.7.2020
if [ $installerVersion -lt 770 ] || [ $installerDate -lt 2020 ]
then
  disabled_components=$("$disabled_components",apitester)
fi

echo 'Performing install steps...'
cd /opt && \
    ./APIGateway_Install.run \
        --acceptGeneralConditions yes \
        --mode unattended \
        --unattendedmodeui none \
        --setup_type complete \
        --prefix /opt/Axway/ \
        --firstInNewDomain 0 \
        --configureGatewayQuestion 0 \
        --nmStartupQuestion 0 \
        --enable-components nodemanager,apimgmt \
        --disable-components "${disabled_components}" \
        --startCassandra 0 && \
    rm -rf /opt/Axway/Axway-installLog.log \
        /opt/Axway/uninstall* \
        /opt/Axway/apigateway/upgrade \
        /opt/Axway/apigateway/docs \
        /opt/Axway/apigateway/agents \
        /opt/Axway/apigateway/Linux.x86_64/bin/wkhtmltopdf \
        /opt/Axway/apigateway/tools/filebeat* \
        /opt/Axway/apigateway/webapps/quickstart
