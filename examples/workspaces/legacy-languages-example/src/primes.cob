      * Primes up to 30, in COBOL.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PRIMES.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 N         PIC 99.
       01 D         PIC 99.
       01 Q         PIC 99.
       01 R         PIC 99.
       01 IS-PRIME  PIC 9.
       01 N-DISP    PIC Z9.
       01 LINE-OUT  PIC X(80) VALUE "COBOL:".
       01 PTR       PIC 99 VALUE 7.
       PROCEDURE DIVISION.
           PERFORM VARYING N FROM 2 BY 1 UNTIL N > 30
               MOVE 1 TO IS-PRIME
               PERFORM VARYING D FROM 2 BY 1 UNTIL D * D > N
                   DIVIDE N BY D GIVING Q REMAINDER R
                   IF R = 0
                       MOVE 0 TO IS-PRIME
                   END-IF
               END-PERFORM
               IF IS-PRIME = 1
                   MOVE N TO N-DISP
                   STRING " " DELIMITED BY SIZE
                          FUNCTION TRIM(N-DISP) DELIMITED BY SIZE
                          INTO LINE-OUT WITH POINTER PTR
               END-IF
           END-PERFORM
           DISPLAY FUNCTION TRIM(LINE-OUT)
           STOP RUN.
