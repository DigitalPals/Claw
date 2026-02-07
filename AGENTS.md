# Claw (Noctalia Plugin) Local Testing

These notes document how we test this plugin locally on a machine running Noctalia Shell (Quickshell).

## Where Noctalia Loads The Plugin From

Noctalia installs enabled plugins under:

- `~/.config/noctalia/plugins/<pluginId>/`

For this plugin the id is typically:

- `5b965e:claw`
- Installed files live at: `~/.config/noctalia/plugins/5b965e:claw/`

## Ensure The Plugin Source Is Enabled

Noctalia reads plugin sources and enabled state from:

- `~/.config/noctalia/plugins.json`

For local testing, ensure there is a source entry pointing at this repo, and the plugin is enabled:

```json
{
  "sources": [
    {
      "enabled": true,
      "name": "DigitalPals Plugins",
      "url": "https://github.com/DigitalPals/Claw"
    }
  ],
  "states": {
    "5b965e:claw": {
      "enabled": true,
      "sourceUrl": "https://github.com/DigitalPals/Claw"
    }
  }
}
```

Note: the file will usually also include the upstream `noctalia-plugins` source.

## Fast Iteration: Sync Repo To Installed Plugin Folder

The simplest loop is to copy the QML + manifest into the installed plugin folder:

```bash
rsync -av --checksum claw/ ~/.config/noctalia/plugins/5b965e:claw/
```

If you have a `settings.json` in the plugin folder, be careful with `--delete`.

## Clear QML Cache

Quickshell caches compiled QML. After changing QML, clear:

```bash
rm -rf ~/.cache/quickshell/qmlcache
```

## Restart Noctalia Shell Correctly

On this system, `noctalia-shell` is launched via Hyprland. The reliable restart loop is:

1. Kill running `noctalia-shell` Quickshell instances (note: the process name is a wrapper: `.quickshell-wra`).
2. Clear QML cache.
3. Start it via `hyprctl`.

```bash
# Kill only quickshell instances running noctalia-shell.
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill
sleep 0.5
ps -eo pid,comm,args | awk '$2==".quickshell-wra" && $0 ~ /noctalia-shell/ {print $1}' | xargs -r kill -9

rm -rf ~/.cache/quickshell/qmlcache

hyprctl dispatch exec "noctalia-shell"
```

## Validate Without Clicking UI (IPC + Logs)

Tail logs:

```bash
qs -c noctalia-shell log --newest -t 200
```

Open the plugin panel via IPC (reproduces panel-load crashes like `Type MessageBubble unavailable`):

```bash
qs -c noctalia-shell ipc call plugin openPanel 5b965e:claw
```

Filter for plugin errors:

```bash
qs -c noctalia-shell log --newest -t 250 | rg -n "5b965e:claw|Plugin load error|MessageBubble|Panel\\.qml"
```

## Common Failure Mode: QML Type/Property Not Available

Noctalia's Qt/QML build may not support all properties you expect from upstream Qt.

When a panel fails to open and you see:

- `Plugin load error [5b965e:claw/panel]: ... Type <X> unavailable`

The next log line usually points to the exact QML file and line number. Fix that first, then restart + re-test with IPC.

