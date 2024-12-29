// businessLogger.js
const pino = require('pino');

class BusinessLogger {
    constructor() {
        this.logger = pino({
            name: 'paymentservice-business',
            messageKey: 'message',
            formatters: {
                level(logLevelString) {
                    return { severity: logLevelString }
                }
            }
        });

        // Keep metrics for overall health monitoring
        this.metrics = {
            transactionCount: 0,
            successCount: 0,
            failureCount: 0
        };

        this.lastReportTime = Date.now();
        this.REPORT_INTERVAL = 5 * 60 * 1000; // 5 minutes
    }

    logTransaction(success, amount, cardType, cardLastFour, transactionId = null, failureReason = null) {
        // Log individual transaction immediately
        this.logger.info({
            event: 'payment_transaction',
            message: success ? 'Payment processed successfully' : 'Payment processing failed',
            transaction_details: {
                transaction_id: transactionId,
                status: success ? 'success' : 'failed',
                amount: {
                    value: amount.units + (amount.nanos / 1000000000),
                    currency: amount.currency_code
                },
                card_type: cardType,
                card_last_four: cardLastFour,
                timestamp: new Date().toISOString(),
                failure_reason: failureReason || undefined
            }
        });

        // Update summary metrics
        if (success) {
            this.metrics.successCount++;
        } else {
            this.metrics.failureCount++;
        }
        this.metrics.transactionCount++;

        // Report overall health metrics periodically
        const now = Date.now();
        if (now - this.lastReportTime >= this.REPORT_INTERVAL) {
            this.reportHealthMetrics();
            this.lastReportTime = now;
        }
    }

    reportHealthMetrics() {
        if (this.metrics.transactionCount === 0) return;

        const successRate = (this.metrics.successCount / this.metrics.transactionCount * 100).toFixed(2);

        // Log only high-level health metrics
        this.logger.info({
            event: 'payment_health_metrics',
            message: 'Payment Service Health Report',
            period_minutes: 5,
            metrics: {
                total_transactions: this.metrics.transactionCount,
                success_rate: `${successRate}%`,
                failure_count: this.metrics.failureCount
            }
        });

        // Reset metrics
        this.metrics = {
            transactionCount: 0,
            successCount: 0,
            failureCount: 0
        };
    }
}

module.exports = new BusinessLogger();