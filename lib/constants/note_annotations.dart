import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class NoteTypeOption {
  final String type;
  final IconData icon;

  const NoteTypeOption({
    required this.type,
    required this.icon,
  });
}

const List<String> notesColors = [
  '66CCFF',
  'FF0000',
  '00FF00',
  'EB3BFF',
  'FFD700',
  // Saturated mid-tones stay distinct from common pale reading backgrounds.
  'FF8C00', // Orange
  'E85D91', // Rose
  '00897B', // Deep teal
  '6C63D9', // Indigo
  'A66C3D', // Brown
];

const List<NoteTypeOption> notesType = [
  NoteTypeOption(
    type: 'highlight',
    icon: AntDesign.highlight_outline,
  ),
  NoteTypeOption(
    type: 'underline',
    icon: Icons.format_underline,
  ),
];
