import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Wraps the mobile screen in a photorealistic modern flagship mobile device shell
/// when viewed on desktop web or wide screens, while staying 100% native edge-to-edge
/// on actual mobile devices.
class DeviceFrameWrapper extends StatelessWidget {
  const DeviceFrameWrapper({
    super.key,
    required this.child,
    required this.screenWidth,
    required this.screenHeight,
    required this.isDesktop,
  });

  final Widget child;
  final double screenWidth;
  final double screenHeight;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return child;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF1B1C20),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _buildPhoneShell(context),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneShell(BuildContext context) {
    // Standard flagship aspect ratio (390 x 844)
    final frameW = screenWidth.clamp(380.0, 420.0);
    final frameH = math.max(screenHeight, 820.0);

    return Container(
      padding: const EdgeInsets.all(11.5), // Outer bezel thickness
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF484A52), // Top specular reflection
            Color(0xFF28292E), // Titanium midtone
            Color(0xFF1F2024),
            Color(0xFF383A42), // Bottom metallic edge
          ],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(54),
        border: Border.all(
          color: const Color(0xFF555861).withValues(alpha: 0.7),
          width: 1.8,
        ),
        boxShadow: [
          // Heavy ambient studio drop shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 45,
            spreadRadius: 4,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 75,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(44),
        child: Container(
          width: frameW,
          height: frameH,
          color: WBColors.bg,
          child: Stack(
            children: [
              // 1. Mobile Screen Content (offset for Dynamic Island notch)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                bottom: 12,
                child: child,
              ),

              // 2. Dynamic Island / Sensor Notch
              Positioned(
                top: 11,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 110,
                    height: 27,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Camera Sensor Lens Reflection
                        Container(
                          width: 10.5,
                          height: 10.5,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF111728),
                            border: Border.all(
                              color: const Color(0xFF1E2840),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Bottom Gesture Bar Indicator
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 134,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
