package main

import (
    "sort"
    "sync"
    "time"
    "github.com/sirupsen/logrus"
    pb "github.com/GoogleCloudPlatform/microservices-demo/src/productcatalogservice/genproto"
)

// ProductSearchLogger represents a product search event
type ProductSearchLogger struct {
    Query          string    `json:"query"`
    ResultCount    int       `json:"result_count"`
    LatencyMs      float64   `json:"latency_ms"`
    Timestamp      time.Time `json:"timestamp"`
}

// ProductViewLogger represents a product view event
type ProductViewLogger struct {
    ProductID      string    `json:"product_id"`
    Name          string    `json:"name"`
    Price         *pb.Money `json:"price"`
    Timestamp     time.Time `json:"timestamp"`
}

// CatalogOperationLogger represents catalog operations
type CatalogOperationLogger struct {
    Operation     string    `json:"operation"`
    ProductCount  int       `json:"product_count"`
    Status        string    `json:"status"`
    Timestamp     time.Time `json:"timestamp"`
}

// BusinessLogger handles all business event logging
type BusinessLogger struct {
    log *logrus.Logger
}

// NewBusinessLogger creates a new BusinessLogger instance
func NewBusinessLogger(logger *logrus.Logger) *BusinessLogger {
    return &BusinessLogger{
        log: logger,
    }
}

// ProductViewCounter tracks view counts for products
type ProductViewCounter struct {
    mutex   sync.RWMutex
    counts  map[string]int
    lastLog time.Time
}

var viewCounter = &ProductViewCounter{
    counts:  make(map[string]int),
    lastLog: time.Now(),
}

// LogProductView aggregates product views and logs summaries periodically
func (bl *BusinessLogger) LogProductView(product *pb.Product) {
    viewCounter.mutex.Lock()
    viewCounter.counts[product.Id]++
    
    // Log aggregated stats every 5 minutes
    if time.Since(viewCounter.lastLog) >= 5*time.Minute {
        // Prepare stats
        total := 0
        topViewed := make([]map[string]interface{}, 0)
        
        // Get top 5 most viewed products
        for id, count := range viewCounter.counts {
            total += count
            topViewed = append(topViewed, map[string]interface{}{
                "product_id": id,
                "views":      count,
            })
        }
        
        // Sort and keep top 5
        sort.Slice(topViewed, func(i, j int) bool {
            return topViewed[i]["views"].(int) > topViewed[j]["views"].(int)
        })
        if len(topViewed) > 5 {
            topViewed = topViewed[:5]
        }

        // Log the aggregated stats
        bl.log.WithFields(logrus.Fields{
            "event_type":      "product_views_summary",
            "total_views":     total,
            "unique_products": len(viewCounter.counts),
            "top_viewed":      topViewed,
            "period_minutes":  5,
            "timestamp":       time.Now().Format(time.RFC3339),
        }).Info("Product views summary")

        // Reset counters
        viewCounter.counts = make(map[string]int)
        viewCounter.lastLog = time.Now()
    }
    viewCounter.mutex.Unlock()
}

// LogProductNotFound logs when a product request fails
func (bl *BusinessLogger) LogProductNotFound(productID string) {
    bl.log.WithFields(logrus.Fields{
        "event_type":     "product_not_found",
        "product_id":     productID,
        "timestamp":      time.Now().Format(time.RFC3339),
    }).Warn("Product not found")
}

// LogSearchQuery logs product search events
func (bl *BusinessLogger) LogSearchQuery(query string, resultCount int, latencyMs float64) {
    bl.log.WithFields(logrus.Fields{
        "event_type":     "product_search",
        "query":          query,
        "result_count":   resultCount,
        "latency_ms":     latencyMs,
        "timestamp":      time.Now().Format(time.RFC3339),
    }).Info("Product search performed")
}

// LogCatalogOperation logs catalog operations (reload/refresh)
func (bl *BusinessLogger) LogCatalogOperation(operation string, productCount int, status string) {
    // Only log catalog operations that are reloads or errors
    if operation == "reload_catalog" || status == "error" {
        level := logrus.InfoLevel
        if status == "error" {
            level = logrus.ErrorLevel
        }
        
        bl.log.WithFields(logrus.Fields{
            "event_type":     "catalog_operation",
            "operation":      operation,
            "product_count":  productCount,
            "status":        status,
            "timestamp":     time.Now().Format(time.RFC3339),
        }).Log(level, "Catalog operation performed")
    }
}