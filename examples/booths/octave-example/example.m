% example.m -- Simple GNU Octave demo

% Generate some data
rand("seed", 42);
x = 1:20;
y = 2 * x + 3 * randn(1, 20);

% Fit a polynomial (linear: degree 1)
p = polyfit(x, y, 1);
y_fit = polyval(p, x);

% Compute R-squared
ss_res = sum((y - y_fit).^2);
ss_tot = sum((y - mean(y)).^2);
r_squared = 1 - ss_res / ss_tot;

printf("=== Linear Regression Summary ===\n\n");
printf("  Slope:     %.3f\n", p(1));
printf("  Intercept: %.3f\n", p(2));
printf("  R-squared: %.3f\n", r_squared);

% Matrix operations
printf("\n=== Matrix Operations ===\n\n");
A = [1 2 3; 4 5 6; 7 8 10];
printf("Matrix A:\n");
disp(A);
printf("Determinant of A: %.3f\n", det(A));
printf("Inverse of A:\n");
disp(inv(A));

% Eigenvalue decomposition
[V, D] = eig(A);
printf("Eigenvalues:\n");
disp(diag(D));
