#!/bin/bash
sleep 3
container=$(docker ps | grep blacklight_org_demo | head -1 | cut -d' ' -f1)
docker logs -f $container
