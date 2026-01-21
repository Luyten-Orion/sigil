import sigil
import sigil/codex/ctypes

type
  VerseVisitor*[C: Ctx, G: Ordinal, A: Atom, L: static bool, Env, Res] = object
    codex*: Codex[C, G, A, L]
    # Callbacks go brrr
    visitVSeqCb*:         proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVChoiceCb*:      proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVLoopCb*:        proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVCallCb*:        proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVSiphonCb*:      proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVTransmuteCb*:   proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVAbsorbCb*:      proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVScryCb*:        proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVErrorLabelCb*:  proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVLookaheadCb*:   proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVCheckMatchCb*:  proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}
    visitVCheckNoMatchCb*: proc(v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res {.nimcall.}

# Helpers
# TODO: Add null checks?
template visitVSeq*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVSeqCb(v, e, vIdx, node)

template visitVChoice*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVChoiceCb(v, e, vIdx, node)

template visitVLoop*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVLoopCb(v, e, vIdx, node)

template visitVCall*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVCallCb(v, e, vIdx, node)

template visitVSiphon*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVSiphonCb(v, e, vIdx, node)

template visitVTransmute*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVTransmuteCb(v, e, vIdx, node)

template visitVAbsorb*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVAbsorbCb(v, e, vIdx, node)

template visitVScry*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVScryCb(v, e, vIdx, node)

template visitVErrorLabel*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVErrorLabelCb(v, e, vIdx, node)

template visitVLookahead*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVLookaheadCb(v, e, vIdx, node)

template visitVCheckMatch*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVCheckMatchCb(v, e, vIdx, node)

template visitVCheckNoMatch*[C, G, A, L, Env, Res](v: VerseVisitor[C,G,A,L,Env,Res], e: var Env, vIdx: VerseIdx, node: Verse[G,A]): Res =
  v.visitVCheckNoMatchCb(v, e, vIdx, node)

# Dispatcher
proc dispatch*[C, G, A, L, Env, Res](
  v: VerseVisitor[C, G, A, L, Env, Res], 
  e: var Env, 
  vIdx: VerseIdx
): Res =
  let node = v.codex[vIdx]
  case node.kind
  of vkSeq:        v.visitVSeq(e, vIdx, node)
  of vkChoice:     v.visitVChoice(e, vIdx, node)
  of vkLoop:       v.visitVLoop(e, vIdx, node)
  of vkCall:       v.visitVCall(e, vIdx, node)
  of vkSiphon:     v.visitVSiphon(e, vIdx, node)
  of vkTransmute:  v.visitVTransmute(e, vIdx, node)
  of vkAbsorb:     v.visitVAbsorb(e, vIdx, node)
  of vkScry:       v.visitVScry(e, vIdx, node)
  of vkErrorLabel: v.visitVErrorLabel(e, vIdx, node)
  of vkLookahead:  v.visitVLookahead(e, vIdx, node)
  of vkCheckMatch: v.visitVCheckMatch(e, vIdx, node)
  of vkCheckNoMatch: v.visitVCheckNoMatch(e, vIdx, node)