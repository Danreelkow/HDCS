Operator non-negotiables:
- Build two small CLI tools in /workspace/tools2/: a stopwatch and a countdown timer.
- Stopwatch takes no args and supports laps.
- Countdown takes minutes and seconds and prints a final message at zero.
- Keep them in separate files, make them testable, verify they actually run before done.
- Do not modify /workspace/tools/.

Rulings:
- Output redirected from task.md's legacy /workspace/tools/ to fresh /workspace/tools2/.
- S4 verifier: openai/gpt-5.6-luna via subagent_gpt; runtime did not expose a delegated session id. Gate verdict PASS.
