import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// A widget that renders Markdown content with LaTeX math support.
/// Inline math (`$...$`) stays inline with text.
/// Block math (`$$...$$`) is centered on its own line.
class MathAwareMarkdown extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet? styleSheet;

  const MathAwareMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
  });

  @override
  Widget build(BuildContext context) {
    // First, split by block math ($$...$$) which should be on separate lines
    final blockRegex = RegExp(r'\$\$[\s\S]*?\$\$');
    final parts = data.split(blockRegex);
    final blockMatches = blockRegex.allMatches(data).toList();
    
    List<Widget> widgets = [];
    
    for (int i = 0; i < parts.length; i++) {
      // Add the markdown/inline-math segment
      if (parts[i].trim().isNotEmpty) {
        widgets.add(_buildInlineContent(parts[i], context));
      }
      
      // Add the block math if exists
      if (i < blockMatches.length) {
        final blockContent = blockMatches[i].group(0)!;
        final latex = blockContent.substring(2, blockContent.length - 2).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Center(
              child: Math.tex(
                latex,
                mathStyle: MathStyle.display,
                textStyle: const TextStyle(fontSize: 20),
                onErrorFallback: (e) => Text(
                  latex,
                  style: const TextStyle(color: Colors.red, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Builds content with inline math rendered inline using WidgetSpan
  Widget _buildInlineContent(String text, BuildContext context) {
    // Check if this segment contains inline math
    final inlineRegex = RegExp(r'\$([^$\n]+)\$');
    
    if (!inlineRegex.hasMatch(text)) {
      // No inline math, just render as markdown
      return MarkdownBody(
        data: text,
        styleSheet: styleSheet ?? MarkdownStyleSheet(
          p: const TextStyle(fontSize: 16, height: 1.6),
        ),
        shrinkWrap: true,
      );
    }
    
    // Has inline math - need to build with WidgetSpan
    // For simplicity, we'll process line by line to handle mixed content
    final lines = text.split('\n');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().isEmpty) return const SizedBox(height: 8);
        
        if (!inlineRegex.hasMatch(line)) {
          // No math in this line, render as markdown
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: MarkdownBody(
              data: line,
              styleSheet: styleSheet ?? MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.6),
              ),
              shrinkWrap: true,
            ),
          );
        }
        
        // This line has inline math - build with WidgetSpan
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildRichTextLine(line, inlineRegex),
        );
      }).toList(),
    );
  }

  /// Builds a single line with inline math using Text.rich
  Widget _buildRichTextLine(String line, RegExp inlineRegex) {
    List<InlineSpan> spans = [];
    int lastEnd = 0;
    
    for (final match in inlineRegex.allMatches(line)) {
      // Add preceding text
      if (match.start > lastEnd) {
        final textBefore = line.substring(lastEnd, match.start);
        spans.add(TextSpan(
          text: textBefore,
          style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
        ));
      }
      
      // Add the math as a WidgetSpan
      final latex = match.group(1)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          latex,
          mathStyle: MathStyle.text,
          textStyle: const TextStyle(fontSize: 16),
          onErrorFallback: (e) => Text(
            latex,
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
        ),
      ));
      
      lastEnd = match.end;
    }
    
    // Add remaining text
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
      ));
    }
    
    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
