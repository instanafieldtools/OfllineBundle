######################################################################################
# Bundler for offline Instana installation 
#   by Alexandre MECHAIN - Instana
#
# This script will generate a self extractable file with all required packages to
# install Instana AP fully offline I
#
# You must run this script on Centos/RHEL to create a bundle for that environment
# You must run this script on Debian/Ubuntu to create a bundle for that environment
# You must have an internet connection to run that script
# You must have a valid agent key to create the bundle (doesn't need to be the final 
#  one form your customer license
#  
# As root run ./bundler_v2.sh -a <agent-key>
# This will generate an approx. 3Gb file called instana_setup.sh
# 
# For any questions please send an email to : alex.mechain@instana.com
######################################################################################

set -o pipefail
export LC_ALL=C

PLATFORM="unknown"
DISTRO="unknown"
FAMILY="unknown"


function detectOS() {
  if test -f /etc/issue; then
    PLATFORM=`cat /etc/issue | head -n 1`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /etc/redhat-release; then
    PLATFORM=`cat /etc/redhat-release`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /usr/bin/lsb_release; then
    VERSION=`lsb_release -r | awk '{print $2}'`
  else
    if [ "$DISTRO" = "CentOS" ]; then
      if [ "`echo $PLATFORM | awk '{print $2}'`" = "Linux" ]; then
        VERSION=`echo $PLATFORM | awk '{print $4}'`
      else
        VERSION=`echo $PLATFORM | awk '{print $3}'`
      fi
    fi
  fi

  if [ "$DISTRO" = "Red" ]; then
    DISTRO="RHEL"
    VERSION=`echo $PLATFORM | awk '{print $7}'`
  fi
}

function set_family() {
  local distro=$1
  if [ "$distro" = "CentOS" ] || [ "$distro" = "RHEL" ]; then
    FAMILY=yum
  fi

  if [ "$distro" = "Ubuntu" ] || [ "$distro" = "Debian" ]; then
    FAMILY=apt
  fi
}
detectOS
set_family $DISTRO

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

CLEAN=1

while getopts "a:n" opt; do
  case $opt in
    a)
      ACCESS_KEY="$OPTARG"
      ;;
    n)
      CLEAN=0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

echo "detected Linux Distribution: $DISTRO"
echo "setting family to $FAMILY"


if [ ! "$ACCESS_KEY" ]; then
  echo "-a ACCES_KEY required!"
  exit 1
fi

PKG_URI=packages.instana.io
DEB_URI="${PKG_URI}/release"
YUM_URI="${PKG_URI}/release"
MACHINE=x86_64
gpg_uri="https://${PKG_URI}/Instana.gpg"
CUR_DIR=`pwd`

function get-instana-packages() {
#This creates the Instana repo file based on access key used to download all required rpm file for back end installation
#This function downloads all necessary rpm files for back end installation. All rpm packages will be stored in folder /localrepo/
#It also createslocal repo file that will be used for creating local repo.
#This file is used during the local repo creation (where bundler get executed) and during the back end installation

# Step 1: add instana repo file to repo list and create local.repo file
# Step 2: prepare env and set list of necessary packages
# Step 3: Download of all rpm package (this is a point of failure since there is no guarantee this package list will last forever.
#       With any new major version, new package can appear and therefore list have to be updated

REPO_FOLDER=/localrepo/
if [ ! -d "$REPO_FOLDER" ]; then 
  mkdir $REPO_FOLDER
fi

local family=$1
if [ "$family" = "yum" ]; then
  #Pre-req to bundle
  yum install -y createrepo
  ########## STEP 1 ##########
  echo " * create instana repo file"
  printf "[instana-product]\nname=Instana-Product\nbaseurl=https://_:"$ACCESS_KEY"@"$YUM_URI"/product/rpm/generic/"$MACHINE"\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey="$gpg_uri"\nsslverify=1" >/etc/yum.repos.d/Instana-Product.repo
  echo " * create local repo file"
  printf "[rhel7]\nname=rhel7\nbaseurl=file:///localrepo/\nenabled=1\ngpgcheck=0" >$CUR_DIR/local.repo
  curl -s -o $CUR_DIR/instana.gpg $gpg_uri
  rpm --import $CUR_DIR/instana.gpg
# This doesn't work with build 145. Some items are "void" when displaying list of instana packages
yum --disablerepo="*" --enablerepo="instana-product" list available | awk '(NR>=3) {print $1}' > $CUR_DIR/list_package
#  echo "nginx">>list_package

# Workaround: feeding list_package with arbitrary list of required packages
# this list might nor work for further releases.
#Array=( "cassandra.noarch" "cassandra-migrator.noarch" "cassandra-tools.noarch" "chef-cascade.x86_64" "clickhouse.x86_64" "elastic-migrator.x86_64" "elasticsearch.noarch" "instana-acceptor.noarch" "instana-appdata-legacy-converter.noarch" "instana-appdata-processor.noarch" "instana-appdata-reader.noarch" "instana-appdata-writer.noarch" "instana-butler.noarch" "instana-cashier.noarch" "instana-common.x86_64" "instana-commonap.x86_64" "instana-eum-acceptor.noarch" "instana-eum-processor.norarch" "instana-filler.noarch" "instana-groundskeeper.noarch" "instana-issue-tracker.noarch" "instana-jre.x86_64" "instana-processor.noarch" "instana-ruby.x86_64" "instana-ui-backend.noarch" "instana-ui-client.noarch" "kafka.noarch" "mason.noarch" "mongodb.x86_64" "nginx.x86_64" "nodejs.x86_64" "onprem-cookbooks.noarch" "postgres-migrator.x86_64" "postgresql.x86_64" "postgresql-libs.x86_64" "postgresql-static.x86_64" "redis.x86_64" "zookeeper.noarch")
#  for item in "${Array[@]}"; do
#    echo "$item" >>$CUR_DIR/list_package
#  done
# End of Workaround

  ########## STEP 3 ##########
  echo " * download list of necessary repos"
  #V2 change
  while read -r line; do
       echo "downloading $line"
       yumdownloader -q "$line" --destdir=/localrepo/
  done < $CUR_DIR/list_package

else
  wget -qO - "https://${PKG_URI}/Instana.gpg" | apt-key add

  echo " * create instana repo file"
  printf "deb [arch=amd64] https://_:"$ACCESS_KEY"@"$DEB_URI"/product/deb generic main" >/etc/apt/sources.list.d/Instana-Product.list
  echo " * update repo list"
  apt-get update>>/dev/null

  #package required to prepare local repo
  apt install dpkg-dev apt-rdepends
  chown -R _apt:root $REPO_FOLDER
  grep ^Package: /var/lib/apt/lists/packages.instana.io_release_product_deb_dists_generic_main_binary-amd64_Packages | awk '{print $2}' > $CUR_DIR/list_package
  echo "nginx" >> $CUR_DIR/list_package
  echo "nginx-extras" >> $CUR_DIR/list_package
  ########## STEP 3 ##########
    #create dependencies list
    echo " * buidling dependency list"
    while read -r line; do
      echo "ligne="$line
      apt-rdepends "$line"|grep -v "^ ">>$REPO_FOLDER/dep.list
    done < $CUR_DIR/list_package

    sort -u $REPO_FOLDER/dep.list > $REPO_FOLDER/dep_sorted.list
    rm $REPO_FOLDER/dep.list
    #download dependency packages
    while read -r line
    do
      cd $REPO_FOLDER
      apt download "$line"
    done < "$REPO_FOLDER/dep_sorted.list"

    #restoring legitimate user
    chown -R root:root $REPO_FOLDER
fi

  echo " * download complete "

}

function create-offline-setup-file() {
echo " * Create offline setup file"

  sleep 5
  _self="${0##*/}"
  #set file marker
  FILE_MARKER=`awk '/^SETUP FILE:/ { print NR + 1; exit 0; }' $CUR_DIR/$_self`

  # Extract the file
  tail -n+$FILE_MARKER $CUR_DIR/$_self  > $CUR_DIR/offline.sh
}

function get-agents() {
#Retreive latest versions of static agents for debian, centos, rhel6 and rhel7
# Step 1: prepare env (this is a point of failure if URL change, some env variables might not be correct)
# Step 2: curl the agent page download using access-key provided to retreive files names (.rpm and .deb)
#         (this is another point of failure if URL change since grep is made using a formal path)
# Step 3: Download the packages and place them into base folder of agents directory
# Step 4: Place agent in their respective directory
# Step 5: create tar package file

########## STEP 1 ##########
  AGENT_URI="https://_:$ACCESS_KEY@packages.instana.io"
  DEB_AGENT_PATH="agent/deb/dists/generic/main/binary-amd64"
  RPM_AGENT_PATH="agent/rpm/generic/x86_64"
  PKG_PREFIX="instana-agent-static"
  AGENT_DIR="$CUR_DIR/agents"

  mkdir $AGENT_DIR

########## STEP 2 ##########
  #rpm packages
  curl -s "$AGENT_URI/agent/download" | grep -oP '<a href="\/agent\/rpm\/generic\/x86_64\/.*static\K[^</a]+' > $AGENT_DIR/agentlist
  #debian packages (appending to agentlist file)
  curl -s "$AGENT_URI/agent/download" | grep -oP '<a href="\/agent\/deb\/dists\/generic\/main\/binary-amd64\/.*static\K[^<\a]+' >> $AGENT_DIR/agentlist

########## STEP 3 ##########
  #download agents
  while read -r line; do
    if [[ $line == *"rpm"* ]]; then
      echo "Downloading $PKG_PREFIX$line"
      curl -s -o "$AGENT_DIR/$PKG_PREFIX$line" "$AGENT_URI/$RPM_AGENT_PATH/$PKG_PREFIX$line"
    else
      echo "Downloading $PKG_PREFIX$line"
      curl -s -o "$AGENT_DIR/$PKG_PREFIX$line" "$AGENT_URI/$DEB_AGENT_PATH/$PKG_PREFIX$line"
    fi
  done < $AGENT_DIR/agentlist

########## STEP 4 ##########

  mkdir $AGENT_DIR/{centos,rhel6,rhel7,debian}
  mv $AGENT_DIR/*el6*.rpm $AGENT_DIR/rhel6
  mv $AGENT_DIR/*el7*.rpm $AGENT_DIR/rhel7
  mv $AGENT_DIR/*.deb $AGENT_DIR/debian
  mv $AGENT_DIR/*.rpm $AGENT_DIR/centos

########## STEP 5 ##########
  echo "packaging agents repo"
  cd $AGENT_DIR
  tar -czf $CUR_DIR/instana_agent_repo.tar.gz *
}

function package-offline() {
#This package everything into a single tar ball
#Step 1: Env preparation/backup of existing repo file and replacement by local repo file. Create local repo DB
#Step 2: Restoring repo to original
#Step 3: create a tar file containing all packages + local repo file references created during step1
#Step 4: repackage everything into a single file
local family=$1

  echo " * backup existing repo and prepare local repo"
  if [ "$family" = "yum" ]; then
    ########## STEP1 ##########
    mkdir $CUR_DIR/backup && mv -f /etc/yum.repos.d/* $CUR_DIR/backup
    cp $CUR_DIR/local.repo /etc/yum.repos.d/
    createrepo /localrepo/
    ########## STEP2 ##########
    rm -f /etc/yum.repos.d/local.repo
    cp $CUR_DIR/backup/* /etc/yum.repos.d/
  else
    ########## STEP1 ##########
    #create package repo
    cd $REPO_FOLDER
    dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
    dpkg-scansources . /dev/null | gzip -9c > Sources.gz
  fi

########## STEP3 ##########
  tar -czf $CUR_DIR/instana_backend_repo.tar.gz /localrepo/

########## STEP5 ##########
  
  echo " * package everything"
  cd $CUR_DIR
  tar -czf instana_offline.tar.gz instana_backend_repo.tar.gz instana_agent_repo.tar.gz local.repo
  cat offline.sh instana_offline.tar.gz >instana_setup.sh

}

function final-cleanup() {
#General cleanup

  echo " * cleaning up"
  #Removal of local repo files and restore original repo files
  rm -Rf /localrepo/

  #Removal of intermediate files
  rm -f $CUR_DIR/instana_backend_repo.tar.gz $CUR_DIR/instana_agent_repo.tar.gz $CUR_DIR/offline.sh $CUR_DIR/local.repo
  rm -Rf $CUR_DIR/agents
}

# Download and prepar agents pack
get-agents

# Prepapre Instana repo and download packages
get-instana-packages $FAMILY

# create setup file
create-offline-setup-file

#package everything
package-offline $FAMILY

#deactivable cleanup
if [ "$CLEAN" == 1 ]; then
  final-cleanup
fi

exit 0

SETUP FILE:
################################################## offline installer file  #######################################
#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

#######self extraction of tar########
_self="${0##*/}"

#set file marker and create tmp dir
FILE_MARKER=`awk '/^TAR FILE:/ { print NR + 1; exit 0; }' $_self`

# Extract the file using pipe
tail -n+$FILE_MARKER $_self  > ./instana_offline.tar.gz

#######End of self extraction#########
export LC_ALL=C
PLATFORM="unknown"
DISTRO="unknown"

#Set ENV
CUR_DIR=`pwd`
AGENT_DIR=/var/www/html/agent-setup

echo " * extracting installation files "
tar -xzvf $CUR_DIR/instana_offline.tar.gz

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function detectOS() {
  if test -f /etc/issue; then
    PLATFORM=`cat /etc/issue | head -n 1`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /etc/redhat-release; then
    PLATFORM=`cat /etc/redhat-release`
    DISTRO=`echo $PLATFORM | awk '{print $1}'`
  fi

  if test -f /usr/bin/lsb_release; then
    VERSION=`lsb_release -r | awk '{print $2}'`
  else
    if [ "$DISTRO" = "CentOS" ]; then
      if [ "`echo $PLATFORM | awk '{print $2}'`" = "Linux" ]; then
        VERSION=`echo $PLATFORM | awk '{print $4}'`
      else
        VERSION=`echo $PLATFORM | awk '{print $3}'`
      fi
    fi
  fi

  if [ "$DISTRO" = "Red" ]; then
    DISTRO="RHEL"
    VERSION=`echo $PLATFORM | awk '{print $7}'`
  fi
}

function get-inputs() {
  VALID=false

  while [ $VALID != true ]
  do
    echo "enter your access key (field AgentKey from the license email you received)"
    read ACCESS_KEY
    echo "enter your salesID (field SalesId from the license email you received)"
    read SALES_ID
    echo "enter your tenant (field customer in your license email you received)"
    read TENANT
    echo "enter your unit (field Environment in your license email you received)"
    read UNIT
    echo "enter your server name (full DNS) or IP adress"
    read SERVER_NAME
    echo "enter your name"
    read NAME
    echo "enter your email address (this will be used to connect to instana once installed)"
    read EMAIL

    NOK=true
    while [ "$NOK" == true ]
    do
      echo "choose your password to connect to instana"
      read -s PASS
      echo "retype your password"
      read -s REPASS
      if [ "$PASS" == "$REPASS" ]; then
        NOK=false
      else
        echo "password does not match"
      fi
    done

    echo "Where do you want your data to be stored? (press enter for default in /mnt/data)"
    read DATA_STORE
    if [[ $DATA_STORE == "" ]];then
      DATA_STORE=/mnt/data
    fi
    echo "Where do you want to store Instana back-end logs? (press enter for default in /mnt/logs)"
    read LOG_STORE
    if [[ $LOG_STORE == "" ]];then
      LOG_STORE=/mnt/logs
    fi

    echo "Access Key : $ACCESS_KEY"
    echo "SalesID : $SALES_ID"
    echo "Tenant : $TENANT"
    echo "Unit : $UNIT"
    echo "Server Name : $SERVER_NAME"
    echo "Your Name : $NAME"
    echo "Your Email : $EMAIL"
    echo "Data location : $DATA_STORE"
    echo "Logs location : $LOG_STORE"

    GOFORIT=false

    while [ "$GOFORIT" != "Y" ] && [ "$GOFORIT" != "n" ]
    do
      echo "Is this information correct [Y/n]?"
      read GOFORIT
      if [ "$ACCESS_KEY" == "" ] || [ "$SALES_ID" == "" ] || [ "$SERVER_NAME" == "" ] || [ "$NAME" == "" ] || [ "$EMAIL" == "" ] || [ "$DATA_STORE" == "" ] || [ "$LOG_STORE" == ""]; then
        echo "*** Some values are empty ***"
        echo ""
        GOFORIT=n
      fi
      if [ "$GOFORIT" == "Y" ]; then
        VALID=true
      fi
    done
  done
}

function feed-settings() {

  # make a fresh copy of settings.yaml in case of reinstall
  # use /bin/cp rather than just cp which is an alias for cp -i and prevent overwrite without confirmation
  /bin/cp -rf /etc/instana/settings.yaml.template /etc/instana/settings.yaml
  sed -i '0,/name:/{s/name:/name: "'$NAME'"/}' /etc/instana/settings.yaml
  sed -i '0,/password:/{s/password:/password: "'$PASS'"/}' /etc/instana/settings.yaml
  sed -i 's/email:/email: "'$EMAIL'"/' /etc/instana/settings.yaml
  sed -i 's/agent:/agent: "'$ACCESS_KEY'"/' /etc/instana/settings.yaml
  sed -i 's/sales:/sales: "'$SALES_ID'"/' /etc/instana/settings.yaml
  sed -i 's/hostname:/hostname: "'$SERVER_NAME'"/' /etc/instana/settings.yaml
  sed -i '0,/name:/!{0,/name:/s/name:/name: "'$TENANT'"/}' /etc/instana/settings.yaml
  sed -i 's/unit:/unit: "'$UNIT'"/' /etc/instana/settings.yaml
  sed -i 's@cassandra: \/mnt\/data@cassandra: '$DATA_STORE'@' /etc/instana/settings.yaml
  sed -i 's@data: \/mnt\/data@data: '$DATA_STORE'@' /etc/instana/settings.yaml
  sed -i 's@logs: \/mnt\/logs@logs: '$LOG_STORE'@' /etc/instana/settings.yaml
}

function prepare-backend-env() {

  mkdir /etc/instana
  mkdir /etc/instana/backup
  #generate ssl keys
  openssl req -x509 -newkey rsa:2048 -keyout /etc/instana/server.key -out /etc/instana/server.crt -days 365 -nodes -subj "/CN=$SERVER_NAME"

  #create data and log folders
  mkdir $DATA_STORE
  mkdir $LOG_STORE  
}


function set-repo-local() {
  #Remove common repos and replace them with local repo.
  #Extract necessary packages in /localrepo/
  local distro=$1

  #prepare repo folder and extract packages
  echo " * extracting repo files *"
  tar -xzf $CUR_DIR/instana_backend_repo.tar.gz --directory /

  if [ "$distro" = "CentOS" ] || [ "$distro" = "RHEL" ]; then
    mv -f /etc/yum.repos.d/* /etc/instana/backup
    cp -f $CUR_DIR/local.repo /etc/yum.repos.d/
    yum clean all
  fi

  if [ "$distro" = "Ubuntu" ] || [ "$distro" = "Debian" ]; then
    mv -f /etc/apt/sources.list /etc/instana/backup
    echo "deb [trusted=yes] file:///localrepo/ localrepo/" > /etc/apt/sources.list
    if [ ! -d "/var/www/html/agent-setup" ]; then
      mkdir /localrepo/localrepo
    fi
    cp /localrepo/* /localrepo/localrepo
    apt-get update>>/dev/null
  fi
}

function prepare-agent-repo() {
  #TODO: check source location of agents before copying them into target
  
  #Step 1: create agent repo folder and extrac agents package in it
  #Step 2: make backup of nginx configuration, insert new location in current config and restart service
  #Step 3: produce the setup_RPM.sh and setup_DEB.sh files
  #Step 4: concatenate rpm file with setup to produce a self extracting shell
  #Step 5: cleanup rpm files
  #Step 6: restart NGinx to make agent repo accessible
  
  #Used if call from update 
  if [ $1 ] && [ $2 ]; then
    SERVER_NAME=$2
    ACCESS_KEY=$1
  fi 

  echo " * Preparing agents * "
  ########## STEP 1 ##########
  if [ ! -d "/var/www/html/agent-setup" ]; then
    mkdir /var/www/html/agent-setup
  fi  

  #This section is for update to keep N-1 version of agent 
  if [ -d "/var/www/html/agent-setup/centos" ]; then
    if [ -d "/var/www/html/agent-setup/N-1" ]; then
      rm -R /var/www/html/agent-setup/N-1/*
    else
      mkdir /var/www/html/agent-setup/N-1
    fi
    mv -f /var/www/html/agent-setup/centos /var/www/html/agent-setup/debian /var/www/html/agent-setup/r* /var/www/html/agent-setup/N-1
  fi
  #End of section

  tar -xzf instana_agent_repo.tar.gz --directory /var/www/html/agent-setup
  
  

  ########## STEP 2 ##########
  #has nginx loadbalancer config been modified? If yes move on, if no modify it.
  local nginx_modified=`cat /etc/nginx/sites-enabled/loadbalancer | grep agent-setup`
  
  if [ ! "$nginx_modified" ]; then
    cp /etc/nginx/sites-enabled/loadbalancer /etc/instana/backup/
    sed -i 's/location \/ump\//location \/agent-setup {\n    autoindex on;\n  }\n\n  location \/ump\//' /etc/nginx/sites-enabled/loadbalancer
  fi
  #This function packages agent in a self extracting shell script by concatenation of setup.sh and rpm file.
  #Setup.sh is supposed to get executed only once server has been set up since ACCESS_KEY and SERVER_NAME are to be populated during this phase
  #Step 1: produce the setup.sh file
  #Step 2: concatenate setup.sh and rpm file to produce a self extracting shell
  #Step 3: cleanup the rpm files
  
  ########## STEP 3 ##########
  printf "#!/bin/bash\n\nif [ \"\$EUID\" -ne 0 ]\n  then echo \"Please run as root\"\n  exit\nfi\n\nwhile getopts \"z:\" opt; do\n  case \$opt in\n    z)\n      ZONE="\$OPTARG"\n      ;;\n    \?)\n      echo \"Invalid option: -\$OPTARG\" >&2\n      exit 1\n      ;;\n  esac\ndone\n\nif [ ! \"\$ZONE\" ]; then\n  echo \"please provide a zone using -z option\"\n  echo \"syntax: instana_static_agent_<DISTRO>.sh -z <zone-name>\"\n  exit 1\nfi\nSERVER_NAME=$SERVER_NAME\nACCESS_KEY=$ACCESS_KEY\n_self=\"\${0##*/}\"\n\n#set file marker and create tmp dir\nCUR_DIR=\`pwd\`\nFILE_MARKER=\`awk '/^RPM FILE:/ { print NR + 1; exit 0; }' \$CUR_DIR/\$_self\`\nTMP_DIR=\`mktemp -d /tmp/instana-self-extract.XXXXXX\`\n\n# Extract the file using pipe\ntail -n+\$FILE_MARKER \$CUR_DIR/\$_self  > \$TMP_DIR/setup.rpm\n\n#Install the agent\necho \" *** installing agent ***\"\nrpm --quiet -i \$TMP_DIR/setup.rpm\n\n# configure agent\necho \" *** configure agent ***\"\n# create a fresh copy of Backend.cfg file\ncp /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg.template /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\n# set appropriate values\nsed -i -e 's/host=\${env:INSTANA_HOST}/host='\$SERVER_NAME'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/port=\${env:INSTANA_PORT}/port=1444/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/key=\${env:INSTANA_KEY}/key='\$ACCESS_KEY'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i 's/#com.instana.plugin.generic.hardware:/com.instana.plugin.generic.hardware:/' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i '0,/#  enabled: true/{s/#  enabled: true/  enabled: true/}' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i \"s@#  availability-zone: 'Datacenter A / Rack 42'@  availability-zone: '\$ZONE'@\" /opt/instana/agent/etc/instana/configuration.yaml\n\n#restart agent\nsystemctl restart instana-agent\n\nexit 0\n\nRPM FILE:\n">$AGENT_DIR/setup_RPM.sh
  
  #Too lazy to make a distro control so creating 2nd file for debian distro
  printf "#!/bin/bash\n\nif [ \"\$EUID\" -ne 0 ]\n  then echo \"Please run as root\"\n  exit\nfi\n\nwhile getopts \"z:\" opt; do\n  case \$opt in\n    z)\n      ZONE="\$OPTARG"\n      ;;\n    \?)\n      echo \"Invalid option: -\$OPTARG\" >&2\n      exit 1\n      ;;\n  esac\ndone\n\nif [ ! \"\$ZONE\" ]; then\n  echo \"please provide a zone using -z option\"\n  echo \"syntax: instana_static_agent_<DISTRO>.sh -z <zone-name>\"\n  exit 1\nfi\nSERVER_NAME=$SERVER_NAME\nACCESS_KEY=$ACCESS_KEY\n_self=\"\${0##*/}\"\n\n#set file marker and create tmp dir\nCUR_DIR=\`pwd\`\nFILE_MARKER=\`awk '/^RPM FILE:/ { print NR + 1; exit 0; }' \$CUR_DIR/\$_self\`\nTMP_DIR=\`mktemp -d /tmp/instana-self-extract.XXXXXX\`\n\n# Extract the file using pipe\ntail -n+\$FILE_MARKER \$CUR_DIR/\$_self  > \$TMP_DIR/setup.deb\n\n#Install the agent\necho \" *** installing agent ***\"\napt install -q \$TMP_DIR/setup.deb\n\n# configure agent\necho \" *** configure agent ***\"\n# create a fresh copy of Backend.cfg file\ncp /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg.template /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\n# set appropriate values\nsed -i -e 's/host=\${env:INSTANA_HOST}/host='\$SERVER_NAME'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/port=\${env:INSTANA_PORT}/port=1444/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i -e 's/key=\${env:INSTANA_KEY}/key='\$ACCESS_KEY'/' /opt/instana/agent/etc/instana/com.instana.agent.main.sender.Backend.cfg\nsed -i 's/#com.instana.plugin.generic.hardware:/com.instana.plugin.generic.hardware:/' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i '0,/#  enabled: true/{s/#  enabled: true/  enabled: true/}' /opt/instana/agent/etc/instana/configuration.yaml\nsed -i \"s@#  availability-zone: 'Datacenter A / Rack 42'@  availability-zone: '\$ZONE'@\" /opt/instana/agent/etc/instana/configuration.yaml\n\n#restart agent\nsystemctl restart instana-agent\n\nexit 0\n\nRPM FILE:\n">$AGENT_DIR/setup_DEB.sh
  
  ########## STEP 4 ##########
  
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/rhel6/*.rpm > $AGENT_DIR/rhel6/instana_static_agent_rhel6.sh
    chmod +x $AGENT_DIR/rhel6/instana_static_agent_rhel6.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/rhel7/*.rpm > $AGENT_DIR/rhel7/instana_static_agent_rhel7.sh
    chmod +x $AGENT_DIR/rhel7/instana_static_agent_rhel7.sh
    cat $AGENT_DIR/setup_DEB.sh $AGENT_DIR/debian/*.deb > $AGENT_DIR/debian/instana_static_agent_debian.sh
    chmod +x $AGENT_DIR/debian/instana_static_agent_debian.sh
    cat $AGENT_DIR/setup_RPM.sh $AGENT_DIR/centos/*.rpm > $AGENT_DIR/centos/instana_static_agent_centos.sh
    chmod +x $AGENT_DIR/centos/instana_static_agent_centos.sh
  
  ########## STEP 5 ##########
    rm -f /var/www/html/agent-setup/rhel6/*.rpm /var/www/html/agent-setup/rhel7/*.rpm /var/www/html/agent-setup/debian/*.deb /var/www/html/agent-setup/centos/*.rpm
    rm -f /var/www/html/agent-setup/*.sh /var/www/html/agent-setup/agentlist
  
  ########## STEP 6 ##########
  systemctl restart nginx
}

function setupBE() {
  
  detectOS
  get-inputs
  prepare-backend-env
  set-repo-local $DISTRO

  ##### install instana-commonap
  if [ "$DISTRO" = "CentOS" ] || [ "$DISTRO" = "RHEL" ]; then
    yum install -y instana-commonap
  fi

  if [ "$DISTRO" = "Ubuntu" ] || [ "$DISTRO" = "Debian" ]; then
    apt -y install instana-commonap
  fi

  feed-settings

  instana-init

  prepare-agent-repo

  echo " * Installation complete * "
  echo " * You can now access your server on https://$SERVER_NAME/ * "
  echo " * Agents are available on https://$SERVER_NAME/agent-setup * "
  exit 0
}

function chk-instana-existence() {
  INSTANA_PRESENT=0
  if [[ -d "/opt/instana" && -d "/etc/instana" ]]; then
    if [[ `instana-status |grep "INSTANA SERVICES"` ]]; then
      echo "It's Alive !!!"
      INSTANA_PRESENT=1
    fi
  else 
    echo "No installation of Instana has been found."
    echo "Operation aborted"
    exit 0
  fi

  if [ ! -f "/etc/instana/settings.yaml" ]; then 
    echo "file /etc/instana/settings.yaml not found"
    echo "Operation aborted"
    exit 0
  fi
}

function updateBE() {
  local testyn
  chk-instana-existence
  echo "update Back-End"
  
  echo "Please check the following values found in settings.yaml"
  echo "press any key to diplay the values"
  read
  parse_yaml /etc/instana/settings.yaml

  while [[ "$testyn" != "y" && "$testyn" != "Y" && "$testyn" != "n" && "$testyn" != "N" ]]
  do
    echo "Are these values correct? (y/n)"
    read testyn
    if [[ $testyn == 'n' || $testyn == 'N' ]]; then
        echo "please edit /etc/instana/settings.yaml and fill appropriate values according to your license"
        exit 1
    fi
    if [[ $testyn == 'y' || $testyn == 'Y' ]]; then
        echo "Let's rock'n roll baby"
    fi
  done
 
  set-repo-local
  echo "launching update"
  instana-update
  if [ ! $1 ]; then 
    exit 0
  fi
}

function updateAgt() {
  local access
  local server
  local testyn
  chk-instana-existence
  echo "update Agents"
  access=`grep agent: /etc/instana/settings.yaml | sed 's/      agent: \(.*\)$/\1/'`
  server=`grep hostname: /etc/instana/settings.yaml | sed 's/    hostname: \(.*\)$/\1/'`      
  echo "ACCESS_KEY=$access"
  echo "SERVER_NAME=$server"
  #echo "Is this correct (y/n)?"
  while [[ "$testyn" != "y" && "$testyn" != "Y" && "$testyn" != "n" && "$testyn" != "N" ]]
  do
    echo "Are these values correct? (y/n)"
    read testyn
    if [[ $testyn == 'n' || $testyn == 'N' ]]; then
        echo "please enter ACCESS_KEY:"
        read access
        echo "please enter SERVER_NAME:"
        read server
    fi
    if [[ $testyn == 'y' || $testyn == 'Y' ]]; then
        echo "Let's rock'n roll baby"
    fi
  done
  prepare-agent-repo access server
  exit 0
}

function updateAll() {
  chk-instana-existence
  echo "update All"
  updateBE noex
  updateAgt
  exit 0
}

function default-prompt() {
  echo "****************************************************"
  echo "*       Welcome in Instana offline installer       *"
  echo "****************************************************"
  
  echo "****************************************************"
  echo "* What do you want to do?                          *"
  echo "* 1 - Install Instana                              *"
  echo "* 2 - Update Instana Back-End                      *"
  echo "* 3 - update Agents repository                     *"
  echo "* 4 - update All (Back-End and Agents repo)        *"
  echo "* 5 - display one-liner options                    *"
  echo "****************************************************"
  echo ""
  echo "Pick a choice (1, 2, 3, 4 or 5)"
  read CHOICE
  
  case "$CHOICE" in
  "1")
      echo "Installation of instana"
      setupBE
      ;;
  "2")
      echo "Update of Instana Back-End"
      updateBE
      ;;
  "3")
      echo "Update of Agents repository"
      updateAgt
      ;;
  "4")
      echo "Update All"
      updateAll
      ;;
  "5")
      echo "This setup can be launched with arguments"
      echo "Syntax: instana_setup.sh [optional install|updateBE|updateAgt|updateAll] [optional for install varfile]"
      echo "  - install: install instana back-end. Can use a varfile as secondary option ex: instana_setup.sh install varfile"
      echo "  - updateBE: update instana back-end"
      echo "  - updateAgt: update agent repository"
      echo "  - updateAll: update both back-end and agent repository"
      echo "  - no option : prompt for choice"
      exit 0
      ;;
  *)
      echo "Wrong choice. Please start over"
      exit 0
      ;;
  esac
}

function varfile() {  
  local testyn
  VAR_FILE=$2
  echo "using var file inputs"
  set -o allexport && source $VAR_FILE && set +o allexport
  echo "Access Key : $ACCESS_KEY"
  echo "SalesID : $SALES_ID"
  echo "Tenant : $TENANT"
  echo "Unit : $UNIT"
  echo "Server Name : $SERVER_NAME"
  echo "Your Name : $NAME"
  echo "Your Email : $EMAIL"
  echo "Data location : $DATA_STORE"
  echo "Logs location : $LOG_STORE"
  while [[ "$testyn" != "y" && "$testyn" != "Y" && "$testyn" != "n" && "$testyn" != "N" ]]
  do
    echo "Are these values correct? (y/n)"
    read testyn
    if [[ $testyn == 'n' || $testyn == 'N' ]]; then
        echo "please correct you varfile or do not pass any parameters"
        exit 1
    fi
    if [[ $testyn == 'y' || $testyn == 'Y' ]]; then
        echo "Let's rock'n roll baby"
    fi
  done
}


case "$1" in
  install)
    echo "install"
    if [[ $2 ]]; then
      #echo "args passed"
      varfile
    else
      get-inputs
    fi
    setupBE
    ;;
  updateBE)
    updateBE
    ;;
  updateAgt)
    updateAgt
    ;;
  updateAll)
    updateAll 
    ;;
  "")
    default-prompt
    ;;
  *)
    echo "Error"
    echo "Syntax: instana_setup.sh [optional install|updateBE|updateAgt|updateAll] [optional for install varfile]"
    echo "  - install: install instana back-end. Can use a varfile as secondary option ex: instana_setup.sh install varfile"
    echo "  - updateBE: update instana back-end"
    echo "  - updateAgt: update agent repository"
    echo "  - updateAll: update both back-end and agent repository"
    echo "  - no option : prompt for choice"
    exit 0
    ;;
esac

TAR FILE:
