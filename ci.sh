#!/usr/bin/env bash

# Continuous Integration test script

set -euf -o pipefail

export SPIFFE_ENDPOINT_SOCKET="unix:/tmp/spire-agent/public/api.sock"
export SPIFFE_ADMIN_ENDPOINT_SOCKET="unix:/tmp/spire-agent/admin/api.sock"

spire_version="1.7.1"
spire_folder="spire-${spire_version}"
spire_server_log_file="/tmp/spire-server/server.log"
spire_agent_log_file="/tmp/spire-agent/agent.log"
agent_id="spiffe://example.org/myagent"

function cleanup() {
  killall -9 spire-agent || true
  killall -9 spire-server || true
  rm -f /tmp/spire-server/private/api.sock
  rm -f /tmp/spire-agent/public/api.sock
  rm -rf ${spire_folder}
}

trap cleanup EXIT

# Install and run a SPIRE server
curl -s -N -L https://github.com/spiffe/spire/releases/download/v${spire_version}/spire-${spire_version}-linux-amd64-glibc.tar.gz | tar xz
pushd "${spire_folder}"
mkdir -p /tmp/spire-server
bin/spire-server run -config conf/server/server.conf > "${spire_server_log_file}" 2>&1 &

spire_server_started=0
for i in {1..10}
do
    if bin/spire-server healthcheck  >/dev/null 2>&1; then
        spire_server_started=1
        break
    fi
    sleep 1
done

if [ ${spire_server_started} -ne 1 ]; then
    cat ${spire_server_log_file} >&2
    echo 'SPIRE Server failed to start' >&2
    exit 1
fi

cat > "conf/agent/agent.conf" <<EOF
agent {
    data_dir = "./data/agent"
    log_level = "DEBUG"
    trust_domain = "example.org"
    server_address = "localhost"
    server_port = 8081

    # Insecure bootstrap is NOT appropriate for production use but is ok for 
    # simple testing/evaluation purposes.
    insecure_bootstrap = true

    admin_socket_path = "/tmp/spire-agent/admin/api.sock"
    authorized_delegates = [
      "spiffe://example.org/myservice",
    ]
}

plugins {
   KeyManager "disk" {
        plugin_data {
            directory = "./data/agent"
        }
    }

    NodeAttestor "join_token" {
        plugin_data {}
    }

    WorkloadAttestor "unix" {
        plugin_data {}
    }
}
EOF

# Run the SPIRE agent with the joint token
bin/spire-server token generate -spiffeID ${agent_id} > token
cut -d ' ' -f 2 token > token_stripped
mkdir -p /tmp/spire-agent
bin/spire-agent run -config conf/agent/agent.conf -joinToken "$(< token_stripped)" > "${spire_agent_log_file}" 2>&1 &

spire_agent_started=0
for i in {1..10}
do
    if bin/spire-agent healthcheck  >/dev/null 2>&1; then
        spire_agent_started=1
        break
    fi
    sleep 1
done

if [ ${spire_agent_started} -ne 1 ]; then
    cat ${spire_agent_log_file} >&2
    echo 'SPIRE Agent failed to start' >&2
    exit 1
fi

# Register the workload through UID with the SPIFFE ID "spiffe://example.org/myservice" with a TTL of 5 seconds
bin/spire-server entry create -parentID ${agent_id} -spiffeID spiffe://example.org/myservice -selector unix:uid:$(id -u) -ttl 5
sleep 10  # this value is derived from the default Agent sync interval
# Register the workload through UID with the SPIFFE ID "spiffe://example.org/myservice2" with a TTL of 5 seconds
bin/spire-server entry create -parentID ${agent_id} -spiffeID spiffe://example.org/myservice2 -selector unix:uid:$(id -u) -ttl 5
<<<<<<< HEAD
sleep 10  # this value is derived from the default Agent sync interval


uid=$(id -u)
# The UID in the test has to match this, so take the current UID and add 1
uid_plus_one=$((uid + 1))
# Register a different UID with the SPIFFE ID "spiffe://example.org/different-process" with a TTL of 5 seconds
bin/spire-server entry create -parentID ${agent_id} -spiffeID spiffe://example.org/different-process -selector unix:uid:${uid_plus_one} -ttl 5
=======
>>>>>>> 75aaa783a90b73d4ad4e06a99a4e3a41b3977d66
sleep 10  # this value is derived from the default Agent sync interval

popd

RUST_BACKTRACE=1 cargo test --features integration-tests
