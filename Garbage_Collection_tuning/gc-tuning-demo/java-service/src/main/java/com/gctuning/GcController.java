package com.gctuning;

import org.springframework.web.bind.annotation.*;
import org.springframework.scheduling.annotation.Scheduled;
import java.lang.management.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.*;

@RestController
public class GcController {

    // Simulate real workload: short-lived objects + some long-lived cache
    private final Map<String, byte[]> cache = new ConcurrentHashMap<>();
    private final AtomicLong requestCount = new AtomicLong(0);
    private final List<Long> latencySamples = Collections.synchronizedList(
        new LinkedList<>()
    );
    private final String gcType = System.getProperty("gc.type", "G1GC");

    // Keep last 1000 samples only
    private void addLatencySample(long ms) {
        synchronized (latencySamples) {
            latencySamples.add(ms);
            if (latencySamples.size() > 1000) {
                latencySamples.remove(0);
            }
        }
    }

    @GetMapping("/process")
    public Map<String, Object> processRequest(
            @RequestParam(defaultValue="medium") String load) {

        long start = System.nanoTime();

        // Simulate allocation-heavy work based on load level
        int allocCount = switch(load) {
            case "heavy" -> 5000;
            case "light" -> 500;
            default -> 2000;
        };

        List<byte[]> tempObjects = new ArrayList<>(allocCount);
        for (int i = 0; i < allocCount; i++) {
            // Short-lived objects (simulate request processing)
            tempObjects.add(new byte[512]);
        }

        // Simulate some computation using those objects
        long checksum = 0;
        for (byte[] b : tempObjects) {
            checksum += b.length;
        }

        // ~5% of requests promote objects to "cache" (long-lived)
        if (requestCount.get() % 20 == 0) {
            String key = "entry-" + (System.currentTimeMillis() % 500);
            cache.put(key, new byte[4096]);
            if (cache.size() > 500) {
                // Evict random entry
                String evict = cache.keySet().iterator().next();
                cache.remove(evict);
            }
        }

        long elapsedMs = (System.nanoTime() - start) / 1_000_000;
        addLatencySample(elapsedMs);
        requestCount.incrementAndGet();

        Map<String, Object> result = new HashMap<>();
        result.put("requestId", requestCount.get());
        result.put("latencyMs", elapsedMs);
        result.put("allocatedObjects", allocCount);
        result.put("checksum", checksum);
        return result;
    }

    @GetMapping("/metrics")
    public Map<String, Object> metrics() {
        Map<String, Object> m = new HashMap<>();

        // GC metrics
        List<GarbageCollectorMXBean> gcBeans = ManagementFactory.getGarbageCollectorMXBeans();
        long totalGcCount = 0, totalGcTime = 0;
        List<Map<String, Object>> gcDetails = new ArrayList<>();
        for (GarbageCollectorMXBean gc : gcBeans) {
            totalGcCount += Math.max(gc.getCollectionCount(), 0);
            totalGcTime  += Math.max(gc.getCollectionTime(), 0);
            Map<String, Object> d = new HashMap<>();
            d.put("name", gc.getName());
            d.put("count", Math.max(gc.getCollectionCount(), 0));
            d.put("timeMs", Math.max(gc.getCollectionTime(), 0));
            gcDetails.add(d);
        }
        m.put("gcCollectors", gcDetails);
        m.put("totalGcCount", totalGcCount);
        m.put("totalGcTimeMs", totalGcTime);

        // Memory metrics
        MemoryMXBean mem = ManagementFactory.getMemoryMXBean();
        MemoryUsage heap = mem.getHeapMemoryUsage();
        m.put("heapUsedMB",  heap.getUsed()      / 1024 / 1024);
        m.put("heapMaxMB",   heap.getMax()        / 1024 / 1024);
        m.put("heapCommitMB",heap.getCommitted()  / 1024 / 1024);

        // Request metrics
        m.put("totalRequests", requestCount.get());
        m.put("cacheSize", cache.size());
        m.put("gcType", gcType);

        // Latency percentiles
        synchronized (latencySamples) {
            if (!latencySamples.isEmpty()) {
                List<Long> sorted = new ArrayList<>(latencySamples);
                Collections.sort(sorted);
                int size = sorted.size();
                m.put("latencyP50",  sorted.get((int)(size * 0.50)));
                m.put("latencyP95",  sorted.get((int)(size * 0.95)));
                m.put("latencyP99",  sorted.get(Math.min((int)(size * 0.99), size - 1)));
                m.put("latencyP999", sorted.get(Math.min((int)(size * 0.999), size - 1)));
                m.put("sampleCount", size);
            }
        }

        return m;
    }

    // Background allocation pressure — simulates background jobs
    @Scheduled(fixedDelay = 2000)
    public void backgroundWork() {
        List<byte[]> scratch = new ArrayList<>(200);
        for (int i = 0; i < 200; i++) {
            scratch.add(new byte[1024]);
        }
        // Intentionally let them go out of scope
        scratch.clear();
    }
}
