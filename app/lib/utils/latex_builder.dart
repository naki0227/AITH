import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

class LatexElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElement(md.Element element, TextStyle? preferredStyle) {
    
    final bool isBlock = element.attributes['style'] == 'display';
    final String rawLatex = element.textContent;

    if (isBlock) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Math.tex(
            rawLatex,
            textStyle: preferredStyle?.copyWith(fontSize: (preferredStyle.fontSize ?? 14) * 1.2),
            mathStyle: MathStyle.display,
            onErrorFallback: (FlutterMathException e) {
               return Text(rawLatex, style: preferredStyle?.copyWith(color: Colors.red));
            },
          ),
        ),
      );
    }

    return Math.tex(
      rawLatex,
      textStyle: preferredStyle,
      mathStyle: MathStyle.text,
      onErrorFallback: (FlutterMathException e) {
        return Text(rawLatex, style: preferredStyle?.copyWith(color: Colors.red));
      },
    );
  }
}
