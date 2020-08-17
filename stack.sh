#!/bin/bash

LOG=/tmp/stack.log 
rm -f $LOG 

R="\e[31m"
G="\e[32m"
Y="\e[33m"
C="\e[36m"
N="\e[0m"

HTML="https://s3-us-west-2.amazonaws.com/studentapi-cit/index.html"
PROXY_CONFIG_VALUES=("student,localhost,8080,student" "web,localhost,8080,student" "api,localhost,8090,")
APPUSER=student
#TOMCAT_VERSION=8.5.37
#TOMCAT_URL="http://mirror.cc.columbia.edu/pub/software/apache/tomcat/tomcat-8/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"

TOMCAT_URL=$(curl -s https://tomcat.apache.org/download-80.cgi | grep tar.gz | head -1 | awk -F \" '{print $2}')
TOMCAT_VERSION=$( echo $TOMCAT_URL | awk -F / '{print $NF}' | awk -F - '{print $3}' | sed -e 's/.tar.gz//')

TOMCAT_DIR=/home/$APPUSER/apache-tomcat-$TOMCAT_VERSION
APP_URL='https://s3-us-west-2.amazonaws.com/studentapi-cit/student.war'
MYSQL_JAR_URL='https://s3-us-west-2.amazonaws.com/studentapi-cit/mysql-connector.jar'
API_URL='https://s3-us-west-2.amazonaws.com/studentapi-cit/studentapi.war'

ID=$(id -u)
if [ $ID -ne 0 ]; then 
    echo "You should be a root user to perform this script. Run as root user or use sudo.."
    exit 1
fi

### Functions
Head() {
    echo -e "\n\t\t\e[4m$1$N\n"
}

Step() {
    echo -e -n " -> $C$1$N"
}

Exit() {
    echo -e "Refer log file $LOG for more information"
    exit 2
}

Stat() {
    case $1 in 
        0) echo -e "$G - SUCCESS $N" ;; 
        SKIP) echo -e "$Y - SKIPPING $N" ;; 
        *) 
            echo -e "$R - FAILURE $N" 
            Exit 
            ;;
    esac
}

Run() {
    echo -e "\n\n$R ********************************************* Executing Command : $1 $N" &>>$LOG
    $1 &>>$LOG 
    Stat $?
}

### Main Program
Head "Web Server Setup"
Step "Installing HTTPD"
Run "yum install httpd -y"

Step "Enabling HTTP Service"
Run "systemctl enable httpd"

Step "Updating Index pages"
Run "curl -s $HTML -o /var/www/html/index.html"

Step "Updating httpd proxy configuration"
rm -f  /etc/httpd/conf.d/studentapp.conf
for set in ${PROXY_CONFIG_VALUES[*]}; do 
    EXTENSION=$(echo $set | awk -F , '{print $1}')
    HOST=$(echo $set | cut -d , -f2)
    PORT=$(echo $set | awk -F , '{print $3}')
    URL_EXT=$(echo $set | awk -F , '{print $4}')
    echo "ProxyPass \"/$EXTENSION\" \"http://$HOST/:$PORT/$URL_EXT\"" >> /etc/httpd/conf.d/studentapp.conf
    echo "ProxyPassReverse \"/$EXTENSION\"  \"http://$HOST:$PORT/$URL_EXT\""  >> /etc/httpd/conf.d/studentapp.conf
done
Stat $?

Step "Starting HTTP Service"
Run "systemctl restart httpd"
#####
Head "Tomcat Server Setup"
Step "Installing JAVA"
Run "yum install java -y"

Step "Creating Application User"
id $APPUSER &>/dev/null
if [ $? -ne 0 ]; then 
    Run "useradd $APPUSER"
else    
    Stat SKIP 
fi 

Step "Downloading tomcat"
cd /home/$APPUSER
wget -qO- $TOMCAT_URL | tar -xz
Stat $?

Step "Downloading Student Application"
rm -rf $TOMCAT_DIR/webapps/*
wget -q $APP_URL -O $TOMCAT_DIR/webapps/student.war
Stat $?

Step "Downloading MySQL connection library"
wget -q $MYSQL_JAR_URL -O $TOMCAT_DIR/lib/mysql-connector.jar
Stat $?

Step "Setting Permissions to Tomcat Directory"
sudo chown $APPUSER:$APPUSER $TOMCAT_DIR -R
Stat $?

Step "Configuring Tomcat Service"
sed -i -e '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="USERNAME" password="PASSWORD" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://DB-ENDPOINT:3306/DATABASE"/>' $TOMCAT_DIR/conf/context.xml
wget -q https://s3-us-west-2.amazonaws.com/studentapi-cit/tomcat-init -O /etc/init.d/tomcat
chmod +x /etc/init.d/tomcat
systemctl daemon-reload
Stat $?

Step "Starting Tomcat"
Run "systemctl restart tomcat"


#####
Head "API Service Setup"
Step "Configuring API Service"
mkdir -p /home/$APPUSER/api 
wget -q $API_URL -O /home/$APPUSER/api/studentapi.war 

### Add DB details
wget -q https://s3-us-west-2.amazonaws.com/studentapi-cit/studentapi-init -O /etc/init.d/studentapi
chmod +x /etc/init.d/studentapi
systemctl daemon-reload
Stat $?

Step "Starting API Service"
Run "systemctl restart studentapi"
