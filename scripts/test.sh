#!/bin/bash

set -o errexit -o pipefail

source ./scripts/common.sh

programs_dir="themes/default/static/programs"

# Delete install artifacts, but leave existing go.mod files.
git clean -fdX -e '!go.mod' "${programs_dir}/*"

# Fix up go.mod files.
clean_gomods
unsuffix_gomods

# By default, only run previews.
mode="${1:-preview}"

# If we're only running previews, just use local mode -- it's faster.
if [[ "$mode" == "preview" ]]; then
    org="organization"
    export PULUMI_CONFIG_PASSPHRASE="foo"
    pulumi login --local
else
    org="$(pulumi whoami -v --json | jq -r .user)"
fi

pushd "$programs_dir"
    for dir in */; do
        project="$(basename $dir)"

        # Optionally test only selected examples by setting an ONLY_TEST="<example-path>"
        # environment variable (e.g., ONLY_TEST="awsx-ecr-repository").
        if [[ ! -z "$ONLY_TEST" && "$dir" != "$ONLY_TEST"* ]]; then
            continue
        fi

        echo
        echo "***"
        echo "* $project"
        echo "***"
        echo

        stack="dev"
        fqsn="${org}/${project}/${stack}"

        # Install dependencies.
        pulumi -C "$project" install

        # Skip previews known not to work.

        # Java examples of FargateService erroneously complain about missing container declarations.
        # https://github.com/pulumi/pulumi-awsx/issues/820
        if [[ "$project" == "awsx-vpc-fargate-service-java" ]]; then
            continue
        elif [[ "$project" == "awsx-load-balanced-fargate-ecr-java" ]]; then
            continue
        elif [[ "$project" == "awsx-load-balanced-fargate-nginx-java" ]]; then
            continue
        fi

        # Destroy any existing stacks.
        pulumi -C "$project" cancel --stack $fqsn --yes || true
        pulumi -C "$project" destroy --stack $fqsn --yes --refresh --remove || true

        # Create a new stack.
        pulumi -C "$project" stack select $fqsn || pulumi -C "$project" stack init $fqsn
        pulumi -C "$project" config set aws:region us-west-2 || true

        # Preview or deploy.
        if [[ "$mode" == "update" ]]; then

            # Skip updates known not to work.

            # Error converting 'java.util.Collections$UnmodifiableRandomAccessList' to 'TypeShape{type=interface java.util.List, parameters=[TypeShape{type=class com.pulumi.aws.lb.outputs.TargetGroupTargetHealthState, parameters=[]}]}'.
            # https://github.com/pulumi/pulumi-java/issues/1276
            if [[ "$project" == "awsx-elb-web-listener-java" ]]; then
                continue
            elif [[ "$project" == "awsx-elb-multi-listener-redirect-java" ]]; then
                continue
            elif [[ "$project" == "awsx-load-balanced-ec2-instances-java" ]]; then
                continue
            fi

            pulumi -C "$project" up --yes
        else
            pulumi -C "$project" preview
        fi

        # Destroy and remove.
        pulumi -C "$project" destroy --yes --remove
    done
popd

clean_gomods
suffix_gomods

# Log out of local mode.
if [[ "$mode" == "preview" ]]; then
    export PULUMI_CONFIG_PASSPHRASE="foo"
    pulumi logout --local
fi
