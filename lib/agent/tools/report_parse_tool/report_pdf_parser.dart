// Financial report PDF parser for Chinese A-share/HK annual and quarterly reports.
// Extracts text and splits report content into structured sections.
//
// Uses `syncfusion_flutter_pdf` for text extraction.

import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ParsedSection {
  final String title;
  final String content;
  final int page;
  final int index;

  ParsedSection({
    required this.title,
    required this.content,
    required this.page,
    required this.index,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'page': page,
    'index': index,
  };
}

class ParsedFigure {
  final String caption;
  final int page;
  final int index;
  final String kind;
  final int originalNumber;

  ParsedFigure({
    required this.caption,
    required this.page,
    required this.index,
    required this.kind,
    required this.originalNumber,
  });

  Map<String, dynamic> toJson() => {
    'caption': caption,
    'page': page,
    'index': index,
    'kind': kind,
    'originalNumber': originalNumber,
  };
}

class ParsedReport {
  final String companyName;
  final String reportPeriod;
  final String reportType;
  final List<ParsedSection> sections;
  final List<ParsedFigure> figures;
  final int totalPages;
  final String rawText;

  ParsedReport({
    required this.companyName,
    required this.reportPeriod,
    required this.reportType,
    required this.sections,
    required this.figures,
    required this.totalPages,
    required this.rawText,
  });

  Map<String, dynamic> toJson() => {
    'companyName': companyName,
    'reportPeriod': reportPeriod,
    'reportType': reportType,
    'sections': sections.map((s) => s.toJson()).toList(),
    'figures': figures.map((f) => f.toJson()).toList(),
    'totalPages': totalPages,
  };
}

// Chinese A-share annual/quarterly report standard sections.
// Per CSRC disclosure rules, these are the standard top-level headings.
const _knownHeadings = [
  '重要提示',
  '释义',
  '公司简介',
  '公司简介和主要财务指标',
  '主要财务指标',
  '会计数据和财务指标摘要',
  '会计数据',
  '主要会计数据和财务指标',
  '公司业务概要',
  '经营情况讨论与分析',
  '管理层讨论与分析',
  '董事会报告',
  '重要事项',
  '股份变动及股东情况',
  '优先股相关情况',
  '可转换公司债券相关情况',
  '董事、监事、高级管理人员',
  '董事、监事、高级管理人员和员工情况',
  '公司治理',
  '环境与社会责任',
  '财务报告',
  '财务报表',
  '财务会计报告',
  '审计报告',
  '备查文件',
  '备查文件目录',
  '合并资产负债表',
  '资产负债表',
  '合并利润表',
  '利润表',
  '合并现金流量表',
  '现金流量表',
  '合并所有者权益变动表',
  '所有者权益变动表',
  '财务报表附注',
  '附注',
];

bool _isKnownHeading(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.length > 80) return false;

  for (final h in _knownHeadings) {
    if (trimmed == h) return true;
  }

  // Numbered Chinese headings: "第一节 重要提示", "第二节 公司简介"
  final numberedRe = RegExp(r'^第[一二三四五六七八九十]+[节章]\s*(.+)$');
  final m = numberedRe.firstMatch(trimmed);
  if (m != null) {
    final rest = m.group(1)!.trim();
    for (final h in _knownHeadings) {
      if (rest == h || rest.startsWith(h)) return true;
    }
  }

  return false;
}

String _normalizeHeading(String line) {
  var h = line.trim();
  h = h.replaceFirst(RegExp(r'^第[一二三四五六七八九十]+[节章]\s*'), '');
  return h;
}

// Caption detection — Chinese reports use 图1, 表1, 图 1, 表 1, plus English.
final _figureRe = RegExp(
  r'^(?:图\s*(\d+)|Fig(?:ure)?\.?\s*(\d+))[.:：、\s]\s*(.*)',
  caseSensitive: false,
);
final _tableRe = RegExp(
  r'^(?:表\s*(\d+)|Table\.?\s*(\d+))[.:：、\s]\s*(.*)',
  caseSensitive: false,
);

({String companyName, String reportPeriod, String reportType})
_extractReportInfo(String firstPagesText) {
  // Look for a header pattern like "<公司>2024年年度报告" or "<公司> 2024 年度报告"
  final headerRe = RegExp(
    r'([一-鿿（）()A-Za-z·\-\s]{2,30}?)\s*(\d{4})\s*年?\s*(年度报告|半年度报告|第一季度报告|第三季度报告|中期报告|年报|中报|一季报|三季报)',
  );
  final m = headerRe.firstMatch(firstPagesText);
  if (m != null) {
    return (
      companyName: m.group(1)!.trim(),
      reportPeriod: m.group(2)!,
      reportType: m.group(3)!,
    );
  }

  // Fallback: first non-empty short line as company name
  final lines = firstPagesText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.length < 50)
      .toList();
  final company = lines.isNotEmpty ? lines.first : '未知公司';

  return (companyName: company, reportPeriod: '', reportType: '');
}

Future<ParsedReport> parseFinancialReport(String filePath) async {
  final bytes = File(filePath).readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);
  final totalPages = document.pages.count;

  final pageTexts = <String>[];
  for (var i = 0; i < totalPages; i++) {
    final extractor = PdfTextExtractor(document);
    final lines = extractor.extractTextLines(
      startPageIndex: i,
      endPageIndex: i,
    );
    final pageBuffer = StringBuffer();
    for (final line in lines) {
      final lineBuffer = StringBuffer();
      for (final word in line.wordCollection) {
        if (lineBuffer.isNotEmpty) lineBuffer.write(' ');
        lineBuffer.write(word.text);
      }
      if (pageBuffer.isNotEmpty) pageBuffer.write('\n');
      pageBuffer.write(lineBuffer.toString());
    }
    pageTexts.add(pageBuffer.toString());
  }

  document.dispose();

  final rawText = pageTexts.join('\n\n');

  // Extract report info from first 3 pages (cover + 重要提示)
  final headPages = pageTexts.take(3).join('\n\n');
  final (:companyName, :reportPeriod, :reportType) = _extractReportInfo(
    headPages,
  );

  final sections = _splitIntoSections(rawText, pageTexts);
  final figures = _detectFiguresAndTables(rawText, pageTexts);

  return ParsedReport(
    companyName: companyName,
    reportPeriod: reportPeriod,
    reportType: reportType,
    sections: sections,
    figures: figures,
    totalPages: totalPages,
    rawText: rawText,
  );
}

int _findPage(int offset, List<String> pageTexts) {
  var cumLen = 0;
  for (var i = 0; i < pageTexts.length; i++) {
    cumLen += pageTexts[i].length + 1;
    if (offset < cumLen) return i + 1;
  }
  return pageTexts.length;
}

List<ParsedSection> _splitIntoSections(String rawText, List<String> pageTexts) {
  final lines = rawText.split('\n');
  final sections = <ParsedSection>[];
  var currentTitle = '封面';
  var currentContent = <String>[];
  var currentOffset = 0;
  var sectionStartOffset = 0;
  var sectionIndex = 0;

  for (final line in lines) {
    if (_isKnownHeading(line)) {
      if (currentContent.isNotEmpty) {
        final content = currentContent.join('\n').trim();
        if (content.isNotEmpty) {
          sections.add(
            ParsedSection(
              title: currentTitle,
              content: content,
              page: _findPage(sectionStartOffset, pageTexts),
              index: sectionIndex++,
            ),
          );
        }
      }
      currentTitle = _normalizeHeading(line);
      currentContent = [];
      sectionStartOffset = currentOffset;
    } else {
      currentContent.add(line);
    }
    currentOffset += line.length + 1;
  }

  if (currentContent.isNotEmpty) {
    final content = currentContent.join('\n').trim();
    if (content.isNotEmpty) {
      sections.add(
        ParsedSection(
          title: currentTitle,
          content: content,
          page: _findPage(sectionStartOffset, pageTexts),
          index: sectionIndex,
        ),
      );
    }
  }

  return sections;
}

List<ParsedFigure> _detectFiguresAndTables(
  String rawText,
  List<String> pageTexts,
) {
  final figures = <ParsedFigure>[];
  final lines = rawText.split('\n');
  var offset = 0;
  var figIndex = 0;

  final captionStartRe = RegExp(
    r'^(?:图\s*\d+|表\s*\d+|Fig(?:ure)?\.?\s*\d+|Table\.?\s*\d+)[.:：、\s]',
    caseSensitive: false,
  );

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    Match? figMatch = _figureRe.firstMatch(line);
    Match? tabMatch = figMatch == null ? _tableRe.firstMatch(line) : null;

    if (figMatch == null && tabMatch == null) {
      offset += lines[i].length + 1;
      continue;
    }

    final isFigure = figMatch != null;
    final match = figMatch ?? tabMatch!;
    final num = int.tryParse(match.group(1) ?? match.group(2) ?? '0') ?? 0;

    final captionLines = <String>[line];
    var j = i + 1;
    while (j < lines.length) {
      final next = lines[j].trim();
      if (next.isEmpty) break;
      if (captionStartRe.hasMatch(next)) break;
      if (_isKnownHeading(next)) break;
      captionLines.add(next);
      if (captionLines.length >= 3) break;
      j++;
    }

    figures.add(
      ParsedFigure(
        caption: captionLines.join(' '),
        page: _findPage(offset, pageTexts),
        index: figIndex++,
        kind: isFigure ? 'figure' : 'table',
        originalNumber: num,
      ),
    );

    offset += lines[i].length + 1;
  }

  return figures;
}
