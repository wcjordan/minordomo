#!/usr/bin/env bats
# Tests for shared/setup-env.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-env.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"

    # Unset any previously derived vars to ensure clean state
    unset DOMAIN_ROOT JIRA_URL JENKINS_USERNAME JIRA_EMAIL JIRA_API_TOKEN GH_TOKEN BASE_BRANCH

    # Fake credentials matching what Jenkins injects
    export ROOT_DOMAIN="example.com"
    export GH_APP_PSW="gh-fake-token"
    export JIRA_ACCT_PSW="jira-fake-token"
    export JIRA_ACCT_USR="test@example.com"
    export JIRA_CLOUD_ID="abc123cloudid"
}

@test "exports DOMAIN_ROOT as the subdomain prefix of ROOT_DOMAIN" {
    source shared/setup-env.sh
    [ "$DOMAIN_ROOT" = "example" ]
}

@test "exports JIRA_URL using JIRA_CLOUD_ID" {
    source shared/setup-env.sh
    [ "$JIRA_URL" = "https://api.atlassian.com/ex/jira/abc123cloudid" ]
}

@test "exports JENKINS_USERNAME as DOMAIN_ROOT@gmail.com" {
    source shared/setup-env.sh
    [ "$JENKINS_USERNAME" = "example@gmail.com" ]
}

@test "exports GH_TOKEN from GH_APP_PSW" {
    source shared/setup-env.sh
    [ "$GH_TOKEN" = "gh-fake-token" ]
}

@test "exports JIRA_EMAIL and JIRA_API_TOKEN from JIRA_ACCT credentials" {
    source shared/setup-env.sh
    [ "$JIRA_EMAIL" = "test@example.com" ]
    [ "$JIRA_API_TOKEN" = "jira-fake-token" ]
}

@test "exports non-empty BASE_BRANCH read from shared/config.yaml" {
    source shared/setup-env.sh
    [ -n "$BASE_BRANCH" ]
}

@test "exports BEADS_DOLT_SERVER_HOST pointing at the k8s dolt service" {
    source shared/setup-env.sh
    [ "$BEADS_DOLT_SERVER_HOST" = "dolt-server.minordomo.svc.cluster.local" ]
}

@test "exports BEADS_DOLT_SERVER_PORT as 3306" {
    source shared/setup-env.sh
    [ "$BEADS_DOLT_SERVER_PORT" = "3306" ]
}

@test "exports BEADS_DOLT_SERVER_USER" {
    source shared/setup-env.sh
    [ -n "$BEADS_DOLT_SERVER_USER" ]
}
