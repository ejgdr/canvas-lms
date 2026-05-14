# AWS + Canvas runbook

## Goal
Stand up Canvas LMS on an EC2 instance in a learner-lab AWS account, with a verifiable signal that the development stack is reachable.

## AI prompts used (summary)

Four prompts executed in order in a remote-editor agent session, each consuming the prior prompt's output:

1. Read `README.md` and `doc/docker/developing_with_docker.md`, output the current commit hash, and quote the bring-up command sequence at that commit.
2. Walk through the prerequisites the chosen bring-up path assumes — Docker engine, Docker Compose plugin, host ports, RAM, disk, DNS — and output a verification command and expected output for each on the current OS. Do not run installs without approval.
3. Execute the bring-up step by step. After each command, capture command, exit code, and last 20 lines of output. Stop on the first non-zero exit and propose a documented fix.
4. Once the stack is up, run `docker compose ps`, curl the app port, and confirm the web container responded 200 or 302.

## Learner Lab + EC2 checklist

- AWS Academy Learner Lab session active.
- EC2: Ubuntu 24.04 LTS, 2 vCPU, 7.6 GiB RAM + 2 GiB swap.
- EBS root volume resized to 30 GiB before bring-up to avoid mid-build disk pressure.
- Elastic IP allocated and associated with the instance; kept associated while stopped to avoid unattached-EIP charges.
- Security group: SSH (22) restricted to the developer's public IP; web port (3000) restricted to the same source IP for browser verification.
- Cost guard: cron job stops the instance after 30 minutes with no logged-in sessions.

## Canvas LMS: clone + doc path followed

Working commit: `5b8b921cf5dbbff3e4c75539522b66fcdacbee05`.

Quick-start path chosen: open-source path from `doc/docker/developing_with_docker.md`, automated entry point `./script/docker_dev_setup.sh`. The Instructure-employee path (`inst-cli/doc/docker/developing_with_docker.md`, `inst canvas setup`) was reviewed and rejected as out of scope for a fork.

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
| 7 | First `./script/docker_dev_setup.sh` invocation (`nohup` + `printf 'y\n' \|` + `TERM=xterm`) | exit 1 after bundle install; UID 9999 write permission denied on `Gemfile.lock` |
| 8 | Apply ACL fix per `doc/docker/README.md` Linux section: install `acl`, `setfacl -Rm u:9999:rwX,g:9999:rwX .` and `setfacl -dRm u:9999:rwX,g:9999:rwX .`; create `docker-instructure` group at gid 9999 and add `ubuntu` | exit 0; uid/gid 9999 rwX confirmed on `Gemfile.lock` |
| 9 | Inject `CANVAS_LMS_ADMIN_EMAIL`, `CANVAS_LMS_ADMIN_PASSWORD`, `CANVAS_LMS_ACCOUNT_NAME`, `CANVAS_LMS_STATS_COLLECTION` into `docker-compose.override.yml` to suppress `highline` prompts inside the container | applied; 6 lines added in two hunks |
| 10 | Re-run `./script/docker_dev_setup.sh` with `printf 'y\ny\nn\ny\n'` | Bundle install ✓, yarn install ✓, asset compile ✓ (295 s); script then exited on 5th unanticipated `read` in `create_db` (DROP/migrate prompt, EOF) |
| 11 | Run remaining three commands directly per `build_helpers.sh` lines 91–96 inside the web container: `rake db:migrate RAILS_ENV=development`, `rake db:migrate RAILS_ENV=test`, `rake db:initial_setup` | All exit 0; admin user and initial account created via env-var-driven highline answers |

### Issues encountered and documented fixes

**Issue 1 — silent script exit under `nohup`.** Root cause: `script/common/utils/logging.sh` runs `BOLD="$(tput bold)"` at source time under `set -e`; `sudo` sets `TERM=dumb`, `tput bold` exits non-zero, and the script dies before any output is produced. Fix: `export TERM=xterm` before invoking the script.

**Issue 2 — `bundle install` permission denied on `Gemfile.lock`.** Root cause: the web container runs as uid 9999 (`docker` user); host bind-mounted repo files are owned by uid 1000 (`ubuntu`) with `-rw-rw-r--`, so uid 9999 hits the "other" bits and is read-only. The setup script hard-codes `CANVAS_SKIP_DOCKER_USERMOD='true'`, so the in-container UID is fixed. Fix from `doc/docker/README.md` Linux section: `setfacl -Rm u:9999:rwX,g:9999:rwX .` plus the default-ACL variant for future files, with a `docker-instructure` group at gid 9999 for reverse-direction writes.

**Issue 3 — script exit on undocumented 5th prompt after asset compilation.** Root cause: `build_helpers.sh` `create_db` invokes `read` for "DROP/migrate" when an existing database is detected; the four piped answers were already consumed, and `read` returning EOF tripped `set -e`. Asset compilation had completed cleanly (295 s) before this point. Fix: skipped re-running the full script in favor of executing the three remaining `rake` commands directly per `build_helpers.sh` lines 91–96, with `CANVAS_LMS_*` env vars already baked into the container suppressing all internal prompts.

## Verification commands and signals (actual results)

```
$ docker compose ps
SERVICE    NAME                     STATUS         PORTS
postgres   canvas-lms-postgres-1    Up 22 min      5432/tcp
redis      canvas-lms-redis-1       Up 40 min      6379/tcp
web        canvas-lms-web-1         Up 22 min      0.0.0.0:3000->80/tcp

$ curl -I http://localhost:3000/login/canvas
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Connection: keep-alive
Status: 200 OK
x-request-cost: 0.44351024100421466
x-session-id: 90d5e48c8b610423536209c1097e1049
cache-control: no-store
x-request-context-id: 14c4edc3-4842-403a-8d62-da9261cadb18
vary: Accept
x-rate-limit-remaining: 600.0
referrer-policy: no-referrer-when-downgrade
x-canvas-meta: o=login/canvas;n=new;b=1374544;m=1380304;u=0.44;y=0.01;d=0.01;rlr=600.0;
x-permitted-cross-domain-policies: none
x-xss-protection: 1; mode=block
pragma: no-cache
server-timing: cache_read.active_support;dur=4.47, cache_fetch_hit.active_support;dur=0.09, start_processing.action_controller;dur=0.03, sql.active_record;dur=8.04, instance.active_record;dur=0.04, instantiation.active_record;dur=1.68, render_partial.action_view;dur=56.47, render_template.action_view;dur=15.59, render_layout.action_view;dur=414.64, process_action.action_controller;dur=453.72
x-download-options: noopen
etag: W/"a5caa9d17fb87f42e8b8e2a34ff986ac"
x-runtime: 0.493746
x-content-type-options: nosniff
content-security-policy: frame-ancestors 'self' canvas.docker;
Date: Thu, 14 May 2026 06:34:09 GMT
Set-Cookie: _csrf_token=d4MPGMGZSw%2FAqQfIiYo6%2FZOaQkz1%2BL78IWG218s2IWMV82N89%2FEvOPfvTf3A%2F3OZ1tkYPY3X98hMFM6epE9JWw%3D%3D; path=/
Set-Cookie: log_session_id=90d5e48c8b610423536209c1097e1049; path=/; httponly
Set-Cookie: _normandy_session=cpHIJekRQfuLSx1ZAy7Mwg+6yJ5d0aNM9RTEGxEVXBIHlvoNErbTig4bAlEozD6t8RopME2DiUiCSplj3UaktiCqXHULC3uQi-nkNtV5vQ2p19rUzJNCT84qH3e2kNpIrqiRWdT0iebCFWeGIGfd9o7MXadLQJ2PM_0DMdbDXHxlg.xbWPscM4d4bnxBgJ_eeUXhyiR9w.agVs4Q; path=/; httponly
Server: nginx + Phusion Passenger(R)

```

Browser verification: Canvas login screen reachable at `http://3.233.56.59:3000/`. Screenshot submitted with this lab.

## Out of scope

Feature implementation is deferred to a separate implementation agent.

---
*Last verified: 2026-05-13 against commit 5b8b921cf5dbbff3e4c75539522b66fcdacbee05; Canvas stack confirmed Up with web container on port 3000.*
