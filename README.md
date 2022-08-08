# Kubernetes example

Repository for a front-end + back-end + database Kubernetes deployment for a personal project 'NoQ'.
Main characteristics of this example:
- File 'deploy.sh' allows to deploy into staging or production environment
- Local docker image registry to allow quick rollback to previous versions if there is any issue.
- Kubernetes secrets to store passwords as safe environment variables inside the containers.
- File 'configure_server.sh' contains a basic script to configure the server.

In the Kubernetes files, there are patterns like '\<\<ENVIRONMENT\>\>' that will change dynamically depending on the desired environment to deploy. It is done like this because my religion does not allow me to use Helm (I might change my opinion in the future).

I strongly recommend these videos to learn Kubernetes:
- https://www.youtube.com/watch?v=aPzpsfQtlKY&t=9s&ab_channel=TechnoTownTechie
- https://www.youtube.com/watch?v=X48VuDVv0do&ab_channel=TechWorldwithNana


# Initial server setup

In the server, VT-x or AMD-v virtualization must be available. The output of this command should be not empty:

```
$ egrep --color 'vmx|svm' /proc/cpuinfo
```

and then we can run
```
$ ./configure_server.sh
```
This script will install [*git*](https://git-scm.com/), [node](https://nodejs.org/en/), [*docker*](https://www.docker.com/) (allowing docker usage without root privileges), and [*k3s*](https://k3s.io/) (hence [kubectl](kubernetes.io)). It will also create local container images registry in **localhost:5000**.


# Deployment procedure
This procedure will update the docker image which is running in *staging/production*.
- *Staging* is the previous step to production. New features and bug fixing must be tested in staging.
- *Production* is the environment where the app is running. The client's data will be stored here.


## Basic explanation
Run script *./deploy.sh*.

```
./deploy.sh <ENVIRONMENT> <BACK_END_VERSION> <FRONT_END_VERSION>
```

Example:
```
./deploy.sh STAGING v1.0.0 v1.0.0
```

## Extended explanation

First, our deployment script will build front-end (and back-end) image(s),
```
$ sudo docker build -t <app-name>:<tag> .
```
where \<tag\> could be something like 'v1.0.0'. The new image will be tagged and pushed to the configured local registry.

```
$ docker tag <app-name> localhost:5000/<app-name>
$ docker push localhost:5000/<app-name>
```
where 5000 is the port of the image registry previously configured.

Depending on the \<ENVIRONMENT\> variable, yml files will be modified according to the configuration of the environment and deployments will be created:

```
$ cd kubernetes
$ sudo kubectl apply -f mysqldb-root-credentials.yml
$ sudo kubectl apply -f mysqldb-credentials.yml
$ sudo kubectl apply -f mysql-configmap.yml
$ sudo kubectl apply -f mysql-deployment.yml
$ sudo kubectl apply -f back-deployment.yml
$ sudo kubectl apply -f front-deployment.yml
```

Service URLs can be checked with the command:
```
$ sudo kubectl get svc
NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes                 ClusterIP   10.43.0.1       <none>        443/TCP          18m
db-staging                 ClusterIP   None            <none>        3306/TCP         17m
noq-back-end-staging       NodePort    10.43.174.159   <none>        8080:31002/TCP   17m
noq-front-end-staging      NodePort    10.43.202.0     <none>        80:31001/TCP     17m
```

### Example: we want to get the URL of service *angular-k8s-service*.

The cluster-ip is the URL inside the cluster, K3s does not use a virtual machine. The port(s) column refers to \<port\>\<nodePort\>/\<protocol\>. If we are inside the Kubernetes cluster we can check the deployment in URL:\<port\> (in this case, *10.43.82.241:80*).
- \<port\>\ is the port where the container is running
- \<nodePort\> is the port that will be available from the internet.

## Troubleshooting problems
We can check deployment errors checking the logs:
```
$ sudo kubectl get pods
$ sudo kubectl logs -f <pod>
```

## Update password of secrets
Use this command to generate base64 encrypted strings to include in Kubernetes secrets (i.e. mysqldb-credentials.yml):
```
$ echo -n 'test' | base64
```

## Connection to database
Once we are connected to the Kubernetes server the database pod can be found using:
```
$ sudo kubectl get pods
NAME                                      READY   STATUS    RESTARTS   AGE
mysql-795b8d8fbb-ldx7d                    1/1     Running   1          81m
```

We can connect to desired database pod using the pod name:
```
$ sudo kubectl exec --stdin --tty mysql-795b8d8fbb-ldx7d -- /bin/bash
```

After this, we can connect to the database using the username and password stored in Kubernetes secrets
```
$ mysql -u<user> -p<password>
mysql> USE <database_name>;
```

TLDR: Hacky way to connect to the database pod
```
$ sudo kubectl exec --stdin --tty `sudo kubectl get pods | grep mysql | awk {'print $1'}` -- /bin/bash
```
we should improve grep command to select staging/production database.

