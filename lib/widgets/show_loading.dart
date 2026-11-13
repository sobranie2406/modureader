import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart'
    show SmartDialog;

void showLoading() {
  SmartDialog.show(
    builder: (context) => Center(
        child: FilledContainer(
            fill: true,
            child: EinkStaticIndicator(child: CircularProgressIndicator()))),
  );
}
