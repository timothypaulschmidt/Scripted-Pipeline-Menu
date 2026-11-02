# Scripted Pipeline Menu

An "AI Scripted Pipeline": you move each change forward by choosing a step, and every step prints
what it runs and stays on screen. Start with a menu instead of remembering script names:

| Where | Start the menu |
|---|---|
| Windows | `.\pipeline-menu-dev.ps1` (also reaches QA and prod over ssh) |
| QA VM | `./pipeline-menu-qa.sh` |
| Prod VM | `./pipeline-menu-prod.sh` |

Each menu choice runs one of the numbered scripts below, shows all its output, and waits for Enter
before the menu redraws, so you can read any error. The scripts also run on their own without the menu.

## Version 2: explanations on every step (verbose mode)

Version 2 is built for learning. By default every command is preceded by green comment lines saying
what the command does and what each option means, and each script starts with a short paragraph on
what it is about to do and why:

```
  # GIT PULL: downloads the newest change from GitHub and merges it into your files. ...
  #   --ff-only: only fast-forward. If your copy has drifted from GitHub, stop ...
  #   origin: the nickname git gives the GitHub copy of this repository.
  $ git -C C:\...\AI-Agents pull --ff-only origin main
```

- Turn it off: press `v` in a menu, or set `$env:LAB_VERBOSE = "0"` (Windows) / `LAB_VERBOSE=0` (VM) before a script.
- All the command explanations live in one file, `lib/explain.txt`, used by both PowerShell and bash. To explain a new
  command or option, add one line there (a pattern, a tab, the text); no script has to change.
- Quick checks whose output is hidden (for example "does this Docker image exist?") are shown as `? command`.
- The version number is in the `VERSION` file and shown at the top of each menu.

Scripts that replace the long lists of commands for the AI lab (AI Assistant, MCP Server, AI Agents).
Windows uses PowerShell scripts, the QA and prod VMs use bash scripts. All of them read one config
file, `lab.env`, so every hostname, port, user and folder is written down exactly once.

**Rules that never change:** no passwords, API keys or tokens live in this repo. The Gemini key is
stored encrypted on Windows (`dev-06`) and as a Kubernetes Secret on QA/prod (`*-06-secrets.sh`).
Every script prints each command before running it, so you can see what it does. Add
`$env:LAB_DRYRUN = "1"` (Windows) or `LAB_DRYRUN=1` (VM) to print the commands without running them.

## Where the scripts come from, and how they reach every machine

`github.com/timothypaulschmidt/Scripted-Pipeline-Menu` is the single source. Each machine holds a clone in the
same relative place, next to the app repos:

| Machine | Folder | Contents |
|---|---|---|
| Windows | `C:\Users\timschmidt\Documents\Projects\Scripted-Pipeline-Menu` | beside `AI-Assistant`, `MCP-Server`, `AI-Agents` |
| QA VM | `/home/administrator/Scripted-Pipeline-Menu` | beside the same three repos |
| Prod VM | `/home/ubuntu/Scripted-Pipeline-Menu` | beside the same three repos |

To change a script: it is changed in this repo and merged to `main`. Then every machine gets it with a
`git pull` (`dev-01-git-pull.ps1 Scripted-Pipeline-Menu` on Windows; the ship scripts do it on the VMs for you,
because the first thing they run on the VM is `git pull` of Scripted-Pipeline-Menu). Nothing is ever copied by hand
with `scp` any more: the VMs clone the app repos from GitHub and deploy from those clones.

## Names and order

`<where>-<number>-<what>`. Run them in number order for a normal day; skip ahead when you only need a later step.

| Prefix | Runs on | Meaning |
|---|---|---|
| `dev-` | Windows | your local machine |
| `qa-0x` / `prod-0x` | the VM itself (bash `.sh`) | work done on the VM |
| `qa-1x` / `prod-1x` | Windows (`.ps1`) | drive the VM over ssh from your desk |

### Windows (`dev-`)
| Script | What it does |
|---|---|
| `dev-00-first-time-setup` | once per computer: check tools, make the Docker network, clone everything |
| `dev-01-git-pull [all/assistant/mcp/agents/menu]` | first time clones, afterwards pulls main (how a merged change reaches you) |
| `dev-02-run-python [all/app] [-Mode vulnerable/safe]` | run from source; `all` opens one window per app |
| `dev-03-docker-pull [all/app]` | download the ready-made images (the new-computer docker step) |
| `dev-04-docker-run [all/app] [-Mode ...]` | run the containers locally |
| `dev-05-docker-build-push <app>` | shows the current version, suggests the next, tests, builds, pushes, records it in the manifest |
| `dev-06-gemini-key` | save or replace your Gemini key for local runs (encrypted) |
| `dev-07-docker-stop [all/app]` | stop the local containers |
| `dev-08-vm-bootstrap <qa/prod>` | once per VM: ssh key, clone Scripted-Pipeline-Menu there, run its first-time setup |
| `dev-09-urls` | print every address and port |

### Windows driving a VM (`qa-1x`, `prod-1x`)
| Script | What it does |
|---|---|
| `qa-10-ship <app/all>` | checks the image is on Docker Hub, then updates and deploys on the VM (prod asks you to type `prod`) |
| `qa-11-remote <pull/deploy/status/logs/reset/secrets/urls> [args]` | run any VM script from Windows, e.g. `.\qa-11-remote.ps1 logs agents -f` |
| `qa-12-gemini-key` | change the Gemini key on that VM (paste hidden), restarts the pods that use it |

### On the VM (`qa-0x`, `prod-0x`, run as `./qa-02-deploy.sh all`)
| Script | What it does |
|---|---|
| `00-first-time-setup` | once: clone the apps, create the namespace and MCP admin token |
| `01-git-pull <all/app/menu>` | clone or pull |
| `02-deploy <all/app>` | `kubectl apply -k`, wait for rollout, print the address |
| `03-status` | pods, running image versions, secret names, code versions, addresses |
| `04-logs <assistant/mcp/agents/ollama> [-f]` | logs |
| `05-reset-mcp-data` | put the MCP data back to seed data |
| `06-secrets [gemini/admin/custom/show]` | change secrets without ever showing them |
| `09-urls` | print every address |

## New Windows computer, step by step

1. Install Git for Windows, Python 3.11+, Docker Desktop (start it), and turn on the OpenSSH Client.
2. Open PowerShell and run these two lines (this is the only time you type git commands by hand):
   ```
   mkdir C:\Users\timschmidt\Documents\Projects
   git clone https://github.com/timothypaulschmidt/Scripted-Pipeline-Menu.git C:\Users\timschmidt\Documents\Projects\Scripted-Pipeline-Menu
   ```
3. `cd C:\Users\timschmidt\Documents\Projects\Scripted-Pipeline-Menu` then `.\dev-00-first-time-setup.ps1`
   (if PowerShell refuses scripts: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once).
4. `.\dev-06-gemini-key.ps1` to store your key.
5. Docker, first time: `.\dev-03-docker-pull.ps1 all`, then `.\dev-04-docker-run.ps1 all`.
   Python instead: `.\dev-02-run-python.ps1 all`.

**First clone vs later pull:** `git clone` happens once per computer (dev-00 does it). After that, every
merge Claude's changes get on GitHub reaches you with `.\dev-01-git-pull.ps1 all`.

## A normal release

1. A change is merged on GitHub. `.\dev-01-git-pull.ps1 <app>`
2. `.\dev-02-run-python.ps1 <app>` or `.\dev-04-docker-run.ps1 <app>` to try it.
3. `.\dev-05-docker-build-push.ps1 <app>` (asks the new version, builds, pushes, commits the manifest).
4. `.\qa-10-ship.ps1 <app>`; look at it; then `.\prod-10-ship.ps1 <app>`.

## New QA or prod VM

`.\dev-08-vm-bootstrap.ps1 qa`, then `.\qa-12-gemini-key.ps1`, then `.\qa-10-ship.ps1 all`.

## Changing a hostname, port or folder

Edit `lab.env`, merge, pull on each machine. No script contains these values.

## Changes

- **2.0.0** Verbose mode: an explanation before every command and an introduction at the start of the main scripts; `v` toggle in the menus; `lib/explain.txt`.
- **1.0.0** First release: dev, qa and prod scripts and the text menus.
