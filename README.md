# patch-release

## Project Name: Release Management Script

This project consists of a script that facilitates managing the release process by switching to the latest release branch, cherry-picking specified commits, and pushing changes to origin. It also provides options for running the release workflow, watching the workflow run, and downloading artifacts.

## Script Usage

The script `release.sh` can be run with the following options:

```bash
Usage: ./release.sh [-c <commit-hash>...] [ -b <branch-name> ] [-p] [-r] [-w]
  -c <commit-hash>   : Cherry-pick the specified commit(s).
  -b <branch-name>   : Specify the branch to cherry-pick from. Default: main.
  -p                 : Push the changes.
  -r                 : Run the release workflow.
  -w                 : Watch the workflow run.
  -d                 : Download artifact.
  -a                 : Download, push changes, run workflow and watch run.
  -m                 : Select commits using fzf.
  -s <release-name>  : Specify a particular release.
Example: ./release.sh -c commit1 -c commit2 -c commit3 -b main -p -r -w
```

### Options Explanation:

- **-c**: Specify one or more commits to be cherry-picked.
- **-b**: Specify the branch from which to cherry-pick commits. Default is `main`.
- **-p**: Push the changes to the origin.
- **-r**: Run the release workflow.
- **-w**: Watch the workflow run to completion.
- **-d**: Download the artifact generated by the workflow.
- **-a**: All in one command to download, push changes, run workflow and watch run.
- **-m**: If no commit is specified, use fzf to select one or more commits for cherry-picking.
- **-s**: Specify a particular release to switch to.

## Features

1. **Error Handling**: The script has built-in error handling to ensure the script exits on any error.
2. **Cleanup**: Ensures that you switch back to the original branch on exit.
3. **Interactive Selection**: If no commits are specified, you can use fzf to interactively select commits.
4. **Downloading Artifacts**: The script can download artifacts from a specified or latest completed workflow run.

## Requirements

- `git`
- `gh` (GitHub CLI)
- `jq`
- `fzf` (optional, for interactive commit selection)

## Required GitHub Workflows
 
This script expects the following GitHub Workflows to be predefined in the repository:
- `release.yml`: This workflow should handle the release process, including any build, test, and deployment steps.
Ensure these workflows are present and correctly configured in your repository before running the script. 
Refer to the [GitHub Actions documentation](https://docs.github.com/en/actions) for more information on setting up workflows.
 

## Running the Script

Ensure you have the necessary permissions to push to the repository and run workflows.

```bash
chmod +x release.sh
./release.sh <options>
```

## Future Improvements

1. Add more robust error handling and reporting.
2. Include logging for better traceability.
3. Extend script to handle more complex workflows and scenarios.

