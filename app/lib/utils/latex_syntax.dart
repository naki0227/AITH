import 'package:markdown/markdown.dart' as md;

class LatexSyntax extends md.InlineSyntax {
  // Simplest working regex: matches $$...$$ or $...$ 
  // We handle escaping in onMatch logic if needed, but for now allow anything except delimiters.
  // Note: We use [^$] which means "not a dollar sign". 
  // To allow \$ inside, we need (?:\\.|[^$])
  LatexSyntax() : super(r'(\$\$[\s\S]*?\$\$)|(\$((?:\\.|[^$])*)\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // The match includes delimiters.
    final matchStart = match.start;
    final matchEnd = match.end;
    final text = match.input.substring(matchStart, matchEnd);

    bool isBlock = text.startsWith(r'$$');
    
    // Strip delimiters
    String rawLatex;
    if (isBlock) {
       rawLatex = text.substring(2, text.length - 2);
    } else {
       rawLatex = text.substring(1, text.length - 1);
    }

    final el = md.Element.text('latex', rawLatex);
    el.attributes['style'] = isBlock ? 'display' : 'inline';
    parser.addNode(el);
    return true;
  }
}
