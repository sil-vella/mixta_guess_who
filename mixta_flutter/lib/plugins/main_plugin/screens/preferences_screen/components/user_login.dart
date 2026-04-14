import 'package:flutter/material.dart';
import 'package:mixta_guess_who/utils/consts/theme_consts.dart';

class LoginWidget extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onLogin;
  final VoidCallback onRegisterToggle;

  const LoginWidget({
    Key? key,
    required this.emailController,
    required this.passwordController,
    required this.onLogin,
    required this.onRegisterToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32), // 🏆 Nice Spacing
      decoration: BoxDecoration(
        color: AppColors.primaryColor, // 🎨 Themed Background
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 📏 Adjusts to content size
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          /// **Login Title**
          Text(
            "Login",
            style: AppTextStyles.headingLarge(color: AppColors.accentColor), // 🌟 Styled Title
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          /// **Email Field**
          TextFormField(
            controller: emailController,
            style: AppTextStyles.bodyMedium, // ✏️ Styled Input Text
            decoration: InputDecoration(
              labelText: "Email",
              prefixIcon: const Icon(Icons.email, color: AppColors.accentColor),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          /// **Password Field**
          TextFormField(
            controller: passwordController,
            style: AppTextStyles.bodyMedium, // ✏️ Styled Input Text
            decoration: InputDecoration(
              labelText: "Password",
              prefixIcon: const Icon(Icons.lock, color: AppColors.accentColor),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),

          /// **Login Button**
          ElevatedButton(
            onPressed: onLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentColor, // 🟡 Themed Button
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text("Login", style: AppTextStyles.buttonText),
          ),

          const SizedBox(height: 12),

          /// **Toggle to Register**
          TextButton(
            onPressed: onRegisterToggle,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentColor, // 🎨 Gold Accent
            ),
            child: const Text("Register new user", style: AppTextStyles.buttonText),
          ),
        ],
      ),
    );
  }
}
