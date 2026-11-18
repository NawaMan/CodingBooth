% Primes up to 30, in Prolog.
prime(N) :-
    N > 1,
    \+ ( between(2, N, D), D * D =< N, N mod D =:= 0 ).

main :-
    findall(N, (between(2, 30, N), prime(N)), Primes),
    atomic_list_concat(Primes, ' ', Text),
    format("Prolog: ~w~n", [Text]).
