#!/usr/bin/env bash

# Halt on error
set -e

emt_dir=/tmp/emt
events_dir=$emt_dir/events
gw_merge_dir=$emt_dir/apigateway
aga_merge_dir=$emt_dir/analytics
reports_dir=$emt_dir/reports
sql_dir=$emt_dir/sql
mysql_jar_version=8.0.25
mysql_image_version=5.7
cassandra_image_version=3.11.11
dagent_image_version=1.1.16
tagent_image_version=1.1.16
metrics_env_vars="-e METRICS_DB_URL=jdbc:mysql://metricsdb:3306/metrics?useSSL=false -e METRICS_DB_USERNAME=root -e METRICS_DB_PASS=root01"
distribution_base=centos7
accept_conditions=no
# force the build of docker images (and cleanup)
force_build=${FORCE_BUILD:-1}
# random uid and gid=0
dynamic_user=${DYNAMIC_USER:-0}

is_linux() {
    [[ "$(uname)" == "Linux" ]]
}

cleanup() {
    echo "*** Cleaning up any previous run ***"
    rm -rf "$emt_dir"
    docker rm -f anm analytics apimgr casshost1 metricsdb dagent tagent 2>/dev/null || true
    if [[ -n "$force_build" && "$force_build" -eq 1 ]]; then
        docker rmi admin-node-manager apigw-analytics api-gateway-defaultgroup apigw-base 2>/dev/null || true
    else
        echo "info: force_build is disabled, not removing previously built images"
    fi
    docker network rm api-gateway-domain 2>/dev/null || true
}

is_substring() {
    case "$2" in
        *$1*) return 0;;
        *) return 1;;
    esac
}

validate_env() {
    echo "*** Validating environment ***"
    local name
    name=$(hostname)
    if is_substring "_" "${name}"
    then
        echo "Error: Configured hostname \"$name\" contains underscore symbol in it. Such is unsupported!"
        exit 1
    fi
}

setup() {
    echo
    echo "Building and starting an API Gateway domain that contains an Admin Node Manager,"
    echo "API Manager and API Gateway Analytics."

    local tmp_jar
    local mysql_jar_url

    # the Docker image can run as any user (thanks to the changes made for OpenShift compatibility)
    # emtuser_uid/emtuser_gid is for the image default user
    if is_linux; then
        emtuser_uid=$(id -u)
        emtuser_gid=$(id -g)
    else
        emtuser_uid=$(id -u)
        # gid on Mac can be above 2^15, which wouldn't work on containers
        emtuser_gid=${EMTUSER_GID:-204} # on Mac, gid=204 is available is user is part of group "_developer"
    fi
    # container_uid/container_gid is for the container user, which may be different than the image ones
    if [[ -z "$dynamic_user" || "$dynamic_user" -eq 0 ]]; then
        container_uid="$emtuser_uid"
        container_gid="$emtuser_gid"
    else
        # OpenShift like, restricted SCC would create a random uid and set gid=0
        container_uid=$(( 5000 + RANDOM % 1000 ))
        container_gid=0
    fi
    echo "info: will start the APIM containers with uid=$container_uid and gid=$container_gid"
    cd "$(dirname "$0")/.."
    mkdir -p "$events_dir" "$gw_merge_dir/ext/lib" "$aga_merge_dir/ext/lib" "$reports_dir" "$sql_dir"
    if [[ ! $(is_linux) ]]; then
        if ! id | grep -w "$emtuser_gid"; then
            echo "Error: host user is not part of group $emtuser_gid"
            exit 1
        fi
        chgrp -R "$emtuser_gid" "$events_dir" "$gw_merge_dir/ext/lib" "$aga_merge_dir/ext/lib" "$reports_dir" "$sql_dir"
    fi

    echo
    echo "Downloading MySQL connector JAR..."
    mysql_jar_url="https://repo1.maven.org/maven2/mysql/mysql-connector-java/$mysql_jar_version/mysql-connector-java-${mysql_jar_version}.jar"
    tmp_jar="$emt_dir/mysql-connector-java-${mysql_jar_version}.jar"
    curl -s "$mysql_jar_url" -o "$tmp_jar"

    cp "$tmp_jar" "$gw_merge_dir/ext/lib/"
    mv "$tmp_jar" "$aga_merge_dir/ext/lib/"
    cp quickstart/mysql-analytics.sql "$sql_dir/"

    echo
    echo "*** Generating default domain certificate ***"
    ./gen_domain_cert.py --default-cert || true

    echo
    echo "*** Creating Docker network to allow containers to communicate with one another ***"
    docker network create api-gateway-domain
    echo
    echo "*** Starting Cassandra container to store API Manager data ***"
    docker run -d --name=casshost1 --network=api-gateway-domain "cassandra:$cassandra_image_version"
    echo
    echo "*** Starting MySQL container to store metrics data ***"
    docker run -d --name metricsdb --network=api-gateway-domain \
        -v "$sql_dir:/docker-entrypoint-initdb.d" \
        -e MYSQL_ROOT_PASSWORD=root01 -e MYSQL_DATABASE=metrics \
        "mysql:$mysql_image_version"
}

build_base_image() {
    echo
    if [[ -n "$force_build" && "$force_build" -eq 1 ]]; then
        echo "******************************************************************"
        echo "*** Building base image for Admin Node Manager and API Gateway ***"
        echo "******************************************************************"
        ./build_base_image.py \
            --installer="$APIGW_INSTALLER" \
            --os="$distribution_base" \
            --user-uid="$emtuser_uid" \
            --user-gid="$emtuser_gid"
    fi
}

build_anm_image() {
    echo
    if [[ -n "$force_build" && "$force_build" -eq 1 ]]; then
        echo "**********************************************************"
        echo "*** Building and starting Admin Node Manager container ***"
        echo "**********************************************************"
        ./build_anm_image.py \
            --default-cert \
            --default-user \
            --metrics \
            --merge-dir="$gw_merge_dir"
    fi

    echo "*** Starting anm container ***"
    # shellcheck disable=SC2086
    docker run -d --name=anm --network=api-gateway-domain \
        -u "$container_uid:$container_gid" \
        -p 8090:8090 \
        -v "$events_dir:/opt/Axway/apigateway/events" \
        -e ACCEPT_GENERAL_CONDITIONS="$accept_conditions" \
        $metrics_env_vars admin-node-manager
}

build_analytics_image() {
    echo
    if [[ -n "$force_build" && "$force_build" -eq 1 ]]; then
        echo "*************************************************************"
        echo "*** Building and starting API Gateway Analytics container ***"
        echo "*************************************************************"
        ./build_aga_image.py \
            --license="$LICENSE" \
            --installer="$APIGW_INSTALLER" \
            --os="$distribution_base" \
            --merge-dir="$aga_merge_dir" \
            --default-user \
            --user-uid="$emtuser_uid" \
            --user-gid="$emtuser_gid"
    fi

    echo "*** Starting analytics container ***"
    # shellcheck disable=SC2086
    docker run -d --name=analytics \
        --network=api-gateway-domain \
        -u "$container_uid:$container_gid" \
        -p 8040:8040 -v "$reports_dir:/tmp/reports" \
        -e ACCEPT_GENERAL_CONDITIONS="$accept_conditions" \
        $metrics_env_vars apigw-analytics
}

build_gateway_image() {
    echo
    if [[ -n "$force_build" && "$force_build" -eq 1 ]]; then
        echo "***************************************************"
        echo "*** Building and starting API Manager container ***"
        echo "***************************************************"
        ./build_gw_image.py \
            --license="$LICENSE" \
            --merge-dir="$gw_merge_dir" \
            --default-cert \
            --api-manager
    fi

    echo "*** Starting apimgr container ***"
    # shellcheck disable=SC2086
    docker run -d --name=apimgr \
        --network=api-gateway-domain \
        -u "$container_uid:$container_gid" \
        -p 8075:8075 -p 8065:8065 -p 8080:8080 \
        -v "$events_dir:/opt/Axway/apigateway/events" \
        -e EMT_DEPLOYMENT_ENABLED=true -e EMT_ANM_HOSTS=anm:8090 -e CASS_HOST=casshost1 \
        -e ACCEPT_GENERAL_CONDITIONS="$accept_conditions" \
        $metrics_env_vars api-gateway-defaultgroup
}

wait_for_apimgr_to_start() {
    set +e
    echo
    echo "*** Waiting for apimgr container to start ****"
    tries=0
    while [[ $tries -lt 12 ]]
    do
        sleep 10
        if docker logs apimgr | grep 'service started' > /dev/null; then
             break;
        fi
        tries=$((tries +1))
    done
    if [[ $tries -eq 12 ]]; then
        echo
        echo "*** Problems starting API Manager. Please check logs using 'docker logs apimgr'"
        exit 1
    fi
}

start_agents() {
    echo
    echo "*** Starting discovery agent ***"
    docker run -d --name=dagent --network=api-gateway-domain \
         --env-file "$AGENTS_ENV_DIR/da_env_vars.env" -v "$AGENTS_ENV_DIR:/keys" \
         axway.jfrog.io/ampc-public-docker-release/agent/v7-discovery-agent:${dagent_image_version}
    echo
    echo "*** Starting traceability agent ***"
    docker run -d --name=tagent --network=api-gateway-domain \
         --env-file "$AGENTS_ENV_DIR/ta_env_vars.env" -v "$AGENTS_ENV_DIR:/keys" -v ${events_dir}:/events \
         axway.jfrog.io/ampc-public-docker-release/agent/v7-traceability-agent:${tagent_image_version}
}

finish() {
    echo
    echo "************"
    echo "*** Done ***"
    echo "************"
    echo
    if [ ! "$AGENTS_ENV_DIR" ]; then
        echo "Wait a couple of minutes for startup to complete."
        echo
    fi
    echo "Login to API Gateway Manager at https://localhost:8090 (admin/changeme)"
    echo "Login to API Manager at https://localhost:8075 (apiadmin/changeme)"
    echo "Login to API Gateway Analytics at https://localhost:8040 (admin/changeme)"
}

if [ $# -lt 2 ]; then
    echo "Usage: quickstart.sh INSTALLER LICENSE ACCEPT_GENERAL_CONDITIONS=yes"
    echo
    echo "Builds and starts an API Gateway domain that contains an Admin Node Manager,"
    echo "API Manager and API Gateway Analytics."
    echo
    echo "Options:"
    echo "  INSTALLER                 Path to 7.6+ API Gateway installer"
    echo "  LICENSE                   Path to license for API Manager and API Gateway Analytics"
    echo "  ACCEPT_GENERAL_CONDITIONS Confirm that you have read the general terms and agreement of the product. Must be set to yes."
    echo "  AGENTS_ENV_DIRECTORY      Path to directory containing Traceability and Discovery Agents' environment files and keys"
    echo
    echo "environment variables altering the behavior of the script:"
    echo "export FORCE_BUILD=0  # the script will not build the images again and will reuse previously built images"
    echo "                      # default is FORCE_BUILD=1"
    echo "export DYNAMIC_USER=1 # the docker containers will be created with a random UID instead of the one built in the images"
    echo "                      # default is DYNAMIC_USER=0"
    exit 1
elif [ ! -f "$1" ]; then
    echo "Error: API Gateway installer does not exist: \"$1\""
    exit 1
elif [ ! -f "$2" ]; then
    echo "Error: License file does not exist: \"$2\""
    exit 1
elif [ ! "$3" ]; then
      echo "Error: ACCEPT_GENERAL_CONDITIONS argument not set. Must be set to ACCEPT_GENERAL_CONDITIONS=yes."
    exit 1
elif [ "$3" != "ACCEPT_GENERAL_CONDITIONS=yes" ]; then
    echo "Error: ACCEPT_GENERAL_CONDITIONS argument must be set to yes: \"$3\""
    exit 1
fi

if [ -L "$1" ]; then
    APIGW_INSTALLER=$(readlink "$1")
else
    APIGW_INSTALLER="$1"
fi
if [ -L "$LICENSE" ]; then
    LICENSE=$(readlink "$2")
else
    LICENSE="$2"
fi
if [ "$4" ]; then
    if [ -L "$4" ]; then
        AGENTS_ENV_DIR=$(readlink "$4")
    else
        AGENTS_ENV_DIR="$4"
    fi
fi
accept_conditions="yes"
validate_env
cleanup
setup
build_base_image
build_anm_image
build_analytics_image
build_gateway_image
if [ "$AGENTS_ENV_DIR" ]; then
    wait_for_apimgr_to_start
    start_agents
fi
finish
