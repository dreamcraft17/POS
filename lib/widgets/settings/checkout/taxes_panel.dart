import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/tax_settings_provider.dart';
import '../../../services/tax_prefs.dart';

class TaxesPanel extends ConsumerStatefulWidget {
  const TaxesPanel({super.key});

  @override
  ConsumerState<TaxesPanel> createState() => _TaxesPanelState();
}

class _TaxesPanelState extends ConsumerState<TaxesPanel> {
  bool _enabled = kDefaultTaxEnabled;
  double _ratePercent = kDefaultTaxRatePct;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await loadTaxSettings();
    if (!mounted) return;
    setState(() {
      _enabled = s.enabled;
      _ratePercent = s.ratePercent;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await saveTaxSettings(enabled: _enabled, ratePercent: _ratePercent);
    ref.invalidate(taxSettingsProvider);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tax settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Taxes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          title: const Text('Enable tax'),
          subtitle:
              const Text('Turn on to apply tax to all orders at checkout'),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tax rate (%)',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _ratePercent.clamp(0, 100),
                        min: 0,
                        max: 30,
                        divisions: 300,
                        label: _ratePercent.toStringAsFixed(1),
                        onChanged: _enabled
                            ? (v) => setState(() => _ratePercent = v)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        enabled: _enabled,
                        initialValue: _ratePercent.toStringAsFixed(1),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (s) {
                          final v = double.tryParse(s.replaceAll(',', '.'));
                          if (v != null) {
                            setState(() => _ratePercent = v.clamp(0, 100));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _enabled
                      ? 'Applied tax: ${_ratePercent.toStringAsFixed(2)}%'
                      : 'Tax is disabled',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Row(
          children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
