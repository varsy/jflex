%%

%unicode 6.2
%public
%class UnicodeCompatibilityProperties_graph_6_2

%type int
%standalone

%include ../../resources/common-unicode-all-binary-property-java

%%

\p{graph} { setCurCharPropertyValue(); }
[^] { }

<<EOF>> { printOutput(); return 1; }
