#!/bin/bash
# shellcheck disable=SC2103

set -e
# removing option -x to avoid disclosure of passwords/tokens

usage() {
    echo "usage: sh $0 -p <project id> -o <openshift host> -b <bitbucket host> -c <http basic auth credentials \
for bitbucket host> -t <target env to clone to> -s <source env to clone from>";
}

export ODS_BITBUCKET_PROJECT=opendevstack

while [[ "$#" -gt 0 ]]; do case $1 in
  -o=*|--openshift-host=*) OPENSHIFT_HOST="${1#*=}";;
  -o|--openshift-host) OPENSHIFT_HOST="$2"; shift;;

  -b=*|--bitbucket-host=*) BITBUCKET_HOST="${1#*=}";;
  -b|--bitbucket-host) BITBUCKET_HOST="$2"; shift;;

  --ods-bitbucket-project=*) ODS_BITBUCKET_PROJECT="${1#*=}";;
  --ods-bitbucket-project) ODS_BITBUCKET_PROJECT="$2"; shift;;

  -p=*|--project-id=*) PROJECT_ID="${1#*=}";;
  -p|--project-id) PROJECT_ID="$2"; shift;;

  -s=*|--source-env=*) SOURCE_ENV="${1#*=}";;
  -s|--source-env) SOURCE_ENV="$2"; shift;;

  -t=*|--target-env=*) TARGET_ENV="${1#*=}";;
  -t|--target-env) TARGET_ENV="$2"; shift;;

  -d|--debug) DEBUG=true;;

  -st|--skiptags) SKIP_TAGS=true;;

  -gb=*|--git-branch=*) GIT_BRANCH="${1#*=}";;
  -gb|--git-branch) GIT_BRANCH="$2"; shift;;

  --skip-tag) SKIP_TAGS="true"; shift;;

  *) echo "Unknown parameter passed: $1"; usage; exit 1;;
esac; shift; done

if [[ -z "$PROJECT_ID" ]]; then
    echo "[ERROR]: No project id set - required value"
    usage
    exit 1
fi
if [[ -z "$BITBUCKET_HOST" ]]; then
    echo "[ERROR]: No BitBucket host set - required value"
    usage
    exit 1
fi
if [[ -z "$TARGET_ENV" ]]; then
    echo "[ERROR]: No target environment set - required value"
    usage
    exit 1
fi
if [[ -z "$SOURCE_ENV" ]]; then
    echo "[ERROR]: No source environment set - required value"
    usage
    exit 1
fi
if [[ -z "$OPENSHIFT_HOST" ]]; then
    echo "[ERROR]: No OpenShift host set - required value"
    usage
    exit 1
fi

if [[ -z "$GIT_BRANCH" ]]; then
    echo "[DEBUG]: no target git branch set - defaulting to master"
    GIT_BRANCH=master
fi

echo "Provided params: \
- PROJECT_ID: $PROJECT_ID \
- OPENSHIFT_HOST: $OPENSHIFT_HOST \
- BITBUCKET_HOST: $BITBUCKET_HOST \
- SOURCE_ENV: $SOURCE_ENV \
- TARGET_ENV: $TARGET_ENV"

SOURCE_PROJECT="$PROJECT_ID-$SOURCE_ENV"
TARGET_PROJECT="$PROJECT_ID-$TARGET_ENV"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "[INFO]: creating workplace: mkdir -p oc_migration_scripts/migration_config"
mkdir -p oc_migration_scripts/migration_config
cd oc_migration_scripts/migration_config
pwd

echo "Creating source file"
echo "oc_env=$OPENSHIFT_HOST" > ocp_project_config_source
echo "OD_OCP_CD_SA_SOURCE=$(oc whoami | sed  -e 's/system:serviceaccount://g')" >> ocp_project_config_source

echo "Creating target file"
echo "oc_env=$OPENSHIFT_HOST" > ocp_project_config_target
echo "OD_OCP_CD_SA_TARGET=$(oc whoami | sed  -e 's/system:serviceaccount://g')" >> ocp_project_config_target

cd ..
pwd

# credentials are expected to be managed by netrc or supplied by OS/user interaction.
git_url="https://$BITBUCKET_HOST/scm/$PROJECT_ID/$PROJECT_ID-occonfig-artifacts.git"

if [[ -z "$DEBUG" ]]; then
  verbose=""
else
  verbose="-v true"
fi

echo "[INFO]: export resources from $SOURCE_ENV"
sh "$SCRIPT_DIR/export-project.sh" -p "$PROJECT_ID" -h "$OPENSHIFT_HOST" -e "$SOURCE_ENV" -g "$git_url" -gb "$GIT_BRANCH" -cpj "$verbose"
echo "[INFO]: import resources into $TARGET_ENV"
sh "$SCRIPT_DIR/import-project.sh" -h "$OPENSHIFT_HOST" -p "$PROJECT_ID" -e "$SOURCE_ENV" -g "$git_url" -gb "$GIT_BRANCH" -n "$TARGET_PROJECT" "$verbose" --apply true

echo "[INFO]: cleanup workplace"
cd ..
rm -rf oc_migration_scripts

if [[ -n "$SKIP_TAGS" ]]; then
  echo "[INFO] Skipping imagestream tagging"
  return
fi

echo "[INFO]: import image tags from $SOURCE_ENV"
oc get is --no-headers -n "$SOURCE_PROJECT" | awk '{print $2}' | while read -r DOCKER_REPO; do
  echo "[INFO]: importing latest image from ${DOCKER_REPO}"
  image="${DOCKER_REPO}:latest"
  oc tag "${SOURCE_PROJECT}/${image}" "${image}" -n "$TARGET_PROJECT" || true
done
