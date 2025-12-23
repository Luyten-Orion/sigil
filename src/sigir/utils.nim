import sigil/sigir/types

func shiftAddresses*(insts: var seq[Instruction], offset: int) =
  for i in 0 ..< insts.len:
    if insts[i].op in {opJump, opChoice, opCommit, opCall}:
      insts[i].valTarget += offset

func sanitize*(s: string): string =
  result = s
  for c in result.mitems:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9'}:
      c = '_'