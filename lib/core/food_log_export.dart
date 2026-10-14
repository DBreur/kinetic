// food_log_export.dart — eetlogboek exporteren als PDF (om te delen/printen,
// bv. voor je diabetesverpleegkundige) of als CSV (opent in Excel/Sheets).

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/food_log_entry.dart';
import 'formatters.dart';

Future<void> exportFoodLogAsPdf(List<FoodLogEntry> entries) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, text: 'Eetlogboek'),
        pw.Paragraph(
          text:
              'Geëxporteerd op ${DateFormat('d MMMM yyyy · HH:mm', 'nl_NL').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [
            'Datum',
            'Tijd',
            'Gegeten',
            'Koolhydraten',
            'Glucose',
            'Insuline',
          ],
          data: [
            for (final e in entries)
              [
                DateFormat('d MMM yyyy', 'nl_NL').format(e.at),
                DateFormat('HH:mm', 'nl_NL').format(e.at),
                e.description,
                e.carbs != null ? '${carbsText(e.carbs!)} g' : '—',
                e.mmol != null ? '${mmolText(e.mmol!)} mmol/L' : '—',
                e.insulinUnits != null
                    ? '${carbsText(e.insulinUnits!)} E'
                          '${e.insulinTiming != null ? ' (${e.insulinTiming!.label})' : ''}'
                    : '—',
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(0.8),
            2: const pw.FlexColumnWidth(2.6),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.3),
            5: const pw.FlexColumnWidth(1.8),
          },
        ),
      ],
    ),
  );
  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: 'eetlogboek.pdf');
}

Future<void> exportFoodLogAsCsv(List<FoodLogEntry> entries) async {
  final buffer = StringBuffer();
  buffer.writeln(
    'Datum;Tijd;Gegeten;Koolhydraten (g);Glucose (mmol/L);Insuline (E);Voor/na eten;Notitie',
  );
  for (final e in entries) {
    final date = DateFormat('yyyy-MM-dd').format(e.at);
    final time = DateFormat('HH:mm', 'nl_NL').format(e.at);
    final desc = _csvField(e.description);
    final carbs = e.carbs != null ? carbsText(e.carbs!) : '';
    final mmol = e.mmol != null ? mmolText(e.mmol!) : '';
    final insulin = e.insulinUnits != null ? carbsText(e.insulinUnits!) : '';
    final timing = e.insulinTiming?.label ?? '';
    final note = _csvField(e.insulinNote);
    buffer.writeln('$date;$time;$desc;$carbs;$mmol;$insulin;$timing;$note');
  }
  final bytes = Uint8List.fromList(buffer.toString().codeUnits);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(bytes, name: 'eetlogboek.csv', mimeType: 'text/csv'),
      ],
    ),
  );
}

String _csvField(String value) {
  if (value.contains(';') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
