import 'package:flutter/material.dart';

class ForceStopButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const ForceStopButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            Colors.redAccent.withValues(alpha: 0.15),
            Colors.orangeAccent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[300],
          side: BorderSide(
            color: Colors.redAccent.withValues(alpha: 0.4),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          shadowColor: Colors.redAccent.withValues(alpha: 0.3),
        ),
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                ),
              )
            : const Icon(
                Icons.gavel_rounded,
                size: 20,
                color: Colors.redAccent,
              ),
        label: Text(
          isLoading ? 'TERMINATING...' : 'FORCE STOP ANYWAY',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontFamily: 'Roboto',
          ),
        ),
      ),
    );
  }
}
