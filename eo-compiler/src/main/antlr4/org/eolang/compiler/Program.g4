grammar Program;

@header {
    import org.eolang.compiler.syntax.Argument;
    import org.eolang.compiler.syntax.Method;
    import org.eolang.compiler.syntax.Tree;
    import org.eolang.compiler.syntax.Type;
    import java.util.Collection;
    import java.util.LinkedList;
}

tokens { INDENT, DEDENT }

@lexer::members {
    // got it here: https://github.com/antlr/grammars-v4/blob/master/python3/Python3.g4

    // A queue where extra tokens are pushed on (see the NEWLINE lexer rule).
    private java.util.LinkedList<Token> tokens = new java.util.LinkedList<>();
    // The stack that keeps track of the indentation level.
    private java.util.Stack<Integer> indents = new java.util.Stack<>();
    // The amount of opened braces, brackets and parenthesis.
    private int opened = 0;
    // The most recently produced token.
    private Token lastToken = null;

    @Override
    public void emit(Token t) {
        super.setToken(t);
        tokens.offer(t);
    }

    @Override
    public Token nextToken() {
        // Check if the end-of-file is ahead and there are still some DEDENTS expected.
        if (_input.LA(1) == EOF && !this.indents.isEmpty()) {
            // Remove any trailing EOF tokens from our buffer.
            for (int i = tokens.size() - 1; i >= 0; i--) {
                if (tokens.get(i).getType() == EOF) {
                    tokens.remove(i);
                }
            }

            // First emit an extra line break that serves as the end of the statement.
            this.emit(commonToken(ProgramParser.NEWLINE, "\n"));

            // Now emit as much DEDENT tokens as needed.
            while (!indents.isEmpty()) {
                this.emit(createDedent());
                indents.pop();
            }

            // Put the EOF back on the token stream.
            this.emit(commonToken(ProgramParser.EOF, "<EOF>"));
        }

        Token next = super.nextToken();

        if (next.getChannel() == Token.DEFAULT_CHANNEL) {
            // Keep track of the last token on the default channel.
            this.lastToken = next;
        }

        return tokens.isEmpty() ? next : tokens.poll();
    }

    private Token createDedent() {
        CommonToken dedent = commonToken(ProgramParser.DEDENT, "");
        dedent.setLine(this.lastToken.getLine());
        return dedent;
    }

    private CommonToken commonToken(int type, String text) {
        int stop = this.getCharIndex() - 1;
        int start = text.isEmpty() ? stop : stop - text.length() + 1;
        return new CommonToken(this._tokenFactorySourcePair, type, DEFAULT_TOKEN_CHANNEL, start, stop);
    }

    // Calculates the indentation of the provided spaces, taking the
    // following rules into account:
    //
    // "Tabs are replaced (from left to right) by one to eight spaces
    //  such that the total number of characters up to and including
    //  the replacement is a multiple of eight [...]"
    //
    //  -- https://docs.python.org/3.1/reference/lexical_analysis.html#indentation
    static int getIndentationCount(String spaces) {
        int count = 0;
        for (char ch : spaces.toCharArray()) {
            switch (ch) {
                case '\t':
                    count += 8 - (count % 8);
                    break;
                default:
                    // A normal space char.
                    count++;
            }
        }

        return count;
    }

    boolean atStartOfInput() {
        return super.getCharPositionInLine() == 0 && super.getLine() == 1;
    }
}


program returns [Tree ret]
    :
    { Collection<Type> types = new LinkedList<Type>(); }
    (
        type_declaration
        { types.add($type_declaration.ret); }
        |
        object_instantiation
        |
        object_copying
    )*
    EOF
    { $ret = new Tree(types); }
    ;

type_declaration returns [Type ret]
    :
    { Collection<Method> methods = new LinkedList<Method>(); }
    TYPE
    SPACE
    HINAME
    (
        SPACE
        EXTENDS
        SPACE
        HINAME
        (
            COMMA
            SPACE
            HINAME
        )*
    )?
    COLON
    NEWLINE
    INDENT
    (
        method_declaration
        { methods.add($method_declaration.ret); }
        NEWLINE
    )+
    DEDENT
    { $ret = new Type($HINAME.text, methods); }
    ;

method_declaration returns [Method ret]
    :
    HINAME
    SPACE
    LONAME
    arguments_declaration
    { $ret = new Method($LONAME.text, $arguments_declaration.ret, $HINAME.text); }
    ;

arguments_declaration returns [List<Argument> ret]
    :
    { $ret = new LinkedList<Argument>(); }
    LBRACKET
    (
        head=argument_declaration
        { $ret.add($head.ret); }
        (
            COMMA
            SPACE
            tail=argument_declaration
            { $ret.add($tail.ret); }
        )*
    )?
    RBRACKET
    ;

argument_declaration returns [Argument ret]
    :
    HINAME
    SPACE
    LONAME
    { $ret = new Argument($LONAME.text, $HINAME.text); }
    ;

object_instantiation
    :
    OBJECT
    SPACE
    LONAME
    SPACE
    AS
    SPACE
    HINAME
    (
        COMMA
        SPACE
        HINAME
    )*
    COLON
    NEWLINE
    INDENT
    (
        attribute_declaration
        NEWLINE
    )+
    (
        ctor_declaration
        NEWLINE
    )+
    (
        method_implementation
        NEWLINE
    )*
    DEDENT
    ;

attribute_declaration
    :
    HINAME
    SPACE
    ATTRIBUTE
    ;

ctor_declaration
    :
    CTOR
    arguments_declaration
    COLON
    NEWLINE
    INDENT
    (
        object_instantiation
        |
        object_copying
    )
    DEDENT
    ;

method_implementation
    :
    method_declaration
    COLON
    NEWLINE
    INDENT
    (
        object_instantiation
        |
        object_copying
    )
    NEWLINE
    DEDENT
    ;

object_copying
    :
    LONAME
    (
        COLON
        NEWLINE
        INDENT
        object_argument
        (
            NEWLINE
            INDENT
            object_argument
            DEDENT
        )*
    )?
    ;

object_argument
    :
    NUMBER
    |
    TEXT
    |
    ATTRIBUTE
    |
    object_copying
    |
    object_instantiation
    ;

SPACE: ' ';
DOT: '.';
COLON: ':';
LBRACKET: '(';
RBRACKET: ')';
COMMA: ',';

TYPE: 'type';
OBJECT: 'object';
EXTENDS: 'extends';
AS: 'as';
CTOR: 'ctor';

ATTRIBUTE: '@' ( 'a' .. 'z' ) LETTER*;
HINAME: ( 'A' .. 'Z' ) LETTER*;
LONAME: ( 'a' .. 'z' ) LETTER*;
NUMBER: ( '0' .. '9' )+;
LETTER: ( 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' );
TEXT: '"' ('\\"' | ~'"')* '"';

fragment SPACES: [ \t]+;

NEWLINE
    :
    // got it here: https://github.com/antlr/grammars-v4/blob/master/python3/Python3.g4
    (
        {atStartOfInput()}?
        SPACES
        |
        ( '\r'? '\n' | '\r' )
        SPACES?
    )
    {
        String newLine = getText().replaceAll("[^\r\n]+", "");
        String spaces = getText().replaceAll("[\r\n]+", "");
        int next = _input.LA(1);
        if (opened > 0 || next == '\r' || next == '\n' || next == '#') {
            // If we're inside a list or on a blank line, ignore all indents,
            // dedents and line breaks.
            skip();
        } else {
            emit(commonToken(NEWLINE, newLine));
            int indent = getIndentationCount(spaces);
            int previous = indents.isEmpty() ? 0 : indents.peek();
            if (indent == previous) {
                // skip indents of the same size as the present indent-size
                skip();
            } else if (indent > previous) {
                indents.push(indent);
                emit(commonToken(ProgramParser.INDENT, spaces));
            } else {
                // Possibly emit more than 1 DEDENT token.
                while(!indents.isEmpty() && indents.peek() > indent) {
                    this.emit(createDedent());
                    indents.pop();
                }
            }
        }
    }
    ;