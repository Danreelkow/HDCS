# task: cli-stopwatch-countdown

reg := cs-programming; canon := POSIX CLI behavior, Python standard library, subprocess acceptance.

intent := Build two small testable CLI tools in `/workspace/tools/`: stopwatch (no args, lap support) ∧ countdown (minutes + seconds, final message at zero).
acceptance := files separate; executable; stopwatch no args; lap input works; countdown validates M:S; zero emits final message; smoke tests pass.
A-laws: A1 preserve separate files; A2 no external dependencies; A3 test behavior via subprocess.
