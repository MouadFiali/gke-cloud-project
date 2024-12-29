// businessLogger.js
const pino = require('pino');

class BusinessLogger {
    constructor() {
        this.logger = pino({
            name: 'currencyservice-business',
            messageKey: 'message',
            formatters: {
                level(logLevelString, logLevelNum) {
                    return { severity: logLevelString }
                }
            }
        });

        // Track currency pair usage
        this.currencyPairCounts = new Map();
        this.lastReportTime = Date.now();
        this.REPORT_INTERVAL = 1 * 60 * 1000; // 5 minutes
    }

    trackConversion(fromCurrency, toCurrency) {
        const pair = `${fromCurrency}->${toCurrency}`;
        this.currencyPairCounts.set(pair, (this.currencyPairCounts.get(pair) || 0) + 1);

        // Check if it's time to report
        const now = Date.now();
        if (now - this.lastReportTime >= this.REPORT_INTERVAL) {
            this.reportMetrics();
            this.lastReportTime = now;
        }
    }

    reportMetrics() {
        if (this.currencyPairCounts.size === 0) return;

        // Get top currency pairs
        const topPairs = [...this.currencyPairCounts.entries()]
            .sort((a, b) => b[1] - a[1])
            .slice(0, 5);

        this.logger.info({
            event: 'currency_conversion_metrics',
            message: 'Currency Conversion Patterns Report',
            total_conversions: [...this.currencyPairCounts.values()].reduce((a, b) => a + b, 0),
            top_currency_pairs: topPairs.map(([pair, count]) => ({
                pair,
                count
            }))
        });

        // Clear counters after reporting
        this.currencyPairCounts.clear();
    }
}

module.exports = new BusinessLogger();