package main

import (
    "fmt"
    "sync"
    "time"
    "github.com/sirupsen/logrus"
    pb "github.com/GoogleCloudPlatform/microservices-demo/src/checkoutservice/genproto"
)

// OrderLogger represents a complete order event
type OrderLogger struct {
    OrderID           string    `json:"order_id"`
    UserID           string    `json:"user_id"`
    Timestamp        time.Time `json:"timestamp"`
    TotalAmount      *pb.Money `json:"total_amount"`
    Currency         string    `json:"currency"`
    ItemCount        int       `json:"item_count"`
    ShippingAddress  *pb.Address `json:"shipping_address"`
    PaymentMethod    string    `json:"payment_method"`
    TransactionID    string    `json:"transaction_id"`
    Status           string    `json:"status"`
}

// OrderStats tracks aggregated order statistics
type OrderStats struct {
    mutex            sync.RWMutex
    orderCount       int
    totalAmount      float64
    successCount     int
    failureCount     int
    lastLog         time.Time
    currencies       map[string]int
}

var orderStats = &OrderStats{
    currencies: make(map[string]int),
    lastLog:   time.Now(),
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

// LogOrderEvent logs a complete order event and updates statistics
func (bl *BusinessLogger) LogOrderEvent(orderLog OrderLogger) {
    // Update stats
    orderStats.mutex.Lock()
    orderStats.orderCount++
    if orderLog.Status == "completed" {
        orderStats.successCount++
    } else {
        orderStats.failureCount++
    }
    orderStats.currencies[orderLog.Currency]++
    amountInUnits := float64(orderLog.TotalAmount.Units) + float64(orderLog.TotalAmount.Nanos)/1e9
    orderStats.totalAmount += amountInUnits

    // Log stats every 5 minutes
    if time.Since(orderStats.lastLog) >= 5*time.Minute {
        bl.log.WithFields(logrus.Fields{
            "event_type":     "order_stats_summary",
            "order_count":    orderStats.orderCount,
            "success_count":  orderStats.successCount,
            "failure_count":  orderStats.failureCount,
            "total_amount":   orderStats.totalAmount,
            "currencies":     orderStats.currencies,
            "period_minutes": 5,
            "timestamp":      time.Now().Format(time.RFC3339),
        }).Info("Order statistics summary")

        // Reset stats
        orderStats.orderCount = 0
        orderStats.successCount = 0
        orderStats.failureCount = 0
        orderStats.totalAmount = 0
        orderStats.currencies = make(map[string]int)
        orderStats.lastLog = time.Now()
    }
    orderStats.mutex.Unlock()

    // Log individual successful orders (these are important business events)
    if orderLog.Status == "completed" {
        bl.log.WithFields(logrus.Fields{
            "event_type":        "order_completed",
            "order_id":         orderLog.OrderID,
            "user_id":          orderLog.UserID,
            "total_amount":     fmt.Sprintf("%d.%d %s", orderLog.TotalAmount.Units, orderLog.TotalAmount.Nanos, orderLog.TotalAmount.CurrencyCode),
            "currency":         orderLog.Currency,
            "item_count":       orderLog.ItemCount,
            "transaction_id":   orderLog.TransactionID,
        }).Info("Order completed successfully")
    }
}

// LogOrderStart - Removed as it's not providing significant business value

// LogCartPreparationError logs cart preparation failures - Keep error logs
func (bl *BusinessLogger) LogCartPreparationError(userID, errorMsg string) {
    bl.log.WithFields(logrus.Fields{
        "event_type": "cart_preparation_failed",
        "user_id":    userID,
        "error":      errorMsg,
    }).Error("Failed to prepare cart items")
}

// LogOrderItemsPrepared - Removed as this information is included in the final order log

// LogPaymentFailure logs payment processing failures - Keep error logs
func (bl *BusinessLogger) LogPaymentFailure(orderID, errorMsg string) {
    bl.log.WithFields(logrus.Fields{
        "event_type": "payment_failed",
        "order_id":   orderID,
        "error":      errorMsg,
    }).Error("Failed to charge card")
}

// LogPaymentSuccess - Removed as this information is included in the final order log

// LogShippingFailure logs shipping failures - Keep error logs
func (bl *BusinessLogger) LogShippingFailure(orderID, errorMsg string) {
    bl.log.WithFields(logrus.Fields{
        "event_type": "shipping_failed",
        "order_id":   orderID,
        "error":      errorMsg,
    }).Error("Shipping failed")
}

// LogCartEmptyFailure logs failures in emptying the cart - Keep warning logs
func (bl *BusinessLogger) LogCartEmptyFailure(userID, errorMsg string) {
    bl.log.WithFields(logrus.Fields{
        "event_type": "cart_empty_failed",
        "user_id":    userID,
        "error":      errorMsg,
    }).Warn("Failed to empty cart")
}

// LogEmailConfirmationFailure logs email confirmation failures - Keep warning logs
func (bl *BusinessLogger) LogEmailConfirmationFailure(orderID, email, errorMsg string) {
    bl.log.WithFields(logrus.Fields{
        "event_type": "email_confirmation_failed",
        "order_id":   orderID,
        "email":      email,
        "error":      errorMsg,
    }).Warn("Failed to send order confirmation email")
}