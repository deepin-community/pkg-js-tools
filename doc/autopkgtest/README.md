# pkg-js-autopkgtest(7) -- autopkgtest runner to automatically test Node.js packages

[[_TOC_]]

## SYNOPSIS

* in debian/control, insert "Testsuite: autopkgtest-pkg-nodejs"
* write upstream test in debian/tests/pkg-js/test (will be launched by
  `sh -e`)
* if some other files than "test\*" and "debian/tests/test\_modules/\*"
  and installed files are needed, write a "debian/tests/pkg-js/files" with
  all needed directories/files

That's all, other debian/tests files will be written on-the-fly by
autodep8 during autopkgtest

If you want to launch the same test during build, simply add
`dh-sequence-nodejs` in build dependencies

## HOW IT WORKS

* if directory `debian/tests/test_modules` exists, `NODE_PATH` will be set
  to `NODE_PATH=debian/tests/test_modules:node_modules`
* if additional modules were linked during build, they will be linked into
  `node_module` _(`debian/nodejs/extlinks`)_
* if additional modules were copies during build, they will be copied into
  `node_module` _(`debian/nodejs/extcopies`)_
* if package contains some other components, they will be linked into
  `node_module`
* autopkgtest will launch 2 tests:
  * a "require" test _(see below)_
  * the test defined in debian/tests/pkg-js/test in a temporary dir (it
    links installed files)
* if `dh-sequence-nodejs` is a build dependency, `dh_auto_test` will
  launch the same test _(debian/tests/pkg-js/test)_ if exists, else just a
  `node -e "require('.')"`. Note that you can override test during build
  using `debian/nodejs/test`
* if file `debian/tests/pkg-js/require-name` exists, its content will be used
  as module name in "require" test _(instead of using package.json value)_

## FULL EXAMPLE

* debian/control

```
...
Testsuite: autopkgtest-pkg-nodejs
Build-Depends: dh-sequence-nodejs
...
```

* debian/tests/pkg-js/test

```shell
mocha -R spec
```

## ADDITIONAL TEST PACKAGES OR TEST RESTRICTIONS

autodep8 allows one to add additional packages during autopkgtest (and/or
additional restrictions) by using a `debian/tests/autopkgtest-pkg-nodejs.conf`
file:

```
extra_depends=mocha, npm
extra-restrictions=needs-internet
```

## ENABLE __proto__

Since version 0.15.0, pkg-js-autopkgtest launches Node.js with
`--disable-proto=throw`. This causes tests to fail if
`Object.prototype.__proto__` property is used.

If a package can use this feature without security hole (for test for example),
it is possible to disable this nodejs option by creating an empty
`debian/tests/pkg-js/enable_proto` file, until Debian's Node.js enables this
feature by default.

## THE "REQUIRE" TEST

### How it works

First, __pkg-js-autopkgtest__ searches the module name.

* if `debian/tests/pkg-js/require-name` exists, its content will be used as
  module name
* else if looks at `package.json` "name" field:
  * if `debian/nodejs/main` exists, like __dh-sequence-nodejs__, it uses the
    `package.json` from this directory
  * else it uses `./package.json`

Then __pkg-js-autopkgtest__ looks at package.json fields, not using the file
mentioned above, but using the file installed by the Debian package to test
_(ie `/usr/share/nodejs/<module-name>/package.json`)_:

* if __type__ equals `module`, then:
  * it builds a `node_modules` directory with all available dependencies of
    the module
  * it builds a test.mjs file that tries to import the module to test and
    launch it
* if __main__ isn't defined and `index.js` doesn't exist, it skip the test
  _(this avoids to try to test `@types/<foo>` modules)_
* else it simply launches a `nodejs -e "require('$moduleName')"`

Since version 0.10.0, __pkg-js-autopkgtest__ does the same test for all other
modules installed in nodejs root directories _(components installed by
dh-sequence-nodejs using `debian/nodejs/root_modules` file)_. If one fail, the
whole test is marked as failed.

Returned values:

* 0 if all tests succeed _(even if some secondary modules are skipped)_
* 77 if all tests succeed but the main module test was skipped. This value
  is used by autopkgtest to report a __SKIP__ instead of a failure.
* else, the number of failure. Then autopkgtest considers the test as __FAIL__

### Customize require test

If you want to skip some secondary module tests, simply list them in
`debian/tests/pkg-js/require-SKIP` _(one module per line)_.

If you want to skip the whole "require" test, use this:

```shell
echo require > debian/tests/pkg-js/SKIP
```

## THE MAIN TEST

__pkg-js-autopkgtest__ uses the same test than __dh-sequence-nodejs__: it
launches `sh -ex debian/tests/pkg-js/test` but using the files installed by
the Debian package.

### How main test works

__pkg-js-autopkgtest__ search for module name using the same way than "require"
test. Then it prepares the test environment:

* it creates a temporary directory
* it links all files installed in the directory corresponding to module name
  `/usr/share/nodejs/<module-name>`
* it creates a `node_modules` directory and links into it:
  * all modules listed in `debian/nodejs/extlinks`
  * all modules present in `debian/build_modules` and `debian/tests/test_modules`
  * all other modules installed by the Debian package in nodejs root directories
    `debian/nodejs/root_modules`
* it copies in `node_modules` directory all modules listed in
   `debian/nodejs/extcopies`
* if looks at `debian/tests/pkg-js/files`
  * if it exists, it copies all files/directories listed in it from source
     directory to temporary one
  * else it copies from source directory to temporary one:
    * all `test*` files
    * all `Makefile` like files _(rollup.config.js, gulpfile.js,... )_

Then it changes its directory to the temporary one launches the test using
`sh -ex debian/tests/pkg-js/test`.

## SEE ALSO

pkg-js-tools(7), autodep8(1)

## COPYRIGHT AND LICENSE

Copyright Yadd \<yadd@debian.org\>

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

On Debian systems, the complete text of version 2 of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-2'.
If not, see [GNU licenses](http://www.gnu.org/licenses/);
