---
type: 'regex'
target:
  source: file
  path: auth/login.py
pattern: 'remember_me'
match: 'not_contains'
---
