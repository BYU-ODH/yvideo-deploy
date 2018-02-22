#/bin/bash

default=""
force_clone=""
attach=""
remove=""
build=""
clean=""
setup_only=""
super_duper_clean=""
travis=""
test_local=""
ayamel_dir=""
project_name="runayamel"
git_dir=${GITDIR:-~/Documents/GitHub}
scriptpath="$(cd "$(dirname "$0")"; pwd -P)"
compose_override_file=""
dev_compose_file="docker-compose.dev.yml"
beta_compose_file="docker-compose.beta.yml"
production_compose_file="docker-compose.production.yml"
test_compose_file="docker-compose.test.yml"
template_file=""
exit_code="0"
container=""

declare -A repos # Associative array! :) used in the compose_dev function
repos=([Ayamel]="" [Ayamel.js]="" [EditorWidgets]="" [subtitle-timeline-editor]="" [TimedText]="")
ayamel_remote=(https://github.com/byu-odh/Ayamel)
dependencies_remotes=(https://github.com/byu-odh/Ayamel.js
        https://github.com/byu-odh/EditorWidgets
        https://github.com/byu-odh/subtitle-timeline-editor
        https://github.com/byu-odh/TimedText)
remotes=("${ayamel_remote[@]}" "${dependencies_remotes[@]}")

usage () {
    echo 'Optional Params:'
    echo
    echo '  [--default          | -e]   Accept the default repository locations '
    echo "                               Used for: ${!repos[@]}"
    echo '                               (default is $GITDIR or ~/Documents/GitHub for everything)'
    echo '                               Only used with --test and --dev'
    echo '  [--help             | -h]    Show this dialog'
    echo '  [--attach           | -a]    Attach to the yvideo container after starting it'
    echo '                               The containers will be run in the background unless attach is specified'
    echo "  [--remove           | -r]    Removes all of the containers that start with the project prefix: $project_name"
    echo '                               Containers are removed before anything else is done.'
    echo '  [--clean            | -c]    Remove all of the created files in the runAyamel directory.'
    echo '                               Cleanup is run before any other setup.'
    echo '                               This option can be used without one of the required params.'
    echo '                               If specified twice, cleanup will be called before and after setup.'
    echo '  [--setup-only           ]    Will set up all of the specified services but will not run docker-compose.'
    echo "                               Mainly for development and testing of $project_name"
    echo '  [--build                ]    Will rebuild images even if they have not changed.'
    echo '                               Passes --build to `docker-compose up`'
    echo '                               The way docker-compose responds to --build means that volumes are not deleted.'
    echo '                               This is good but also bad because we want a full reset of the image.'
    echo '                               So if you need to totally recreate the image without it needing a build according to docker-compose,'
    echo '                               then you should delete the images and containers beforehand to ensure everything is up to date.'
    echo '  [--force-recreate   | -x]    Will recreate the containers even if they are up to date.'
    echo '                               Passes --force-recreate to `docker-compose up`'
    echo
    echo
    echo 'Required Params (One of the following. The last given option will be used if multiple are provided):'
    echo
    echo '  [--production       | -p]    Use the production docker-compose override file.'
    echo '  [--beta             | -b]    Use the beta docker-compose override file.'
    echo '  [--dev              | -d]    Use the development docker-compose override file.'
    echo '  [--test             | -t]    Use the development docker-compose override file.'
    echo '                               Use volumes and run tests locally'
    echo '  [--travis               ]    Use the testing docker-compose override file.'
    echo '                               Travis specific setup'
    echo
    echo
    echo 'Environment Variables:'
    echo
    echo '  YVIDEO_SQL              The folder that contains all of the sql scripts to be run. *Not required'
    echo '                          Files in this folder should be named <DATABASE_NAME>.sql.'
    echo '                          One database will be created per file and will have the same name as the .sql file.'
    echo '  YVIDEO_SQL_DATA         The folder for the mysql data volume. *Required (Except when using --travis)'
    echo '  YVIDEO_CONFIG_PROD      The path to the application.conf. *Required only for production'
    echo '  YVIDEO_CONFIG_BETA      The path to the application.conf for the beta service. *Required only for beta'
    echo "  GITDIR                  The path to the yvideo project and all it's dependencies. Used for development. *Not required"
}

options () {
    for opt in "$@"; do
        if [[ "$opt" = "--default" ]] || [[ "$opt" = "-e" ]];
        then
            default="true"

        elif [[ "$opt" = "--force-clone" ]] || [[ "$opt" = "-f" ]];
        then
            force_clone="true"

        elif [[ "$opt" = "--dev" ]] || [[ "$opt" = "-d" ]];
        then
            template_file="template.dev.yml"
            compose_override_file="$dev_compose_file"
            container="$project_name""_yvideo_dev_1"

        elif [[ "$opt" = "--production" ]] || [[ "$opt" = "-p" ]];
        then
            template_file="template.production.yml"
            compose_override_file="$production_compose_file"
            container="$project_name""_yvideo_prod_1"

        elif [[ "$opt" = "--beta" ]] || [[ "$opt" = "-b" ]];
        then
            template_file="template.beta.yml"
            compose_override_file="$beta_compose_file"
            container="$project_name""_yvideo_beta_1"

        elif [[ "$opt" = "--travis" ]];
        then
            template_file=""
            compose_override_file="$test_compose_file"
            container="$project_name""_yvideo_test_1"
            travis=true

        elif [[ "$opt" = "--test" ]] || [[ "$opt" = "-t" ]];
        then
            template_file="template.dev.yml"
            compose_override_file="$dev_compose_file"
            container="$project_name""_yvideo_dev_1"
            test_local=true

        elif [[ "$opt" = "--build" ]];
        then
            build="$opt"

        elif [[ "$opt" = "--force-recreate" ]] || [[ "$opt" = "-x" ]];
        then
            recreate="--force-recreate"

        elif [[ "$opt" = "--help" ]] || [[ "$opt" = "-h" ]];
        then
            usage && exit 1

        elif [[ "$opt" = "--attach" ]] || [[ "$opt" = "-a" ]];
        then
            attach=true

        elif [[ "$opt" = "--remove" ]] || [[ "$opt" = "-r" ]];
        then
            remove=true
        elif [[ "$opt" = "--clean" ]] || [[ "$opt" = "-c" ]];
        then
            if [[ -n "$clean" ]]; then
                super_duper_clean=true
            fi
            clean=true

        elif [[ "$opt" = "--setup-only" ]];
        then
            setup_only=true
        else
            echo "Argument: [$opt] not recognized."
        fi
    done

    if [[ -z "$compose_override_file" ]] && [[ -z "$remove" ]] && [[ -z "$clean" ]]; then
        echo "[Error]: No mode specified"
        echo
        usage
        exit 1
    fi
}

remove_containers () {
    # remove all of the containers that start with runayamel_
    container_ids=$(sudo docker ps -aq -f name=${project_name}_*)
    if [[ -n "$container_ids" ]]; then
        # check non-empty so there are no errors printed
        # can't simply use variable substitution as the output contains newlines
        # clearest is to simply call ps -a twice
        sudo docker rm -f $(sudo docker ps -aq -f name=${project_name}_*)
    fi
}

remove_volumes () {
    echo hi
}

compose_dev () {
    # setting up volumes
    # loop over the keys of the repos associative array
    for repo in "${!repos[@]}"; do
        if [[ -z "$default" ]]; then
            read -r -p "Enter path to $repo (default: ${dir_name:-$git_dir}/$repo): " user_dir
        else
            user_dir=""
        fi
        if [[ -z "$user_dir" ]]; then
            user_dir="$git_dir/$repo"
        else
            # expand the path
            if [[ -d "$user_dir" ]]; then
                user_dir="$( cd "$user_dir"; pwd -P )"
                dir_name=$(dirname "$user_dir")
            else
                echo "$user_dir does not exist."
                user_dir="$dir_name/$repo"
            fi
        fi
        echo "Using $user_dir for $repo."
        repos["$repo"]="$user_dir"
    done

    # set command which will run in the container
    # dev and test use the same dockerfile
    if [[ -n "$test_local" ]]; then
        dev_command="test"
    else
        dev_command="run"
    fi
    export dev_command
    export Ayamel="${repos[Ayamel]}"
    export Ayamel_js="${repos[Ayamel.js]}"
    export subtitle_timeline_editor="${repos[subtitle-timeline-editor]}"
    export EditorWidgets="${repos[EditorWidgets]}"
    export TimedText="${repos[TimedText]}"
    substitute_environment_variables "template.dev.yml" "docker-compose.dev.yml"
}

# used when --travis is specified
compose_test () {

    if [[ -z "$BRANCH" ]]; then
        echo "--travis flag is meant for use on travis CI."
        echo "To test this mode, create an environment variable named BRANCH that"
        echo "contains the name of the branch that you want to test."
        exit 1
    fi
    if [[ "$BRANCH" != "master" ]]; then
        # all branches of Ayamel use the develop branch of the dependencies except for
        # the master branch which uses the master branch of the dependencies
        BRANCH="develop"
    fi
}

# does a shallow clone with only 1 commit on the $1 branch for all repositories
# expects a branchname as an argument
# The branch should exist on all yvideo repositories
# clones the repos into the $2 folder
# $2 should be either production or beta
compose_production () {

    # copy the application.conf file into the context of the dockerfile
    # Needs to be copied because:
    # The <src> path must be inside the context of the build;
    # you cannot COPY ../something /something, because the first step of a docker build
    # is to send the context directory (and subdirectories) to the docker daemon.
    # https://docs.docker.com/engine/reference/builder/#copy
    if [[ -f "$YVIDEO_CONFIG" ]]; then
        # clone the ayamel branch into the production folder
        git clone -b "$1" --depth 1 "$ayamel_remote" "$2"/$(basename $ayamel_remote) &> /dev/null
        # copy it into the production dockerfile folder
        cp "$YVIDEO_CONFIG" "$2"/application.conf
    else
        echo "[$YVIDEO_CONFIG] does not exist."
        echo "The environment variable YVIDEO_CONFIG_[BETA | PROD] needs to be exported to this script in order to run yvideo in production mode."
        exit 1
    fi
}

# $1 is the template file ex: template.dev.yml
# and corresponds to the docker-compose template we want to fill out
# with environment variables
# $2 is the name of the output file
substitute_environment_variables () {
    echo "Substituting Environment variables for $1 --> $2"
    if [[ ! -f "$1" ]]; then
        echo "[ERROR]: substitute environment variables: $1 does not exist."
        exit 1
    fi
    cat "$1" | envsubst > "$2"
}

prod_cleanup () {
    cd production
    rm -rf Ayamel
    rm -f application.conf
    cd ../
}

beta_cleanup () {
    cd beta
    rm -rf Ayamel
    rm -f application.conf*
    cd ..
}

dev_cleanup () {
    # This file is the one with the volumes filled in by envsubst
    # so we get rid of the filled out version here
    rm -f docker-compose.dev.yml
}

cleanup () {
    echo "Cleanup..."
    prod_cleanup
    beta_cleanup
    dev_cleanup

    cd db
    rm -f *.sql
    cd ..

    cd lamp
    rm -rf beta
    rm -rf production
    cd ..
}

configure_lamp () {
    # the dependencies go inside there
    # docker 17.05 doesn't like to copy the deps' folders' if they are in production/Dep_folder
    # it cuts out the first folder for some reason
    # so we nest another folder there
    # it might just be an error with the way we are copying in the dockerfile
    mkdir -p lamp/beta lamp/production

    # clone the dependencies into the lamp folder
    declare -A services
    services[production]="master"
    services[beta]="develop"

    for service in "${!services[@]}"; do
        for repo in "${dependencies_remotes[@]}"; do
            git clone -b "${services[$service]}" --depth 1 "$repo" lamp/"$service"/$(basename $repo) &> /dev/null
        done
    done
}

configure_database () {
    # Check if data volume env var is defined and the path exists if we need it
    if [[ ! -d "$YVIDEO_SQL_DATA" ]]; then
        # We don't use database volumes for testing on travis
        if [[ "$compose_override_file" != "$test_compose_file" ]]; then
            echo "[$YVIDEO_SQL_DATA] does not exist."
            echo "The environment variable YVIDEO_SQL_DATA needs to be exported to this script."
            echo "And it needs to contain the path to a directory."
            exit 1
        fi
    fi

    # Special case for when running from within travis
    if [[ "$compose_override_file" = "$test_compose_file" ]]; then
        # copy the travis sql files from the test folder
        cp test/*.sql db/
    elif [[ -d "$YVIDEO_SQL" ]]; then
        # YVIDEO_SQL is a folder that contains the sql files to load into the database
        # copy it into the database dockerfile folder
        cp "$YVIDEO_SQL/"*.sql db/
    else
        echo "[$YVIDEO_SQL] does not exist."
        echo "No new databases will be created."
    fi
}

setup () {
    # Turn off other mysql servers
    if [[ -n $(pgrep mysql) ]]; then
        echo "Stopping mysql database..."
        sudo service mysql stop
    fi

    configure_database
    if [[ -n "$template_file" ]]; then
        echo "Creating $compose_override_file"
        substitute_environment_variables "$template_file" "$compose_override_file"
    elif [[ "$compose_override_file" != "$test_compose_file" ]]; then
        echo "Script Broken Error: "
        echo "Using $compose_override_file but no template file was specified."
        echo "This should not happen...exiting"
        exit 1
    fi
    configure_lamp

    if [[ "$compose_override_file" = "$dev_compose_file" ]]; then
        compose_dev
    elif [[ "$compose_override_file" = "$production_compose_file" ]]; then
        branchname="master"
        destination="production"
        YVIDEO_CONFIG="$YVIDEO_CONFIG_PROD"
        compose_production $branchname $destination
    elif [[ "$compose_override_file" = "$beta_compose_file" ]]; then
        branchname="develop"
        destination="beta"
        YVIDEO_CONFIG="$YVIDEO_CONFIG_BETA"
        compose_production $branchname $destination
    elif [[ "$compose_override_file" = "$test_compose_file" ]]; then
        compose_test
    fi
}

run_docker_compose () {
    # Run docker-compose file (within runAyamel directory)
    echo "Creating Containers..."

    if [[ -n $build ]]; then
        echo "[INFO] - Re-Building All Docker Images."
    else
        echo "[INFO] - Using Existing Images if Available."
    fi

    # quoting like so: "$build" breaks docker-compose up if it is empty
    sudo docker-compose -f docker-compose.yml -f "$compose_override_file" up -d $build $recreate
    exit_code="$?"
    [[ -n "$attach" ]] && [[ -n "$container" ]] && sudo docker attach --sig-proxy=false "$container"
}

cd "$scriptpath"
options "$@"
[[ -n "$remove" ]] && remove_containers
[[ -n "$clean" ]]                 && cleanup
[[ -n "$compose_override_file" ]] && setup && [[ -z "$setup_only" ]] && run_docker_compose
[[ -n "$super_duper_clean" ]]     && cleanup
# use the docker-compose up command exit code rather than whatever the last line may output
exit "$exit_code"

