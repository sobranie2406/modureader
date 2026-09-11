import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/provider_brand.dart';
import 'package:flutter/material.dart';

/// One presentation for settings, model switching and chat history.
class AiProviderLogo extends StatelessWidget {
  const AiProviderLogo({super.key, required this.provider, this.size = 32});

  final AiProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = resolveProviderBrand(provider);
    final fallback = Icon(Icons.smart_toy_outlined, size: size * .72);
    return Semantics(
      label: provider.title,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: brand == null
            ? fallback
            : DecoratedBox(
                // Preserve original colours, including on a dark reader theme.
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(size * .18),
                ),
                child: Padding(
                  padding: EdgeInsets.all(size * .06),
                  child: Image.asset(
                    brand.asset,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => fallback,
                  ),
                ),
              ),
      ),
    );
  }
}
