# git-dozdi — Commit-Driven Downloader for GitHub

A single GitHub Actions workflow (`download.yml`) that turns any repository into
a remote download/relay machine, **driven entirely by commit messages**.

Push a commit whose message contains a magic command (e.g. `download: <url>`)
and the workflow will:

- Pull the file on a fast GitHub-hosted runner using `aria2c` (multi-connection)
- Either upload it as a **GitHub Release asset** (up to 2 GB per file) or **commit it back into the repo** (auto-split as a multi-volume zip when over 95 MB)
- Skip itself entirely when no command is present — no wasted minutes

---

## ✨ Features

- **Early skip**: a tiny detection job decides whether to run anything at all. No deps installed, no time wasted on unrelated commits.
- **Two destinations**:
  - `download:` / `download-zip:` → published as a **GitHub Release**
  - `downloadc:` → **committed into the repo** under `commit-files/`
- **Smart splitting** for repo commits: files over 95 MB are wrapped in a `zip -s 95m -0` (store mode, no compression) multi-volume archive that Windows users can extract with **7-Zip / WinRAR / PeaZip** in one click.
- **Per-volume manifest** with extraction instructions for Windows, Linux and macOS.
- **Fast downloads** via `aria2c` with 4 parallel connections per server.

---

## 🚀 Quick Start — add to any repo

1. Create a new (or use an existing) GitHub repository.
2. Add the workflow file at `.github/workflows/download.yml` — copy the contents of [`download.yml`](./download.yml).
3. (Optional) Enable workflow write permissions:
   - Repo → **Settings** → **Actions** → **General** → **Workflow permissions** → select **Read and write permissions**.
   - This is required for `downloadc:` (commit) and for creating Releases.
4. Push any commit whose message contains a command — see below.

That's it. No secrets, no extra setup; the built-in `GITHUB_TOKEN` is used.

---

## 📜 Commands

All commands are **prefixes inside the commit message**. URLs follow them, separated by spaces. Multiple commands can coexist in the same commit.

| Command          | Destination                | Size limit       | Behaviour                                                                          |
| ---------------- | -------------------------- | ---------------- | ---------------------------------------------------------------------------------- |
| `download:`      | GitHub Release             | 2 GB / file      | Each URL becomes its own release asset                                             |
| `download-zip:`  | GitHub Release             | 2 GB total       | All URLs are bundled into a single `release-bundle.zip` asset                      |
| `downloadc:`     | Repo commit (`commit-files/`) | 100 MB / object | Files ≤ 95 MB committed as-is. Larger files are split into a multi-volume zip.     |

> **Note**: GitHub blocks individual git objects > 100 MB, which is why `downloadc:` splits at 95 MB. Releases have no such limit (up to 2 GB per asset).

---

## 🧪 Usage examples

### Release a single file

```bash
git commit --allow-empty -m "download: https://ash-speed.hetzner.com/100MB.bin"
git push
```

→ Creates a release `auto-YYYYMMDD-HHMMSS` containing `100MB.bin`.

### Release several files in one zip

```bash
git commit --allow-empty -m "download-zip: https://example.com/a.iso https://example.com/b.iso"
git push
```

→ Creates a release containing `release-bundle.zip` with both files inside.

### Commit a large file into the repo

```bash
git commit --allow-empty -m "downloadc: https://ash-speed.hetzner.com/1GB.bin"
git push
```

→ Workflow auto-commits to the repo:

```
commit-files/
└── 1GB/
    ├── 1GB.z01            (95 MB)
    ├── 1GB.z02            (95 MB)
    ├── …
    ├── 1GB.zip            (last volume)
    └── MANIFEST.txt
```

### Combine both in one push

```bash
git commit --allow-empty -m "download: https://example.com/public.bin
downloadc: https://example.com/private.bin"
git push
```

→ `public.bin` goes to a Release; `private.bin` is committed to the repo.

### Push without a command

```bash
git commit -m "fix typo"
git push
```

→ The `check-command` job runs (a few seconds), detects no command, and the workflow ends. No download, no release, no commit.

---

## 📦 Reassembling split files (for `downloadc:` over 95 MB)

The workflow uses **standard zip multi-volume format** (`zip -s 95m -0`), so no custom scripts are needed.

### Windows

1. Download the entire folder (`commit-files/<name>/`) — keep **all** `.z01`, `.z02`, …, `.zip` files together.
2. Right-click `<name>.zip` → **7-Zip** → **Extract Here**.
   (Or use WinRAR / PeaZip — they all auto-detect the split.)

> ⚠️ **Windows Explorer's built-in "Extract All" cannot handle split zips.** Install [7-Zip](https://www.7-zip.org/) (free).

### Linux / macOS

```bash
zip -s 0 <name>.zip --out joined.zip
unzip joined.zip
```

The `MANIFEST.txt` next to the parts repeats these instructions.

---

## 🔁 Reproduction steps — full setup from scratch

```bash
# 1. Create the repo locally and push
mkdir my-downloader && cd my-downloader
git init
git remote add origin git@github.com:<you>/my-downloader.git

# 2. Add the workflow
mkdir -p .github/workflows
curl -fsSL https://raw.githubusercontent.com/<you>/git-dozdi/main/download.yml \
     -o .github/workflows/download.yml
# (or copy the file from this repo)

# 3. Initial commit
echo "# my-downloader" > README.md
git add .
git commit -m "ci: add download workflow"
git push -u origin main

# 4. Enable write permissions in
#    Settings → Actions → General → Workflow permissions → Read and write

# 5. Trigger your first download
git commit --allow-empty -m "download: https://ash-speed.hetzner.com/100MB.bin"
git push
```

Open the **Actions** tab to watch the run, then check the **Releases** tab for the asset.

---

## 🗂 Output layout in the repo

```
your-repo/
├── .github/workflows/download.yml
├── commit-files/                        ← created by `downloadc:`
│   ├── small-file.bin                   (≤ 95 MB, kept as-is)
│   └── big-file/                        (> 95 MB, multi-volume zip)
│       ├── big-file.z01
│       ├── big-file.z02
│       ├── big-file.zip
│       └── MANIFEST.txt
└── (release assets live in GitHub Releases, not in the repo)
```

---

## ⚙️ How it works (high level)

```
push ──▶ check-command job  ──(no command)──▶ workflow ends
              │
              └──(command found)──▶ release-upload job
                                      │
                                      ├─ install aria2 + zip
                                      ├─ download via aria2c
                                      ├─ (zip-mode) bundle release files
                                      ├─ split commit files via `zip -s 95m -0`
                                      ├─ git add + commit + push (if downloadc:)
                                      └─ create GitHub Release (if download:)
```

Two-job structure means **commits without a command cost only a few seconds of runner time**.

---

## ❓ FAQ

**Why not just `wget`/`curl`?**
`aria2c` opens 4 parallel connections per server, which is significantly faster on most CDNs.

**Why not store split files with the original `.partXXXofYYY` naming?**
Multi-volume zip is a universal, well-known format with built-in CRC32 integrity checks. Every major archiver handles it natively, with no custom reassembly script required.

**Can I tweak the chunk size / worker count?**
Yes — edit `download.yml`:
- `--split=4 --max-connection-per-server=4` for aria2c parallelism
- `LIMIT=$((95 * 1024 * 1024))` and `zip -s 95m` for split size (keep them in sync)

**Does the workflow need any secrets?**
No. The built-in `${{ secrets.GITHUB_TOKEN }}` is sufficient for both committing and creating releases.

**Will it run on every push?**
The `check-command` job runs on every push, but it's fast and free (Linux runner minutes are unmetered for public repos). The heavy `release-upload` job only runs when a command is detected.

---

## 📄 License

MIT — do whatever you want.
