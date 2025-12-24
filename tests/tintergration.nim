import std/[strutils, sets]
import sigil/[sigir, sigvm]
import common

block Integration:
  echo "Running Integration Test..."
  
  const jsonParser = static:
    let g = newGrammar[TestContext]()
    
    let ws = many0(g.match({' ', '\t'}))
    let comma = g.match(',') and ws
    let lbracket = g.match('[') and ws
    let rbracket = g.match(']') and ws
    
    let digit = g.match({'0'..'9'})
    let number = capture(many1(digit)).action(
      proc(c: var TestContext, caps: seq[string]): bool =
        c.logs.add("ParsedNum:" & caps[0])
        return true
    )

    let arrayRule = lbracket and sepBy(number, comma) and ws and rbracket
    
    g.compile(arrayRule)
    
  var jCtx = TestContext()
  let input = "[ 1, 22, 333 ]"
  let res = run(jsonParser, input, jCtx)
  
  doAssert res.success, "Parse failed. Error at " & $res.furthestFailureIdx & " Found: " & res.foundTerminal
  doAssert res.matchLen == input.len
  doAssert jCtx.logs == @["ParsedNum:1", "ParsedNum:22", "ParsedNum:333"]
  
  # Error Case
  let resErr = run(jsonParser, "[ 1, 2 ", jCtx)
  doAssert not resErr.success
  # Expect closing bracket or comma
  doAssert "']'" in resErr.expectedTerminals or "',' " in resErr.expectedTerminals