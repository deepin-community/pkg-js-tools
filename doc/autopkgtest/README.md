# pkg-js-autopkgtest

autodep8 includes Node.js files to build autopkgtest files on-the-fly.

[[_TOC_]]

## What maintainer has to do

 * in debian/control, insert "Testsuite: autopkgtest-pkg-nodejs"
 * write upstream test in debian/tests/pkg-js/test (will be launched by
   sh)
 * if some other files than "test\*" and "debian/tests/test\_modules/\*"
   and installed files are needed, write a "debian/tests/pkg-js/files" with
   all needed files

That's all, other debian/tests files will be written on-the-fly by
autodep8 during autopkgtest

If you want to launch the same test during build, simply add
`dh-sequence-nodejs` in build dependencies

## How it works

 * if directory `debian/tests/test_modules` exists, `NODE_PATH` will be set
   to `NODE_PATH=debian/tests/test_modules:node_modules`
 * autopkgtest will launch 2 tests:
   - a `node -e "require('name')`
   - the test defined in debian/tests/pkg-js/test in a temporary dir (it
     links installed files)
 * if `dh-sequence-nodejs` is a build dependency, `dh_auto_test` will
   launch the same test _(debian/tests/pkg-js/test)_ if exists, else just a
   `node -e "require('.')"`. Note that you can override test during build
   using `debian/nodejs/test`
 * if file `debian/tests/pkg-js/require-name` exists, its content will be used
   as module name in "require" test _(instead of using package.json value)_

## Full example

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

## Additional test packages or test restrictions

autodep8 allows one to add additional packages during autopkgtest (and/or
additional restrictions) by using a `debian/tests/autopkgtest-pkg-nodejs.conf`
file:

```
extra_depends=mocha, npm
extra-restrictions=needs-internet
```
