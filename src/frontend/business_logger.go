package main

import (
    "sync"
    "time"
    "github.com/sirupsen/logrus"
)

type BusinessLogger struct {
    logger *logrus.Logger
    metrics struct {
        sync.RWMutex
        productViews     map[string]int
        checkoutStarts   int
        checkoutComplete int
        orderValueTotal  map[string]float64
        currencyChanges  map[string]int
    }
    lastReport time.Time
}

func NewBusinessLogger(logger *logrus.Logger) *BusinessLogger {
    bl := &BusinessLogger{
        logger: logger,
        lastReport: time.Now(),
    }
    bl.resetMetrics()
    go bl.startReportingLoop()
    return bl
}

func (bl *BusinessLogger) resetMetrics() {
    bl.metrics.productViews = make(map[string]int)
    bl.metrics.currencyChanges = make(map[string]int)
    bl.metrics.orderValueTotal = make(map[string]float64)
    bl.metrics.checkoutStarts = 0
    bl.metrics.checkoutComplete = 0
}

func (bl *BusinessLogger) startReportingLoop() {
    ticker := time.NewTicker(5 * time.Minute)
    for range ticker.C {
        bl.reportMetrics()
    }
}

func (bl *BusinessLogger) TrackProductView(productId string) {
    bl.metrics.Lock()
    bl.metrics.productViews[productId]++
    bl.metrics.Unlock()
}

func (bl *BusinessLogger) TrackCheckoutStart() {
    bl.metrics.Lock()
    bl.metrics.checkoutStarts++
    bl.metrics.Unlock()
}

func (bl *BusinessLogger) TrackOrderComplete(amount float64, currency string) {
    bl.metrics.Lock()
    bl.metrics.checkoutComplete++
    bl.metrics.orderValueTotal[currency] += amount
    bl.metrics.Unlock()
}

func (bl *BusinessLogger) TrackCurrencyChange(currency string) {
    bl.metrics.Lock()
    bl.metrics.currencyChanges[currency]++
    bl.metrics.Unlock()
}

func (bl *BusinessLogger) reportMetrics() {
    bl.metrics.Lock()
    defer bl.metrics.Unlock()

    if bl.metrics.checkoutStarts > 0 || len(bl.metrics.productViews) > 0 {
        bl.logger.WithFields(logrus.Fields{
            "event": "business_metrics_report",
            "period": "5m",
            "checkout_conversion": float64(bl.metrics.checkoutComplete) / float64(bl.metrics.checkoutStarts) * 100,
            "total_checkouts": bl.metrics.checkoutComplete,
            "total_cart_views": bl.metrics.checkoutStarts,
            "order_value_by_currency": bl.metrics.orderValueTotal,
            "currency_preferences": bl.metrics.currencyChanges,
        }).Info("Frontend business metrics report")
    }

    bl.resetMetrics()
}