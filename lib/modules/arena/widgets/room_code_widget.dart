import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';

class RoomCodeWidget extends StatelessWidget {
  final String code;

  const RoomCodeWidget({
    super.key,
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copyToClipboard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) {
          final char = index < code.length ? code[index] : '';
          return Container(
            width: 44,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.arenaAccent.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.arenaAccent.withValues(alpha: 0.05),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                char,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 0,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: code));
    Get.snackbar(
      'Copied!',
      'Code copied!',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.cardSurface,
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(16),
    );
  }
}
