type
  Atom* = char | byte
  Ctx* = not (ref | void)

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

  # Transmute, transforms the capture stack in some way. Example: Squashing chars
  # into a single string.
  TransmuteProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] =
    proc(ctx: var ParserCtx[C, G, A, L], stack: var seq[seq[A]]): bool {.nimcall.}

  # https://www.reddit.com/r/MemeRestoration/comments/f32opt/
  AbsorbAndScryProc[C: Ctx, G: Ordinal, A: Atom, L: static bool] =
    proc(ctx: var ParserCtx[C, G, A, L]): bool {.nimcall.}

  ScryProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = AbsorbAndScryProc[C, G, A, L]

  AbsorbProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = AbsorbAndScryProc[C, G, A, L]
