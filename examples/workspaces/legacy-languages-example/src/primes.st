"Primes up to 30, in Smalltalk (Pharo)."
| primes out |
primes := (2 to: 30) select: [ :n | (2 to: n sqrtFloor) allSatisfy: [ :d | n \\ d ~= 0 ] ].
out := Stdio stdout.
out nextPutAll: 'Smalltalk:'.
primes do: [ :p | out nextPutAll: ' ', p printString ].
out lf; flush.
