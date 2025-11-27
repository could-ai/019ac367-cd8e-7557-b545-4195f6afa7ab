import 'package:flutter/material.dart';
import 'dart:math';
import 'swg_data.dart';

class MotorHelperScreen extends StatefulWidget {
  const MotorHelperScreen({super.key});

  @override
  State<MotorHelperScreen> createState() => _MotorHelperScreenState();
}

class _MotorHelperScreenState extends State<MotorHelperScreen> {
  // Constants
  final double rhoCopper = 1.68e-8;
  final double rhoAl = 2.82e-8;

  // State variables
  final TextEditingController _inputSwgController = TextEditingController(text: "12");
  final TextEditingController _copperTurnsController = TextEditingController(text: "50");
  final TextEditingController _slotAreaController = TextEditingController(text: "40.0");
  final TextEditingController _insulationController = TextEditingController(text: "0.05");
  final TextEditingController _fillFactorController = TextEditingController(text: "0.55");
  
  String _mode = "Same resistance";
  final List<String> _modes = ["Same resistance", "Same amp-turns", "Same ampacity"];
  
  final TextEditingController _jCuController = TextEditingController(text: "4.0");
  final TextEditingController _jAlController = TextEditingController(text: "2.5");

  bool _useStranded = false;
  final TextEditingController _nStrandsController = TextEditingController(text: "7");
  bool _strandUsesSwg = true;
  final TextEditingController _strandSwgController = TextEditingController(text: "20");
  final TextEditingController _strandDiaMmController = TextEditingController(text: "0.914");
  final TextEditingController _strandingPackingFactorController = TextEditingController(text: "0.9");

  String _resultText = "";

  @override
  void dispose() {
    _inputSwgController.dispose();
    _copperTurnsController.dispose();
    _slotAreaController.dispose();
    _insulationController.dispose();
    _fillFactorController.dispose();
    _jCuController.dispose();
    _jAlController.dispose();
    _nStrandsController.dispose();
    _strandSwgController.dispose();
    _strandDiaMmController.dispose();
    _strandingPackingFactorController.dispose();
    super.dispose();
  }

  void _computeResults() {
    final resistivityRatio = rhoAl / rhoCopper;
    final swgMap = {for (var e in swgTable) e.swg: e};

    final inputSwg = _inputSwgController.text.trim();
    final cuEntry = swgMap[inputSwg];

    if (cuEntry == null) {
      setState(() {
        _resultText = "Unknown copper SWG. Try values in SWG table (e.g. 8..20).";
      });
      return;
    }

    final copperTurnsInt = int.tryParse(_copperTurnsController.text) ?? 0;
    final slotAreaVal = (double.tryParse(_slotAreaController.text) ?? 40.0).clamp(0.1, double.infinity);
    final insulationThickness = (double.tryParse(_insulationController.text) ?? 0.05).clamp(0.0, double.infinity);
    final ff = (double.tryParse(_fillFactorController.text) ?? 0.55).clamp(0.05, 0.95);
    final jCuVal = (double.tryParse(_jCuController.text) ?? 4.0).clamp(0.1, double.infinity);
    final jAlVal = (double.tryParse(_jAlController.text) ?? 2.5).clamp(0.1, double.infinity);
    final nStr = (int.tryParse(_nStrandsController.text) ?? 1).clamp(1, 1000);

    double insulatedArea(double diamMm) {
      final dIns = diamMm + 2.0 * insulationThickness;
      final r = dIns / 2.0;
      return pi * r * r;
    }

    final cuArea = cuEntry.areaMm2;
    // Resistance-based required Al area
    final requiredAlAreaResistance = cuArea * resistivityRatio;
    // Ampacity-based required Al area
    final requiredAlAreaAmpacity = cuArea * (jCuVal / jAlVal);

    // Candidate selection
    SwgEntry findFirstSwgAtLeast(double area) {
      try {
        return swgTable.firstWhere((it) => it.areaMm2 >= area);
      } catch (e) {
        return swgTable.last;
      }
    }

    final candidateRes = findFirstSwgAtLeast(requiredAlAreaResistance);
    final candidateAmp = findFirstSwgAtLeast(requiredAlAreaAmpacity);

    // Stranded computation
    double strandArea = 0.0;
    if (_useStranded) {
      if (_strandUsesSwg) {
        final sSwg = _strandSwgController.text.trim();
        strandArea = swgMap[sSwg]?.areaMm2 ?? 
            (pi * pow((double.tryParse(_strandDiaMmController.text) ?? 0.0) / 2.0, 2));
      } else {
        final d = double.tryParse(_strandDiaMmController.text) ?? 0.0;
        strandArea = pi * pow(d / 2.0, 2);
      }
    }
    
    final totalAlAreaIfStranded = _useStranded
        ? nStr * strandArea * (double.tryParse(_strandingPackingFactorController.text) ?? 0.9)
        : 0.0;

    String computeForEntry(SwgEntry entry, [double useStrandedArea = 0.0]) {
      final alArea = _useStranded ? max(useStrandedArea, 0.0001) : entry.areaMm2;
      final alDiamEquiv = sqrt(4.0 * alArea / pi);
      final cuIns = insulatedArea(cuEntry.diameterMm);
      final alIns = insulatedArea(alDiamEquiv);
      
      final maxTurnsCu = (slotAreaVal * ff / cuIns).floor();
      final maxTurnsAl = (slotAreaVal * ff / alIns).floor();
      
      final iCu = jCuVal * cuArea;
      final iAl = jAlVal * alArea;
      
      final ampTurnsTarget = copperTurnsInt * iCu;
      final reqTurnsAlForAmpTurns = iAl > 0.0 ? ampTurnsTarget / iAl : double.infinity;

      return "SWG ${entry.swg}: Al-area=${alArea.toStringAsFixed(4)} mm², eq-dia=${alDiamEquiv.toStringAsFixed(3)} mm, maxTurnsCu=$maxTurnsCu, maxTurnsAl=$maxTurnsAl, IcapCu=${iCu.toStringAsFixed(2)} A, IcapAl=${iAl.toStringAsFixed(2)} A, reqTurnsToMatchAmpTurns=${reqTurnsAlForAmpTurns.toStringAsFixed(2)}";
    }

    // Generate CSV Content (for display/copy)
    final csvSb = StringBuffer();
    csvSb.writeln("Mode,Value");
    csvSb.writeln("Input copper SWG,${cuEntry.swg}");
    csvSb.writeln("Copper area mm2,${cuArea.toStringAsFixed(4)}");
    csvSb.writeln("Slot area mm2,${slotAreaVal.toStringAsFixed(4)}");
    csvSb.writeln("Insulation mm,${insulationThickness.toStringAsFixed(4)}");
    csvSb.writeln("Fill factor,${ff.toStringAsFixed(3)}");
    csvSb.writeln("");
    csvSb.writeln("SameResistance_requiredAlArea_mm2,${requiredAlAreaResistance.toStringAsFixed(4)}");
    csvSb.writeln("SameAmpacity_requiredAlArea_mm2,${requiredAlAreaAmpacity.toStringAsFixed(4)}");
    csvSb.writeln("");
    csvSb.writeln("Candidates,Details");
    csvSb.writeln("${candidateRes.swg},\"${computeForEntry(candidateRes, totalAlAreaIfStranded)}\"");
    csvSb.writeln("${candidateAmp.swg},\"${computeForEntry(candidateAmp, totalAlAreaIfStranded)}\"");

    // Generate Display Text
    final sb = StringBuffer();
    sb.writeln("Assumptions:");
    sb.writeln("  ρ_Al/ρ_Cu = ${resistivityRatio.toStringAsFixed(3)}");
    sb.writeln("  J_cu=${jCuVal.toStringAsFixed(2)} A/mm², J_al=${jAlVal.toStringAsFixed(2)} A/mm²");
    sb.writeln("\nCopper SWG: ${cuEntry.swg} — dia ${cuEntry.diameterMm.toStringAsFixed(3)} mm — area ${cuArea.toStringAsFixed(4)} mm²\n");

    sb.writeln("=== SAME RESISTANCE ===");
    sb.writeln("Required Al area = ${requiredAlAreaResistance.toStringAsFixed(4)} mm²");
    sb.writeln("Suggested Al SWG: ${candidateRes.swg}");
    sb.writeln(computeForEntry(candidateRes, totalAlAreaIfStranded));
    sb.writeln("\n");

    sb.writeln("=== SAME AMPACITY ===");
    sb.writeln("Required Al area = ${requiredAlAreaAmpacity.toStringAsFixed(4)} mm²");
    sb.writeln("Suggested Al SWG: ${candidateAmp.swg}");
    sb.writeln(computeForEntry(candidateAmp, totalAlAreaIfStranded));
    sb.writeln("\n");

    sb.writeln("Stranded conductor total area (if used): ${totalAlAreaIfStranded.toStringAsFixed(4)} mm²");

    setState(() {
      _resultText = sb.toString();
    });
    
    // Show CSV Dialog
    _showCsvDialog(csvSb.toString());
  }

  void _showCsvDialog(String csvContent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("CSV Export Data"),
        content: SingleChildScrollView(
          child: SelectableText(csvContent),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Motor Helper PRO"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Aluminum/Copper conversion",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Input Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _inputSwgController,
                      decoration: const InputDecoration(
                        labelText: "Original copper SWG (e.g. 12)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _copperTurnsController,
                            decoration: const InputDecoration(
                              labelText: "Copper turns",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _slotAreaController,
                            decoration: const InputDecoration(
                              labelText: "Slot area (mm²)",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _insulationController,
                            decoration: const InputDecoration(
                              labelText: "Insulation (mm)",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _fillFactorController,
                            decoration: const InputDecoration(
                              labelText: "Slot fill (0-1)",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            const Text("Mode / Goal", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Column(
              children: _modes.map((mode) => RadioListTile<String>(
                title: Text(mode),
                value: mode,
                groupValue: _mode,
                onChanged: (val) => setState(() => _mode = val!),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )).toList(),
            ),

            const SizedBox(height: 16),
            const Text("Current density (A/mm²) assumptions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _jCuController,
                    decoration: const InputDecoration(
                      labelText: "J_cu",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _jAlController,
                    decoration: const InputDecoration(
                      labelText: "J_al",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text("Use stranded conductor"),
              value: _useStranded,
              onChanged: (val) => setState(() => _useStranded = val!),
              contentPadding: EdgeInsets.zero,
            ),

            if (_useStranded) ...[
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nStrandsController,
                              decoration: const InputDecoration(
                                labelText: "Num strands",
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Radio<bool>(
                                      value: true,
                                      groupValue: _strandUsesSwg,
                                      onChanged: (v) => setState(() => _strandUsesSwg = v!),
                                    ),
                                    const Text("SWG"),
                                    Radio<bool>(
                                      value: false,
                                      groupValue: _strandUsesSwg,
                                      onChanged: (v) => setState(() => _strandUsesSwg = v!),
                                    ),
                                    const Text("Dia"),
                                  ],
                                ),
                                if (_strandUsesSwg)
                                  TextFormField(
                                    controller: _strandSwgController,
                                    decoration: const InputDecoration(
                                      labelText: "Strand SWG",
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                  )
                                else
                                  TextFormField(
                                    controller: _strandDiaMmController,
                                    decoration: const InputDecoration(
                                      labelText: "Strand dia mm",
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _strandingPackingFactorController,
                        decoration: const InputDecoration(
                          labelText: "Strand packing factor (0-1)",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _computeResults,
                icon: const Icon(Icons.calculate),
                label: const Text("Compute & Export CSV"),
              ),
            ),

            if (_resultText.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SelectableText(
                  _resultText,
                  style: const TextStyle(fontFamily: 'Monospace'),
                ),
              ),
            ],

            const SizedBox(height: 32),
            const Text("SWG Reference (partial):", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                itemCount: min(12, swgTable.length),
                itemBuilder: (context, index) {
                  final item = swgTable[index];
                  return ListTile(
                    dense: true,
                    title: Text("SWG ${item.swg} — dia ${item.diameterMm.toStringAsFixed(3)} mm — area ${item.areaMm2.toStringAsFixed(4)} mm²"),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),
            const Text("Pro Tools", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Star–Delta helper: Δ → Y current = I/√3 (≈ 0.577×)."),
            const SizedBox(height: 4),
            const Text("Slot fill estimate: uses fill factor to estimate max turns (estimate, not exact)."),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
