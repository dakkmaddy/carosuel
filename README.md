# carosuel

The carosuel is simply a shell script thaat starts common dockers and leaves them active for random times. The purpose is to provide a honeypot. Once the random time ends, the script captures log files and moves them to /srv/tftp so you can grab them later and analyze the visiting IPs.
