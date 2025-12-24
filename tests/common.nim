import sigil/sigvm

type TestContext* = object
  count*: int
  logs*: seq[string]

proc reset*(c: var TestContext) =
  c.count = 0
  c.logs = @[]

# Helper to print VmResult on failure
func `$`*(res: VmResult): string =
  if res.success: "Success(len=" & $res.matchLen & ")"
  else: "Failure(idx=" & $res.furthestFailureIdx & ", expected=" & $res.expectedTerminals & ", found=" & res.foundTerminal & ")"