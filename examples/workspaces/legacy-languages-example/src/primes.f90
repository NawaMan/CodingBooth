! Primes up to 30, in Fortran 90.
program primes
  implicit none
  integer :: n, d
  logical :: is_prime

  write(*, '(a)', advance='no') 'Fortran:'
  do n = 2, 30
    is_prime = .true.
    d = 2
    do while (d * d <= n)
      if (mod(n, d) == 0) is_prime = .false.
      d = d + 1
    end do
    if (is_prime) write(*, '(1x,i0)', advance='no') n
  end do
  write(*, *)
end program primes
