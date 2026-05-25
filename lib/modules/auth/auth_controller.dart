import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';

class AuthController extends GetxController {
  // State
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool isLoggedIn = false.obs;
  final RxString displayName = ''.obs;

  // Form state
  final RxBool isLoginMode = true.obs; // true = login, false = register
  final RxBool isConfirmMode = false.obs; // true = confirming email code
  final RxBool obscurePassword = true.obs;

  // Text controllers
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final codeController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final restored = await AuthService.tryRestoreSession();
    isLoggedIn.value = restored;
    if (restored) {
      displayName.value = AuthService.displayName;
    }
  }

  void toggleMode() {
    isLoginMode.value = !isLoginMode.value;
    errorMessage.value = '';
  }

  Future<void> login() async {
    if (emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
      errorMessage.value = 'Please fill in all fields';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await AuthService.login(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      isLoggedIn.value = true;
      displayName.value = AuthService.displayName;
      Get.back(); // Close bottom sheet
    } on CognitoUserNewPasswordRequiredException {
      errorMessage.value = 'New password required. Contact support.';
    } on CognitoUserMfaRequiredException {
      errorMessage.value = 'MFA required. Contact support.';
    } on CognitoUserCustomChallengeException {
      errorMessage.value = 'Custom challenge. Contact support.';
    } on CognitoUserConfirmationNecessaryException {
      errorMessage.value = 'Please confirm your email first.';
      isConfirmMode.value = true;
    } on CognitoClientException catch (e) {
      errorMessage.value = e.message ?? 'Login failed';
    } catch (e) {
      errorMessage.value = 'Login failed. Check your credentials.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> register() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty ||
        nameController.text.trim().isEmpty) {
      errorMessage.value = 'Please fill in all fields';
      return;
    }
    if (passwordController.text.length < 8) {
      errorMessage.value = 'Password must be at least 8 characters';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await AuthService.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        displayName: nameController.text.trim(),
      );
      isConfirmMode.value = true;
    } on CognitoClientException catch (e) {
      errorMessage.value = e.message ?? 'Registration failed';
    } catch (e) {
      errorMessage.value = 'Registration failed. Try again.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> confirmEmail() async {
    if (codeController.text.trim().isEmpty) {
      errorMessage.value = 'Please enter the verification code';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await AuthService.confirmRegistration(
        email: emailController.text.trim(),
        code: codeController.text.trim(),
      );
      // Auto-login after confirmation
      await AuthService.login(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      isLoggedIn.value = true;
      displayName.value = AuthService.displayName;
      isConfirmMode.value = false;
      Get.back(); // Close bottom sheet
    } catch (e) {
      errorMessage.value = 'Invalid code. Try again.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await AuthService.logout();
    isLoggedIn.value = false;
    displayName.value = '';
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    codeController.dispose();
    super.onClose();
  }
}
