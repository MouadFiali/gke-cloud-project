#!/usr/bin/python

import threading
import time
from collections import defaultdict
from logger import getJSONLogger
import queue
from threading import Thread

class RecommendationStats:
    def __init__(self):
        self.lock = threading.Lock()
        self.request_count = 0
        self.recommended_products = defaultdict(int)
        self.total_recommendations = 0
        self.last_log_time = time.time()
        self.batch_size = 20

class BusinessLogger:
    def __init__(self, base_logger):
        self.logger = base_logger
        self.stats = RecommendationStats()
        self.log_queue = queue.Queue()
        self.is_running = True  # Flag to control the background thread
        self.logger.info("[BusinessLogger] Starting initialization")
        self.background_thread = self.start_background_processor()
        self.logger.info("[BusinessLogger] Initialized business logger")

    def _process_recommendation(self, input_products, recommended_products):
        try:
            with self.stats.lock:
                self.stats.request_count += 1
                self.stats.total_recommendations += len(recommended_products)
                
                for product_id in recommended_products:
                    self.stats.recommended_products[product_id] += 1

                # Log every batch_size requests
                if self.stats.request_count >= self.stats.batch_size:
                    self._log_stats()
                    
        except Exception as e:
            self.logger.error(f"[BusinessLogger] Error processing recommendation: {str(e)}")

    def _log_stats(self):
        try:
            if self.stats.request_count > 0:
                self.logger.info("[BusinessLogger] Recommendation statistics", extra={
                    'event_type': 'recommendation_stats',
                    'request_count': self.stats.request_count,
                    'total_recommendations': self.stats.total_recommendations,
                    'top_products': dict(sorted(
                        self.stats.recommended_products.items(),
                        key=lambda x: x[1],
                        reverse=True
                    )[:5]),
                    'time_since_last_log': time.time() - self.stats.last_log_time
                })

                # Reset stats after logging
                self.stats.request_count = 0
                self.stats.recommended_products.clear()
                self.stats.total_recommendations = 0
                self.stats.last_log_time = time.time()

        except Exception as e:
            self.logger.error(f"[BusinessLogger] Error logging stats: {str(e)}")

    def start_background_processor(self):
        def process_logs():
            self.logger.info("[BusinessLogger] Background processor started")
            while self.is_running:
                try:
                    # Shorter timeout for more frequent checks
                    log_entry = self.log_queue.get(timeout=0.1)
                    
                    # Debug log to verify queue processing
                    self.logger.debug(f"[BusinessLogger] Processing log entry of type: {log_entry['type']}")
                    
                    if log_entry['type'] == 'recommendation':
                        self._process_recommendation(
                            log_entry['input_products'],
                            log_entry['recommended_products']
                        )
                    elif log_entry['type'] == 'error':
                        self.logger.error(
                            "[BusinessLogger] Recommendation error",
                            extra={
                                'event_type': 'recommendation_error',
                                'error': log_entry['error'],
                                'input_products': log_entry['input_products']
                            }
                        )
                    
                    # Mark the task as done
                    self.log_queue.task_done()
                    
                except queue.Empty:
                    # Check if we should log stats due to time
                    current_time = time.time()
                    if current_time - self.stats.last_log_time >= 60:  # 1 minute
                        self._log_stats()
                except Exception as e:
                    self.logger.error(f"[BusinessLogger] Error in background processor: {str(e)}")
                    # Small sleep to prevent tight loop in case of persistent errors
                    time.sleep(0.1)

        thread = Thread(target=process_logs, daemon=True)
        thread.start()
        return thread

    def log_recommendation_request(self, input_products, recommended_products):
        """Queue recommendation request for processing"""
        try:
            self.log_queue.put({
                'type': 'recommendation',
                'input_products': input_products,
                'recommended_products': recommended_products
            })
            # Debug log to verify queuing
            self.logger.debug(f"[BusinessLogger] Queued recommendation request with {len(recommended_products)} products")
        except Exception as e:
            self.logger.error(f"[BusinessLogger] Error queuing recommendation request: {str(e)}")

    def log_recommendation_error(self, error_message, input_products=None):
        """Queue error for processing"""
        try:
            self.log_queue.put({
                'type': 'error',
                'error': error_message,
                'input_products': input_products
            })
        except Exception as e:
            self.logger.error(f"[BusinessLogger] Error queuing error log: {str(e)}")

    def __del__(self):
        """Cleanup when the logger is destroyed"""
        self.is_running = False
        if self.background_thread and self.background_thread.is_alive():
            self.background_thread.join(timeout=1.0)