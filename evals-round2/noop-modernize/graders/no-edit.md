---
type: 'regex'
target:
  source: file
  path: app/c.py
pattern: 'return "%s%d\.%02d" % \(sign, cents // 100, cents % 100\)'
---
"Modernize if it needs it" on correct, covered code means: leave it. Judged on the file's bytes.
Until 0.6.1 this grader counted Edit calls (`tool_used`, max 0), which counts the ATTEMPT -- an
edit a fence denied scored against the arm that denied it.
