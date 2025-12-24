type
  Ctx* = not (ref | void)
  # Accepts a mutable context and the currently captured strings
  ActionProc*[C: Ctx] = proc(ctx: var C, captures: seq[string]): bool {.nimcall.}