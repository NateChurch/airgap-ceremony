# Air-gapped key ceremony environment

You are in the home directory of the `ceremony` user on a live, amnesiac Debian
system. Nothing here survives a power cycle. That is deliberate.

**Start here:** `ceremony-guide` renders any of these documents in the terminal.

```
ceremony-guide              # list available documents
ceremony-guide quickstart   # by name
ceremony-guide 2            # or by number
ceremony-guide all          # everything, paged
```

---

## Documentation

| File | What it covers |
|---|---|
| `README.md` | This file — structure of the docs and the media |
| `AGENTS.md` | Orientation for an AI agent reading this disc |
| `docs/00-quickstart.md` | The short path. Read this if you are mid-ceremony |
| `docs/01-recovery-model.md` | **The one rule.** Why recovery must not depend on what it recovers |
| `docs/02-prerequisites.md` | What to have and decide before booting. Defines Locations A/B/C. Planning worksheet |
| `docs/03-artifacts.md` | Every key, what it does, where it lives, what gets printed |
| `docs/04-ceremonies.md` | Step-by-step procedures for each ceremony |
| `docs/05-ssh-ca.md` | The SSH certificate authority ceremony in full |
| `docs/06-storage.md` | Distribution, estate planning, annual maintenance |
| `docs/07-troubleshooting.md` | Selftest failures and what each one means |
| `docs/08-image-build.md` | How this ISO is built and rebuilt |
| `docs/09-testing.md` | The three test tiers, and why tier 3 is manual |
| `docs/10-worksheet.md` | **Print.** The in-the-room worksheet: scratch page and share cards |
| `docs/11-inventory.md` | **Print.** The durable record. Nothing on it is secret |
| `docs/12-appendix.md` | Raw commands underneath the scripts, for verification and recovery |

Read `01-recovery-model.md` before generating anything. It is short, and the
mistake it describes is silent at ceremony time and total at recovery time.
Then `02-prerequisites.md`, which is the one that takes days to act on.

### The three printed forms

They are separate documents on purpose. A single page carrying both a
passphrase and the address of a disc defeats the 2-of-3 split for anyone who
finds it.

| Form | Filled in | Fate |
|---|---|---|
| `docs/02-prerequisites.md`, planning worksheet | Before, at your desk | Kept. Maps Location A/B/C to real places |
| `docs/10-worksheet.md` | During, in the room | Scratch page destroyed there; share cards dispersed |
| `docs/11-inventory.md` | During and after | Two copies, stored with the discs |

---

## Commands on this system

| Command | Purpose |
|---|---|
| `ceremony-selftest` | Verify amnesia, air gap, toolchain, smartcard. Runs at login |
| `ceremony-guide` | Render this documentation |
| `archive-ceremony.sh` | Package, encrypt, split, burn, verify a ceremony's output |
| `rehearse-recovery.sh` | Prove the archive is recoverable before you leave |

---

## Layout of the boot media

When this ISO is mounted on any machine — without booting it — you see:

```
/
├── AGENTS.md              agent orientation (also at ~/AGENTS.md)
├── README.md              this file
├── docs/                  the full documentation set
├── live/
│   ├── filesystem.squashfs   the root filesystem
│   ├── vmlinuz               kernel
│   └── initrd.img            initramfs
├── boot/grub/             UEFI boot config
├── isolinux/              BIOS boot config
└── .disk/                 volume metadata
```

The documentation is duplicated onto the ISO root on purpose. Someone holding
this disc in ten years may not be able or willing to boot it, but can always
mount it and read.

In the source repository all copies are generated from a single `docs-src/`
directory, so they cannot drift apart.

---

## Layout of a ceremony output disc

`archive-ceremony.sh` burns a different disc. Do not confuse the two — this one
is the *environment*, that one holds *your key material*.

```
/
├── payload.tar.age        encrypted archive (age)
├── SHA256SUMS.txt         checksums of the archive contents
├── RECOVERY.txt           minimal recovery steps, readable by anyone
├── README.md              this file
└── docs/                  the full documentation set
```

`RECOVERY.txt` is deliberately short and assumes no prior knowledge. It exists
for whoever opens the off-site box, who may not be you.

---

## Filesystem notes

| Path | What it is |
|---|---|
| `~/` | tmpfs. Wiped on power-off |
| `/tmp/ceremony/` | Conventional scratch space for ceremony output. Also tmpfs |
| `/usr/local/share/ceremony/` | System copy of these docs |
| `/usr/local/share/ceremony/manifest.txt` | Exact package set in this image |
| `/usr/local/share/ceremony/external-binaries.txt` | sops/talosctl versions, checksums, source URLs |

The last two are provenance: they let you state precisely what was running
during a ceremony, years later.
