# zebra-utils.zig

Zig toolkit for talking to a running [Zebra](https://github.com/ZcashFoundation/zebra) node over its **JSON-RPC** interface.

---

## Prerequisites

- **Zig** 0.14.x
- A **running Zebra** (`zebrad`) with RPC enabled (see [Zebra README](https://github.com/ZcashFoundation/zebra) and deployment docs).

---

## Installation

```bash
git clone https://github.com/gorusys/zebra-utils.zig.git
cd zebra-utils.zig
zig build -Doptimize=ReleaseSafe
```

Artifacts install to `zig-out/bin/`. All binaries are linked **without libc** (`link_libc = false`).

**Optional dependency (for future / `zebra-scan`):** add [`zcash-addr.zig`](https://github.com/gorusys/zcash-addr.zig) via `build.zig.zon` and wire the module into tools that need transparent/sapling/unified address parsing.

---

## Quick start

```bash
# Tip height and truncated hash (human-readable)
zebra-cli tip

# Chain summary
zebra-cli chain

# Peers as a table
zebra-cli peers --format table

# Another host / port
zebra-cli --node 127.0.0.1:8232 info

# Read optional config + overrides
zebra-cli --format compact --no-color tip
```

---

## Binaries (overview)

| Binary | Status | Purpose |
|--------|--------|---------|
| **zebra-cli** | **Implemented** | General RPC CLI: info, chain, blocks, tx, mempool, peers, network, treestate, ping, broadcast |
| **zebra-watch** | Planned | Live dashboard (refresh interval, sync/mempool/peers summary) |
| **zebra-rpc-diff** | Planned | Same RPC call against two endpoints; field-level JSON diff |
| **zebra-scan** | Planned | Scan block ranges for transparent outputs touching given addresses (`zcash-addr.zig`) |
| **zebra-checkpoint** | Planned | Emit block-hash checkpoints on an interval (for tooling / verification workflows) |

Detailed references below focus on **zebra-cli** (current); others match the intended CLI shapes in the project roadmap.

---

## `zebra-cli` (reference)

```
zebra-cli [options] <command> [args...]

Options:
  --node <host:port>     RPC address (default from config or 127.0.0.1:8232)
  --user <user:pass>     JSON-RPC Basic authentication
  --format <fmt>         json | table | compact
  --color / --no-color   Override ANSI coloring
  -h, --help             Usage
```

| Command | Arguments | RPC (conceptually) |
|---------|-----------|-------------------|
| `info` | — | `getinfo` |
| `chain` | — | `getblockchaininfo` |
| `tip` | — | `getblockcount`, `getbestblockhash` |
| `block` | `<hash \| height>` | `getblock` |
| `tx` | `<txid>` | `getrawtransaction` |
| `mempool` | — | `getmempoolinfo` |
| `peers` | — | `getpeerinfo` |
| `network` | — | `getnetworkinfo` |
| `treestate` | `<hash \| height>` | `z_gettreestate` |
| `ping` | — | `ping` |
| `send` | `<hex>` | `sendrawtransaction` |

Exit **0** on success, **1** on usage/unknown command or RPC failure (errors on stderr).

---

## Planned tools (summary)

### zebra-watch

Terminal dashboard: height, tip hash, chain, sync progress, peers, mempool; flags such as `--node`, `--interval`, `--no-color`; redraw with cursor control; tolerate offline RPC with retry.

### zebra-rpc-diff

```
zebra-rpc-diff [--node-a host:port] [--node-b host:port] <method> [params...]
```

Same JSON-RPC method against two nodes; recursive object diff (only A / only B / changed).

### zebra-scan

```
zebra-scan --address <addr> [--address <addr>...] [--from H] [--to H] [--format json|csv|table] [--node ...]
```

Scan blocks for transparent outputs matching decoded addresses (via `zcash-addr.zig`).

### zebra-checkpoint

```
zebra-checkpoint [--start H] [--end H] [--interval N] [--output file] [--node ...]
```

Print `height<TAB>hash` lines at each checkpoint height; progress on stderr.

---

## Configuration

Default path: **`~/.config/zebra-utils/config.toml`**

Subset of TOML: `[section]` headers, `key = "string"`, `key = 123`, `#` comments.

```toml
[node]
host = "127.0.0.1"
port = 8232
username = ""
password = ""

[display]
color = true
format = "table"   # table | json | compact
```

If the file is missing, built-in defaults apply (see `src/config.zig`). CLI flags override file settings.

---

## Development

```bash
zig build          # debug binaries
zig build test     # library + unit tests (JSON, client helpers, types, fmt, ansi, config, CLI parser tests)
```

**Without a live node:** tests under `src/rpc/` use fixtures and mock HTTP slices; no daemon required.

**With Zebra:** point `--node` at your RPC and exercise `zebra-cli tip`, `chain`, `peers`, etc.

---

## Specifications and upstream docs

- [Zebra](https://github.com/ZcashFoundation/zebra) — node implementation this project targets.
- [Zcash RPC reference](https://zcash.github.io/rpc/) — method names and shapes (Zebra aims for compatibility where applicable).
- [ZIP-173](https://zips.z.cash/zip-0173) (Bech32), [ZIP-316](https://zips.z.cash/zip-0316) (Unified addresses) — relevant when using `zcash-addr.zig` in scanners.

---

## Roadmap

| Phase | Deliverable | Notes |
|-------|-------------|--------|
| **Done** | Core library: `json`, `client`, `types`, `methods`, `config`, `fmt`, `ansi` | Unit tests; no libc |
| **Done** | **`zebra-cli`** | Arg parsing, main RPC commands, table/json/compact output |
| **Next** | **`build.zig`**: all five executables + `zcash-addr` module for scan | Align `build.zig.zon` with sibling path or `zig fetch` |
| **Next** | **`zebra-watch`** | 5s (configurable) refresh, SIGINT, offline handling |
| **Next** | **`zebra-rpc-diff`** | Two-node JSON tree diff, optional verbose match lines |
| **Next** | **`zebra-scan`** | Block iteration, `gettxout` / verbose block tx introspection, CSV/table/json |
| **Next** | **`zebra-checkpoint`** | Interval checkpoints, stderr progress |
| **Polish** | Release binary size (strip), stricter warning-free `zig build`, optional integration test job against Zebra testnet | Target &lt; ~1 MB per binary where practical |

Contributions welcome along this roadmap; open issues or PRs that advance the next row are especially helpful.
