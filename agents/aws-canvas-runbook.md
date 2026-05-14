# AWS + Canvas runbook

## Goal

Stand up Canvas LMS on an EC2 instance in a learner-lab AWS account, with a verifiable signal that the development stack is reachable.

## AI prompts used (summary)

The bring-up was driven by an agent in a remote editor session, four prompts in order, each consuming the prior prompt's output:

1. Read `README.md` and `doc/docker/developing_with_docker.md`, output the current commit hash, and quote the bring-up command sequence at that commit.
2. Walk through the prerequisites the chosen bring-up path assumes — Docker engine, Docker Compose plugin, host ports, RAM, disk, DNS — and for each, output the verification command and expected output on the current OS. Do not run installs without approval.
3. Execute the bring-up step by step. After each command, capture command, exit code, and last 20 lines of output. Stop on the first non-zero exit and propose a documented fix.
4. Once the stack is up, run `docker compose ps`, curl the app port, and confirm the web container responded 200 or 302.

## Learner Lab + EC2 checklist

- AWS Academy Learner Lab session active.
- EC2: Ubuntu 24.04 LTS, 2 vCPU, 7.6 GiB RAM + 2 GiB swap.
- EBS root volume resized to 30 GiB before bring-up to avoid mid-build disk pressure.
- Elastic IP allocated and associated with the instance; kept associated while stopped to avoid unattached-EIP charges.
- Security group: SSH (22) restricted to the developer's public IP; planned web port (3000) to be opened to the same source IP once the stack is up.
- Cost guard: cron job stops the instance after 30 minutes with no logged-in sessions.

## Canvas LMS: clone + doc path followed

Working commit: `5b8b921cf5dbbff3e4c75539522b66fcdacbee05`.

Quick-start path chosen: open-source path documented in `doc/docker/developing_with_docker.md`, automated entry point `./script/docker_dev_setup.sh`. The Instructure-employee path (`inst-cli/doc/docker/developing_with_docker.md`, `inst canvas setup`) was reviewed and rejected as out of scope for a fork.

DNS option: dory was skipped. The no-dory alternative was applied — a `ports: ["3000:80"]` block added to `docker-compose.override.yml` under the `web` service, and a `127.0.0.1 canvas.docker` entry added to `/etc/hosts`.

## Steps executed and results

| # | Action | Result |
|---|--------|--------|
| 1 | Install Docker CE + Compose plugin via Docker's official apt repository | exit 0; Docker 29.4.3, Compose plugin 5.1.3 |
| 2 | `sudo usermod -aG docker ubuntu` | exit 0 |
| 3 | Verify `docker ps` as `ubuntu` user | exit 0; empty container list |
| 4 | `cp docker-compose/config/*.yml config/` | 11 YAML files copied |
| 5 | Edit `docker-compose.override.yml` to add `ports: ["3000:80"]` under `web` | applied; diff reviewed |
| 6 | Append `127.0.0.1 canvas.docker` to `/etc/hosts` | applied |
| 7 | `./script/docker_dev_setup.sh` (dory `y`) wrapped in `nohup` + `printf 'y\n' \|` and `export TERM=xterm` | exit 1 after bundle install; diagnosis below |

### Issues encountered and documented fixes

**Issue 1 — silent script exit under `nohup`.** Root cause: `script/common/utils/logging.sh` runs `BOLD="$(tput bold)"` at source time under `set -e`; with `TERM=dumb` (the value `sudo` sets), `tput bold` exits non-zero and kills the script before any output is produced. Fix: `export TERM=xterm` before invoking the script. Applied; resolved the silent-exit symptom and let the build proceed through image build and into bundle install.

**Issue 2 — `bundle install` permission denied on `Gemfile.lock`.** Root cause: the web container runs as uid 9999 (`docker` user); the host bind-mounted repo files are owned by uid 1000 (`ubuntu`) with `-rw-rw-r--` permissions, so uid 9999 hits the "other" bits and is read-only. The setup script hard-codes `CANVAS_SKIP_DOCKER_USERMOD='true'`, so the in-container UID is fixed. Documented fix from `doc/docker/README.md` (Linux section):

```
sudo apt-get install -y acl
setfacl -Rm u:9999:rwX,g:9999:rwX .
setfacl -dRm u:9999:rwX,g:9999:rwX .
sudo addgroup --gid 9999 docker-instructure
sudo usermod -a -G docker-instructure $USER
```

Status at time of submission: ACL fix identified and validated against the doc; application and re-run are the next planned step.

## Verification commands and expected signals

Once the bring-up completes, verification is:

```
docker compose ps                              # all services in state "Up"
curl -I http://localhost:3000/login/canvas     # expect HTTP/1.1 200 OK or 302 Found
```

Browser verification: `http://<elastic-ip>:3000/` returns the Canvas login screen.

## Out of scope

Feature implementation is deferred to a separate implementation agent.

---
*Last verified: 2026-05-13 against commit 5b8b921cf5dbbff3e4c75539522b66fcdacbee0
