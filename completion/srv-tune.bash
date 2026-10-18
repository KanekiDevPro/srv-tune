# SPDX-License-Identifier: MIT
# Bash completion for srv-tune (the optimizer.sh entrypoint installs as
# srv-tune). Install: source this file from ~/.bashrc, or drop it into
# bash-completion's completions dir as "srv-tune".
# shellcheck shell=bash

_srv_tune_cmds="scan recommend apply rollback list-backups status benchmark explain audit update uninstall confirm ssh-close-port health repair tunnel"
_srv_tune_flags="--profile --only --dry-run --yes --lang --json --diff --with-ssh --with-firewall --with-registry --with-dot --mirror --dns-extra --config --out --iperf-server --install-deps --compare --format --force --help --version --fp --file --comment --permit-open --gateway-ports --port --bind"
_srv_tune_profiles="generic web database docker vpn-tunnel low-ram custom"
_srv_tune_modules="limits network kernel dns mirror pip_mirror npm_mirror docker_mirror ssh firewall fail2ban"
_srv_tune_tunnel_cmds="status keys access sessions web"

_srv_tune() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  case "$prev" in
  --profile)
    mapfile -t COMPREPLY < <(compgen -W "$_srv_tune_profiles" -- "$cur")
    return 0
    ;;
  --only)
    mapfile -t COMPREPLY < <(compgen -W "$_srv_tune_modules" -- "$cur")
    return 0
    ;;
  --lang)
    mapfile -t COMPREPLY < <(compgen -W "fa en" -- "$cur")
    return 0
    ;;
  --format)
    mapfile -t COMPREPLY < <(compgen -W "md json html" -- "$cur")
    return 0
    ;;
  tunnel)
    mapfile -t COMPREPLY < <(compgen -W "$_srv_tune_tunnel_cmds" -- "$cur")
    return 0
    ;;
  esac
  if [[ "$cur" == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$_srv_tune_flags" -- "$cur")
    return 0
  fi
  mapfile -t COMPREPLY < <(compgen -W "$_srv_tune_cmds" -- "$cur")
}

complete -F _srv_tune srv-tune
