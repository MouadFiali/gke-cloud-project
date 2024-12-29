using System;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Caching.Distributed;
using cartservice.cartstore;
using cartservice.services;
using Microsoft.Extensions.Caching.StackExchangeRedis;
using cartservice.logging;

namespace cartservice
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }
        
        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            string redisAddress = Configuration["REDIS_ADDR"];
            string spannerProjectId = Configuration["SPANNER_PROJECT"];
            string spannerConnectionString = Configuration["SPANNER_CONNECTION_STRING"];
            string alloyDBConnectionString = Configuration["ALLOYDB_PRIMARY_IP"];

            // Add logging first
            services.AddLogging(logging =>
            {
                logging.AddConsole();
                logging.SetMinimumLevel(LogLevel.Debug);
            });

            if (!string.IsNullOrEmpty(redisAddress))
            {
                services.AddStackExchangeRedisCache(options =>
                {
                    options.Configuration = redisAddress;
                });
                services.AddSingleton<ICartStore>(sp =>
                {
                    var cache = sp.GetRequiredService<IDistributedCache>();
                    var logger = sp.GetRequiredService<ILogger<RedisCartStore>>();
                    return new RedisCartStore(cache, logger);
                });
            }
            else if (!string.IsNullOrEmpty(spannerProjectId) || !string.IsNullOrEmpty(spannerConnectionString))
            {
                services.AddSingleton<ICartStore, SpannerCartStore>();
            }
            else if (!string.IsNullOrEmpty(alloyDBConnectionString))
            {
                services.AddLogging(builder => builder.AddConsole())
                    .Configure<LoggerFilterOptions>(options => options.MinLevel = LogLevel.Information);
                services.AddSingleton<ICartStore, AlloyDBCartStore>();
            }
            else
            {
                services.AddLogging(builder => builder.AddConsole())
                    .Configure<LoggerFilterOptions>(options => options.MinLevel = LogLevel.Information);
                services.AddDistributedMemoryCache();
                services.AddSingleton<ICartStore>(sp =>
                {
                    var cache = sp.GetRequiredService<IDistributedCache>();
                    var logger = sp.GetRequiredService<ILogger<RedisCartStore>>();
                    return new RedisCartStore(cache, logger);
                });
            }

            services.AddSingleton<ICartBusinessLogger, CartBusinessLogger>();
            services.AddGrpc();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseRouting();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapGrpcService<CartService>();
                endpoints.MapGrpcService<cartservice.services.HealthCheckService>();

                endpoints.MapGet("/", async context =>
                {
                    await context.Response.WriteAsync("Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");
                });
            });
        }
    }
}