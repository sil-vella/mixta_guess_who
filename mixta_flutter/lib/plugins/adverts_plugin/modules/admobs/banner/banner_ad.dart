import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../../../core/00_base/module_base.dart';
import '../../../../../tools/logging/logger.dart';

class BannerAdModule extends ModuleBase {
  static final Logger _log = Logger();
  final Map<String, BannerAd> _banners = {}; // Store multiple ads

  /// ✅ Constructor
  BannerAdModule() : super("admobs_banner_ad_module") {
    _log.info('📢 BannerAdModule initialized and auto-registered.');
  }

  /// ✅ Loads the banner ad with a specified ad unit ID
  Future<void> loadBannerAd(String adUnitId) async {
    if (_banners.containsKey(adUnitId)) {
      _log.info('🔄 Banner Ad already exists for ID: $adUnitId');
      return; // ✅ Prevent reloading if already exists
    }

    _log.info('📢 Loading Banner Ad for ID: $adUnitId');

    final bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _log.info('✅ Banner Ad Loaded for ID: $adUnitId.'),
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.error('❌ Failed to load Banner Ad for ID: $adUnitId. Error: ${error.message}');
          ad.dispose();
          _banners.remove(adUnitId); // ✅ Remove failed instance
        },
      ),
    );

    await bannerAd.load();
    _banners[adUnitId] = bannerAd;
  }

  /// ✅ Retrieve a new unique banner ad widget each time
  Widget getBannerWidget(BuildContext context, String adUnitId) {
    _log.info('🔄 Creating new Banner Ad instance for Widget.');

    final newBannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _log.info('✅ Banner Ad Loaded for ID: $adUnitId.'),
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          _log.error('❌ Failed to load Banner Ad for ID: $adUnitId. Error: ${error.message}');
          ad.dispose();
        },
      ),
    );

    newBannerAd.load();

    return SizedBox(
      width: newBannerAd.size.width.toDouble(),
      height: newBannerAd.size.height.toDouble(),
      child: AdWidget(ad: newBannerAd),
    );
  }

  /// ✅ Dispose a specific banner ad
  void disposeBannerAd(String adUnitId) {
    if (_banners.containsKey(adUnitId)) {
      _banners[adUnitId]?.dispose();
      _banners.remove(adUnitId);
      _log.info('🗑 Banner Ad Disposed for ID: $adUnitId.');
    } else {
      _log.error('⚠️ Tried to dispose non-existing Banner Ad for ID: $adUnitId.');
    }
  }

  /// ✅ Override `dispose()` to clean up all banner ads
  @override
  void dispose() {
    _log.info('🗑 Disposing all Banner Ads...');
    for (final ad in _banners.values) {
      ad.dispose();
    }
    _banners.clear();
    super.dispose(); // ✅ Calls `ModuleBase.dispose()` for cleanup
  }
}
