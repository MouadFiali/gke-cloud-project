using System;
using System.Linq;
using System.Threading.Tasks;
using Grpc.Core;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Google.Protobuf;
using System.Collections.Concurrent;

namespace cartservice.cartstore
{
    public class RedisCartStore : ICartStore
    {
        private readonly IDistributedCache _cache;
        private readonly ILogger<RedisCartStore> _logger;
        private static readonly ConcurrentDictionary<string, DateTime> _lastLoggedAccess = new();
        private const int LOG_THRESHOLD_MINUTES = 5;

        public RedisCartStore(IDistributedCache cache, ILogger<RedisCartStore> logger)
        {
            _cache = cache;
            _logger = logger;
        }

        public async Task AddItemAsync(string userId, string productId, int quantity)
        {
            try
            {
                Hipstershop.Cart cart;
                var value = await _cache.GetAsync(userId);
                if (value == null)
                {
                    cart = new Hipstershop.Cart();
                    cart.UserId = userId;
                    cart.Items.Add(new Hipstershop.CartItem { ProductId = productId, Quantity = quantity });
                    
                    _logger.LogDebug("Created new cart for user {UserId}", userId);
                }
                else
                {
                    cart = Hipstershop.Cart.Parser.ParseFrom(value);
                    var existingItem = cart.Items.SingleOrDefault(i => i.ProductId == productId);
                    if (existingItem == null)
                    {
                        cart.Items.Add(new Hipstershop.CartItem { ProductId = productId, Quantity = quantity });
                    }
                    else
                    {
                        existingItem.Quantity += quantity;
                    }
                }
                await _cache.SetAsync(userId, cart.ToByteArray());
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to add item to cart for user {UserId}. ProductId: {ProductId}", 
                    userId, productId);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task EmptyCartAsync(string userId)
        {
            try
            {
                var cart = new Hipstershop.Cart();
                await _cache.SetAsync(userId, cart.ToByteArray());
                _logger.LogDebug("Cart emptied for user {UserId}", userId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to empty cart for user {UserId}", userId);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        public async Task<Hipstershop.Cart> GetCartAsync(string userId)
        {
            try
            {
                var value = await _cache.GetAsync(userId);

                // Only log if we haven't logged for this user recently
                if (ShouldLogAccess(userId))
                {
                    _logger.LogDebug("Cart accessed for user {UserId}, HasItems: {HasItems}", 
                        userId, value != null);
                }

                if (value != null)
                {
                    return Hipstershop.Cart.Parser.ParseFrom(value);
                }

                return new Hipstershop.Cart();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to get cart for user {UserId}", userId);
                throw new RpcException(new Status(StatusCode.FailedPrecondition, $"Can't access cart storage. {ex}"));
            }
        }

        private bool ShouldLogAccess(string userId)
        {
            var now = DateTime.UtcNow;
            var lastLog = _lastLoggedAccess.AddOrUpdate(
                userId,
                now,
                (_, existing) => (now - existing).TotalMinutes >= LOG_THRESHOLD_MINUTES ? now : existing);
            
            return lastLog == now;
        }

        public bool Ping()
        {
            try
            {
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Redis ping failed");
                return false;
            }
        }
    }
}