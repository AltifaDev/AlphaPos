#!/usr/bin/env bash
set -euo pipefail

# Docker-published ports bypass UFW's INPUT chain. Keep Kong reachable from
# the local Caddy reverse proxy while blocking direct Internet access to 54321.
rule=(-p tcp -m conntrack --ctorigdstport 54321 -j DROP)
if ! /usr/sbin/iptables -C DOCKER-USER "${rule[@]}" 2>/dev/null; then
  /usr/sbin/iptables -I DOCKER-USER 1 "${rule[@]}"
fi

