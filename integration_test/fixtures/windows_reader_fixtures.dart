import 'dart:convert';

const tinyReaderText = 'MODU one TXT indexing fixture has 42 chars';

// ASCII-only one-page PDF with selectable text and exact xref offsets.
List<int> tinyReaderPdf() {
  const stream = 'BT /F1 12 Tf 40 100 Td (MODU_PDF_SENTINEL) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
  ];
  final data = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(data.length);
    data.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = data.length;
  data.write('xref\n0 6\n0000000000 65535 f \n');
  for (final offset in offsets) {
    data.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  data.write('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return ascii.encode(data.toString());
}
