cygorphan
=========
Find orphaned packages of Cygwin.

It is respected for [deborphan](http://freecode.com/projects/deborphan) and [rpmorphan](http://rpmorphan.sourceforge.net/).


How to use
----------
1. Install Ruby.
2. Just execute it.

If a message "setup.ini is not readable!!" is displayed, update the constant `SETUPINI` to your location of setup.ini file.
setup.ini file will be located at download directory of your installation.



Knowledge
---------
* You can remove orphaned packages by using `-o` or `--delete-orphans` options of `setup-x86.exe` or `setup-x86_64.exe`.
  For more details, see [FAQ of setup cli arguments](http://www.cygwin.com/faq/faq.html#faq.setup.cli).

* It may be displayed Cygwin path warning.
  The warning messages can be avoided by setting an environment variable `CYGWIN=nodosfilewarning`.
  For more details, google it :D

* You can also do the same in using `cygcheck-dep`.
  For more details of this package, install this package and execute `cygcheck-dep --help`.
  There are many more features as compared to cygorphan.

