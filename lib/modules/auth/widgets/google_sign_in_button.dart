import 'package:flutter/material.dart';
import '../../../constants/asset_path.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, this.onPressed, this.busy = false});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1F1F),
        disabledBackgroundColor: const Color(0xFFF2F2F2),
        disabledForegroundColor: const Color(0xFF757575),
        side: const BorderSide(color: Color(0xFF747775)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        minimumSize: const Size.fromHeight(48),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Image.asset(
              AssetPath.googleLogo,
              width: 20,
              height: 20,
              excludeFromSemantics: true,
            ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              busy ? 'Opening Google…' : 'Continue with Google',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ),
  );
}
