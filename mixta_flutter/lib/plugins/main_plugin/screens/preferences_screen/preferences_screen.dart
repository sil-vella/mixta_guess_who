import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../modules/login_module/login_module.dart';
import 'components/user_register.dart';

class PreferencesScreen extends BaseScreen {
  const PreferencesScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return "Profile";
  }

  @override
  PreferencesScreenState createState() => PreferencesScreenState();
}

class PreferencesScreenState extends BaseScreenState<PreferencesScreen> {
  final Logger logger = Logger();

  late ServicesManager _servicesManager;
  late ModuleManager _moduleManager;
  SharedPrefManager? _sharedPref;
  LoginModule? _loginModule;

  String? _username;
  bool _deletingData = false;

  @override
  void initState() {
    super.initState();
    logger.info("🔧 Initializing PreferencesScreen...");

    // ✅ Retrieve managers and modules using Provider
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _moduleManager = Provider.of<ModuleManager>(context, listen: false);

    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    _loginModule = _moduleManager.getLatestModule<LoginModule>();

    if (_sharedPref == null) {
      logger.error('❌ SharedPreferences service not available.');
      return;
    }

    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    if (_sharedPref == null) return;

    final username = _sharedPref!.getString('username');

    setState(() {
      _username = (username != null && username.isNotEmpty) ? username : null;
    });

    logger.info("📌 Username from SharedPreferences: ${_username ?? 'None'}");
  }

  Future<void> _confirmAndDeleteMyData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.primaryColor,
        title: Text(
          'Delete all data?',
          style: AppTextStyles.headingSmall(color: AppColors.redAccent),
        ),
        content: SingleChildScrollView(
          child: Text(
            _username != null && _username!.isNotEmpty
                ? 'This permanently deletes your account and all progress on the server, then clears this device (game progress, login, cached images). This cannot be undone.'
                : 'No account is registered. This clears all locally stored game data on this device only.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.lightGray)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    logger.info(
      '🗑️ [prefs] delete confirmed | loginModule=${_loginModule != null} | sharedPref=${_sharedPref != null} | username=$_username',
    );

    setState(() => _deletingData = true);

    try {
      if (_loginModule != null) {
        final result = await _loginModule!.deleteMyData(
          moduleManager: _moduleManager,
          servicesManager: _servicesManager,
        );
        logger.info('🗑️ [prefs] deleteMyData result=$result');
        if (!mounted) return;

        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'].toString()),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await _checkLoginStatus();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your data has been removed.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (_sharedPref != null) {
        await _sharedPref!.clear();
        await _checkLoginStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Local data cleared.'), backgroundColor: Colors.green),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _deletingData = false);
      }
    }
  }

  /// ✅ Handle user registration
  Future<void> _registerUser(String username) async {
    if (_loginModule == null) return;

    final result = await _loginModule!.registerUser(
      context: context,
      username: username,
    );

    if (result.containsKey("success")) {
      await _checkLoginStatus();
      if (!mounted) return;
      setState(() {}); // Trigger UI update
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result["error"] ?? "Registration failed."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ✅ Show the Profile OR Register Form based on username existence
  @override
  Widget buildContent(BuildContext context) {
    return _buildProfileTab(context);
  }

  Widget _buildProfileTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _username != null && _username!.isNotEmpty
                ? _buildUserSection()
                : RegisterWidget(
                    onRegister: (username) async => await _registerUser(username),
                  ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  context.go("/progress");
                },
                child: const Text("View Your Progress"),
              ),
            ),
            const SizedBox(height: 24),
            _buildDeleteDataSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteDataSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delete my data',
          style: AppTextStyles.headingMedium(color: AppColors.accentColor),
        ),
        const SizedBox(height: 12),
        Text(
          _username != null && _username!.isNotEmpty
              ? 'Remove your account from the server (progress, guessed names, points) and erase all data stored on this device.'
              : 'You have not registered a username. You can still clear all game data stored on this device.',
          style: AppTextStyles.bodyLarge,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _deletingData ? null : _confirmAndDeleteMyData,
            icon: _deletingData
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_outlined, color: AppColors.redAccent),
            label: Text(
              _deletingData ? 'Working…' : 'Delete my data',
              style: AppTextStyles.buttonText.copyWith(color: AppColors.redAccent),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.redAccent),
              padding: AppPadding.cardPadding,
            ),
          ),
        ),
      ],
    );
  }

  /// ✅ User Profile Section
  Widget _buildUserSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: AppColors.primaryColor,
      elevation: 4,
      margin: AppPadding.defaultPadding,
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Account Details",
              style: AppTextStyles.headingMedium(color: AppColors.accentColor),
            ),
            const Divider(
              color: AppColors.lightGray,
              thickness: 1,
            ),
            const SizedBox(height: 10),
            Text(
              "👤 Username: $_username",
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
