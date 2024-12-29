#!/usr/bin/python

import threading
import time
from collections import defaultdict
from logger import getJSONLogger

class EmailStats:
    def __init__(self):
        self.lock = threading.Lock()
        self.email_sent_count = 0
        self.email_failed_count = 0
        self.template_error_count = 0
        self.domain_stats = defaultdict(int)  # Track emails by domain
        self.last_log_time = time.time()
        self.batch_size = 50  # Log stats every 50 events
        self.current_batch = 0

class BusinessLogger:
    def __init__(self):
        self.logger = getJSONLogger('emailservice-business')
        self.stats = EmailStats()
    
    def _get_email_domain(self, email):
        try:
            return email.split('@')[1] if '@' in email else 'unknown'
        except:
            return 'unknown'
    
    def _check_and_log_stats(self):
        # Log stats if batch size reached or 5 minutes passed
        current_time = time.time()
        if (self.stats.current_batch >= self.stats.batch_size or 
            current_time - self.stats.last_log_time >= 300):  # 300 seconds = 5 minutes
            
            self.logger.info('Email service statistics summary', extra={
                'event_type': 'email_stats_summary',
                'emails_sent': self.stats.email_sent_count,
                'emails_failed': self.stats.email_failed_count,
                'template_errors': self.stats.template_error_count,
                'domain_stats': dict(self.stats.domain_stats),
                'period_seconds': int(current_time - self.stats.last_log_time)
            })
            
            # Reset stats
            self.stats.email_sent_count = 0
            self.stats.email_failed_count = 0
            self.stats.template_error_count = 0
            self.stats.domain_stats.clear()
            self.stats.last_log_time = current_time
            self.stats.current_batch = 0

    def log_email_success(self, email, order_id):
        """Log successful email sending and update stats"""
        with self.stats.lock:
            domain = self._get_email_domain(email)
            self.stats.email_sent_count += 1
            self.stats.domain_stats[domain] += 1
            self.stats.current_batch += 1
            self._check_and_log_stats()

    def log_email_failure(self, email, error_message):
        """Log email sending failure"""
        with self.stats.lock:
            domain = self._get_email_domain(email)
            self.stats.email_failed_count += 1
            self.stats.current_batch += 1
            self._check_and_log_stats()
            
        # Always log failures immediately
        self.logger.error('Failed to send email', extra={
            'event_type': 'email_send_failed',
            'email_domain': domain,
            'error': error_message
        })

    def log_template_error(self, error_message):
        """Log template rendering errors"""
        with self.stats.lock:
            self.stats.template_error_count += 1
            self.stats.current_batch += 1
            self._check_and_log_stats()
            
        # Always log template errors immediately
        self.logger.error('Template rendering failed', extra={
            'event_type': 'template_render_failed',
            'error': error_message
        })