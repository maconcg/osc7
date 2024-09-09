# OSC-7 support for bash and pdksh

The files in this repository provide robust implementations of OSC-7 output support for the two shells I use willingly: the ubiquitous [GNU Bash](https://tiswww.case.edu/php/chet/bash/bashtop.html) and OpenBSD's [`ksh(1)`](https://man.openbsd.org/ksh.1), a.k.a. `pdksh`.  This helps the program running your shell (e.g., Emacs or a conventional terminal emulator) keep track of the shell's working directory.

By “robust,” I mean it works with all reasonable directory names and most unreasoanble names.  For now, you can break it by changing to, say, a directory whose name is just the carriage return character.

## Overview

### What is OSC-7?

First, some terminology:
  - “__OSC__” stands for “operating system command”.  Somewhat cryptically defined in [ECMA-48 standard](https://ecma-international.org/publications-and-standards/standards/ecma-48), it's essentially a convention that a (typically interactive) process can use to send messages intended ”for operating system use.”  “Operating system use” is a term broad enough to cause confusion, but in our case it just means “for use by the program running the shell.”
    
  - “__OSC-7__” refers to a kind of OSC message used to communicate a process's working directory.  As of writing, it isn't described by ECMA-48 or any other “official” document but there's been [some discussion](https://gitlab.freedesktop.org/terminal-wg/specifications/-/issues/20) on that.

If the program running the interactive shell session knows the working directory of the shell process, it can use this information in a variety of helpful ways.  For example, a conventional terminal emulator might set its frame title to reflect the shell's working directory.  Emacs can use this information to set the current window's `default-directory`, thereby helping functions like `dired` (`C-x d`) “do the right thing” when run from a shell window.

Alternative methods for keeping track of the interactive shell's working directory are generally lacking.  These methods include, for example, watching for `cd` commands to parse, or including the arbitrarily-long path in the user-visible prompt.  Compared to OSC-7 messages, the alternatives I've encountered are less reliable and sometimes require the user to tolerate significant inconveniences (e.g., prompts that span most of the terminal width, forking a sed process forking every time you run a command).

### How do I use this?

You'll typically want to load these functions when you start interactive shell session.  For `bash`, you would either
  - copy the function definitions from `osc7.bash` to your `~/.bashrc` file.
  - “include” the functions via the `source`/`.` builtin.

For `pdksh`, you would either
  - copy the function definitions from `osc7.ksh` to your `ENV` file (there's no default value).
  - “include” the functions via the `.` builtin.

Once you've set up the shell (the _producer_ of the messages), you'll likely need to set up the _consumer_.  If the OSC-7 message were a baseball, the pitcher would be the shell and the catcher would be the program under which you're running the shell.

I'll eventually add some info on setting up the consumer (for me, the most important is Emacs).

## Why is this the best implementation?

The main goal of my approach is reliability.  Ideally, the consuming program should never fall out of sync with the shell's working directory, even in corner cases like `cd $(mktemp -d)`, changing directories via aliases, etc.

The secondary goal is to have implementations that I can treat as _black-box abstractions_.  I don't want to keep track of shell-specific quirks, and I want using this after I forget how it works.

Subordinate goals include:
1. Accommodate nonstandard characters.
  - The “body” of an OSC-7 message is a [percent-encoded](https://en.wikipedia.org/wiki/Percent-encoding) [file URI](https://en.wikipedia.org/wiki/File_URI_scheme).  This means that in order to accommodate less-common characters in path names, we need to tell the shell how to perform that transformation.  In `ksh`, this is made more difficult by the lack of a `printf` builtin, which would facilitate hexadecimal conversion.  My solution is to call in ([`vis(1)`](https://man.openbsd.org/vis.1) for help transforming such characters.

2. Avoid forking “helper” processes.
  - This keeps the process tree simpler and cuts down on “noise” when you're watching for execs via, say, [`ktrace(1)`](https://man.openbsd.org/ktrace.1).  Fewer dependencies is generally conducive to portability.

  - Before I tested this, I guessed that the most efficient implementation would be the one that never forks other processes.  This guess was wrong; the `pdksh` implementation is faster.  Note the 18 forked `vis(1)` processes:
```
$ ktrace -di -tx time ksh osc7.test >/dev/null
        0.11 real         0.02 user         0.09 sys
$ kdump | grep -c /usr/bin/vis
18
$ ktrace -di -tx time bash osc7.test >/dev/null
        0.47 real         0.07 user         0.31 sys
$ kdump
 41328 ktrace   ARGS  
	[0] = "time"
	[1] = "bash"
	[2] = "osc7.test"
 39766 time     ARGS  
	[0] = "bash"
	[1] = "osc7.test"
```
 
In a vast majority of cases, I only navigate directories that stick to the ASCII character set, which means there's no need to fork.

Happy accidents include:
1. The `bash` implementation doesn't use `PROMPT_COMMAND`.  `PROMPT_COMMAND` is the obvious way to implement this stuff and had served me well for a year or so.  But `pdksh` doesn't provide `PROMPT_COMMAND`, so I had to make this work in its absence.  Turns out the same general approach that works for `pdksh` works for `bash`, so you're free to use `PROMPT_COMMAND` for something else.

## Bugs
It's hard to tell whether a given bug should be attributed to the producer (i.e., this implementation) or the consumer.  Testing this implementation against multiple consumers would help there.  With that said, I've managed to cause problems via unreasonably-named directories (e.g., ending the directory name with a carriage return or a newline).
