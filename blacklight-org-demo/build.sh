#!/bin/bash
name="blacklight_org_demo"
container=$(docker ps | grep $name | head -1 | cut -d' ' -f1)
if [ -n "$container" ]
then
    echo "Killing existing container $container"
    docker kill $container
    sleep 1
fi

docker build --pull --tag $name .
