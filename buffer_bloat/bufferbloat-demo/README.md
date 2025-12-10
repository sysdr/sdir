# Buffer Bloat Demonstration

This demo shows how excessive network buffering causes high latency.

## Quick Start

```bash
bash demo.sh
```

Then open http://localhost:5000 in your browser.

## What You'll See

- **Normal Queue**: Healthy latency (~20-30ms)
- **Buffer Bloat**: High latency (~200-500ms+) even with no packet loss
- **AQM (FQ-CoDel)**: Optimal latency (~25-40ms) with smart dropping

## Architecture

The demo creates three network namespaces, each with different queue management:
1. Normal: Reasonable buffer size (100 packets)
2. Bloated: Excessive buffer (10,000 packets)
3. AQM: FQ-CoDel active queue management

## Cleanup

```bash
bash cleanup.sh
```
