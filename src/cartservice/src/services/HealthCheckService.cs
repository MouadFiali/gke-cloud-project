using System;
using System.Threading.Tasks;
using Grpc.Core;
using Grpc.Health.V1;
using static Grpc.Health.V1.Health;
using cartservice.cartstore;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;

namespace cartservice.services
{
    internal class HealthCheckService : HealthBase
    {
        private ICartStore _cartStore { get; }
        private static DateTime _lastLogTime = DateTime.UtcNow;
        private const int LOG_INTERVAL_SECONDS = 180;

        public HealthCheckService(ICartStore cartStore) 
        {
            _cartStore = cartStore;
        }

        public override Task<HealthCheckResponse> Check(HealthCheckRequest request, ServerCallContext context)
        {
            var currentTime = DateTime.UtcNow;
            if ((currentTime - _lastLogTime).TotalSeconds >= LOG_INTERVAL_SECONDS)
            {
                Console.WriteLine("Checking CartService Health");
                _lastLogTime = currentTime;
            }
            
            return Task.FromResult(new HealthCheckResponse {
                Status = _cartStore.Ping() ? HealthCheckResponse.Types.ServingStatus.Serving : HealthCheckResponse.Types.ServingStatus.NotServing
            });
        }
    }
}