# Local Testing

Claw is a pure QML plugin — no build step. Noctalia loads it from
`~/.config/noctalia/plugins/5b965e:claw/`. Testing means syncing the
changed files there and restarting quickshell.

## Quick Reference

```bash
# 1. Sync plugin files
rsync -av --checksum claw/ ~/.config/noctalia/plugins/5b965e:claw/

# 2. Kill running noctalia-shell
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill
sleep 0.5
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill -9

# 3. Clear QML cache
rm -rf ~/.cache/quickshell/qmlcache

# 4. Restart noctalia-shell
hyprctl dispatch exec "noctalia-shell"

# 5. Verify
sleep 3
qs -c noctalia-shell log --newest -t 250 | rg "5b965e:claw|Plugin load error"
```

## Step-by-Step

### 1. Sync modified files

```bash
rsync -av --checksum claw/ ~/.config/noctalia/plugins/5b965e:claw/
```

This copies only files whose contents changed. Avoid `--delete` if you have
a local `settings.json` in the plugin folder that you want to keep.

### 2. Kill running noctalia-shell

The process name is `.quickshell-wra` (the Nix wrapper). Kill gracefully
first, then force-kill stragglers:

```bash
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill
sleep 0.5
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill -9
```

This only targets noctalia-shell instances, not other quickshell processes.

### 3. Clear QML cache

```bash
rm -rf ~/.cache/quickshell/qmlcache
```

Quickshell caches compiled QML. Without clearing, old code may still run
even after syncing new files.

### 4. Restart noctalia-shell

```bash
hyprctl dispatch exec "noctalia-shell"
```

Must use `hyprctl dispatch exec` (not direct execution) for proper Wayland
integration. Noctalia is not a systemd service — it's launched by Hyprland.

### 5. Validate via logs and IPC

Wait a few seconds for startup, then:

```bash
# Tail recent logs
qs -c noctalia-shell log --newest -t 200

# Open the Claw panel (tests panel loading without clicking the bar)
qs -c noctalia-shell ipc call plugin openPanel 5b965e:claw

# Filter for plugin errors
qs -c noctalia-shell log --newest -t 250 | rg "5b965e:claw|Plugin load error"
```

A healthy load looks like:

```
PluginRegistry  Loaded plugin: 5b965e:claw - Claw
PluginService   Loaded Main.qml for plugin: 5b965e:claw
PluginService   Loaded bar widget for plugin: 5b965e:claw
PluginService   Plugin loaded: 5b965e:claw
```

## Troubleshooting

### `module "QtWebSockets" is not installed`

The noctalia-shell package needs `qt6.qtwebsockets` in its build inputs.
This is configured in
`~/nixos-config/home/shells/noctalia/shell.nix` via a package override:

```nix
package = pkgs.noctalia-shell.overrideAttrs (old: {
  buildInputs = (old.buildInputs or []) ++ [ pkgs.qt6.qtwebsockets ];
});
```

After changing this, rebuild with `home-manager switch` (or full NixOS
rebuild). For a quick test before rebuilding, inject the QML import path
at launch:

```bash
hyprctl dispatch exec "env NIXPKGS_QT6_QML_IMPORT_PATH=/nix/store/a8zfmf66fry9l5n55fwjzi2f51jfgr1a-qtwebsockets-6.10.1/lib/qt-6/qml noctalia-shell"
```

> The store path is host-specific. Find yours with:
> `nix eval --raw nixpkgs#qt6.qtwebsockets.outPath`

### `Type <X> unavailable` / panel won't open

A QML type or import is missing. The log line after the error usually
points to the exact file and line number. Fix, re-sync, and re-test with
the IPC `openPanel` command above.

### Changes not taking effect

Make sure you cleared the QML cache (step 3). Quickshell aggressively
caches compiled QML and will ignore file changes otherwise.
