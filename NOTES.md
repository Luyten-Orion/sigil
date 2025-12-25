# Notes
## Potential IR Optimisations
A list of potential IR optimisations that could be done once
there's enough/big enough optimisations that make it worth it.
- Merge `{opChar,opStr} + {opChar,opStr}` into a single `opStr`.

## TODOs
- [x] Move `sigir/combinators` into a separate module with a
  higher-level descriptive AST so we can perform left-recursive
  elimination.
- [x] Make 'actionPool' for `ParserBuilder` so `Instruction`s
  don't require a generic parameter.
- [ ] Implement one of the parsers implemented in the stdlb, from
  scratch, and make a benchmark.
- [ ] Implement Codex transformation API:
  - Primary usecase: Left recursive elimination pass
  - Secondary usecase: Performing minor optimisations when possible
- [ ] Implement **capture groups**.
  - Capture groups would restrict what captured text a given parser
    has access to. This would be useful for 'sandboxing' parsers,
    so that complex parsers could be freely moved around without
    breaking everything due to simply adding a new `capture` rule.
