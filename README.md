# OSC-7 support for bash and pdksh
The files in this repository provide robust implementations of OSC-7 output support for the two shells I use willingly: the ubiquitous [GNU Bash](https://tiswww.case.edu/php/chet/bash/bashtop.html) and OpenBSD's [`ksh(1)`](https://man.openbsd.org/ksh.1), a.k.a. `pdksh`.  This helps the program running your shell (e.g., Emacs or a conventional terminal emulator) keep track of the shell's working directory.  A generic term for this functionality is _directory tracking_.

## Jargon
  - __OSC__ stands for _operating system command_.  Somewhat cryptically defined in the [ECMA-48 standard](https://ecma-international.org/publications-and-standards/standards/ecma-48/), it's essentially a convention that a process can use to send messages intended ”for operating system use.”  “Operating system use” is a term so broad it may cause confusion.  In our case, it just means “for use by the program running the shell.”

  - __OSC-7__ refers to a kind of OSC message used to communicate a process's working directory.  As of writing, it isn't described by ECMA-48 or any other “official” document, but there's been [some discussion](https://gitlab.freedesktop.org/terminal-wg/specifications/-/issues/20) on that.

  - The __producer__ process sends an OSC-7 message to its __consumer__ process.  The __consumer__ process uses the information contained in that message to provide some functionality.  Below are some clarifying examples:

```
  PID  PPID COMMAND
    1     0 /sbin/init
64722     1 -ksh (ksh)
```
Unambiguously, this example's producer is `ksh` and its potential consumer is `init`.  For decades, this was the _only_ common use case.  There's not much need for OSC-7 messages in this case; the shell's only ancestor is `init`, which is owned by `root`, who can use other means to obtain the working directory of a process.


```
  PID  PPID COMMAND
36913     1 - /usr/X11R6/bin/xenodm
30368 36913 |-- /usr/X11R6/bin/X
40411 36913 `-- xenodm
20582 40411   `-- /bin/sh /etc/X11/xenodm/Xsession
 3993 20582     `-- /usr/X11R6/bin/cwm
16388  3993       `-- emacs
13058 16388         `-- /bin/ksh -i
```
A more typical modern use case shows the shell running under a graphical Emacs process.  OSC-7 messages are especially useful in this scenario because Emacs can use the shell's working directory in many ways.  In our context, we can abstract away all ancestors consumer process.  The relevant lines from this example, then, are these:

```
  PID  PPID COMMAND
16388  3993       `-- emacs
13058 16388         `-- /bin/ksh -i
```
The idea of a consumer process is an abstraction; ideally, the OSC-7 messages the shell would send in this example should be the same as the messages it would send in this example:

```
  PID  PPID COMMAND
40178  3993       `-- /usr/X11R6/bin/xterm
13058 40178         `-- /bin/ksh -i
```
The idea of a producer process is also an abstraction.  Once we've respectively told `bash` and `ksh` how to send OSC-7 messages, we can swap one shell for the other:

```
  PID  PPID COMMAND
16388  3993       `-- emacs
46402 16388         `-- bash -i
```

## Overview
### Benefits
A consumer that knows the producer's working directory can do many helpful things with this information.  A conventional terminal emulator might set its frame title to reflect the shell's working directory.  Emacs might use this information to set the current window's `default-directory`, thus helping `dired` “do what you mean” when run from a shell window.

### Goals
The main goal of my approach is reliability.  Ideally, the consuming program should never fall out of sync with the shell's working directory, even in corner cases like `cd $(mktemp -d)`, changing directories via aliases, etc.

The secondary goal is to have implementations that I can treat as _black-box abstractions_.  I don't want to keep track of shell-specific quirks, and I want using this after I forget how it works.

Subordinate goals include:
1. Accommodate nonstandard characters.
  - The “body” of an OSC-7 message is a [percent-encoded](https://en.wikipedia.org/wiki/Percent-encoding) [file URI](https://en.wikipedia.org/wiki/File_URI_scheme).  This means that in order to accommodate less-common characters in path names, we need to tell the shell how to perform that transformation.  In `ksh`, this is made more difficult by the lack of a `printf` builtin, which would facilitate hexadecimal conversion.  My solution is to call in ([`vis(1)`](https://man.openbsd.org/vis.1) for help transforming such characters.

2. Avoid forking “helper” processes.
  - This keeps the process tree simpler and cuts down on “noise” when you're watching for execs via, say, [`ktrace(1)`](https://man.openbsd.org/ktrace.1).  Having fewer dependencies is generally conducive to portability.

### Alternatives
The classic approach, which developed in contexts like the first example shown above, is to do nothing.  For such use cases, this makes perfect sense.

One approach (used by default in [`shell-mode`](https://www.gnu.org/software/emacs/manual/html_node/emacs/Directory-Tracking.html) as of Emacs 29.4) is to have the consumer watch the user's input for well-known directory-changing commands.  This fails when you change directories via some mechanism not anticipated by the watcher (examples: `cd $(mktemp -d)`, `alias ugh='cd /usr'`).

Another approach is to embed the working directory in the user-visible shell prompt.  This can work in theory and in practice, but may result in abominations like this:
`[username@hostname /usr/src/gnu/llvm/llvm/utils/gn/secondary/clang/include/clang/StaticAnalyzer/Checkers] $ `

## How do I use this?
You'll typically want to load these functions when you start interactive shell session.  For `bash`, you would either
  - copy the function definitions from `osc7.bash` to your `~/.bashrc` file.
  - “include” the functions via the `source`/`.` builtin.

For `pdksh`, you would either
  - copy the function definitions from `osc7.ksh` to your `ENV` file (there's no default value).
  - “include” the functions via the `.` builtin.

Once you've set up the shell (the _producer_ of the messages), you'll likely need to set up the _consumer_. 

I'll eventually add some info on setting up the consumer, with details about using Emacs as the consumer.

## Other
### Miscellany
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
Regardless, I rarely encounter directories whose names contain characters outside the ASCII set, which means there's no need to fork.

  - The `bash` implementation doesn't use `PROMPT_COMMAND`.  `PROMPT_COMMAND` is the obvious way to implement this stuff and had served me well for a year or so.  But `pdksh` doesn't provide `PROMPT_COMMAND`, so I had to make this work in its absence.  Turns out the same approach that works for `pdksh` works for `bash`, so you're free to use `PROMPT_COMMAND` for something else.

## Bugs
It's hard to tell whether a given bug should be attributed to the producer (i.e., this implementation) or the consumer.  Testing this implementation against multiple consumers would help with this.

These implementations are “robust” to the extent that they produce messages usable by the consuming processes and directory names I've tested.  I've found that they work with all reasonable directory names and most unreasoanble ones.  For now, however, consumer can fall out of sync when the producer changes to a directory whose name is something clever, like the carriage return character.

The most “reasonable” names currently known _not_ to work are those that end with a newline character.
