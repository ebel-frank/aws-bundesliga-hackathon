import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import 'auth_controller.dart';

/// Shows the auth bottom sheet. Call this when user needs to login.
void showAuthBottomSheet(BuildContext context) {
  // Ensure AuthController is registered
  if (!Get.isRegistered<AuthController>()) {
    Get.put(AuthController(), permanent: true);
  }
  final controller = Get.find<AuthController>();

  // Reset form state when opening
  controller.errorMessage.value = '';
  controller.isConfirmMode.value = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _AuthSheetContent(controller: controller),
    ),
  );
}

class _AuthSheetContent extends StatelessWidget {
  final AuthController controller;
  const _AuthSheetContent({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        image: const DecorationImage(
          image: AssetImage('assets/images/bundesliga_bg.jpg'),
          fit: BoxFit.cover,
          opacity: 0.15,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Obx(() {
          if (controller.isConfirmMode.value) {
            return _buildConfirmForm();
          }
          return controller.isLoginMode.value
              ? _buildLoginForm()
              : _buildRegisterForm();
        }),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome back',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Login to continue',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        // Email
        _buildTextField(
          controller.emailController,
          'Email',
          Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        // Password
        Obx(() => _buildTextField(
              controller.passwordController,
              'Password',
              Icons.lock_outline,
              obscure: controller.obscurePassword.value,
              suffixIcon: IconButton(
                icon: Icon(
                  controller.obscurePassword.value
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => controller.obscurePassword.value =
                    !controller.obscurePassword.value,
              ),
            )),
        const SizedBox(height: 20),
        // Error
        Obx(() => controller.errorMessage.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  controller.errorMessage.value,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              )
            : const SizedBox.shrink()),
        // Login button
        Obx(() => GestureDetector(
              onTap: controller.isLoading.value ? null : () => controller.login(),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.arenaAccent,
                ),
                child: Center(
                  child: controller.isLoading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            )),
        const SizedBox(height: 16),
        // Toggle to register
        Center(
          child: GestureDetector(
            onTap: () => controller.toggleMode(),
            child: RichText(
              text: const TextSpan(
                text: "Don't have an account? ",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                children: [
                  TextSpan(
                    text: 'Register',
                    style: TextStyle(
                      color: AppColors.arenaAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Create Account',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Join the prediction arena',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller.nameController,
          'Display Name (max 6 chars)',
          Icons.person_outline,
          maxLength: 6,
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller.emailController,
          'Email',
          Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        Obx(() => _buildTextField(
              controller.passwordController,
              'Password (min 8 chars)',
              Icons.lock_outline,
              obscure: controller.obscurePassword.value,
              suffixIcon: IconButton(
                icon: Icon(
                  controller.obscurePassword.value
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () => controller.obscurePassword.value =
                    !controller.obscurePassword.value,
              ),
            )),
        const SizedBox(height: 20),
        Obx(() => controller.errorMessage.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  controller.errorMessage.value,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              )
            : const SizedBox.shrink()),
        Obx(() => GestureDetector(
              onTap: controller.isLoading.value
                  ? null
                  : () => controller.register(),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.arenaAccent,
                ),
                child: Center(
                  child: controller.isLoading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            )),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () => controller.toggleMode(),
            child: RichText(
              text: const TextSpan(
                text: 'Already have an account? ',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                children: [
                  TextSpan(
                    text: 'Login',
                    style: TextStyle(
                      color: AppColors.arenaAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildConfirmForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Verify Email',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Enter the 6-digit code sent to your email',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller.codeController,
          'Verification Code',
          Icons.verified_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        Obx(() => controller.errorMessage.value.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  controller.errorMessage.value,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              )
            : const SizedBox.shrink()),
        Obx(() => GestureDetector(
              onTap: controller.isLoading.value
                  ? null
                  : () => controller.confirmEmail(),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.arenaAccent,
                ),
                child: Center(
                  child: controller.isLoading.value
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'VERIFY',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            )),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textMuted.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
        suffixIcon: suffixIcon,
        counterText: '',
        filled: true,
        fillColor: AppColors.background.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.arenaAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
