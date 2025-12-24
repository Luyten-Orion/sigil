# Notes
## Potential IR Optimisations
A list of potential IR optimisations that could be done once
there's enough/big enough optimisations that make it worth it.
- Merge `{opChar,opStr} + {opChar,opStr}` into a single `opStr`.
- Merge `{opExceptChar,opExceptStr} + {opExceptChar,opExceptStr}`
  into a single `opExceptStr`.

## TODOs
- Implement one of the parsers implemented in the stdlb, from
  scratch, and make a benchmark.
- Move `sigir/combinators` into a separate module with a
  higher-level descriptive AST so we can perform left-recursive
  elimination.
- Make 'actionPool' for `ParserBuilder` so `Instruction`s
  don't require a generic parameter.