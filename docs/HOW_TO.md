# Using Codex Usage Monitor

## Setup

Install Node.js 22+, the Swift tools, and an authenticated Codex CLI:

```bash
node --version
codex --version
swift --version
```

## Run

```bash
npm test
npm start
```

In another terminal, to use the macOS interface:

```bash
./scripts/build-macos.sh
open build/CodexUsageMonitor.app
```

## Quotas and alerts

The app displays the remaining **5h** and **Week** quotas. The compact view and menu-bar icon alternate between them every four seconds. In **Settings**, configure an alert percentage for each quota; the alert is re-armed once usage exceeds `codex.rearm_percent`.

The preferred source is an active read from `codex app-server`. If it is unavailable, the app first uses the file at `codex.rate_limit_snapshot_path`, then the latest local metadata from Codex sessions, and finally the manual 5h value.

## Advanced configuration

Configuration is stored at:

```text
~/.config/codex-usage-monitor/config.json
```

The default is `"plan": "personal"`. The only values editable through the UI are `codex.five_hour_alert_percent` and `codex.weekly_alert_percent`.

## Troubleshooting

```bash
curl -s http://127.0.0.1:47931/snapshot | jq
curl -s http://127.0.0.1:47931/config | jq
curl -X POST http://127.0.0.1:47931/refresh | jq
```

If no quota is available, confirm that `codex` works and that the account is authenticated. You can also provide a fallback JSON through `codex.rate_limit_snapshot_path`.
