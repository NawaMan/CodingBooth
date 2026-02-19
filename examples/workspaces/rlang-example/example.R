# example.R — Simple R demo

# Generate some data
set.seed(42)
x <- 1:20
y <- 2 * x + rnorm(20, sd = 3)

# Fit a linear model
model <- lm(y ~ x)

cat("=== Linear Regression Summary ===\n\n")
print(summary(model))

cat("\nCoefficients:\n")
cat(sprintf("  Intercept: %.3f\n", coef(model)[1]))
cat(sprintf("  Slope:     %.3f\n", coef(model)[2]))
cat(sprintf("  R-squared: %.3f\n", summary(model)$r.squared))
