// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using System;
using System.Threading.Tasks;
using Grpc.Core;
using Microsoft.Extensions.Logging;
using cartservice.cartstore;
using cartservice.logging;
using Hipstershop;

namespace cartservice.services
{
    public class CartService : Hipstershop.CartService.CartServiceBase
    {
        private readonly static Empty Empty = new Empty();
        private readonly ICartStore _cartStore;
        private readonly ICartBusinessLogger _businessLogger;

        public CartService(ICartStore cartStore, ICartBusinessLogger businessLogger)
        {
            _cartStore = cartStore;
            _businessLogger = businessLogger;
        }

        public async override Task<Empty> AddItem(AddItemRequest request, ServerCallContext context)
        {
            try 
            {
                await _cartStore.AddItemAsync(request.UserId, request.Item.ProductId, request.Item.Quantity);
                _businessLogger.LogAddToCart(
                    userId: request.UserId,
                    productId: request.Item.ProductId,
                    quantity: request.Item.Quantity
                );
                return Empty;
            }
            catch (Exception ex)
            {
                _businessLogger.LogError(
                    eventType: "add_to_cart",
                    userId: request.UserId,
                    errorDetails: ex.Message
                );
                throw;
            }
        }

        public override async Task<Cart> GetCart(GetCartRequest request, ServerCallContext context)
        {
            try 
            {
                var cart = await _cartStore.GetCartAsync(request.UserId);
                // Only log if cart has items, as empty cart views aren't as business relevant
                if (cart.Items.Count > 0)
                {
                    _businessLogger.LogViewCart(
                        userId: request.UserId,
                        cartId: request.UserId, // Using userId as cartId since they're 1:1
                        totalItems: cart.Items.Count
                    );
                }
                return cart;
            }
            catch (Exception ex)
            {
                _businessLogger.LogError(
                    eventType: "view_cart",
                    userId: request.UserId,
                    errorDetails: ex.Message
                );
                throw;
            }
        }

        public async override Task<Empty> EmptyCart(EmptyCartRequest request, ServerCallContext context)
        {
            try 
            {
                var cartBeforeEmpty = await _cartStore.GetCartAsync(request.UserId);
                // Only log empty cart operation if the cart actually had items
                if (cartBeforeEmpty.Items.Count > 0)
                {
                    await _cartStore.EmptyCartAsync(request.UserId);
                    _businessLogger.LogEmptyCart(request.UserId);
                }
                return Empty;
            }
            catch (Exception ex)
            {
                _businessLogger.LogError(
                    eventType: "empty_cart",
                    userId: request.UserId,
                    errorDetails: ex.Message
                );
                throw;
            }
        }
    }
}