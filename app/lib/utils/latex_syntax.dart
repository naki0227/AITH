import 'package:markdown/markdown.dart' as md;

class LatexSyntax extends md.InlineSyntax {
  LatexSyntax() : super(r'(\$\$[\s\S]*?\$\$)|(\$[^$]*\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final input = match.input;
    final matchStart = match.start;
    final matchEnd = match.end;
    final text = input.substring(matchStart, matchEnd);
    // Remove $$ or $
    final rawLatex = text.replaceAll(r'$', '');
    
    final el = md.Element.text('latex', rawLatex);
    parser.addNode(el);
    return true;
  }
}
