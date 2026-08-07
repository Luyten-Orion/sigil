type
  Atom* = char | byte
  Ctx* = not (ptr | ref | void  | pointer)

  ParserCtx*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    ## `C`: User-defined context object for their parser
    ## `G`: Capture group ordinal, aka an enum (`int` works but rip memory)
    ## `A`: Atom type
    ## `L`: Enable line tracking (only really applicable to `char` parsers tbh)
    ext*: C
    channels*: array[G, seq[seq[A]]]
    cursorPos*: int
    when L:
      column*: int  # Current column
      line*: int    # Current line
      lastCr*: bool # If it ended with a carriage return (so `'\n' | '\r' ('\n')?`)

  # Perform an 
  ActProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] =
    proc(ctx: var ParserCtx[C, G, A, L]): bool {.nimcall.}