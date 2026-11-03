import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Thin wrapper around Syncfusion's community-licensed PDF text extraction.
/// Extracts all textual content from a local PDF file path. Fully on-device.
class PdfExtractor {
  static Future<String> extractText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final buffer = StringBuffer();
    for (int i = 0; i < doc.pages.count; i++) {
      buffer.writeln(extractor.extractText(startPageIndex: i, endPageIndex: i));
    }
    doc.dispose();
    return buffer.toString();
  }
}
