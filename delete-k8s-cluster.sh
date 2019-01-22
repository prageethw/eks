#!/bin/bash
cd cluster
source ./k8s-eks-cluster.temp
./eks-aws-prerequisite-cleanup.sh
./delete-eks.sh
