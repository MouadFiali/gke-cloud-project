package main

import (
    "sync"
    "time"
    "github.com/sirupsen/logrus"
    pb "github.com/GoogleCloudPlatform/microservices-demo/src/shippingservice/genproto"
)

// ShippingStats tracks aggregated shipping statistics
type ShippingStats struct {
    mutex              sync.RWMutex
    quoteRequests      int
    shippingOrders     int
    totalQuoteAmount   float64
    regionStats        map[string]int    // Tracks shipping by region
    lastLog           time.Time
    batchSize         int               // Number of events before logging
    currentBatch      int               // Current count in batch
}

// BusinessLogger handles shipping-related business event logging
type BusinessLogger struct {
    log *logrus.Logger
    stats *ShippingStats
}

// NewBusinessLogger creates a new BusinessLogger instance
func NewBusinessLogger(logger *logrus.Logger) *BusinessLogger {
    return &BusinessLogger{
        log: logger,
        stats: &ShippingStats{
            regionStats: make(map[string]int),
            lastLog:    time.Now(),
            batchSize:  100,  // Only log stats every 100 events
        },
    }
}

// LogQuoteRequest logs shipping quote requests and updates statistics
func (bl *BusinessLogger) LogQuoteRequest(address *pb.Address, quote *pb.Money) {
    if bl == nil || bl.stats == nil {
        return
    }

    region := "unknown"
    if address != nil {
        region = address.State
        if region == "" {
            region = "unknown"
        }
    }

    var amountInUsd float64
    if quote != nil {
        amountInUsd = float64(quote.Units) + float64(quote.Nanos)/1e9
    }

    // Update stats
    bl.stats.mutex.Lock()
    defer bl.stats.mutex.Unlock()
    
    bl.stats.quoteRequests++
    bl.stats.regionStats[region]++
    bl.stats.totalQuoteAmount += amountInUsd
    bl.stats.currentBatch++

    // Log stats either when batch size is reached or 5 minutes have passed
    if bl.stats.currentBatch >= bl.stats.batchSize || time.Since(bl.stats.lastLog) >= 5*time.Minute {
        bl.log.WithFields(logrus.Fields{
            "event_type":        "shipping_stats_summary",
            "quote_requests":    bl.stats.quoteRequests,
            "shipping_orders":   bl.stats.shippingOrders,
            "total_quote_amount": bl.stats.totalQuoteAmount,
            "region_stats":      bl.stats.regionStats,
            "period":           time.Since(bl.stats.lastLog).String(),
        }).Info("Shipping statistics summary")

        // Reset stats
        bl.stats.quoteRequests = 0
        bl.stats.shippingOrders = 0
        bl.stats.totalQuoteAmount = 0
        bl.stats.regionStats = make(map[string]int)
        bl.stats.lastLog = time.Now()
        bl.stats.currentBatch = 0
    }
}

// LogShippingOrder logs successful shipping order creation
func (bl *BusinessLogger) LogShippingOrder(address *pb.Address, trackingId string) {
    if bl == nil || bl.stats == nil {
        return
    }

    region := "unknown"
    if address != nil {
        region = address.State
        if region == "" {
            region = "unknown"
        }
    }

    bl.stats.mutex.Lock()
    bl.stats.shippingOrders++
    bl.stats.mutex.Unlock()

    // Only log shipping orders as they're more significant business events
    bl.log.WithFields(logrus.Fields{
        "event_type":     "order_shipped",
        "tracking_id":    trackingId,
        "address_region": region,
        "city":          address.GetCity(),
    }).Info("Shipping order created")
}

// LogQuoteError logs errors in quote generation
func (bl *BusinessLogger) LogQuoteError(address *pb.Address, err string) {
    if bl == nil || bl.log == nil {
        return
    }

    region := "unknown"
    if address != nil {
        region = address.State
        if region == "" {
            region = "unknown"
        }
    }

    // Always log errors
    bl.log.WithFields(logrus.Fields{
        "event_type":     "quote_error",
        "address_region": region,
        "error":         err,
    }).Error("Failed to generate shipping quote")
}

// LogShippingError logs errors in shipping order creation
func (bl *BusinessLogger) LogShippingError(address *pb.Address, err string) {
    if bl == nil || bl.log == nil {
        return
    }

    region := "unknown"
    if address != nil {
        region = address.State
        if region == "" {
            region = "unknown"
        }
    }

    // Always log errors
    bl.log.WithFields(logrus.Fields{
        "event_type":     "shipping_error",
        "address_region": region,
        "error":         err,
    }).Error("Failed to create shipping order")
}