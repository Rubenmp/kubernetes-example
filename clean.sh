#!/bin/bash

git stash
sudo kubectl delete --all deployments
sudo kubectl delete --all services
yes | docker system prune -a
