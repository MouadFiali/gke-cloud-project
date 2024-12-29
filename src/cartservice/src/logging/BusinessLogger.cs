using System;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Hipstershop;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Linq;
using System.Threading;

namespace cartservice.logging
{
    [JsonSerializable(typeof(CartBusinessEvent))]
    [JsonSerializable(typeof(Dictionary<string, int>))]
    public partial class CartBusinessEventContext : JsonSerializerContext { }

    public class CartStats
    {
        public int ViewCount { get; set; }
        public int AddCount { get; set; }
        public int EmptyCount { get; set; }
        public Dictionary<string, int> ProductAdditions { get; set; } = new();
        public HashSet<string> UniqueUsers { get; set; } = new();
        public int TotalItemsAdded { get; set; }
    }

    public class CartBusinessEvent
    {
        [JsonInclude]
        public string EventType { get; set; }
        
        [JsonInclude]
        public string UserId { get; set; }
        
        [JsonInclude]
        public string ProductId { get; set; }
        
        [JsonInclude]
        public int? Quantity { get; set; }
        
        [JsonInclude]
        public int? TotalItems { get; set; }
        
        [JsonInclude]
        public string CartId { get; set; }
        
        [JsonInclude]
        public DateTime Timestamp { get; set; }
        
        [JsonInclude]
        public string ErrorDetails { get; set; }
    }

    public interface ICartBusinessLogger
    {
        void LogViewCart(string userId, string cartId, int totalItems);
        void LogAddToCart(string userId, string productId, int quantity);
        void LogEmptyCart(string userId);
        void LogError(string eventType, string userId, string errorDetails);
    }

    public class CartBusinessLogger : ICartBusinessLogger, IDisposable
    {
        private readonly ILogger<CartBusinessLogger> _logger;
        private static readonly JsonSerializerOptions _options = new()
        {
            WriteIndented = true,
            TypeInfoResolver = CartBusinessEventContext.Default,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        private const string BusinessCategory = "Business";
        private static DateTime _lastLogTime = DateTime.UtcNow;
        private static readonly CartStats _stats = new();
        private static readonly object _lockObj = new();
        private readonly Timer _logTimer;

        public CartBusinessLogger(ILogger<CartBusinessLogger> logger)
        {
            _logger = logger;
            
            // Initialize timer to log stats every 5 minutes
            _logTimer = new Timer(LogStatsCallback, null, 
                TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
        }

        private void LogStatsCallback(object state)
        {
            LogStatsIfNeeded();
        }

        private void LogStatsIfNeeded()
        {
            lock (_lockObj)
            {
                if (_stats.ViewCount == 0 && _stats.AddCount == 0 && _stats.EmptyCount == 0)
                {
                    return; // No activity to report
                }

                var topProducts = _stats.ProductAdditions
                    .OrderByDescending(kv => kv.Value)
                    .Take(5)
                    .ToDictionary(kv => kv.Key, kv => kv.Value);

                using (_logger.BeginScope(new Dictionary<string, object>
                {
                    ["Category"] = BusinessCategory
                }))
                {
                    _logger.LogInformation(
                        "Cart Statistics Summary - Views: {ViewCount}, Additions: {AddCount}, Empties: {EmptyCount}, UniqueUsers: {UniqueUsers}, TotalItems: {TotalItems}, TopProducts: {TopProducts}",
                        _stats.ViewCount,
                        _stats.AddCount,
                        _stats.EmptyCount,
                        _stats.UniqueUsers.Count,
                        _stats.TotalItemsAdded,
                        JsonSerializer.Serialize(topProducts, CartBusinessEventContext.Default.DictionaryStringInt32)
                    );
                }

                // Reset stats
                _stats.ViewCount = 0;
                _stats.AddCount = 0;
                _stats.EmptyCount = 0;
                _stats.ProductAdditions.Clear();
                _stats.UniqueUsers.Clear();
                _stats.TotalItemsAdded = 0;
                _lastLogTime = DateTime.UtcNow;
            }
        }

        public void LogViewCart(string userId, string cartId, int totalItems)
        {
            lock (_lockObj)
            {
                _stats.ViewCount++;
                _stats.UniqueUsers.Add(userId);
            }

            // Log large carts individually as they might be interesting
            if (totalItems > 10)
            {
                LogCartEvent(new CartBusinessEvent
                {
                    EventType = "large_cart_view",
                    UserId = userId,
                    CartId = cartId,
                    TotalItems = totalItems,
                    Timestamp = DateTime.UtcNow
                });
            }
        }

        public void LogAddToCart(string userId, string productId, int quantity)
        {
            lock (_lockObj)
            {
                _stats.AddCount++;
                _stats.UniqueUsers.Add(userId);
                _stats.TotalItemsAdded += quantity;
                
                if (!_stats.ProductAdditions.ContainsKey(productId))
                {
                    _stats.ProductAdditions[productId] = 0;
                }
                _stats.ProductAdditions[productId] += quantity;
            }

            // Log large quantity additions individually
            if (quantity > 5)
            {
                LogCartEvent(new CartBusinessEvent
                {
                    EventType = "large_quantity_addition",
                    UserId = userId,
                    ProductId = productId,
                    Quantity = quantity,
                    Timestamp = DateTime.UtcNow
                });
            }
        }

        public void LogEmptyCart(string userId)
        {
            lock (_lockObj)
            {
                _stats.EmptyCount++;
                _stats.UniqueUsers.Add(userId);
            }
        }

        public void LogError(string eventType, string userId, string errorDetails)
        {
            // Always log errors individually
            LogCartEvent(new CartBusinessEvent
            {
                EventType = $"{eventType}_error",
                UserId = userId,
                ErrorDetails = errorDetails,
                Timestamp = DateTime.UtcNow
            });
        }

        private void LogCartEvent(CartBusinessEvent businessEvent)
        {
            var eventJson = JsonSerializer.Serialize(businessEvent, 
                CartBusinessEventContext.Default.CartBusinessEvent);

            using (_logger.BeginScope(new Dictionary<string, object>
            {
                ["Category"] = BusinessCategory
            }))
            {
                _logger.LogInformation(
                    "Business event: {EventType}, UserID: {UserId}, Details: {EventDetails}", 
                    businessEvent.EventType,
                    businessEvent.UserId,
                    eventJson
                );
            }
        }

        public void Dispose()
        {
            _logTimer?.Dispose();
        }
    }
}