%%

%unicode 6.1
%public
%class UnicodeDecimalDigit3_6_1

%type int
%standalone

%include ../../resources/common-unicode-all-enumerated-property-java

%%

<<EOF>> { printOutput(); return 1; }
\d { setCurCharPropertyValue("Nd"); }
[^\d] { setCurCharPropertyValue("Not-Nd"); }
