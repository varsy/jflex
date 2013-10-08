/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * JFlex 1.5                                                               *
 * Copyright (C) 1998-2012  Gerwin Klein <lsf@jflex.de>                    *
 * All rights reserved.                                                    *
 *                                                                         *
 * License: BSD                                                            *
 *                                                                         *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

package jflex;

import java_cup.runtime.Symbol;
import java.io.*;
import java.util.Stack;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import jflex.unicode.UnicodeProperties;

%%

%final
%public
%class LexScan
%implements sym, java_cup.runtime.Scanner
%function next_token

%type Symbol
%unicode

%column
%line

%eofclose

%state COMMENT, STATELIST, MACROS, REGEXPSTART
%state REGEXP, JAVA_CODE, STATES, STRING_CONTENT
%state CHARCLASS, COPY, REPEATEXP, EATWSPNL
%state CTOR_ARG

%cupdebug

%{
  int balance = 0;
  int commentbalance = 0;
  int action_line = 0;
  int bufferSize = 16384;

  File file;
  Stack<File> files = new Stack<File>();

  StringBuilder userCode   = new StringBuilder();

  String classCode;
  String initCode;
  String initThrow;
  String eofCode;
  String eofThrow;
  String lexThrow;
  String eofVal;
  String scanErrorException;
  String cupSymbol = "sym";

  StringBuilder actionText = new StringBuilder();
  StringBuilder string     = new StringBuilder();

  private UnicodeProperties unicodeProperties;

  boolean charCount;
  boolean lineCount;
  boolean columnCount;
  boolean cupCompatible;
  boolean cupDebug;
  boolean isInteger;
  boolean isIntWrap;
  boolean isYYEOF;
  boolean notUnix;
  boolean isPublic;
  boolean isFinal;
  boolean isAbstract;
  boolean bolUsed;
  boolean standalone;
  boolean debugOption;
  boolean useRowMap = Options.gen_method == Options.PACK || Options.gen_method == Options.TABLE;
  boolean packed = Options.gen_method == Options.PACK;
  boolean caseless;
  boolean inclusive_states;
  boolean eofclose;
  boolean isASCII;
  // TODO: In the version of JFlex after 1.6, the InputStream ctor 
  // TODO: will never be emitted, and this option will cease to exist.
  boolean emitInputStreamCtor = Options.emitInputStreamCtor;

  String isImplementing;
  String isExtending;
  String className = "Yylex";
  String functionName;
  String tokenType;
  String visibility = "public";
    
  List<String> ctorArgs = new ArrayList<String>();
  List<String> ctorTypes = new ArrayList<String>();
    
  LexicalStates states = new LexicalStates();

  List<Action> actions = new ArrayList<Action>();

  private int nextState;

  boolean macroDefinition;

  Timer t = new Timer();

  public int currentLine() {
    return yyline;
  }

  public void setFile(File file) {
    this.file = file;
  }

  private Symbol symbol(int type, Object value) {
    return new Symbol(type, yyline, yycolumn, value);
  }

  private Symbol symbol(int type) {
    return new Symbol(type, yyline, yycolumn);
  }

  // updates line and column count to the beginning of the first
  // non whitespace character in yytext, but leaves yyline+yycolumn
  // untouched
  private Symbol symbol_countUpdate(int type, Object value) {
     int lc = yyline;
     int cc = yycolumn;
     String text = yytext();

     for (int i=0; i < text.length(); i++) {
      char c = text.charAt(i);

      if (c != '\n' && c != '\r' && c != ' ' && c != '\t' )
        return new Symbol(type, lc, cc, value);

      if (c == '\n') {
        lc++;
        cc = 0;
      }
      else
        cc++;
    }

    return new Symbol(type, yyline, yycolumn, value);
  }

  private String makeMacroIdent() {
    String matched = yytext().trim();
    return matched.substring(1, matched.length()-1).trim();
  }

  public static String conc(Object a, Object b) {
    if (a == null && b == null) return null;
    if (a == null) return b.toString();
    if (b == null) return a.toString();

    return a.toString()+b.toString();
  }

  public static String concExc(Object a, Object b) {
    if (a == null && b == null) return null;
    if (a == null) return b.toString();
    if (b == null) return a.toString();

    return a.toString()+", "+b.toString();
  }
  
  public UnicodeProperties getUnicodeProperties() {
    return unicodeProperties;
  }
  
  private void populateDefaultVersionUnicodeProperties() {
    try {
      unicodeProperties = new UnicodeProperties();
    } catch (UnicodeProperties.UnsupportedUnicodeVersionException e) {
      throw new ScannerException
        (file, ErrorMessages.UNSUPPORTED_UNICODE_VERSION, yyline);
    }
  }
%}

%init{
  states.insert("YYINITIAL", true);
%init}


Digit      = [0-9]
HexDigit   = [0-9a-fA-F]
OctDigit   = [0-7]

Number     = {Digit}+
HexNumber  = \\ x {HexDigit} {2}
OctNumber  = \\ [0-3]? {OctDigit} {1, 2}

// Unicode4 can encode chars only in the BMP with the 16 bits provided by its
// (at most) 4 hex digits.
Unicode4  = \\ u {HexDigit} {1, 4}

// Unicode6 can encode all Unicode chars, both in the BMP and in the
// supplementary planes -- only 21 bits are required as of Unicode 5.0,
// but its six hex digits provide 24 bits.
Unicode6  = \\ U {HexDigit} {1, 6}

// see http://www.unicode.org/unicode/reports/tr18/
WSP        = [ \t\b]
WSPNL      = [\u2028\u2029\u000A\u000B\u000C\u000D\u0085\t\b\ ]
NL         = [\u2028\u2029\u000A\u000B\u000C\u000D\u0085] | \u000D\u000A
NNL        = [^\u2028\u2029\u000A\u000B\u000C\u000D\u0085]

Ident      = {IdentStart} {IdentPart}*
QualIdent  = {Ident} ( {WSP}* "." {WSP}* {Ident} )*
QUIL       = {QualIdent} ( {WSP}* "," {WSP}* {QualIdent} )*
Array      = "[" {WSP}* "]"
ParamPart  = {IdentStart}|{IdentPart}|"<"|">"|","|{WSP}|"&"|"?"|"."
GenParam   = "<" {ParamPart}+ ">"
ClassT     = {Ident} ({WSP}* {GenParam})?
QClassT    = {QualIdent} ({WSP}* {GenParam})?
ArrType    = ({GenParam} {WSP}*)? {QClassT} ({WSP}* {Array})*

IdentStart = [:jletter:]
IdentPart  = [:jletterdigit:]

JFlexCommentChar = [^*/]|"/"+[^*/]|"*"+[^*/]
JFlexComment = {JFlexCommentChar}*

/* Java comments */
JavaComment = {TraditionalComment}|{EndOfLineComment}
TraditionalComment = "/*"{CommentContent}\*+"/"
EndOfLineComment = "//".*{NL}

CommentContent = ([^*]|\*+[^*/])*

StringCharacter = [^\u2028\u2029\u000A\u000B\u000C\u000D\u0085\"\\]

CharLiteral = \'([^\u2028\u2029\u000A\u000B\u000C\u000D\u0085\'\\]|{EscapeSequence})\'
StringLiteral = \"({StringCharacter}|{EscapeSequence})*\"

EscapeSequence = \\[^\u2028\u2029\u000A\u000B\u000C\u000D\u0085]|\\+u{HexDigit}{4}|\\[0-3]?{OctDigit}{1,2}

/* \\(b|t|n|f|r|\"|\'|\\|[0-3]?{OctDigit}{1,2}|u{HexDigit}{4}) */

JavaRest = [^\{\}\"\'/]|"/"[^*/]
JavaCode = ({JavaRest}|{StringLiteral}|{CharLiteral}|{JavaComment})+

DottedVersion =  [1-9][0-9]*(\.[0-9]+){0,2}

%%

<YYINITIAL> {
  "%%".*{NL}?              {
                             t.start();
                             yybegin(MACROS);
                             macroDefinition = true;
                             return symbol(USERCODE,userCode);
                           }
  .*{NL}                   { userCode.append(yytext()); }
  .*                       { return symbol(EOF); }
}

<MACROS>   ("%{"|"%init{"|"%initthrow{"|"%eof{"|"%eofthrow{"|"%yylexthrow{"|"%eofval{").*{NL}
                                     { string.setLength(0); yybegin(COPY); }
<COPY> {
  "%}".*{NL}                    { classCode = conc(classCode,string);  yybegin(MACROS);  }
  "%init}".*{NL}                { initCode = conc(initCode,string);    yybegin(MACROS);  }
  "%initthrow}".*{NL}           { initThrow = concExc(initThrow,string);  yybegin(MACROS); }
  "%eof}".*{NL}                 { eofCode = conc(eofCode,string); yybegin(MACROS); }
  "%eofthrow}".*{NL}            { eofThrow = concExc(eofThrow,string); yybegin(MACROS); }
  "%yylexthrow}".*{NL}          { lexThrow = concExc(lexThrow,string); yybegin(MACROS); }
  "%eofval}".*{NL}              { eofVal = string.toString(); yybegin(MACROS); }

  .*{NL}                        { string.append(yytext()); }

  <<EOF>>                       { throw new ScannerException(file,ErrorMessages.EOF_IN_MACROS); }
}


<MACROS> ^"%s" ("tate" "s"?)? {WSP}+   { inclusive_states = true; yybegin(STATELIST); }
<MACROS> ^"%x" ("state" "s"?)? {WSP}+  { inclusive_states = false; yybegin(STATELIST); }
<STATELIST> {
  {Ident}                             { states.insert(yytext(),inclusive_states); }
  ([\ \t]*","[\ \t]*)|([\ \t]+)       { }
  {NL}                                { yybegin(MACROS);  }
  <<EOF>>                       { throw new ScannerException(file,ErrorMessages.EOF_IN_MACROS); }
}

<MACROS> {
  "%char"                     { charCount = true;  }
  "%line"                     { lineCount = true;  }
  "%column"                   { columnCount = true; }
  "%byaccj"                   { isInteger = true;
                                if (eofVal == null)
                                  eofVal = "return 0;";
                                eofclose = true;
                              }
  "%cup"                      { cupCompatible = true;
                                isImplementing = concExc(isImplementing, "java_cup.runtime.Scanner");
                                if (functionName == null)
                                  functionName = "next_token";
                                if (tokenType == null)
                                  tokenType = "java_cup.runtime.Symbol";
                                if (eofVal == null)
                                  eofVal = "return new java_cup.runtime.Symbol("+cupSymbol+".EOF);";
                                if (!Options.jlex) eofclose = true;
                              }
  "%cupsym"{WSP}+{QualIdent} {WSP}*  { cupSymbol = yytext().substring(8).trim();
                                if (cupCompatible) Out.warning(ErrorMessages.CUPSYM_AFTER_CUP, yyline); }
  "%cupsym"{WSP}+{NNL}*       { throw new ScannerException(file,ErrorMessages.QUIL_CUPSYM, yyline); }
  "%cupdebug"                 { cupDebug = true; }
  "%eofclose"({WSP}+"true")?  { eofclose = true; }
  "%eofclose"({WSP}+"false")  { eofclose = false; }
  "%class"{WSP}+{ClassT} {WSP}*     { className = yytext().substring(7).trim();  }
  "%ctorarg"{WSP}+{ArrType}{WSP}+   { yybegin(CTOR_ARG); ctorTypes.add(yytext().substring(8).trim()); }
  "%function"{WSP}+{Ident} {WSP}*   { functionName = yytext().substring(10).trim(); }
  "%type"{WSP}+{ArrType} {WSP}*     { tokenType = yytext().substring(6).trim(); }
  "%integer"|"%int"           { isInteger = true;  }
  "%intwrap"                  { isIntWrap = true;  }
  "%yyeof"                    { isYYEOF = true;  }
  "%notunix"                  { notUnix = true;  }
  "%7bit"                     { isASCII = true; return symbol(ASCII); }
  "%full"|"%8bit"             { return symbol(FULL); }
  "%16bit"                    { populateDefaultVersionUnicodeProperties();
                                return symbol(UNICODE);
                              }
  "%unicode"({WSP}+{DottedVersion})? { String v = yytext().substring(8).trim();
                                       if (v.length() == 0) {
                                         populateDefaultVersionUnicodeProperties();
                                       } else {
                                         try {
                                           unicodeProperties = new UnicodeProperties(v);
                                         } catch (UnicodeProperties.UnsupportedUnicodeVersionException e) {
                                           throw new ScannerException
                                             (file, ErrorMessages.UNSUPPORTED_UNICODE_VERSION, yyline);
                                         }
                                       }
                                       return symbol(UNICODE);
                                     }

  "%caseless"|"%ignorecase"   { caseless = true; }
  "%implements"{WSP}+.*       { isImplementing = concExc(isImplementing, yytext().substring(12).trim());  }
  "%extends"{WSP}+{QClassT}{WSP}* { isExtending = yytext().substring(9).trim(); }
  "%public"                   { isPublic = true; }
  "%apiprivate"               { visibility = "private"; Skeleton.makePrivate(); }
  "%final"                    { isFinal = true; }
  "%abstract"                 { isAbstract = true; }
  "%debug"                    { debugOption = true; }
  "%standalone"               { standalone = true; isInteger = true; }
  "%switch"                   { packed = false; useRowMap = false; }
  "%table"                    { packed = false; useRowMap = true; }
  "%pack"                     { packed = true; useRowMap = true; }
  "%include" {WSP}+ .*        { File f = new File(file.getParentFile(), yytext().substring(9).trim());
                                if ( !f.canRead() )
                                  throw new ScannerException(file,ErrorMessages.NOT_READABLE, yyline);
                                // check for cycle
                                if (files.search(f) > 0)
                                  throw new ScannerException(file,ErrorMessages.FILE_CYCLE, yyline);
                                try {
                                  yypushStream( new FileReader(f) );
                                  files.push(file);
                                  file = f;
                                  Out.println("Including \""+file+"\"");
                                }
                                catch (FileNotFoundException e) {
                                  throw new ScannerException(file,ErrorMessages.NOT_READABLE, yyline);
                                }
                              }
  "%buffer" {WSP}+ {Number} {WSP}*   { bufferSize = Integer.parseInt(yytext().substring(8).trim()); }
  "%buffer" {WSP}+ {NNL}*     { throw new ScannerException(file,ErrorMessages.NO_BUFFER_SIZE, yyline); }
  "%initthrow" {WSP}+ {QUIL} {WSP}* { initThrow = concExc(initThrow,yytext().substring(11).trim()); }
  "%initthrow" {WSP}+ {NNL}*  { throw new ScannerException(file,ErrorMessages.QUIL_INITTHROW, yyline); }
  "%eofthrow"  {WSP}+ {QUIL} {WSP}*  { eofThrow = concExc(eofThrow,yytext().substring(10).trim()); }
  "%eofthrow"  {WSP}+ {NNL}*  { throw new ScannerException(file,ErrorMessages.QUIL_EOFTHROW, yyline); }
  "%yylexthrow"{WSP}+ {QUIL} {WSP}*  { lexThrow = concExc(lexThrow,yytext().substring(12).trim()); }
  "%throws"    {WSP}+ {QUIL} {WSP}*  { lexThrow = concExc(lexThrow,yytext().substring(8).trim()); }
  "%yylexthrow"{WSP}+ {NNL}*  { throw new ScannerException(file,ErrorMessages.QUIL_YYLEXTHROW, yyline); }
  "%throws"    {WSP}+ {NNL}*  { throw new ScannerException(file,ErrorMessages.QUIL_THROW, yyline); }
  "%scanerror" {WSP}+ {QualIdent} {WSP}* { scanErrorException = yytext().substring(11).trim(); }
  "%scanerror" {WSP}+ {NNL}*  { throw new ScannerException(file,ErrorMessages.QUIL_SCANERROR, yyline); }
// TODO: In the version of JFlex after 1.6, the %inputstreamctor directive will become a no-op: the InputStream ctor will never be emitted.  
  "%inputstreamctor"({WSP}+"true")? { emitInputStreamCtor = true; }  
  "%inputstreamctor"{WSP}+"false"   { emitInputStreamCtor = false; }

  {Ident}                     { return symbol(IDENT, yytext()); }
  "="{WSP}*                   { if (null == unicodeProperties && ! isASCII) {
                                  populateDefaultVersionUnicodeProperties();
                                }
                                yybegin(REGEXP); 
                                return symbol(EQUALS); 
                              }

  "/*"                        { nextState = MACROS; yybegin(COMMENT); }

  {EndOfLineComment}          { }

  /* no {NL} at the end of this expression, because <REGEXPSTART>
     needs at least one {WSPNL} to start a regular expression! */
  ^"%%" {NNL}*                { if (null == unicodeProperties && ! isASCII) {
                                  populateDefaultVersionUnicodeProperties();
                                }
                                macroDefinition = false; 
                                yybegin(REGEXPSTART);
                                return symbol(DELIMITER); 
                              }
  "%"{Ident}                  { throw new ScannerException(file,ErrorMessages.UNKNOWN_OPTION, yyline, yycolumn); }
  "%"                         { throw new ScannerException(file,ErrorMessages.UNKNOWN_OPTION, yyline, yycolumn); }
  ^{WSP}+"%"                  { Out.warning(ErrorMessages.NOT_AT_BOL, yyline); yypushback(1); }

  {WSP}+                      { }
  {NL}+                       { }
  <<EOF>>                     { if ( yymoreStreams() ) {
                                  file = (File) files.pop();
                                  yypopStream();
                                }
                                else
                                  throw new ScannerException(file,ErrorMessages.EOF_IN_MACROS);
                              }
}

<CTOR_ARG> {
  {Ident} {WSP}*   { yybegin(MACROS); ctorArgs.add(yytext().trim()); }
  [^]              { throw new ScannerException(file,ErrorMessages.CTOR_ARG,yyline,yycolumn); }
}

<REGEXPSTART> {
  {WSPNL}* "/*"               { nextState = REGEXPSTART; yybegin(COMMENT); }
  {WSPNL}+                    { yybegin(REGEXP); }
  {WSPNL}* "<"                { yybegin(STATES); return symbol_countUpdate(LESSTHAN, null); }
  {WSPNL}* "}"                { return symbol_countUpdate(RBRACE, null); }
  {WSPNL}* "//" {NNL}*        { }
  {WSPNL}* "<<EOF>>" {WSPNL}* "{"
                              { actionText.setLength(0); yybegin(JAVA_CODE);
                                Symbol s = symbol_countUpdate(EOFRULE, null);
                                action_line = s.left+1;
                                return s;
                              }
}

<STATES> {
  {Ident}                     { return symbol(IDENT, yytext()); }
  ","                         { return symbol(COMMA); }
  {WSPNL}+                    { }

  // "{" will be caught in REGEXP
  ">"{WSPNL}*                 { yybegin(REGEXP); return symbol(MORETHAN); }

  <<EOF>>                     { throw new ScannerException(file,ErrorMessages.EOF_IN_STATES); }
}


<REGEXP> {
  "<<EOF>>" {WSPNL}+ "{"  { actionText.setLength(0); yybegin(JAVA_CODE); action_line = yyline+1; return symbol(EOFRULE); }
  "<<EOF>>"               { throw new ScannerException(file,ErrorMessages.EOF_WO_ACTION); }

  {WSPNL}*"|"{WSP}*$      { if (macroDefinition) {
                              yybegin(EATWSPNL);
                              return symbol(BAR);
                            }
                            else {
                              yybegin(REGEXPSTART);
                              return symbol(NOACTION);
                            }
                          }

  // stategroup
  "{"           { yybegin(REGEXPSTART); return symbol(LBRACE); }

  {WSPNL}*"|"   { return symbol(BAR); }

  {WSPNL}*\"    { string.setLength(0); nextState = REGEXP; yybegin(STRING_CONTENT); }
  {WSPNL}*"!"   { return symbol(BANG); }
  {WSPNL}*"~"   { return symbol(TILDE); }
  {WSPNL}*"("   { return symbol(OPENBRACKET); }
  {WSPNL}*")"   { return symbol(CLOSEBRACKET); }
  {WSPNL}*"*"   { return symbol(STAR); }
  {WSPNL}*"+"   { return symbol(PLUS); }
  {WSPNL}*"?"   { return symbol(QUESTION); }
  {WSPNL}*"$"   { return symbol(DOLLAR); }
  {WSPNL}*"^"   { bolUsed = true; return symbol(HAT); }
  {WSPNL}*"."   { return symbol(POINT); }
  {WSPNL}*"\\R" { return symbol(NEWLINE); }
  {WSPNL}*"["   { yybegin(CHARCLASS); return symbol(OPENCLASS); }
  {WSPNL}*"/"   { return symbol(LOOKAHEAD); }
  
  {WSPNL}* "{" {WSP}* {Ident} {WSP}* "}" { return symbol_countUpdate(MACROUSE, makeMacroIdent()); }
  {WSPNL}* "{" {WSP}* {Number}   { yybegin(REPEATEXP); 
                                   return symbol(REPEAT, 
                                                 new Integer(yytext().trim().substring(1).trim())); 
                                 }

  {WSPNL}+ "{"    { actionText.setLength(0); yybegin(JAVA_CODE); action_line = yyline+1; return symbol(REGEXPEND); }
  {NL}            { if (macroDefinition) { yybegin(MACROS); } return symbol(REGEXPEND); }

  {WSPNL}*"/*"    { nextState = REGEXP; yybegin(COMMENT); }

  {WSPNL}*"//"{NNL}*  { }

  {WSP}+          { }

  <CHARCLASS> {
    {WSPNL}*"[:jletter:]"      { return symbol(JLETTERCLASS); }
    {WSPNL}*"[:jletterdigit:]" { return symbol(JLETTERDIGITCLASS); }
    {WSPNL}*"[:letter:]"       { return symbol(LETTERCLASS); }
    {WSPNL}*"[:uppercase:]"    { return symbol(UPPERCLASS); }
    {WSPNL}*"[:lowercase:]"    { return symbol(LOWERCLASS); }
    {WSPNL}*"[:digit:]"        { return symbol(DIGITCLASS); }
    {WSPNL}*"\\d"              { return symbol(DIGITCLASS); }
    {WSPNL}*"\\D"              { return symbol(DIGITCLASSNOT); }
    {WSPNL}*"\\s"              { return symbol(WHITESPACECLASS); }
    {WSPNL}*"\\S"              { return symbol(WHITESPACECLASSNOT); }
    {WSPNL}*"\\w"              { return symbol(WORDCLASS); }
    {WSPNL}*"\\W"              { return symbol(WORDCLASSNOT); }
    {WSPNL}*"\\p{"[^}]*"}"     { String trimmedText = yytext().trim();
                                 String propertyValue = trimmedText.substring(3,trimmedText.length()-1);
                                 IntCharSet set = unicodeProperties.getIntCharSet(propertyValue);
                                 if (null == set) {
                                   throw new ScannerException(file,ErrorMessages.INVALID_UNICODE_PROPERTY, yyline, yycolumn + 3);
                                 }
                                 return symbol(UNIPROPCCLASS, set);
                               }
    {WSPNL}*"\\P{"[^}]*"}"     { String trimmedText = yytext().trim();
                                 String propertyValue = trimmedText.substring(3,trimmedText.length()-1);
                                 IntCharSet set = unicodeProperties.getIntCharSet(propertyValue);
                                 if (null == set) {
                                   throw new ScannerException(file,ErrorMessages.INVALID_UNICODE_PROPERTY, yyline, yycolumn + 3);
                                 }
                                 return symbol(UNIPROPCCLASSNOT, set);
                               }
  }

  . { return symbol(CHAR, yytext().charAt(0)); }
}

<EATWSPNL> {WSPNL}+  { yybegin(REGEXP); }


<REPEATEXP> {
  "}"          { yybegin(REGEXP); return symbol(RBRACE); }
  "," {WSP}* {Number}  { return symbol(REPEAT, new Integer(yytext().substring(1).trim())); }
  {WSP}+       { }

  <<EOF>>                 { throw new ScannerException(file,ErrorMessages.EOF_IN_REGEXP); }
}

<CHARCLASS> {
  "{"{Ident}"}" { return symbol(MACROUSE, yytext().substring(1,yytext().length()-1)); }
  "["  { balance++; return symbol(OPENCLASS); }
  "]"  { if (balance > 0) balance--; else yybegin(REGEXP); return symbol(CLOSECLASS); }
  "^"  { return symbol(HAT); }
  "-"  { return symbol(DASH); }
  "--" { return symbol(DIFFERENCE); }
  "&&" { return symbol(INTERSECTION); }
  "||" { /* union is the default operation - '||' can be ignored */ }
  "~~" { return symbol(SYMMETRICDIFFERENCE); }

  // this is a hack to keep JLex compatibilty with char class
  // expressions like [+-]
  "-]" { yypushback(1); yycolumn--; return symbol(CHAR, yytext().charAt(0)); }

  \"   { string.setLength(0); nextState = CHARCLASS; yybegin(STRING_CONTENT); }

  .    { return symbol(CHAR, yytext().charAt(0)); }

  \n   { throw new ScannerException(file,ErrorMessages.EOL_IN_CHARCLASS,yyline,yycolumn); }

  <<EOF>>     { throw new ScannerException(file,ErrorMessages.EOF_IN_REGEXP); }
}

<STRING_CONTENT> {
  \"       { yybegin(nextState); return symbol(STRING, string.toString()); }
  \\\"     { string.append('\"'); }
  [^\"\\\u2028\u2029\u000A\u000B\u000C\u000D\u0085]+ { string.append(yytext()); }

  {NL}     { throw new ScannerException(file,ErrorMessages.UNTERMINATED_STR, yyline, yycolumn); }

  {HexNumber} { string.append( (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {Unicode4}  { string.append( (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {Unicode6}  { string.append( (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {OctNumber} { string.append( (char) Integer.parseInt(yytext().substring(1,yytext().length()), 8)); }

  \\b { string.append('\b'); }
  \\n { string.append('\n'); }
  \\t { string.append('\t'); }
  \\f { string.append('\f'); }
  \\r { string.append('\r'); }

  \\. { string.append(yytext().charAt(1)); }

  <<EOF>>     { throw new ScannerException(file,ErrorMessages.EOF_IN_STRING); }
}


<REGEXP, CHARCLASS> {
  {HexNumber} { return symbol(CHAR, (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {Unicode4}  { return symbol(CHAR, (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {Unicode6}  { return symbol(CHAR, (char) Integer.parseInt(yytext().substring(2,yytext().length()), 16)); }
  {OctNumber} { return symbol(CHAR, (char) Integer.parseInt(yytext().substring(1,yytext().length()), 8)); }

  \\b { return symbol(CHAR,'\b'); }
  \\n { return symbol(CHAR,'\n'); }
  \\t { return symbol(CHAR,'\t'); }
  \\f { return symbol(CHAR,'\f'); }
  \\r { return symbol(CHAR,'\r'); }

  \\. { return symbol(CHAR, yytext().charAt(1)); }
}


<JAVA_CODE> {
  "{"        { balance++; actionText.append('{'); }
  "}"        { if (balance > 0) {
                 balance--;
                 actionText.append('}');
               }
               else {
                 yybegin(REGEXPSTART);
                 Action a = new Action(actionText.toString(), action_line);
                 actions.add(a);
                 return symbol(ACTION, a);
               }
             }

  {JavaCode}     { actionText.append(yytext()); }

  <<EOF>>     { throw new ScannerException(file,ErrorMessages.EOF_IN_ACTION, action_line-1); }
}

<COMMENT> {

  "/"+ "*"  { commentbalance++; }
  "*"+ "/"  { if (commentbalance > 0)
                commentbalance--;
              else
                yybegin(nextState);
            }

  {JFlexComment} { /* ignore */ }

  <<EOF>>     { throw new ScannerException(file,ErrorMessages.EOF_IN_COMMENT); }
}


.  { throw new ScannerException(file,ErrorMessages.UNEXPECTED_CHAR, yyline, yycolumn); }
\n { throw new ScannerException(file,ErrorMessages.UNEXPECTED_NL, yyline, yycolumn); }

<<EOF>>  { if ( yymoreStreams() ) {
             file = (File) files.pop();
             yypopStream();
           }
           else
             return symbol(EOF); }