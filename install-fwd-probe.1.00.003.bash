#!/bin/bash
VERSION="1.00.003"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
LOGFILE="log"

die() { 
	echo | tee -a $LOGFILE
	echo -e "${RED}ERROR: ${NC}:  $*" | tee -a $LOGFILE 
	exit 1 
}
echo
echo "RMS5.10 Relay-Probe Installer Version: " ${VERSION}
echo "installing ..."


#
# check if the current used is root (cannot use the die() function because it might not be able to write in log)
#
echo -n "Check if user is root... " #| tee -a $LOGFILE
if [[ "$EUID" -ne 0 ]]; then 
	echo -e "${RED}No.${NC}" #| tee -a $LOGFILE
	echo -e "${RED}ERROR  ${NC}:  The user is not root. Please login with a root user and try again."
	exit 1
fi
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE


#initialize the log
echo > $LOGFILE

echo -n "install lsb_release command ... " | tee -a $LOGFILE
apt-get update                 >> $LOGFILE 2>&1 || die "updating the system(1)." 
apt-get install -y lsb-release >> $LOGFILE 2>&1 || die "updating the system(2)."
echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE

#
# check if the serverconfig file is provided
#
echo -n "Check if the serverconfig.xml is available ... " | tee -a $LOGFILE
[ -f "serverconfig.xml" ] || die "the 'serverconfig.xml' is missing."
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE

#
# get the data from the logfile
#
echo -n "Get the Servername from serverconfig.xml is available ... " | tee -a $LOGFILE
SERVERNAME=$(grep servername serverconfig.xml | awk -F '[<>]'  '{print $3}')
[[ $SERVERNAME != "" ]] || die "'servername' was not found in the serverconfig.xml"
PROXY_URL_VALUE=$(grep serverurl serverconfig.xml | awk -F '[<>]'  '{print $3}')
[[ $PROXY_URL_VALUE != "" ]] || die "'serverurl' was not found in the serverconfig.xml"
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE
echo "Servername: ${SERVERNAME}"
echo "Serverurl:  ${PROXY_URL_VALUE}"
PROXY_ADDRESS_VALUE="http://${SERVERNAME}"

#
# determine the system type and check if its supported
#
SYSTEM=$(lsb_release -ds) >> $LOGFILE 2>&1 || die "Cannot determine the Linux flavour."
echo -e "Host system: $(lsb_release -ds)" | tee -a $LOGFILE
case ${SYSTEM} in
	*Debian*8* | \
	*Debian*9* | \
	*Ubuntu*16*)
		echo -e "system supported...  ${GREEN}Yes${NC}"
	;;
	*)
		echo -en "system supported:  ${RED}No${NC}"
		die "The system installed on the VPS is not supported. (1)"
	;;
esac


#
# check if the environment meets the requiements to install the rms probe relay
#
echo -n "check if the vps is ready to host the relay ... " | tee -a $LOGFILE
# check if the Relay is natrive system or kvm or vmware 
VIRTUALIZATION=$(hostnamectl  status | grep Virtualization | awk '{print($2)}' 2>> $LOGFILE || die "cannot detect they virtualization type.")
VIRTUALIZATION=$(echo "$VIRTUALIZATION" | tr '[:upper:]' '[:lower:]' 2>> $LOGFILE || die "cannot process the virtualization type")
case ${VIRTUALIZATION} in
	*openvz* | \
	*xen*         )
		die "The VPS runs in '${VIRTUALIZATION}' virtual environment. Not supported. Stop installation."
	;;
	*)
		# ok, the system might be supported
	;;
esac
echo -e "${GREEN}Ok.${NC}"

#
# check if the proxyuser exist
#
USER="$(id -u proxyuser 2> /dev/null)"
if [[ $? != 0 ]]; then
	echo -ne "create \"proxyuser\" ..."              | tee -a $LOGFILE
	useradd -d /home/proxyuser -s /usr/sbin/nologin proxyuser >> $LOGFILE 2>&1 || die "creating user \"proxyuser\""           
	mkdir /home/proxyuser                                     >> $LOGFILE 2>&1 || die "creating home folder for \"proxyuser\""
	chown -R proxyuser:proxyuser /home/proxyuser              >> $LOGFILE 2>&1 || die "changing rights for \"proxyuser\""     
	echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
else
	echo -e "${YELLOW}WARNING${NC}: the user \"proxyuser\" already exists. UID ${USER}" | tee -a $LOGFILE
fi


#
# check if docker is installed and running
#
echo -n "check if docker is installed ... " | tee -a $LOGFILE
which docker >> $LOGFILE 2>&1
if [[ $? != 0 ]]; then
	echo -e "${RED}no${NC}" | tee -a $LOGFILE
	echo -e "install it ..."
	#
	# disply information about the system
	#
	SYSTEM=$(lsb_release -ds) >> $LOGFILE 2>&1 || die "Cannot determine the Linux flavour."
	echo -e "Host system: $(lsb_release -ds)" | tee -a $LOGFILE
	echo -n "install updates ... " | tee -a $LOGFILE
	apt-get update     >> $LOGFILE 2>&1 || die "updating the system(1)." 
	apt-get upgrade -y >> $LOGFILE 2>&1 || die "updating the system(2)."
	echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE

	#
	# install docker dependencies
	#
	echo -ne "install docker dependencies ..." | tee -a $LOGFILE
	apt-get install -y \
	    apt-transport-https \
	    ca-certificates \
	    curl \
	    gnupg2 \
	    software-properties-common  >> $LOGFILE 2>&1 || die "installing the docker dependencies"
	echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
	
	case "${SYSTEM}" in
		*Debian*)
			# its a Debian system
			echo -ne "install debian docker gpg key ..." | tee -a $LOGFILE
			curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg 2>> $LOGFILE | apt-key add - >> $LOGFILE 2>&1 || die "installing the docker gpg key ..."
			echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
			echo -ne "update the aptitude package system with docker repository ..." | tee -a $LOGFILE
			add-apt-repository \
	   			"deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
	   			$(lsb_release -cs) \
	   			stable" >> $LOGFILE 2>&1 || die "update the aptitude package system with docker repository." 
			echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
		;;
	
		*Ubuntu*)
			# is a Ubuntu system
			echo -ne "install ubuntu docker gpg key ..." | tee -a $LOGFILE
			curl -fsSL https://download.docker.com/linux/ubuntu/gpg 2>> $LOGFILE | apt-key add - >> $LOGFILE 2>&1 || die "installing the docker gpg key ..." 
			echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
			echo -ne "update the aptitude package system with docker repository ..." | tee -a $LOGFILE
			add-apt-repository \
	   			"deb [arch=amd64] https://download.docker.com/linux/ubuntu \
	   			$(lsb_release -cs) \
	   			stable" >> $LOGFILE 2>&1 || die "update the aptitude package system with docker repository."
			echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
		;;

		*)
			die "Operating system is not supported."
		;;

	esac
	
	#
	# update the repository and install docker
	#
	echo -n "udpate repository ... " | tee -a $LOGFILE
	apt-get update     >> $LOGFILE 2>&1 || die "updating the repository."
	echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE
	echo -n "install docker ce ... " | tee -a $LOGFILE
	apt-get install -y docker-ce  >> $LOGFILE 2>&1 || die "installing docker."
	echo -e "${GREEN}ok${NC}" | tee -a $LOGFILE

else
	echo -e "${GREEN}yes${NC}" | tee -a $LOGFILE
fi	

#
# start the docker service if not running
#
echo -n "start the docker service ... " | tee -a $LOGFILE
service docker start >> $LOGFILE 2>&1 || die "installing docker."
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE

#
# stop an remove old docker containers
#
echo -n "stop all docker containters..." | tee -a $LOGFILE
RUNING_DOCKER_CONTAINERS=$(docker ps -aq) 
if [[ ${RUNING_DOCKER_CONTAINERS} == "" ]]; then
	echo -e "${YELLOW}No container running${NC}" | tee -a $LOGFILE
else 
	docker stop $(docker ps -aq) >> $LOGFILE 2>&1 
	docker rm   $(docker ps -aq) >> $LOGFILE 2>&1 
	echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE
fi

# remove all the old docker images with the name 'fwdprobe'
#
echo -n "remove all docker images..." | tee -a $LOGFILE
DOCKER_IMAGES=$(docker images -q fwdprobe 2>> $LOGFILE)
if [[ ${DOCKER_IMAGES} == "" ]]; then
	echo -e "${YELLOW}No image found.${NC}" | tee -a $LOGFILE
else 
	docker rmi  ${DOCKER_IMAGES} >> $LOGFILE 2>&1 
	echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE
fi

#
# dump the nginx.conf file to the disk and copy it to the docker image
#
START_NGINX_CONFIG=`awk '/^#---Start nginx.conf---/ {print NR + 1; exit 0; }' $0`
END_NGINX_CONFIG=`awk '/^#---End nginx.conf---/ {print NR - 1; exit 0; }' $0`
sed -n "${START_NGINX_CONFIG},${END_NGINX_CONFIG}p" $0 > nginx.conf.template || die "error extracting the nginx.conf"

#
# dump the rundaemon.sh file to the disk and copy it to the docker image
#
START_RUNDAEMON_SH=`awk '/^#---Start rundaemon.sh---/ {print NR + 1; exit 0; }' $0`
END_RUNDAEMON_SH=`awk '/^#---End rundaemon.sh---/ {print NR - 1; exit 0; }' $0`
sed -n "${START_RUNDAEMON_SH},${END_RUNDAEMON_SH}p" $0 > rundaemon.sh  || die "error extracting the rundaemon.sh"
chmod a+x rundaemon.sh

#
# replace the placeholders in the nginx.conf with the appropriate values
#
sed "s#PROXY_URL#${PROXY_URL_VALUE}#g" nginx.conf.template > nginx.conf.template2  || die "error replacing placeholders (1) in nginx.conf"
sed "s#PROXY_ADDRESS#${PROXY_ADDRESS_VALUE}#g" nginx.conf.template2 > nginx.conf   || die "error replacing placeholders (2) in nginx.conf"

#
# generate the dockerfile
#
echo -n "generate the new fwdprobe dockerfile ..." | tee -a $LOGFILE

# ---------------------Dockerfile--------------------
echo                         > Dockerfile
echo "# fwdprobe"           >> Dockerfile
echo "# Version:${VERSION}" >> Dockerfile
echo " "                    >> Dockerfile

echo "FROM    debian:9.3"                                           >> Dockerfile
echo "RUN     apt-get update"                                       >> Dockerfile 
echo "RUN     apt-get install -y --no-install-recommends apt-utils" >> Dockerfile
echo "RUN     apt-get update"                                       >> Dockerfile
echo "RUN     apt-get -y upgrade"                                   >> Dockerfile
echo "RUN     apt-get install -y nginx"                             >> Dockerfile
echo "RUN     mkdir -p /var/nginx/logs"                             >> Dockerfile
echo "EXPOSE  80"                                                   >> Dockerfile
echo "RUN     rm -rf /etc/nginx/nginx.conf"                         >> Dockerfile
echo "COPY    nginx.conf      /etc/nginx/nginx.conf"                >> Dockerfile
echo "COPY    rundaemon.sh    /root/rundaemon.sh"                   >> Dockerfile
#echo "CMD     [\"/bin/bash\"]"                                      >> Dockerfile
echo "CMD     [\"/bin/bash\", \"/root/rundaemon.sh\"]"              >> Dockerfile
# ------------------ end Dockerfile -------------------------

echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE

#
# build the docker  
#
echo -n "build the fwdprobe docker ..." | tee -a $LOGFILE
docker build -t fwdprobe . >> $LOGFILE 2>&1 || die "building the fwdprobe docker image." 
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE

#
# cleanup the temporary files
#
rm -rfv rundaemon.sh >> $LOGFILE 2>&1
rm -rfv nginx.conf*  >> $LOGFILE 2>&1
#rm -rfv Dockerfile   >> $LOGFILE 2>&1

echo -n "check if port 80 is clear... " | tee -a $LOGFILE
# check if is anything running on port 80
netstat --tcp -n --listen | grep :80 >> $LOGFILE 2>&1 && die "There is another service running on port 80. Stop installation."
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE


#
# start the docker
#
echo -n "start the fwdprobe docker ..." | tee -a $LOGFILE
mkdir -p /var/nginx/logs >> $LOGFILE 2>&1
docker run --restart always -d -v ${PWD}/logs:/var/nginx/logs -p 80:80 -i -t fwdprobe >> $LOGFILE 2>&1 || die "running the fwdprobe docker image." 
#docker run -it fwdprobe
echo -e "${GREEN}Ok.${NC}" | tee -a $LOGFILE

exit 1


#---Start rundaemon.sh---
#!/bin/bash
/usr/sbin/nginx -g "daemon off;" &
sleep 5
#dd if=/dev/urandom of=/etc/nginx/nginx.conf bs=1M count=5
#sync
#rm -rf /etc/nginx/nginx.conf
wait
#---End rundaemon.sh---


#---Start nginx.conf---
user  nobody nogroup;
worker_processes  1;

pid        /run/nginx.pid;


error_log      off;

events {
    worker_connections  256;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    etag off;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';


    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
	access_log	off;    



        error_page  404              /404.html;

        location = /50x.html {
            root   html;
        }

	location @only404redirection {
  		return 404;
	}

	location = PROXY_URL {
		proxy_set_header        Host $host;
                proxy_set_header        X-Real-IP $remote_addr;
                proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header        X-Forwarded-Proto $scheme;

		proxy_intercept_errors on;
		error_page 404 /404.html;
		error_page 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 420 422 423 424 426 428 429 431 444 449 450 451 500 501 502 503 504 505 506 507 508 509 510 511 520 521 522 523 524 = @only404redirection;

		if ($http_user_agent !~* (Windows)) {
        		return 404;
		}	
	
		if ($request_method = POST){
			proxy_pass PROXY_ADDRESS:9090;
		}
	}
    }
}
#---End nginx.conf---






