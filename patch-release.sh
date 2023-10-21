#!/bin/bash 

set -e

usage() {
    echo "Usage: $0 [-c <commit-hash>...] [ -b <branch-name> ] [-p] [-r] [-w]"
    echo "This script switches to the latest release branch, cherry-picks the specified commits, and pushes the changes to origin."
    echo "Multiple commits can be specified with multiple -c options."
    echo "If no commits are specified, you will be prompted to select one using fzf."
    echo "-p : push the changes"
    echo "-r : run the release workflow"
    echo "-b : Pick cherries from branch. Default: main"
    echo "-d : Download artifact"
    echo "-w : watch the workflow run"
    echo "Example: $0 -c commit1 -c commit2 -c commit3 -b main -p -r -w"
    exit 1;
}

# default values
push_changes=false
run_workflow=false
watch_run=false

SELECT_CHERRIES=false

BRANCH=main
download=false

declare -a CHERRIES=()

while getopts ":c:b:madprws:" opt; do
    case ${opt} in
	    a)
	        download=true
	        push_changes=true
	        run_workflow=true
	        watch_run=true
	        ;;
	    b)
	        BRANCH=${OPTARG}
	        ;;
	    c)
            CHERRIES+=("${OPTARG}")
            ;;
        m)
            SELECT_CHERRIES=true
            ;;
	    d)
	        download=true
	        ;;
	    p)
	        push_changes=true
	        ;;
	    r)
	        run_workflow=true
	        ;;
	    w)
	        watch_run=true
	        ;;
	    s)
	        SELECTED_RELEASE=${OPTARG}
	        ;;
	    \?)
	        echo "Invalid option: -$OPTARG" >&2
	        usage
	        ;;
	    :)
	        echo "Option -$OPTARG requires an argument." >&2
	        usage
	        ;;
    esac
done

# Debugging function
execute() {
    [ "$debug" = true ] && echo "+ $@"
    "$@"
}


function cleanup {
    # Check if we already are on $BRANCH
    echo Cleaning up
    current_branch=$(git branch --show-current)

    # Check if there is a cherry-pick or revert currently in progress
    if git rev-parse --quiet --verify CHERRY_PICK_HEAD || git rev-parse --quiet --verify REVERT_HEAD; then
        echo REVERTING PICK
        git cherry-pick --abort
        git revert --abort
    fi

    if [[ $current_branch != $BRANCH ]]; then
        git switch $BRANCH # switch back to the original branch on exit
    fi

}

trap cleanup EXIT

RELEASE=$(git branch -r | grep -E "origin/release/[0-9]\." | sort -V |  sed -En '$s#origin/|\s+##p')

if [ -z "$RELEASE" ]; then
    echo "No release branch found."
    exit 1
else
    echo Release: $RELEASE
fi

RELEASE=${RELEASE#origin/}

function switch_to_release() {
    echo switching to release
    git fetch origin
    # If a specific release was provided as an argument, use it
    if [ -n "$SELECTED_RELEASE" ]; then
	    if [ "$SELECTED_RELEASE" = "-" ]; then
	        # Use fzf to select the release
	        RELEASE=$(git branch -r | grep -E "origin/release/[0-9]\." | sort -V | fzf --height 20% --reverse | sed -En '$s#origin/|\s+##p')
	    else
	        RELEASE=$SELECTED_RELEASE
	    fi
    else
	    # Else fetch the latest one
	    RELEASE=$(git branch -r | grep -E "origin/release/[0-9]\." | sort -V |  sed -En '$s#origin/|\s+##p')
    fi

    if [ -z "$RELEASE" ]; then
	    echo "No release branch found."
	    exit 1
    fi

    RELEASE=${RELEASE#origin/}

    if ! git rev-parse --verify ${RELEASE} > /dev/null 2>&1
    then
	    git branch ${RELEASE} origin/${RELEASE}
    fi

    git switch $RELEASE
    git pull
    if [ $? -ne 0 ]; then
	    echo "Failed to switch to $RELEASE."
	    exit 1
    fi
}

# git log --pretty=format:"%C(red)%h%C(reset) %C(green)%s%C(reset) %C(yellow)%d%C(reset) %C(blue)%an%C(reset)" --color| fzf --ansi --height 20% --reverse --multi | awk '{print $1}'

function cherry_pick_commit() {
    echo Cherry picking commits

    if [ ${#CHERRIES[@]} -eq 0 ]; then
        echo "No commit specified, using fzf to select one or more."
        selected_commits=($(git log --oneline origin/$BRANCH | fzf --height 20% --reverse --multi | awk '{print $1}'))
        CHERRIES=("${selected_commits[@]}")
    fi

    NUM_COMMITS=${#CHERRIES[@]}

    for CHERRY in "${CHERRIES[@]}"; do
        echo Picking: $CHERRY
        git cherry-pick $CHERRY
        if [ $? -ne 0 ]; then
            echo "Failed to cherry-pick $CHERRY."
            exit 1
        fi
    done

    git log --pretty=format:"%C(red)%h%C(reset) %C(green)%s%C(reset) %C(yellow)%d%C(reset)" -n $(($NUM_COMMITS + 3))
}

function push_to_origin() {
    read -p "Do you want to push the release (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "No file selected."
        exit 1
    fi

    
    git push origin
    if [ $? -ne 0 ]; then
	    echo "Failed to push changes to origin."
	    exit 1
    fi

    echo "Successfully cherry-picked $CHERRY to $RELEASE and pushed to origin."
}

RUN_ID=""


function get_worflow_id () {
    # Wait until the run appears in the list
    echo Getting workflow id
    attempts=0
    max_attempts=5
    waitfor=5
    
    while [[ $attempts -lt $max_attempts ]]; do
	    RUN_ID=$(gh run list --workflow=release.yml --status "queued" --json databaseId| jq '.[0].databaseId')

	    if [[ RUN_ID == "null" ]]
	    then
	        RUN_ID=$(gh run list --workflow=release.yml --status "in_progress" --json databaseId| jq '.[0].databaseId')
	    fi

        if [[ $RUN_ID != "null" ]]; then
	        echo found workflow: $RUN_ID
            break
        fi 

	    echo $attempts try did not find workflow, waiting $attempts sec.
        sleep $attempts
        let attempts++
    done

    if [[ $attempts -eq $max_attempts ]]; then
        echo "Failed to get workflow run ID after $max_attempts attempts."
        exit 1
    fi
}

function run_release_workflow () {
    echo gh workflow run release.yml --field release-mode=patch --ref ${RELEASE}
    gh workflow run  release.yml --field release-mode=patch --ref ${RELEASE}
    get_worflow_id
}

function watch () {
    if [[ -z ${RUN_ID} ]]; then
	    RUN_ID=$(gh run list --workflow=release.yml --status "queued" --status "in_progress" --json databaseId | jq '.[0].databaseId')
    fi
    if [[ $RUN_ID != null ]]; then
	    gh run watch $RUN_ID
    else
	    echo nothing to watch
    fi
}



if [[ $SELECT_CHERRIES == true ]]; then
    switch_to_release
    cherry_pick_commit
else
    if [[  ${#CHERRIES[@]} -ne 0 ]]; then
        switch_to_release
        cherry_pick_commit
    fi
fi


if [[ $push_changes == true ]]; then
    switch_to_release
    push_to_origin
fi

if [[ $run_workflow == true ]]; then
    switch_to_release
    run_release_workflow
fi

if [[ $watch_run == true ]]; then
    watch
fi


# Get names of artifacts from:
# gh api -H "Accept: application/vnd.github+json"   -H "X-GitHub-Api-Version: 2022-11-28"   /repos/fremtind/bsf-online/actions/runs/5312684050/artifacts
#





if $download; then
    echo "Downloading artifacts:..."

    if [[ -z $RUN_ID ]]; then
	    RUN_ID=$(gh run list --workflow=release.yml --status "completed" --json databaseId| jq '.[0].databaseId')
    fi;
    
    # Get OWNER and REPO with git commands
    REPO_URL=$(git config --get remote.origin.url)
    OWNER=$(basename $(dirname $REPO_URL)| cut -f 2 -d :)
    REPO=$(basename $REPO_URL .git)

    # Get the artifact details 
    ARTIFACTS=$(gh api /repos/$OWNER/$REPO/actions/runs/$RUN_ID/artifacts)
    
    # Loop through the artifacts
    echo "$ARTIFACTS" | jq -r '.artifacts[] | "\(.id) \(.name)"' | while read -r line; do
	    ARTIFACT_ID=$(echo $line | cut -d' ' -f1)
	    ARTIFACT_NAME=$(echo $line | cut -d' ' -f2-)

	    echo "Downloading $ARTIFACT_NAME"

	    # Create a placeholder file
	    touch ~/Downloads/$ARTIFACT_NAME.zip.tmp
	    
	    # Download the artifact into a temporary file
	    gh api \
           -H "Accept: application/vnd.github+json" \
           -H "X-GitHub-Api-Version: 2022-11-28" \
           /repos/$OWNER/$REPO/actions/artifacts/$ARTIFACT_ID/zip \
           > ~/Downloads/$ARTIFACT_NAME.zip.tmp
	    
	    # Once the download is complete, replace the placeholder file with the actual file
	    mv ~/Downloads/$ARTIFACT_NAME.zip.tmp ~/Downloads/$ARTIFACT_NAME.zip
    done
fi
