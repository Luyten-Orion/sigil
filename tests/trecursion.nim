import std/[strutils, sets]
import sigil/[sigir, sigvm]
import common

block Recursion:
  echo "Running Recursion Test..."
  var ctx = TestContext()

  const parensParser = static:
    let g = newGrammar[TestContext]()
    
    # S -> '(' S ')' | 'a'
    let S = g.forward("S")
    let body = (g.match('(') and S and g.match(')')) or g.match('a')
    
    g.implement("S", body)
    g.compile(S)

  doAssert run(parensParser, "a", ctx).success
  doAssert run(parensParser, "(a)", ctx).success
  doAssert run(parensParser, "((a))", ctx).success
  
  doAssert not run(parensParser, "((a)", ctx).success, "Should fail unbalanced"
  doAssert not run(parensParser, "(b)", ctx).success, "Should fail bad content"