#!/bin/bash

sudo apt-get update


####################
# Install git
####################

sudo apt-get update
sudo apt-get install -y git
git --version


####################
# Install gawk
####################
sudo apt-get install -y gawk


####################
# Install docker
####################
# https://docs.docker.com/engine/install/ubuntu/

# 1. Update the apt package index and install packages to allow apt to use a repository over HTTPS:
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
    
# 2. Add Docker’s official GPG key:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# 3. Use the following command to set up the stable repository
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable" 
 
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo docker run hello-world

# 4. Post installation
# This step is required because otherwise we will need tu use sudo
# to build images, preventing `eval &(minikube docker-env)`
sudo groupadd docker
sudo usermod -aG docker ${USER}
newgrp docker # Activates changes of the groups. It allows to use docker without root, enabling `eval &(minikube docker-env)`
echo "newgrp docker # Activates changes of the groups. It allows to use docker without root, enabling \`eval &(minikube docker-env)\`" >> .bashrc

# Run local image registry
docker run -d -p 5000:5000 --restart=always --name registry registry:2


#####################################
# Install kubernetes (k3s & kubectl)
#####################################

# Enable container features in Kernel
sudo touch /boot/cmdline.txt

curl -sfL https://get.k3s.io | sh -
sudo kill -9 $(sudo lsof -t -i:6443)
sudo k3s server --write-kubeconfig-mode 664 &
sudo k3s kubectl get nodes

