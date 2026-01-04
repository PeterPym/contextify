# Instruments Profiling Guide

## Quick Start

### Time Profiler (CPU)

```bash
# Launch app with Time Profiler
xcrun xctrace record --template "Time Profiler" \
    --output /tmp/contextify-cpu.trace \
    --launch ".derived-dmg/Build/Products/Debug/Contextify.app/Contents/MacOS/Contextify"
```

### Allocations (Memory)

```bash
# Launch app with Allocations instrument
xcrun xctrace record --template "Allocations" \
    --output /tmp/contextify-memory.trace \
    --launch ".derived-dmg/Build/Products/Debug/Contextify.app/Contents/MacOS/Contextify"
```

### System Trace (Full System)

```bash
# Full system trace (very detailed, large files)
xcrun xctrace record --template "System Trace" \
    --output /tmp/contextify-system.trace \
    --launch ".derived-dmg/Build/Products/Debug/Contextify.app/Contents/MacOS/Contextify"
```

## Analyzing Traces

Open trace files in Instruments:

```bash
open /tmp/contextify-cpu.trace
```

### Key Areas to Examine

1. **Startup Path**
   - Look for `AppStateOrchestrator.startup()`
   - Check `LightweightDiscoveryService.discoverProjectsLightweight()`
   - Verify main thread is not blocked

2. **Ingest Path**
   - Look for `HooverEngine.hooverTranscript()`
   - Check `TranscriptParsers` methods
   - Verify batch processing is efficient

3. **Memory Hotspots**
   - Look for allocation spikes during ingest
   - Check for memory not being released
   - Verify batch size is appropriate

## Attaching to Running Process

```bash
# Attach Time Profiler to running Contextify
xcrun xctrace record --template "Time Profiler" \
    --output /tmp/contextify-attach.trace \
    --attach "Contextify"
```

## Custom Instruments Template

For repeated benchmarking, create a custom template in Instruments GUI:
1. File > New > Blank
2. Add instruments: Time Profiler, Allocations, System Usage
3. Save as template: `Contextify Benchmark`

Then use:
```bash
xcrun xctrace record --template "Contextify Benchmark" \
    --output /tmp/contextify-full.trace \
    --launch ".derived-dmg/Build/Products/Debug/Contextify.app/Contents/MacOS/Contextify"
```
