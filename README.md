# claude-code-multiple-accounts

Use multiple Claude Code accounts on one machine with shared sessions, skills, plugins and MCP servers. It is a single shell file.

When one account hits its limit, exit and continue the same conversation with another account:

```bash
/exit
claude-work -c
```

No copying session files, no hunting for session IDs.

## How it works

Claude Code reads its config directory from the `CLAUDE_CONFIG_DIR` environment variable. Each extra account keeps its own login in its own directory (`~/.claude-work`, `~/.claude-work2`, ...). The script symlinks the shareable parts of those directories to the main account's directory (`~/.claude`):

| What | How it is shared |
|---|---|
| `projects`, `todos`, `session-env`, `file-history` | Existing content is merged into the main account, then symlinked |
| `skills`, `plugins`, `commands`, `agents`, `settings.json`, `CLAUDE.md` | The main account is the single source; symlinked |
| User-scope MCP servers | Copied from the main account's `~/.claude.json` with `jq` |

Logins are never shared; every account stays separate.

## Requirements

- Claude Code
- zsh or bash
- `rsync`
- `jq` (for MCP sync; that step is skipped without it)

macOS: `brew install jq` — Ubuntu: `sudo apt install jq rsync`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/MehmetSert/claude-code-multiple-accounts/main/install.sh | bash
```

The installer saves the script as `~/.claude-accounts.sh` and adds `source ~/.claude-accounts.sh` to your `~/.zshrc` or `~/.bashrc`. New terminals load it automatically. To use it in the terminal you installed from, run:

```bash
source ~/.claude-accounts.sh
```

Close all running Claude Code sessions before adding your first account.

Run the install command again to update to the latest version, then run the `source` line above or open a new terminal.

<details>
<summary>Manual install</summary>

1. Download the script:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/MehmetSert/claude-code-multiple-accounts/main/claude-accounts.sh -o ~/.claude-accounts.sh
   ```

2. Add this line to the end of `~/.zshrc` or `~/.bashrc`:

   ```bash
   source ~/.claude-accounts.sh
   ```

3. Close all running Claude Code sessions and open a new terminal.

</details>

## Usage

Add an account. The name becomes both a command and a config directory (`claude-work` -> `~/.claude-work`):

```bash
claude-accounts add claude-work
```

Start it and log in once with `/login`:

```bash
claude-work
```

From then on:

```bash
claude                 # main account
claude-work            # extra account
claude-work -c         # continue the latest session in this directory
claude-work --resume <SESSION_ID>
```

Every account command checks its links and MCP servers on start and repairs what is missing.

### Commands

| Command | What it does |
|---|---|
| `claude-accounts add <name>` | Adds an account, defines its command and sets up the links |
| `claude-accounts remove <name>` | Removes the account from the list; its directory is kept |
| `claude-accounts list` | Shows accounts and what is linked |
| `claude-accounts sync` | Repairs links and copies MCP servers for all accounts |

`add` works with directories that already exist. If you already use `CLAUDE_CONFIG_DIR=~/.claude-work claude`, run `claude-accounts add claude-work` and your login is kept. Remove any alias with the same name from your shell file.

The account list is a plain text file at `~/.config/claude-accounts/accounts`, one name per line. Terminals that were already open pick up a new account after any `claude-accounts` command or a restart.

## Good to know

- **Nothing is deleted.** The previous version of every linked file or folder stays in the account directory as `<name>.bak-<date>`.
- **Add MCP servers in the main account only.** The copy is one-way. A user-scope server added in an extra account is overwritten the next time that account starts. MCP servers are copied after the account's first login.
- **Configuration is not merged.** A skill or plugin installed only in an extra account stays in the backup; move it to the main account by hand.
- **Do not open the same session in two accounts at once.** Two processes writing to one session file can corrupt it.
- **Auto memory is shared too**, because it lives under `projects/<project>/memory/`.
- **The first message after switching may use more quota**, because the prompt cache is rebuilt on the new account.
- **MCP servers that need OAuth** get their definition copied, but the login is per account; run `/mcp` once in each account.
- **Local-scope MCP servers and claude.ai connectors are not shared.**
- Check your company's policy before continuing work projects with a personal account.

## Disclaimer

This is not an official Anthropic tool. The layout of Claude Code's config directory may change between versions.
