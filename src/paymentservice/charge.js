// Copyright 2018 Google LLC
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

const cardValidator = require('simple-card-validator');
const { v4: uuidv4 } = require('uuid');
const pino = require('pino');
const businessLogger = require('./businessLogger');

const logger = pino({
  name: 'paymentservice-charge',
  messageKey: 'message',
  formatters: {
    level (logLevelString, logLevelNum) {
      return { severity: logLevelString }
    }
  }
});


class CreditCardError extends Error {
  constructor (message) {
    super(message);
    this.code = 400; // Invalid argument error
  }
}

class InvalidCreditCard extends CreditCardError {
  constructor (cardType) {
    super(`Credit card info is invalid`);
  }
}

class UnacceptedCreditCard extends CreditCardError {
  constructor (cardType) {
    super(`Sorry, we cannot process ${cardType} credit cards. Only VISA or MasterCard is accepted.`);
  }
}

class ExpiredCreditCard extends CreditCardError {
  constructor (number, month, year) {
    super(`Your credit card (ending ${number.substr(-4)}) expired on ${month}/${year}`);
  }
}

/**
 * Verifies the credit card number and (pretend) charges the card.
 *
 * @param {*} request
 * @return transaction_id - a random uuid.
 */
module.exports = function charge (request) {
  const { amount, credit_card: creditCard } = request;
  const cardNumber = creditCard.credit_card_number;
  const cardInfo = cardValidator(cardNumber);
  const {
    card_type: cardType,
    valid
  } = cardInfo.getCardDetails();
  const cardLastFour = cardNumber.slice(-4);
  try {
    if (!valid) {
      businessLogger.logTransaction(false, amount, cardType, cardLastFour, null, 'invalid_card');
      throw new InvalidCreditCard();
    }

    if (!(cardType === 'visa' || cardType === 'mastercard')) {
      businessLogger.logTransaction(false, amount, cardType, cardLastFour, null, 'unsupported_card_type');
      throw new UnacceptedCreditCard(cardType);
    }

    const currentMonth = new Date().getMonth() + 1;
    const currentYear = new Date().getFullYear();
    const { credit_card_expiration_year: year, credit_card_expiration_month: month } = creditCard;
    
    if ((currentYear * 12 + currentMonth) > (year * 12 + month)) {
      businessLogger.logTransaction(false, amount, cardType, cardLastFour, null, 'expired_card');
      throw new ExpiredCreditCard(cardNumber.replace('-', ''), month, year);
    }

    const transactionId = uuidv4();

    // Log successful transaction
    businessLogger.logTransaction(true, amount, cardType, cardLastFour, transactionId);

    // Remove the detailed logging since we have it in business metrics
    logger.info(`Transaction processed successfully`);

    return { transaction_id: transactionId };
  } catch (error) {
    if (error instanceof CreditCardError) {
      throw error;
    }
    // Unexpected errors
    businessLogger.logTransaction(false, amount, cardType, cardLastFour, null, 'system_error');
    throw error;
  }
};
