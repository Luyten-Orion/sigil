import std/[strutils, sets]
import sigil/[sigir, sigvm]
import common

block Actions:
  echo "Running Actions Test..."
  
  const actionParser = static:
    let g = newGrammar[TestContext]()
    
    let digit = g.match({'0'..'9'})
    
    let validateAndAdd: ActionProc[TestContext] = proc(c: var TestContext, caps: seq[string]): bool =
      if caps.len == 0: return false
      try:
        let val = parseInt(caps[0])
        if val >= 100: return false # Fail if >= 100
        c.count += val
        c.logs.add("Added " & $val)
        return true
      except: return false

    let num = capture(many1(digit)).action(validateAndAdd)
    
    # Allow comma separated numbers
    g.compile(sepBy(num, g.match(',')))

  # Success Case
  var ctx1 = TestContext()
  let res1 = run(actionParser, "10,20,5", ctx1)
  
  doAssert res1.success
  doAssert ctx1.count == 35, "Count should be 35, got: " & $ctx1.count
  doAssert ctx1.logs == @["Added 10", "Added 20", "Added 5"]
  doAssert res1.captures.len == 0, "Actions should consume captures"

  # Validation Failure Case
  var ctx2 = TestContext()
  # "200" fails validation. Parsing should stop after "10," or trigger backtrack logic.
  # Since sepBy is greedy, it parses "10", then ",", then fails on "200". 
  # It should succeed with just "10" (as the rest is optional repetitions).
  
  let res2 = run(actionParser, "10,200", ctx2)
  doAssert res2.success
  doAssert res2.matchLen == 2, "Should parse '10' (len 2), got: " & $res2.matchLen
  doAssert ctx2.count == 10, "Should only add 10"