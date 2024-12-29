package hipstershop;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import com.google.common.collect.ConcurrentHashMultiset;
import com.google.common.collect.Multiset;
import java.util.Map;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.time.Instant;

public class BusinessLogger {
    private static final Logger logger = LogManager.getLogger(BusinessLogger.class);
    
    // Metrics collectors
    private final Map<String, AtomicLong> categoryServeCount;
    private final ConcurrentHashMultiset<String> contextKeyStats;
    private final Map<String, AtomicLong> errorCounts;
    private long lastReportTimestamp;
    private static final long REPORT_INTERVAL_MS = 300000; // 5 minutes

    public BusinessLogger() {
        this.categoryServeCount = new ConcurrentHashMap<>();
        this.contextKeyStats = ConcurrentHashMultiset.create();
        this.errorCounts = new ConcurrentHashMap<>();
        this.lastReportTimestamp = System.currentTimeMillis();
    }

    public void logAdRequest(List<String> contextKeys, int resultCount) {
        // Only log if we have context keys (more meaningful)
        if (!contextKeys.isEmpty()) {
            logger.info("Ad request processed: context_keys={}, ads_returned={}", 
                       String.join(",", contextKeys), resultCount);
            
            // Update context key stats
            contextKeys.forEach(contextKeyStats::add);
        }
    }

    public void logAdServed(String category) {
        if (category != null) {
            categoryServeCount.computeIfAbsent(category, k -> new AtomicLong()).incrementAndGet();
            
            // Check if it's time to report aggregated metrics
            long currentTime = System.currentTimeMillis();
            if (currentTime - lastReportTimestamp >= REPORT_INTERVAL_MS) {
                reportAggregatedMetrics();
                lastReportTimestamp = currentTime;
            }
        }
    }

    public void logError(String errorType, String message) {
        errorCounts.computeIfAbsent(errorType, k -> new AtomicLong()).incrementAndGet();
        logger.error("Ad Service error: type={}, message={}", errorType, message);
    }

    private void reportAggregatedMetrics() {
        // Report category performance
        logger.info("Ad Category Performance Report:");
        categoryServeCount.forEach((category, count) -> 
            logger.info("  Category: {} - Serve Count: {}", category, count.get())
        );

        // Report top context keys
        logger.info("Top Context Keys Report:");
        contextKeyStats.entrySet().stream()
            .sorted((e1, e2) -> Integer.compare(e2.getCount(), e1.getCount()))
            .limit(5)
            .forEach(entry -> 
                logger.info("  Context Key: {} - Usage Count: {}", 
                          entry.getElement(), entry.getCount())
            );

        // Report error summary if any
        if (!errorCounts.isEmpty()) {
            logger.warn("Error Summary Report:");
            errorCounts.forEach((errorType, count) ->
                logger.warn("  Error Type: {} - Count: {}", errorType, count.get())
            );
        }

        // Reset counters after reporting
        categoryServeCount.clear();
        contextKeyStats.clear();
        errorCounts.clear();
    }
}