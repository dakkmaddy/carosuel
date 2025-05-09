#!/bin/bash
#
startdelay() {
# The purpose of this function is to randomize the daily start of the carosuel
od -An -N2 -i /dev/urandom | awk '{print $1 % 33}' > /tmp/snooze.txt
initialdelay=$(cat /tmp/snooze.txt)
sleep $initialdelay
rm /tmp/snooze.txt
}

cleandockers() {
# Purpose of this function is to completely purge the dockers.
echo "[-] Removing all previous dockers!"
docker system prune -a -f
}
sleeper() {
        # The purpose of this function is to randomize the time each docker is up
        napper=3600
        od -An -N2 -i /dev/urandom | awk '{print $1 % 10800}' > /tmp/snooze.txt
        snooze=$(cat /tmp/snooze.txt)
        rm /tmp/snooze.txt
        totalsleep=$(( $snooze + $napper ))
        echo "[-] Snoozing $snooze + standard hour = $totalsleep docker time up for today's carosuel"
        sleep $totalsleep
}
checkmidnight() {
# If the hour is 23, and the minute is > 57, this function runs to set the hour to 0
# Otherwise, it sets to 24
        if [ $thishour = "23" ]
        then
                thishour="0"
        fi
}
getcontainerid() {
# The purpose of this function is to get the container name for copy/start/stop commands
        cid=$(docker ps -a | head -n 2 | tail -n 1 | awk '{print $1}')
}
timestamp() {
#Simple function to assign time variables. These will be used to control tcpdump in crontab and rename log files
thisminute=$(date +%M)
thishour=$(date +%H)
filetime=$(date +%Y_%m_%d_%H)
# Korn
rightnow=$(date +%Y-%m-%d)
}
starttcpdump(){
#This function echos tcpdump into /etc/crontab to support modbus pcap
#tcpdump is hard to start in script or background
#Only way I can figure this out is to dynamicly edit the crontab
#Grab variables for the current minute and hour for crontab
timestamp
# If time is within last 2 minutes of the hour, have to account in crontab echo by adjusting variables
if [ $thisminute = "58" ]
then
        thishour=$(( $thishour + 1 ))
        plus2mins="0"
        checkmidnight
elif [ $thisminute = "59" ]
then
        thishour=$(( $thishour + 1 ))
        plus2mins="1"
        checkmidnight
else
        # It is 57 mins or less past the hour, the current hour and two minutes will work
        plus2mins=$(( $thisminute + 2 ))
fi
filename="$app_$filetime.pcap"
echo "[-] Manipulating crontab ... crontab will execute at $plus2mins past the hour"
/bin/cp /etc/crontab /root/crontab.bak
echo "$plus2mins $thishour * * * root /usr/bin/tcpdump -A -v port 502,6379 -w /tmp/$filename" >> /etc/crontab
/bin/cp /etc/crontab /root/crontab.errorcheck
echo "[-] Sleeping an extra two mins so the crontab will definitely trigger with new tcpdump command"
sleep 120
echo "[-] Sleep complete, tcpdump should be running and capturing port 502 for Modbus"
}
stoptcpdump() {
# This function stops tcpdump and reverts the crontab to the original file.
kill $(ps -e | pgrep tcpdump);
# Editing crontab only supports modbus honeypot and tcpdump, we can revert crontab
echo "[-] Reverting crontab"
/bin/mv /root/crontab.bak /etc/crontab
echo "[-] Moving pcap to tftp server"
movepcaps
echo "[-] pcap move complete"
}
movepcaps() {
# Moving the pcap to tftp server for processing with zeek
timestamp
echo "[-] Moving /tmp/*.pcap /srv/tfp"
mv /tmp/*.pcap /srv/tftp/
sleep 2
echo "[-] file moved " && ls -l /srv/tftp/*.pcap
}
runnginx() {
# Command to run nginx
echo "[-] Launching nginx in background"
sudo docker run -d --name nginx -p 8080:80 nginx
echo "[-] Changing default logs so they will actually write in container, remember, the carosuel pulls a new image everytime"
docker exec -it nginx rm /var/log/nginx/access.log
docker exec -it nginx rm /var/log/nginx/error.log
docker exec -it nginx touch /var/log/nginx/access.log
docker exec -it nginx touch /var/log/nginx/error.log
echo "[-] Invoke sleep"
sleeper
echo "[-] Sleep complete. Now preparing new filenames for log capture before trashing the docker"
timestamp
nginxerror=$(echo nginxerror_.$rightnow.txt)
nginxaccess=$(echo nginxaccess_.$rightnow.txt)
getcontainerid
docker cp -a $cid:/var/log/nginx/access.log /srv/tftp/$nginxaccess
docker cp -a $cid:/var/log/nginx/error.log /srv/tftp/$nginxerror
sudo docker stop $cid
#docker purge -a -f
}
runmodbus() {
app="modbus"
echo "[-] Running modbus docker"
#docker pull oitc/modbus-server
#docker run -d --rm -p 502:5020 oitc/modbus-server:latest
starttcpdump
sleeper
stoptcpdump
getcontainerid
sudo docker stop $cid
}
runbacnet() {
docker run fh1ch/bacstack-compliance-docker
starttcpdump
sleeper
stoptcpdump
getcontainerid
sudo docker stop $cid
}
runmqtt() {
# Running and pulling mqtt docker
echo "[-] Launching mqtt docker"
docker run -d -p 1883:1883 --name mqtt -v "/srv/mosquitto/config:/mosquitto/config" -v /mosquitto/data -v /mosquitto/log eclipse-mosquitto
sleeper
timestamp
getcontainerid
echo "[-] Now that mqtt docker is done time to retrieve the log file and send it to the tftp server"
mqttlog=$(echo "mqtt_$rightnow.txt")
docker cp -a $cid:/mosquitto/log/mosquitto.log /srv/tftp/$filename
sudo docker stop $cid
}
runtomcat() {
echo "[-] Running tomcat on port 8888 for $totalsleep"
# Command to run tomcat
sudo docker run -d --name tomcat --rm -p 8888:8080 tomcat:9.0
#sleeper
echo "[-] Sleeping ..."
sleeper
#
# Here, need to run commands like docker cp or docker exec to extract logs from tomcat
# Logfile observed on docker test is localhost_access_log.2025-01-20.txt
# Previous logs need to be deleted.
# Current logs need to be tarballed
# Once everything is done, the docker can be stopped
echo "Step 0, purge previous file"
/bin/rm -rf /home/ubuntu/tomcat*
echo "Step 1, get the container id for log copying"
getcontainerid
echo "Step 2, define timestamp/variable for filename"
timestamp
tomcatlog=$(echo localhost_access_log.$rightnow.txt)
echo "Step 3 Docker the logfile to ubuntu home"
docker cp -a $cid:/usr/local/tomcat/logs/$tomcatlog /srv/tftp/$tomcatlog
echo "Step 4, tar the file for future use on Splunk"
tar -cvf /home/ubuntu/tomcatlog.tar /home/ubuntu/localhost_access*
echo "Step 5, stop the docker"
docker stop $cid
}
#
runsolr() {
# Command to run solr
echo "[-] Launching solr in background"
sudo docker run -d --name solr -p 8984:8984 bitnami/solr:latest
echo "[-] Invoke sleep ... "
sleeper
getcontainerid
sudo docker stop $cid
echo "[-] No logs copied!"
#docker purge -a -f
}
runredis() {
app="redis"
echo "[-] Running Redis Docker!"
# Grab time and edit config file to capture log properly
timestamp
/bin/cp /srv/redis/redis.conf /root/redis.bak
sed -i "s/abcdefg/$filetime/" /srv/redis/redis.conf
# Get tcpdump running
starttcpdump
# Command to run redis
#docker run -v /srv/redis/redis.conf:/usr/local/etc/redis --name some-redis -d redis redis-server
#docker run --name some-redis -d redis redis-server -p 6379:6379 --save 60 1 --loglevel warning
#docker run --name test-redis -v /srv/redis/redis.conf:/usr/local/etc/redis/redis.conf -d redis -p 6379:6379
docker run -d --name redis-stack-server -p 6379:6379 redis/redis-stack-server:latest
#docker run --name some-redis -d redis redis-server --save 60 1 --loglevel warning
echo "[-] Invoke sleep ..."
sleeper
echo "[-] Redis carosuel complete"
stoptcpdump
# Get container id, grab the redis log file, and then stop it
getcontainerid
docker cp -a $cid:/var/log/redis* /srv/tftp
sudo docker stop $cid
# Restore original redis.conf
/bin/mv /root/redis.bak /srv/redis/redis.conf
}
startdelay
cleandockers
runmqtt
#runsolr
runnginx
runmodbus
runtomcat
#runbacnet
runredis
#runmqtt
echo "[-] carosuel complete, verifying no running dockers"
docker ps -a
exit 1
