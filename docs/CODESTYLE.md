# Code Style Guide

This document captures coding preferences for this project to help future AI agents get started quickly.

## General Philosophy

- **Not aiming for perfection** - Balance quality with pragmatism
- **Minimal but sufficient** - Document and test what's necessary, not everything
- **Clarity over cleverness** - Code should be readable and maintainable

## Go-Specific Preferences

### Variable Naming

**Avoid single-letter variables** - Use descriptive names instead of Go's conventional single letters:

```go
// ❌ Avoid
func (l List[T]) Get(i int) (T, bool)

// ✅ Prefer
func (thisList List[TYPE]) Get(index int) (TYPE, bool)
```

**Naming conventions:**
- Generic type parameters: `TYPE` (not `T`)
- Receiver variables: `thisList`, `thisBuilder` (not `l`, `a`)
- Loop variables: `index`, `value` (not `i`, `v`)
- Function parameters: `fn` (not `f`)

### File Organization

**One type per file** - Similar to Java's one-class-per-file:
- `list.go` → `List` type and methods
- `appendable_list.go` → `AppendableList` type and methods
- Use snake_case for multi-word filenames: `appendable_list.go`

**Matching test files:**
- `list_test.go` → tests for `List`
- `appendable_list_test.go` → tests for `AppendableList`
- `api_test.go` → API-level integration tests
- `example_test.go` → documentation examples

### Documentation

**Minimal but clear** - One-liner comments for each public method:

```go
// ✅ Good - concise and clear
// Length returns the number of elements in the list.
func (thisList List[TYPE]) Length() int

// ❌ Too verbose - avoid explaining obvious behavior
// Length returns the number of elements in the list.
// This method has O(1) time complexity and is safe to call
// on empty lists. It will never return a negative value.
func (thisList List[TYPE]) Length() int
```

**Document surprises only:**
- Panic behavior: `// At panics if index is out of bounds.`
- Early termination: `// Range stops early if fn returns false.`
- Gotchas: `// Note: To create from a slice, use NewListFromSlice...`
- Reasoning: Explain *why* when the decision isn't obvious

### Method Naming

**Descriptive and symmetric:**
- `Length()` not `Len()` - spell it out
- `ExtendBySlice()` and `ExtendByList()` - symmetric naming makes intent clear
- Avoid abbreviations unless universally understood

### Testing

**Essential coverage only** - Test what matters:

**✅ Keep:**
- Deep copy verification (prevent aliasing bugs)
- Core functionality (snapshot immutability, clone independence)
- Edge cases that could fail (bounds checking, panic behavior)
- Real-world workflows (Docker args pattern)

**❌ Remove:**
- Obvious behavior what will be tested by other tests (basic append, length checks) (except sanity checks)
- Redundant tests (empty lists, single elements)
- Duplicate coverage (multiple tests for same concept)

**Test organization:**
- Group tests by type in matching test files
- Keep API tests and examples in separate files for clarity

## Package Structure

```
cli/src/pkg/packagename/
├── type_name.go              # One type per file
├── type_name_test.go         # Tests for that type
├── api_test.go               # API-level tests
└── example_test.go           # Documentation examples
```

## Comments

- Package-level: Brief overview of purpose and types
- Type-level:    Usually not needed if name is clear
- Method-level:  One-liner describing what it does
- Inline:        Only for non-obvious logic

## Summary

**Key principles:**
1. Descriptive names over Go conventions (no single letters)
2. One type per file (Java-style organization)
3. Minimal documentation (one-liners, document surprises)
4. Essential testing (quality over quantity)
5. Clarity and maintainability first
