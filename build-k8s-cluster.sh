#!/bin/bash
if [[ -z "${MY_ORG_DNS_NAME}" && -z "${MAX_NODE_COUNT}" && -z "${BASIC_AUTH_PWD}" &&  -z "${NAME}" ]]; then

    echo "You need to specify MY_ORG_DNS_NAME , MAX_NODE_COUNT , BASIC_AUTH_PWD and NAME at minimum"
    exit
fi

cd cluster
./eks-aws-prerequisite.sh
./cluster-setup.sh
