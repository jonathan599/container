#!/bin/bash

# If you want to update databases then use "-u" flag
# ./deploy -u
if [[ $1 == "-u" ]]; then
echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Online"
  echo -e "\n\n"
  echo "========================================================================="
  echo "                           Verifying databases"
  echo "========================================================================="
  echo "Details of databases to be collected are:"
  echo "-------------------------------------------------------------------------"

  # wordpress_data is a smaller database and its modified version is available in the repo itself.
  echo "->mysql/wordpress_data/reactome-wordpress.sql.gz"
  echo "->mysql/tomcat_data/gk_current.sql.gz"
  echo "->neo4j/data/reactome.graphdb.tgz"
  echo "->solr/data/solr_data.tgz"
  echo "->java-application-builder/downloads/analysis_v61.bin.gz"
  echo "->java-application-builder/downloads/interactors.db.gz"
  echo "-------------------------------------------------------------------------"

  # The first value in the list is the filepath in host directory and second value is the download link
  declare -A file_list
  file_list+=( ["mysql/tomcat_data/gk_current.sql.gz"]="http://www.reactome.org/download/current/databases/gk_current.sql.gz" ) # tomcat_data
  file_list+=( ["neo4j/data/reactome.graphdb.tgz"]="http://reactome.org/download/current/reactome.graphdb.tgz" ) # neo4j data
  file_list+=( ["solr/data/solr_data.tgz"]="https://reactome.org/download/current/solr_data.tgz" ) # solr data
  file_list+=( ["java-application-builder/downloads/analysis.bin.gz"]="https://reactome.org/download/current/analysis_v61.bin.gz" ) # Analysis.bin for analysis service
  file_list+=( ["java-application-builder/downloads/interactors.db.gz"]="https://reactome.org/download/current/interactors.db.gz" ) # interactors.db required to create analysis.bin
  file_list+=( ["java-application-builder/downloads/diagrams_and_fireworks.tgz"]="https://reactome.org/download/current/diagrams_and_fireworks.tgz" )
  # file_list+=( ["mysql/wordpress_data/reactome-wordpress.sql.gz"]="http://www.reactome.org/download/current/databases/gk_wordpress.sql.gz")

  for db_file in "${!file_list[@]}";
  do
    # Initialization before prepairing download
    URL=${file_list[${db_file}]}
    file_path=${db_file}
    file_name=$(basename $file_path)
    mkdir -p $(dirname $file_path)

    if [ -f $file_path ] ; then
        # Get size information
        typeset -i remote_file_size=$(curl -sI $URL | tr -d '\r' | grep -i content-length | awk '{print $2}')
        typeset -i local_file_size=$(stat -c %s -- $file_path)
        echo "======================================================================="
        echo "======================================================================="
        echo "Filename:    " $file_name
        echo "Remote Size: " $remote_file_size
        echo "Local Size:  " $local_file_size

        if [[ $local_file_size -eq $remote_file_size ]]; then
          echo "Database up to date. Update not required"
        elif [[ $remote_file_size -eq 0 ]]; then
          echo "Remote file not acccessible. Not updating!"
        else
          echo "Database needs to be updated!"
          echo "Removing old file if it exists!"
          rm $file_path 2> /dev/null # 2> /dev/null is to ignore error if file not found
          echo "Downloading newer version"
          # To resume partially completed download, use --continue flag and comment out "rm $file_path 2> /dev/null"
          wget -O $file_path $URL
        fi
    else
        echo "File $file_path does not exist. Will download now."
        wget -O $file_path $URL
    fi
    echo -e "\n\n"
  done
else
    echo "No internet access! Not verifying databases!"
fi
fi


echo -e "\n\n"
echo "==========================================================================="
echo "                           Unpacking required files"
echo "==========================================================================="
if [[ ! -f solr/data/solr_data_extracted.flag ]]; then
  echo "Unpacking SolrData"
  rm -rf solr/solr_data
  tar -xvzf solr/data/solr_data.tgz -C solr/data
  touch solr/data/solr_data_extracted.flag
  chmod a+w solr/data/solr_data/reactome
  chmod a+w solr/data/solr_data/reactome/data
  chmod a+w solr/data/solr_data/reactome/data/index/write.lock
  chmod a+w solr/data/solr_data/reactome/data/index
  chmod a+w -R solr/data/solr_data/reactome/data/tlog
  mkdir -p logs/solr
  chmod a+w logs/solr

else
  echo "solr_data already unpacked"
fi

cd java-application-builder/downloads
if [[ ! -f diagrams_and_fireworks_extracted.flag ]]; then
  echo "Extracting diagrams and fireworks"
  rm -rf diagrams_and_fireworks
  set -e
  tar -xvzf diagrams_and_fireworks.tgz
  touch diagrams_and_fireworks_extracted.flag
  set +e

else
  echo "Diagrams and fireworks already unpacked"
fi

if [[ ! -f interactorsdb_extracted.flag ]]; then
  echo "Extracting interactors.db"
  rm -rf interactors.db
  set -e
  gzip -dk interactors.db.gz
  touch interactorsdb_extracted.flag
  set +e
else
  echo "interactors.db already unpacked"
fi

if [[ ! -f analysis.bin_extracted.flag ]]; then
  rm -rf analysis.bin
  echo "Extracting analysis.bin"
  set -e
  gzip -dk analysis.bin.gz
  touch analysis.bin_extracted.flag
  set +e
else
  echo "analysis.bin already unpacked"
fi

cd ../..
read -p "Build webapps? Press [y/n]" -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
  echo
  echo "========================================================================="
  echo "                Building webapps using reactome-app-builder"
  echo "========================================================================="
  cd ./java-application-builder
  bash ./build_webapps.sh |& tee ../logs/build_webapps.log
  cd ..
  echo "Reactome-app-builder exits here."
fi

echo -e "\n\n"
echo "==========================================================================="
echo "                      Linking mysql Logs"
echo "==========================================================================="

# Link mysql logs
mkdir -p ./logs/mysql/wordpress
mkdir -p ./logs/mysql/tomcat
sudo chown -vR 999:999 ./logs/mysql
owner=$(ls -ld ./logs/mysql | awk 'NR==1 {print $3}')
if ! [[ $owner == 999 || $owner == 'mysql' ]]; then
  # Permissions remain unchanged, logs will reside in internal docker volumes
  # if it is first run of this script, volumes do not exist, we need to create them before providing its link
  # this docker run will exit immidiately due to errors on startup, since we have not supplied root password
  docker run --rm -itd \
  -v "container_mysql-for-tomcat-log:/random/location" \
  -v "container_mysql-for-wordpress-log:/another/random" mysql:5.7

  # Volumes are created, now we can link those volumes to /backup inside container
  sudo ln -s $(docker volume inspect --format '{{ .Mountpoint }}' container_mysql-for-tomcat-log) $(pwd)/logs/mysql/wordpress/Link_to_internal_log
  sudo ln -s $(docker volume inspect --format '{{ .Mountpoint }}' container_mysql-for-wordpress-log) $(pwd)/logs/mysql/tomcat/Link_to_internal_log
  # Use sudo to view content inside the linked directory.
fi

echo -e "\n\n"
echo "==========================================================================="
echo "                        Starting docker containers"
echo "==========================================================================="
docker-compose up
# docker-compose down
