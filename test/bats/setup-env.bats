#!/usr/bin/env bats
# Tests for shared/setup-env.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-env.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"

    # Unset any previously derived vars to ensure clean state
    unset DOMAIN_ROOT JENKINS_USERNAME GH_TOKEN BASE_BRANCH

    # Fake credentials matching what Jenkins injects
    export ROOT_DOMAIN="example.com"
    export GH_APP_PSW="gh-fake-token"
}

@test "exports DOMAIN_ROOT as the subdomain prefix of ROOT_DOMAIN" {
    source shared/setup-env.sh
    [ "$DOMAIN_ROOT" = "example" ]
}

@test "exports JENKINS_USERNAME as DOMAIN_ROOT@gmail.com" {
    source shared/setup-env.sh
    [ "$JENKINS_USERNAME" = "example@gmail.com" ]
}

@test "exports GH_TOKEN from GH_APP_PSW" {
    source shared/setup-env.sh
    [ "$GH_TOKEN" = "gh-fake-token" ]
}

@test "exports non-empty BASE_BRANCH read from shared/config.yaml" {
    source shared/setup-env.sh
    [ -n "$BASE_BRANCH" ]
}
