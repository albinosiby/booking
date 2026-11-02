import 'dart:async';

import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';

/// What the checkout UI reported. It is only a hint: the server decides
/// whether money was received.
enum CheckoutOutcome { completed, closed }

abstract interface class PaymentCheckout {
  Future<CheckoutOutcome> pay({
    required String orderId,
    required String paymentSessionId,
    required bool production,
  });
}

/// Opens Cashfree checkout with a session created by the BookingOS API.
class CashfreeCheckoutService implements PaymentCheckout {
  Completer<CheckoutOutcome>? _pending;

  @override
  Future<CheckoutOutcome> pay({
    required String orderId,
    required String paymentSessionId,
    required bool production,
  }) {
    _pending?.complete(CheckoutOutcome.closed);
    final pending = _pending = Completer<CheckoutOutcome>();
    void finish(CheckoutOutcome outcome) {
      if (!pending.isCompleted) pending.complete(outcome);
    }

    try {
      final gateway = CFPaymentGatewayService()
        ..setCallback(
          (_) => finish(CheckoutOutcome.completed),
          (CFErrorResponse _, String _) => finish(CheckoutOutcome.closed),
        );
      final session = CFSessionBuilder()
          .setEnvironment(
            production ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX,
          )
          .setOrderId(orderId)
          .setPaymentSessionId(paymentSessionId)
          .build();
      // On web this redirects to Cashfree; the order's return URL brings the
      // owner back to the wallet page with `?order_id=` to confirm.
      gateway.doPayment(
        CFWebCheckoutPaymentBuilder().setSession(session).build(),
      );
    } catch (_) {
      finish(CheckoutOutcome.closed);
    }
    return pending.future;
  }
}
