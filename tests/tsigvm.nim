import sigil/codex/ctypes
import sigil/sigvm
import sigil/sigir/compiler
import sigil/combinators

type TestCtx = object
  captured: seq[string]

type RB = RuleBuilder[TestCtx]

proc runTest(p: Rule[TestCtx], input: string): VmResult =
  let glyph = compile(p)
  var ctx = TestCtx()
  result = run(glyph, input, ctx)

block BasicExecution:
  let p = RB.define("Main", RB.match("hello"))
  let res = runTest(p, "hello")
  doAssert res.success
  doAssert res.matchLen == 5
  
  let resFail = runTest(p, "hell")
  doAssert not resFail.success

block InvertedChar:
  let p = RB.define("NotA", RB.noMatch('a'))

  let res = runTest(p, "b")
  doAssert res.success
  doAssert res.matchLen == 1

  let resFail = runTest(p, "a")
  doAssert not resFail.success
  doAssert "anything but 'a'" in resFail.expectedTerminals

block SetMatching:
  let digits = {'0'..'9'}
  let p = RB.define("Digit", RB.match(digits))
  
  let res = runTest(p, "7")
  doAssert res.success
  doAssert res.matchLen == 1

  let resFail = runTest(p, "a")
  doAssert not resFail.success
  doAssert "[0-9]" in resFail.expectedTerminals

block InvertedSet:
  let digits = {'0'..'9'}
  let p = RB.define("NotDigit", RB.noMatch(digits))

  let res = runTest(p, "a")
  doAssert res.success

  let resFail = runTest(p, "5")
  doAssert not resFail.success
  doAssert "anything but '[0-9]'" in resFail.expectedTerminals

block ChoiceBacktracking:
  let p = RB.define("Main", 
    (RB.match('a') and RB.match('b')) or 
    (RB.match('a') and RB.match('c'))
  )
  
  let res = runTest(p, "ac")
  doAssert res.success
  doAssert res.matchLen == 2

block Loops:
  let p = RB.define("Main", many0(RB.match('a')))
  let glyph = compile(p)
  var ctx = TestCtx()
  
  let res = run(glyph, "aaab", ctx)
  doAssert res.success
  doAssert res.matchLen == 3

block RecursionRuntime:
  let p = RB.define("P")
  
  let body = (RB.match('a') and call(p) and RB.match('a')) or RB.match('b')
  p.implement(body)
  
  let res1 = runTest(p, "b")
  doAssert res1.success
  
  let res2 = runTest(p, "aba")
  doAssert res2.success
  
  let res3 = runTest(p, "aabaa")
  doAssert res3.success
  
  let resFail = runTest(p, "aaba")
  doAssert not resFail.success

block PositiveLookahead:
  let p = RB.define("Main", 
    peek(RB.match('a')) and RB.match('a')
  )
  
  let res = runTest(p, "a")
  doAssert res.success
  doAssert res.matchLen == 1
  
  let resFail = runTest(p, "b")
  doAssert not resFail.success

block NegativeLookahead:
  let p = RB.define("Main", 
    reject(RB.match('a')) and RB.any()
  )
  
  let res = runTest(p, "b")
  doAssert res.success
  
  let resFail = runTest(p, "a")
  doAssert not resFail.success

block NestedLookaheadStackCleanliness:
  let inner = peek(RB.match('a'))
  let p = RB.define("Main", reject(inner))
  
  let res = runTest(p, "b")
  doAssert res.success

block Captures:
  let p = RB.define("Main", capture(RB.match('a')))
  
  let res = runTest(p, "a")
  doAssert res.success
  doAssert res.captures.len == 1
  doAssert res.captures[0] == "a"

block ActionExecution:
  proc myAction(ctx: var TestCtx, caps: seq[string]): bool =
    ctx.captured = caps
    return true

  let p = RB.define("Main", 
    capture(RB.match('a')) and action(RB.any(), myAction)
  )
  
  let glyph = compile(p)
  var ctx = TestCtx()
  let res = run(glyph, "ab", ctx)
  
  doAssert res.success
  doAssert ctx.captured.len == 1 
  doAssert ctx.captured[0] == "a"

block ActionFailureBacktracking:
  proc failAction(ctx: var TestCtx, caps: seq[string]): bool =
    return false

  let p = RB.define("Main", 
    (RB.match('a') and action(RB.any(), failAction)) or 
    (RB.match('a') and RB.match('b'))
  )

  let res = runTest(p, "ab")
  doAssert res.success
  doAssert res.matchLen == 2

block ErrorReporting:
  let p = RB.define("Main", RB.match('a') and RB.match('b'))
  let res = runTest(p, "ac")
  
  doAssert not res.success
  doAssert res.furthestFailureIdx == 1
  doAssert res.foundTerminal == "`c`" 
  doAssert "'b'" in res.expectedTerminals

block CustomErrorLabels:
  let p = RB.define("Main", errorLabel(RB.match('a'), "Expected Alpha"))
  
  let res = runTest(p, "b")
  doAssert not res.success
  
  doAssert res.foundTerminal == "`b`"
  doAssert "Expected Alpha" in res.expectedTerminals
  doAssert "'a'" notin res.expectedTerminals