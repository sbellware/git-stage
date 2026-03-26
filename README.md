# git-stage

*All the world's a stage, and all the untracked files are unfinished business.*

![git-stage demo](git-stage-demo.gif)

An interactive terminal tool for staging files and committing with Git.

Rather than juggling `git add` and `git status` at the command line, `git-stage` presents all changed files in an interactive list. Navigate with arrow keys, select what to stage, review diffs, and commit — all in one flow.

## Features

- Interactive file selector with keyboard navigation
- Shows current branch, previous commit, and per-file line change counts in the header
- Pre-selects already-staged files so you can see and adjust the current index state
- Unstage files by deselecting them
- View word-level diffs before deciding what to stage
- Revert unstaged changes to a file
- Remove untracked files
- Amend the last commit — optionally adding more files and editing the message
- Status screen showing staged, unstaged, untracked, stashed, and unpushed changes
- Push to origin after committing, or when the working tree is clean with unpushed commits
- Dry run mode to preview what would be staged and committed
- Prints the git commands run after each session

## Usage

Run from inside any Git repository:

```sh
git-stage
```

### Controls

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate the file list |
| `k` / `j` | Navigate (vim-style) |
| `Space` | Toggle selection |
| `d` | View diff of file under cursor |
| `x` | Remove untracked file (with confirmation) |
| `u` | Revert unstaged changes to file under cursor (with confirmation) |
| `s` | Show repository status screen |
| `m` | Amend the last commit |
| `a` | Select / deselect all |
| `Enter` | Confirm — stage selected, unstage deselected, then prompt for commit message |
| `q` / `Ctrl-C` | Quit — leaves the index exactly as-is |

### Header

The header displays the current branch, the previous commit (with author, date, and short SHA), and the total number of changed files and selected files. Per-file line change counts (`+N -N`) are shown next to each file in the list.

### Staging and unstaging

Files already in the index appear pre-checked. Leaving them checked keeps them staged. Unchecking a staged file and pressing `Enter` will unstage it.

### Diff viewer

Press `d` on any file to open its diff in `less`:

- **Staged files** show the diff against `HEAD` (what would be committed)
- **Unstaged modified files** show the worktree diff
- **Untracked files** show the raw file contents

Quit the diff with `q` to return to the file selector.

### Status screen

Press `s` to open an overview of the repository state, or run `git-stage --status` / `git-stage -s` from the command line. The status screen isn't interactive. It displays the information, but doesn't trigger any actions.

The status screen displays:

- **Staged** — files in the index, with per-file line change counts
- **Unstaged** — files with worktree changes not yet staged, with line change counts
- **Untracked** — new files not tracked by git, with total line counts shown as additions
- **Stashes** — entries from `git stash list`, if any exist
- **Unpushed** — commits on the local branch not yet pushed to the remote, if an upstream is configured

Sections with no content are omitted. Press `q` or `Esc` to return to the file selector.

### Committing

After pressing `Enter`, any staging changes are applied and you are prompted for a commit message. Leave the message blank to abort the commit while keeping the index as staged.

### Amending

Press `m` to amend the last commit. If files are selected, they are staged into the amended commit and listed before the message prompt. The previous commit message is shown so you can edit or keep it as-is — pressing `Enter` on a blank line keeps the existing message.

### Pushing

After a successful commit, a post-commit screen offers the option to push to origin (`p`) or quit (`q`). If the working tree is already clean but there are unpushed commits, the same screen is shown when `git-stage` is run, allowing you to push without going through the selector.

### Quitting

Pressing `q` or `Ctrl-C` exits immediately without modifying the index. Files that were already staged remain staged.

### Commands run

After each session, the git commands that were executed are printed, so you always have a clear record of what the tool did on your behalf.

## CLI Flags

```sh
git-stage --help, -h            # Show usage and controls
git-stage --version, -v         # Show version and copyright
git-stage --status, -s          # Show repository status screen and exit
git-stage -q                    # Quiet mode. Suppress the output of Git commands executed.
git-stage -C, --no-copyright    # Suppress the copyright notice in the UI
git-stage -U, --unsafe-confirm  # Confirm dangerous actions with Enter instead of 'y'
git-stage -A, --select-all      # Start with all files pre-selected
git-stage --dry-run             # Show what would be staged/committed without doing it
```

## Requirements

- Bash 4.0+
- Git
- Standard Unix utilities: `tput`, `stty`, `less`

macOS ships with Bash 3.2. Install a current version via Homebrew:

```sh
brew install bash
```

## Installation

Download the script and place it somewhere on your `$PATH`:

```sh
curl -o ~/.local/bin/git-stage https://raw.githubusercontent.com/sbellware/git-stage/main/git-stage.sh
chmod +x ~/.local/bin/git-stage
```

Or clone the repository and symlink it:

```sh
git clone https://github.com/sbellware/git-stage.git
ln -s "$PWD/git-stage/git-stage.sh" ~/.local/bin/git-stage
```

## License

Copyright (c) 2026 Scott Bellware. All rights reserved.

See [LICENSE](LICENSE) for full terms.
