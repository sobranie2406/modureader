import 'package:modu_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

bool desktopWheelZoomModifierPressed() {
  if (!AnxPlatform.isDesktop) return false;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isAltPressed || keyboard.isShiftPressed) return false;
  return AnxPlatform.isMacOS
      ? keyboard.isMetaPressed && !keyboard.isControlPressed
      : keyboard.isControlPressed && !keyboard.isMetaPressed;
}
