import std/[sequtils, sets]
import sigil
import sigil/codex
import sigil/codex/ctypes
import sigil/combinators
import sigil/executors/tree

type 
  TestCtx = object
    captured: seq[string]

  TestGroups = enum tgNone, tgVal

  # Some aliases
  RB = RuleBuilder[TestCtx, TestGroups, char, true]
  MyCtx = ParserCtx[TestCtx, TestGroups, char, true]
  MyRule = Rule[TestCtx, TestGroups, char, true]
  MyEnv = ExecEnv[TestCtx, TestGroups, char, true]

# Simple helper
template runTest(
  p: MyRule, 
  inputStr: string
): (bool, MyEnv) =
  let codex = p.builder.finalise()
  var env = MyEnv(
    input: @inputStr,
    ctx: MyCtx()
  )
  let exe = newExecutor(codex)
  let success = exe.dispatch(env, codex[p.id].entry)
  (success, env)

# Tests
block BasicExecution:
  let p = RB.define("Main", RB.match("hello"))
  let (success, env) = runTest(p, "hello")
  doAssert success
  doAssert env.ctx.cursorPos == 5
  
  let (failSuccess, _) = runTest(p, "hell")
  doAssert not failSuccess

block InvertedChar:
  let p = RB.define("NotA", RB.noMatch('a'))
  let (success, env) = runTest(p, "b")
  doAssert success
  doAssert env.ctx.cursorPos == 1

  let (failSuccess, failEnv) = runTest(p, "a")
  doAssert not failSuccess
  doAssert "Not a" in failEnv.expectedLabels

block SetMatching:
  let p = RB.define("Digit", RB.match({'0'..'9'}))
  let (success, _) = runTest(p, "7")
  doAssert success

  let (failSuccess, failEnv) = runTest(p, "a")
  doAssert not failSuccess
  # The tree executor uses the same pretty-printing for sets
  doAssert "[0-9]" in failEnv.expectedLabels

block ChoiceBacktracking:
  let p = RB.define("Main", 
    (RB.match('a') and RB.match('b')) or 
    (RB.match('a') and RB.match('c'))
  )
  let (success, env) = runTest(p, "ac")
  doAssert success
  doAssert env.ctx.cursorPos == 2

block Loops:
  let p = RB.define("Main", many0(RB.match('a')))
  let (success, env) = runTest(p, "aaab")
  doAssert success
  doAssert env.ctx.cursorPos == 3

block RecursionRuntime:
  let p = block:
    var r = RB.define("P")
    let body = (RB.match('a') and r.call() and RB.match('a')) or RB.match('b')
    r.implement(body)
    r
  
  doAssert runTest(p, "b")[0]
  doAssert runTest(p, "aba")[0]
  doAssert runTest(p, "aabaa")[0]
  doAssert not runTest(p, "aaba")[0]

block PositiveLookahead:
  let p = RB.define("Main", peek(RB.match('a')) and RB.match('a'))
  let (success, env) = runTest(p, "a")
  doAssert success
  doAssert env.ctx.cursorPos == 1

block NegativeLookahead:
  let p = RB.define("Main", reject(RB.match('a')) and RB.any())
  doAssert runTest(p, "b")[0]
  doAssert not runTest(p, "a")[0]

block Siphoning:
  let p = RB.define("Main", RB.match('a').siphon(tgVal))
  let (success, env) = runTest(p, "a")
  doAssert success
  doAssert env.ctx.channels[tgVal].len == 1
  doAssert env.ctx.channels[tgVal][0] == @['a']

block AbsorbExecution:
  proc myAbsorb(ctx: var MyCtx): bool =
    for cap in ctx.channels[tgVal]:
      ctx.ext.captured.add(cast[string](cap))
    return true

  let p = RB.define("Main", 
    RB.match('a').siphon(tgVal).absorb(myAbsorb.AbsorbProc)
  )
  let (success, env) = runTest(p, "ab")
  doAssert success
  doAssert env.ctx.ext.captured[0] == "a"

block AbsorbFailureBacktracking:
  proc failAbsorb(ctx: var MyCtx): bool = false
  let p = RB.define("Main", 
    (RB.match('a').absorb(failAbsorb.AbsorbProc)) or 
    (RB.match('a') and RB.match('b'))
  )
  let (success, env) = runTest(p, "ab")
  doAssert success
  doAssert env.ctx.cursorPos == 2

block ErrorReporting:
  let p = RB.define("Main", RB.match('a') and RB.match('b'))
  let (success, env) = runTest(p, "ac")
  doAssert not success
  doAssert env.furthestFailureIdx == 1
  # The tree executor provides the expected terminals in expectedLabels
  doAssert "b" in env.expectedLabels

block CustomErrorLabels:
  let p = RB.define("Main", errorLabel(RB.match('a'), "Expected Alpha"))
  let (success, env) = runTest(p, "b")
  doAssert not success
  doAssert "Expected Alpha" in env.expectedLabels
  # Check that the label overrides the default terminal message
  doAssert "a" notin env.expectedLabels 