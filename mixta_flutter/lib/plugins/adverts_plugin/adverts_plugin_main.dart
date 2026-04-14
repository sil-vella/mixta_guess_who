import 'package:mixta_guess_who/plugins/adverts_plugin/modules/admobs/banner/banner_ad.dart';
import 'package:mixta_guess_who/plugins/adverts_plugin/modules/admobs/interstitial/interstitial_ad.dart';
import 'package:mixta_guess_who/plugins/adverts_plugin/modules/admobs/rewarded/rewarded_ad.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/00_base/plugin_base.dart';
import '../../core/managers/hooks_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';

class AdvertsPlugin extends PluginBase {
  late final ServicesManager servicesManager;
  late final StateManager stateManager;
  final interstitialAdUnitId = Config.admobsInterstitial01;
  final rewardedAdUnitId = Config.admobsRewarded01;

  AdvertsPlugin();

  @override
  void initialize(BuildContext context) {
    super.initialize(context); // ✅ Fetch dependencies

    servicesManager = Provider.of<ServicesManager>(context, listen: false);
    stateManager = Provider.of<StateManager>(context, listen: false);
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);

    _preLoadAds(context);

    // ✅ Register all modules in ModuleManager
    final modules = createModules();
    for (var entry in modules.entries) {
      final instanceKey = entry.key;
      final module = entry.value;
      moduleManager.registerModule(module, instanceKey: instanceKey);
    }
  }

  /// ✅ Define initial states for this plugin
  @override
  Map<String, Map<String, dynamic>> getInitialStates() {
    return {}; // Return initial states if needed
  }

  /// ✅ Register Ad-related modules with specific instance keys
  @override
  Map<String?, ModuleBase> createModules() {
    return {
      null: BannerAdModule(), // ✅ Hardcoded key
      null: InterstitialAdModule(interstitialAdUnitId), // ✅ Pass `adUnitId`
      null: RewardedAdModule(rewardedAdUnitId), // ✅ Pass `adUnitId`
    };
  }

  /// ✅ Preload all ads to ensure fast loading
  Future<void> _preLoadAds(BuildContext context) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false); // ✅ Fetch ModuleManager dynamically

    final bannerAdModule = moduleManager.getModuleInstance<BannerAdModule>('admobs_banner_ad_module');
    final interstitialAdModule = moduleManager.getLatestModule<InterstitialAdModule>(); // ✅ Works for auto keys
    final rewardedAdModule = moduleManager.getLatestModule<RewardedAdModule>(); // ✅ Works for auto keys

    if (bannerAdModule != null) {
      await bannerAdModule.loadBannerAd(Config.admobsTopBanner);
      await bannerAdModule.loadBannerAd(Config.admobsBottomBanner);
      log.info('✅ Banner Ads preloaded.');
    } else {
      log.error('❌ Failed to preload Banner Ads: Module not found.');
    }

    if (interstitialAdModule != null) {
      await interstitialAdModule.loadAd();
      log.info('✅ Interstitial Ad preloaded.');
    } else {
      log.error('❌ Failed to preload Interstitial Ad: Module not found.');
    }

    if (rewardedAdModule != null) {
      await rewardedAdModule.loadAd();
      log.info('✅ Rewarded Ad preloaded.');
    } else {
      log.error('❌ Failed to preload Rewarded Ad: Module not found.');
    }
  }



}
