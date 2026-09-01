# Jenkins Docker

* Jenkinsfile builds and pushes a base hardened image based on the default docker jenkins image
* Default docker image can be found here - https://github.com/jenkinsci/docker
* Dockerfile is for the image to run in the cluster. We need to override ENTRYPOINT / COMMAND because the hardening process inserted /bin/bash in the args so it does not run and add further configuration

## init.d Scripts

Some scripts are prepended with a number, this is so that they are executed first.  
".override" is appended to the scripts in order to ensure that they overwrite what is currently in Jenkins Home when the instance is restarted:  
https://github.com/jenkinsci/docker#script-usage