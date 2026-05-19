import 'package:flutter/material.dart';

class ModifierResult {
  final String? temp; // Ice | Hot
  final String? sugar; // Less | Normal | More
  final String? ice; // Less | Normal | More
  final String notes;

  const ModifierResult(
      {required this.temp,
      required this.sugar,
      required this.ice,
      required this.notes});

  String toSuffix() {
    final parts = <String>[];
    if (temp?.isNotEmpty ?? false) parts.add(temp!);
    if (sugar?.isNotEmpty ?? false) parts.add('$sugar Sugar');
    if (ice?.isNotEmpty ?? false) parts.add('$ice Ice');
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }

  String toNoteLine() => notes.trim().isEmpty ? '' : '\nNotes: ${notes.trim()}';
}

Future<ModifierResult?> showModifiersDialog(BuildContext context) async {
  String? temp; // wajib
  String? sugar; // wajib
  String? ice; // wajib
  final notesCtrl = TextEditingController();

  return showModalBottomSheet<ModifierResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final bottom = media.viewInsets.bottom; // keyboard
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: LayoutBuilder(
          builder: (ctx, cons) {
            return StatefulBuilder(
              builder: (ctx, setState) {
                // bool valid() => temp != null && sugar != null && ice != null;
                bool valid() => true;

                Widget groupLabel(IconData icon, String text) => Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 8),
                        Text(text,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    );

                Widget chip(String label, bool selected, VoidCallback onTap) {
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => onTap(),
                    elevation: selected ? 2 : 0,
                    pressElevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                }

                Widget section({
                  required IconData icon,
                  required String title,
                  required List<Widget> chips,
                  String? helper,
                }) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      groupLabel(icon, title),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: chips),
                      if (helper != null) ...[
                        const SizedBox(height: 6),
                        Text(helper,
                            style:
                                TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ],
                  );
                }

                // String summary() {
                //   final t = temp ?? '—';
                //   final s = sugar ?? '—';
                //   final i = ice ?? '—';
                //   final n = (notesCtrl.text.trim().isEmpty) ? '' : ' · Notes';
                //   return '$t • $s Sugar • $i Ice$n';
                // }

                String summary() {
                  final parts = <String>[];
                  if (temp != null) parts.add(temp!);
                  if (sugar != null) parts.add('$sugar Sugar');
                  if (ice != null) parts.add('$ice Ice');
                  if (notesCtrl.text.trim().isNotEmpty) parts.add('Notes');
                  return parts.isEmpty ? 'No modifiers' : parts.join(' • ');
                }

                void resetAll() {
                  temp = null;
                  sugar = null;
                  ice = null;
                  notesCtrl.clear();
                  setState(() {});
                }

                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Row(
                          children: [
                            const Text('Customize',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: resetAll,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reset'),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                            )
                          ],
                        ),
                      ),

                      // Body
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Temperature
                              section(
                                icon: Icons.local_cafe_outlined,
                                title: 'Temperature',
                                chips: [
                                  chip('Ice', temp == 'Ice',
                                      () => setState(() => temp = 'Ice')),
                                  chip('Hot', temp == 'Hot',
                                      () => setState(() => temp = 'Hot')),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Sugar
                              section(
                                icon: Icons.cookie_outlined,
                                title: 'Sugar',
                                chips: [
                                  chip('No Sugar', sugar == 'No Sugar',
                                      () => setState(() => sugar = 'No')),
                                  chip('Less', sugar == 'Less',
                                      () => setState(() => sugar = 'Less')),
                                  chip('Normal', sugar == 'Normal',
                                      () => setState(() => sugar = 'Normal')),
                                  chip('More', sugar == 'More',
                                      () => setState(() => sugar = 'More')),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Ice level
                              section(
                                icon: Icons.ac_unit_outlined,
                                title: 'Ice Level',
                                chips: [
                                  chip('No Ice', ice == 'No Ice',
                                      () => setState(() => ice = 'No')),
                                  chip('Less', ice == 'Less',
                                      () => setState(() => ice = 'Less')),
                                  chip('Normal', ice == 'Normal',
                                      () => setState(() => ice = 'Normal')),
                                  chip('More', ice == 'More',
                                      () => setState(() => ice = 'More')),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Notes
                              groupLabel(
                                  Icons.note_alt_outlined, 'Notes (optional)'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: notesCtrl,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'e.g. No ice, less sweet, etc.',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Preview pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: .6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.tune, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        summary(),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Footer (sticky)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surface,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          boxShadow: const [
                            BoxShadow(
                                blurRadius: 12,
                                color: Color(0x1A000000),
                                offset: Offset(0, -2))
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child:
                                  // FilledButton(
                                  //   onPressed: valid()
                                  //       ? () {
                                  //           Navigator.pop(
                                  //             ctx,
                                  //             ModifierResult(
                                  //               temp: temp,
                                  //               sugar: sugar,
                                  //               ice: ice,
                                  //               notes: notesCtrl.text,
                                  //             ),
                                  //           );
                                  //         }
                                  //       : null,
                                  //   child: const Text('Add to Cart'),
                                  // ),
                                  FilledButton(
                                onPressed: () {
                                  Navigator.pop(
                                    ctx,
                                    ModifierResult(
                                      temp: temp, // boleh null
                                      sugar: sugar, // boleh null
                                      ice: ice, // boleh null
                                      notes: notesCtrl.text,
                                    ),
                                  );
                                },
                                child: const Text('Add to Cart'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
    },
  );
}
