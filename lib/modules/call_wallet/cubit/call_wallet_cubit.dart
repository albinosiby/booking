import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/cashfree_checkout_service.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/call_wallet_models.dart';
import '../repositories/call_wallet_repository.dart';

enum RechargePhase { idle, creating, checkout, confirming }

class RechargeNotice extends Equatable {
  const RechargeNotice(this.status, this.message);
  final RechargeStatus status;
  final String message;
  bool get success => status == RechargeStatus.paid;
  @override
  List<Object?> get props => [status, message];
}

class CallWalletState extends Equatable {
  const CallWalletState({
    this.wallet = const CallWallet(),
    this.loading = true,
    this.loadingMore = false,
    this.phase = RechargePhase.idle,
    this.error,
    this.notice,
  });
  final CallWallet wallet;
  final bool loading, loadingMore;
  final RechargePhase phase;
  final String? error;
  final RechargeNotice? notice;
  bool get recharging => phase != RechargePhase.idle;
  CallWalletState copyWith({
    CallWallet? wallet,
    bool? loading,
    bool? loadingMore,
    RechargePhase? phase,
    String? Function()? error,
    RechargeNotice? Function()? notice,
  }) => CallWalletState(
    wallet: wallet ?? this.wallet,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    phase: phase ?? this.phase,
    error: error != null ? error() : this.error,
    notice: notice != null ? notice() : this.notice,
  );
  @override
  List<Object?> get props => [
    wallet,
    loading,
    loadingMore,
    phase,
    error,
    notice,
  ];
}

String walletError(Object error) => error is AppException
    ? error.message
    : 'Could not complete this action. Please try again.';

/// Owner-only wallet. Every balance shown comes from the API, which confirms
/// recharges with Cashfree; the checkout callback only decides how long to wait.
class CallWalletCubit extends Cubit<CallWalletState> {
  CallWalletCubit(
    this.session,
    this.repository,
    this.checkout, {
    this.retryDelay = const Duration(seconds: 3),
    this.retries = 5,
  }) : super(const CallWalletState()) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        emit(
          const CallWalletState(
            loading: false,
            error: 'Only the owner can manage the call wallet.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final CallWalletRepository repository;
  final PaymentCheckout checkout;
  final Duration retryDelay;
  final int retries;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;

  bool get owner =>
      session.state.data.organization != null &&
      scope == workspaceAccessScope(session.state.data) &&
      session.state.data.isOwner;
  bool _valid(int g) => !isClosed && owner && g == generation;

  Future<void> load() async {
    if (!owner || state.recharging) return;
    final g = ++generation;
    emit(state.copyWith(error: () => null));
    try {
      final wallet = await repository.wallet();
      if (_valid(g)) emit(state.copyWith(wallet: wallet, loading: false));
    } catch (e) {
      if (_valid(g)) {
        emit(state.copyWith(loading: false, error: () => walletError(e)));
      }
    }
  }

  Future<void> loadMore() async {
    final offset = state.wallet.nextOffset;
    if (offset == null || state.loadingMore || !owner) return;
    final g = generation;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await repository.transactions(offset: offset);
      if (_valid(g)) {
        emit(
          state.copyWith(
            loadingMore: false,
            wallet: state.wallet.copyWith(
              entries: [...state.wallet.entries, ...page.entries],
              nextOffset: () => page.nextOffset,
            ),
          ),
        );
      }
    } catch (e) {
      if (_valid(g)) {
        emit(state.copyWith(loadingMore: false, error: () => walletError(e)));
      }
    }
  }

  void dismissNotice() => emit(state.copyWith(notice: () => null));

  Future<void> recharge(int amountPaise) async {
    if (state.recharging || !owner) return;
    final g = ++generation;
    emit(
      state.copyWith(
        phase: RechargePhase.creating,
        error: () => null,
        notice: () => null,
      ),
    );
    try {
      final order = await repository.createOrder(amountPaise);
      if (!_valid(g)) return;
      emit(state.copyWith(phase: RechargePhase.checkout));
      final outcome = await checkout.pay(
        orderId: order.orderId,
        paymentSessionId: order.paymentSessionId,
        production: order.production,
      );
      if (!_valid(g)) return;
      await _confirm(g, order.orderId, outcome);
    } catch (e) {
      if (_valid(g)) {
        emit(
          state.copyWith(
            phase: RechargePhase.idle,
            error: () => walletError(e),
          ),
        );
      }
    }
  }

  /// Web checkout redirects back with `?order_id=`; confirm it with the server.
  Future<void> confirmReturn(String orderId) async {
    if (state.recharging || !owner) return;
    final g = ++generation;
    emit(state.copyWith(error: () => null, notice: () => null));
    try {
      await _confirm(g, orderId, CheckoutOutcome.completed);
    } catch (e) {
      if (_valid(g)) {
        emit(
          state.copyWith(
            loading: false,
            phase: RechargePhase.idle,
            error: () => walletError(e),
          ),
        );
      }
    }
  }

  Future<void> _confirm(int g, String orderId, CheckoutOutcome outcome) async {
    emit(state.copyWith(phase: RechargePhase.confirming));
    var result = await repository.verify(orderId);
    // Cashfree can confirm a few seconds after checkout reports success.
    for (
      var i = 0;
      i < retries &&
          outcome == CheckoutOutcome.completed &&
          result.status == RechargeStatus.pending;
      i++
    ) {
      await Future<void>.delayed(retryDelay);
      if (!_valid(g)) return;
      result = await repository.verify(orderId);
    }
    if (!_valid(g)) return;
    emit(
      state.copyWith(
        wallet: result.wallet,
        loading: false,
        phase: RechargePhase.idle,
        notice: () => RechargeNotice(
          result.status,
          _message(result.status, outcome, result.amountPaise),
        ),
      ),
    );
  }

  static String _message(
    RechargeStatus status,
    CheckoutOutcome outcome,
    int amountPaise,
  ) => switch (status) {
    RechargeStatus.paid =>
      '${rupees(amountPaise)} was added to your call wallet.',
    RechargeStatus.pending when outcome == CheckoutOutcome.completed =>
      'Your payment is processing. ${rupees(amountPaise)} will be added as soon as the bank confirms it.',
    RechargeStatus.pending =>
      'The payment was not completed. If money was debited, it will be added to your wallet automatically.',
    RechargeStatus.failed =>
      'The payment failed and no money was added. Please try again.',
    RechargeStatus.cancelled => 'The payment was cancelled.',
    RechargeStatus.expired =>
      'This payment session expired. Please start a new recharge.',
  };

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
