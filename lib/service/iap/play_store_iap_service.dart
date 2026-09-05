import 'dart:convert';

import 'package:anx_reader/service/iap/base_iap_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';
import 'package:anx_reader/config/app_identity.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

class PlayStoreIAPService extends BaseIAPService {
  PlayStoreIAPService({
    required super.trialDays,
  })  : _inAppPurchase = InAppPurchase.instance,
        _trialStartDate = DateTime.fromMillisecondsSinceEpoch(0);

  static const MethodChannel _installInfoChannel =
      MethodChannel('${AppIdentity.bundleId}/install_info');
  final InAppPurchase _inAppPurchase;
  DateTime _trialStartDate;
  final String _productId = 'anx_reader_lifetime';

  @override
  String get storeName => 'Play Store';

  @override
  String get productId => _productId;

  @override
  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      _inAppPurchase.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProductDetails() async {
    final Set<String> productIds = {productId};
    return _inAppPurchase.queryProductDetails(productIds);
  }

  @override
  Future<void> buy(ProductDetails productDetails) async {
    final purchaseParam = PurchaseParam(productDetails: productDetails);
    await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {
    await _inAppPurchase.completePurchase(purchaseDetails);
  }

  @override
  Future<void> restorePurchases() {
    return _inAppPurchase.restorePurchases();
  }

  @override
  Future<bool> isAvailable() {
    return _inAppPurchase.isAvailable();
  }

  @override
  Future<void> initialize() async {
    AnxLog.info('IAP: Initializing Play Store IAP Service');
    await _resolveTrialStartDate();
  }

  @override
  Future<IapPlatformSnapshot> loadSnapshot() async {
    await _resolveTrialStartDate();

    try {
      final response = await _queryPastPurchases();
      final activePurchase = _selectActivePurchase(response.pastPurchases);
      final purchaseDate =
          activePurchase != null ? _extractPurchaseDate(activePurchase) : null;

      return IapPlatformSnapshot(
        hasPurchase: activePurchase != null,
        isPurchaseStatusReliable: response.error == null,
        trialStartDate: _trialStartDate,
        purchaseDate: purchaseDate,
        isOriginalUser: false,
      );
    } catch (e, stack) {
      AnxLog.warning('IAP: Play Store snapshot error: $e', stack);
      return IapPlatformSnapshot(
        hasPurchase: null,
        isPurchaseStatusReliable: false,
        trialStartDate: _trialStartDate,
        purchaseDate: null,
        isOriginalUser: false,
      );
    }
  }

  Future<void> _resolveTrialStartDate() async {
    final installDate = await _getInstallDate();
    AnxLog.info('IAP: Install date: $installDate');
    if (installDate != null) {
      _trialStartDate = installDate;
      return;
    }

    if (_trialStartDate.year == 1970) {
      _trialStartDate = DateTime.now();
    }
  }

  Future<DateTime?> _getInstallDate() async {
    try {
      final installInfo =
          await _installInfoChannel.invokeMapMethod<String, dynamic>(
        'getInstallInfo',
      );
      final firstInstall = installInfo?['firstInstallTime'] as int?;
      final lastUpdate = installInfo?['lastUpdateTime'] as int?;
      final timestampMs = firstInstall ?? lastUpdate;
      if (timestampMs == null || timestampMs <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(timestampMs);
    } catch (e) {
      AnxLog.warning('IAP: Unable to read install info: $e');
      return null;
    }
  }
}

extension on PlayStoreIAPService {
  Future<QueryPurchaseDetailsResponse> _queryPastPurchases() async {
    final addition = _inAppPurchase
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    if (response.error != null) {
      AnxLog.warning(
          'IAP: Play Store queryPastPurchases error: ${response.error}');
    }
    return response;
  }

  PurchaseDetails? _selectActivePurchase(List<PurchaseDetails> purchases) {
    AnxLog.info('IAP: Evaluating ${purchases.length} past purchases');

    for (final purchase in purchases) {
      if (purchase.productID == _productId &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        AnxLog.info('IAP: Found active purchase: '
            'pendingCompletePurchase: ${purchase.pendingCompletePurchase},'
            'productID: ${purchase.productID},'
            'status: ${purchase.status.name},'
            'purchaseID: ${purchase.purchaseID},'
            'transactionDate: ${purchase.transactionDate},'
            'error: ${purchase.error?.message},'
            'verificationData: ${purchase.verificationData.localVerificationData}');

        return purchase;
      }
    }
    return null;
  }

  DateTime? _extractPurchaseDate(PurchaseDetails purchase) {
    if (purchase is GooglePlayPurchaseDetails) {
      final millis = purchase.billingClientPurchase.purchaseTime;
      if (millis > 0) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }

    try {
      final data = jsonDecode(purchase.verificationData.serverVerificationData)
          as Map<String, dynamic>;
      final millis = data['purchaseTime'] as int?;
      if (millis != null && millis > 0) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    } catch (_) {
      // Ignore parse errors, fall back to null.
    }
    return null;
  }
}
