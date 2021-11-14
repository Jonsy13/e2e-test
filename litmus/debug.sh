#!/bin/bash

namespace=${1}
for i in {1..20}
do
echo -e "---------------------------------------------------\n" >> debugFile.txt

echo -e "Pods Status in ${namespace} at ${i} minute(s)\n" >> debugFile.txt
kubectl get pods -n ${namespace} >> debugFile.txt

echo -e "\nNodes Status at ${i} minute(s)\n" >> debugFile.txt
kubectl top nodes >> debugFile.txt

echo -e "\n---------------------------------------------------\n" >> debugFile.txt
sleep 1m
done
