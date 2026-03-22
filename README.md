# git-stage

An interactive terminal tool for staging files and committing with Git.

Rather than juggling `git add` and `git status` at the command line, `git-stage` presents all changed files in an interactive list. Navigate with arrow keys, select what to stage, review diffs, and commit — all in one flow.

## Features

- Interactive file selector with keyboard navigation
- Pre-selects already-staged files so you can see and adjust the current index state
- Unstage files by deselecting them
- View word-level diffs inline before deciding what to stage
- Revert unstaged changes to a file
- Remove untracked files
- Commit message prompt after staging

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
| `a` | Select / deselect all |
| `Enter` | Confirm — stage selected files, unstage deselected, then prompt for commit message |
| `q` / `Ctrl-C` | Quit — leaves the index exactly as-is |

### Staging and unstaging

Files already in the index appear pre-checked. Leaving them checked keeps them staged. Unchecking a staged file and pressing `Enter` will unstage it.

### Diff viewer

Press `d` on any file to open its diff in `less`:

- **Staged files** show the diff against `HEAD` (what would be committed)
- **Unstaged modified files** show the worktree diff
- **Untracked files** show the raw file contents

Quit the diff with `q` to return to the file selector.

### Committing

After pressing `Enter`, any staging changes are applied and you are prompted for a commit message. Leave the message blank to abort the commit while keeping the index as staged.

### Quitting

Pressing `q` or `Ctrl-C` exits immediately without modifying the index. Files that were already staged remain staged.

## CLI Flags

```sh
git-stage --help      # Show usage and controls
git-stage --version   # Show version and copyright
```

Short forms `-h` and `-v` are also supported.

## License

Copyright (c) 2026 Scott Bellware. All rights reserved.
