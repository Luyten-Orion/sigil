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

  # Absorb, takes the stack, performs some action and consumes it.
  AbsorbProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] =
    distinct AbsorbAndScryProc[C, G, A, L]

  # Scry, lets you inspect the stack without consuming it.
  ScryProc*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = 
    distinct AbsorbAndScryProc[C, G, A, L]

func `==`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  a, b: AbsorbProc[C, G, A, L]
): bool = a == b

func `==`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  a, b: ScryProc[C, G, A, L]
): bool = a == b



converter toAbsorb*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: AbsorbAndScryProc[C, G, A, L]
): AbsorbProc[C, G, A, L] = AbsorbProc[C, G, A, L](p)
converter toScry*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: AbsorbAndScryProc[C, G, A, L]
): ScryProc[C, G, A, L] = ScryProc[C, G, A, L](p)