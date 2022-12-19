# pkg-js-tools

pkg-js-tools is a collection of tools to aid packaging Node modules in Debian.

[[_TOC_]]

## Working with salsa.debian.org repository

To use salsa(1) with pkg-javascript configuration, add something like that in
your .bashrc:
```shell
alias js-salsa='salsa --conf-file +/usr/share/pkg-js-tools/pkg-js-salsa.conf'
```
Then you can use salsa simply. Some examples:

* if you created a local repo and want to create and push it on
https://salsa.debian.org/js-team, launch simply:

    js-salsa push_repo .

* to configure a repo already pushed:

    js-salsa update_safe node-foobar

* to clone locally a js-team package:

    js-salsa co node-foobar

See salsa(1) for more.

## Debhelper addon

Examples:
 * basic  migration to pkg-js-tools:
   [Switch install and test to pkg-js-tools](https://salsa.debian.org/js-team/node-pumpify/commit/416495cd)

pkg-js-tools provides hooks for:
 * **dh\_auto\_configure** for embedded components: it automatically
   creates links in `node_modules/` directory and removes them during clean
 * **dh\_auto\_build**: automatic build (0.9.0)
 * **dh\_auto\_test**: launch test written in `debian/tests/pkg-js/test`
   _(using `sh -e`)_. If you use pkg-js-autopkgtest, you can also use the same
   test during build.
 * **dh\_auto\_install**: automatic install (0.8.4)
   * **main module**: if no debian/install exists, pkg-js-tools will read
     package.json#files and package.json#types fields to install files. If not,
     it will install all files except \*.md, doc\*, example\*, test\*.
     **If install is not good**, use `debian/nodejs/files` to fix the list.
     Files are installed following "Architecture" field in `/usr/share/nodejs`
     or `/usr/lib/<gnu-arch>/nodejs`
   * **components**: pkg-js-tools does the same for each component in
     `<module/path>/node_modules/<component-package-name>`. To restrict this
     behavior, write a `debian/nodejs/submodules` and list the components to
     install. An empty `debian/nodejs/submodules` installs no component.
     To install some component in nodejs root directory, list them in
     `debian/nodejs/root_modules`, then pkg-js-tools will list them in
     `${nodejs:Provides}`. You can use this value in "Provides:" field
     _(in `debian/control`)_. **Warning: never add a arch-dependent
     component in a arch-indep package**
 * **dh\_link**: arch relative links (0.9.8). `dh_link` is unable to use `*`
     then we can't use `/usrlib/*/nodejs/foo/bin/run /usr/bin/foo`. This can
     be done using `debian/nodejs/links`: If source or destination does not
     start with `/`, pkg-js-tools will add arch path

Variables:
 * **${nodejs:Provides}**: components list installed in main nodejs directories
 * **${nodejs:Version}**: Node.js version used during build

Files _(use component name, not module name here if different)_:
 * all steps:
   * **debian/nodejs/additional\_components** is used to set some
     subdirectories that should be considered as components even if they
     are not listed in `debian/watch`. Content exemple: `packages/*`.
     **Important note**: in this example, component name is `packages/foo` in
     every other files, including paths
   * **debian/nodejs/main** is used to indicates where is the main module.
     Default is '.'. An empty file means that only components will be
     built and installed _(bundle package)_
 * configure step:
   * **debian/build\_modules** additional modules needed to build, will be
     linked in `node_modules` directory
   * **debian/nodejs/component\_links** lists needed links between components:
     links `../../component-src` in `component-dst/node_modules/component-src-name`
   * **debian/nodejs/\<component-name\>/nolink** avoids `node_modules` links
     creation for this component _(configuration step)_
   * **debian/nodejs/extlinks** lists installed node modules that should be
     linked into `node_modules` directory _(modules are searched using nodejs
     algorithm)_. You can mark them with "test" to avoid errors when build
     profile contains `nocheck`
   * **debian/nodejs/extcopies** lists installed node modules that should be
     copied into `node_modules` directory. You can also mark them with "test"
   * **debian/nodejs/\<component\>/extlinks** lists installed node modules that
     should be linked in `<component>/node_modules` directory _(`test` flag available)_
   * **debian/nodejs/\<component\>/extcopies** lists installed node modules that
     should be copied in `<component>/node_modules` directory _(`test` flag available)_
 * build step:
   * **debian/nodejs/build** custom build. An empty file stops auto build
   * **debian/nodejs/build\_order** orders components build (one component
     per line). Else components are built in alphabetic order except components
     declared in **debian/nodejs/links**: a component that depends on another
     is built after
   * **debian/nodejs/\<component\>/build**: same for components
 * test step:
   * **debian/tests/test\_modules**: additional modules needed for test, will
     be linked in `node_modules` directory during test step only
   * **debian/tests/pkg-js/test**: script to launch during test
     _(launched with `set -e`)_
   * **debian/tests/pkg-js/files**: lists other files than
     `debian/tests/test\_modules/\*` and installed files needed for autopkgtest
     _(default: `test*`)_
   * **debian/nodejs/test**: overwrite `debian/tests/pkg-js/test` during
     build if test differs in build and autopkgtest
   * **debian/nodejs/\<component-name\>/test**: same for components
     (launched during build only)
   * **autopkgtest files**:
     * **debian/tests/autopkgtest-pkg-nodejs.conf**: autodep8 configuration file
       which can be used to add packages or restrictions during autopkgtest only
       * `extra_depends=p1, p2, p3` permits to add p1, p2 and p3 packages
       * `extra-restrictions=needs-internet` permits to add additional restrictions
         during autopkgtest
     * **debian/tests/pkg-js/require-name**: contains the name to use in
       autopkgtest `require` test instead of package.json value
 * install step:
   * **debian/nodejs/submodules** lists components to install _(all if missing)_
   * **debian/nodejs/root\_modules** lists components to install in nodejs root
     directory _(instead of `node_modules` subdirectory)_. If this file
     contains `*`, all components are installed in root directory
   * **debian/nodejs/files** overwrites `package.json#files` field.
   * **debian/nodejs/\<component-name\>/files** overwrites `package.json#files`
     field. An empty file avoid any install
   * **debian/nodejs/name** overwrites `package.json#name` field.
   * **debian/nodejs/\<component-name\>/name** overwrites `package.json#name`
   * **debian/nodejs/install** overwrites **debian/nodejs/files**: same usage as
     debian/install except that destination not starting with `/` are related to
     arch path _(`/usr/share/nodejs` or `/usr/lib/<gnu-arch>/nodejs`)_
   * **debian/nodejs/\<component-name\>/install** same as **debian/nodejs/install**
     for components
 * link step:
   * **debian/nodejs/links**: same usage as debian/links except that source or
   destination not starting with `/` are related to arch path
   _(`/usr/share/nodejs` or `/usr/lib/<gnu-arch>/nodejs`)_

> To install a component in another directory, set its files in
**debian/install**.

Example:

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

See also [pkg-js-autopkgtest README](../autopkgtest/README.md).

### Multiple binary packages

When `debian/control` provides more than one binary package, `dh_auto_install`
populates a `debian/tmp` and `dh_install` install files in each package. In
this case, you must write a `debian/<package>.install` for each binary
package. Each line with only one argument is related to `debian/tmp`.
Examples:

 * debian/node-arch-indep.install: pick files from `debian/tmp`
```
usr/share/nodejs/foo/
```
 * debian/node-arch-dep.install: pick files from `debian/tmp`
```
usr/lib/*/nodejs/foo/
```
 * debian/libjs.install: pick files from sources
```
  dist/* usr/share/javascript/foo/
```

### Links

Since path is not fixed for arch-dependent package, you must write
`debian/nodejs/links`:
```
# debian/nodejs/links
foo/bin/cli.js  /usr/bin/foo
```

With a arch independent package, pkg-js-tools transforms this into:
```
/usr/share/nodejs/foo/bin/cli.js    /usr/bin/foo
```
and for a arch dependent package, it uses `DEB_GNU_ARCH`. Example with amd64:
```
/usr/lib/x86_64-linux-gnu/foo/bin/cli.js  /usr/bin/foo
```

All fields that does not start with `/` are prefixed with the good nodejs path

### .eslint* files

pkg-js-tools auto installer always removes `.eslint*` files unless it
is explicitly specified in `debian/nodejs/**/files` or
`debian/nodejs/**/install`.

### Having different test between build and autopkgtest

When `debian/nodejs/test` exists, this file is used during build test instead
of `debian/tests/pkg-js/test`. This permits to have a different test. You can
also overwrite `dh_auto_test` step in `debian/rules`:

```
override_dh_auto_test:
      # No test during build (test needs Internet)
```

### Autopkgtest additional test packages or test restrictions

autodep8 allows one to add additional packages during autopkgtest (and/or
additional restrictions) by using a debian/tests/autopkgtest-pkg-nodejs.conf
file:
```
extra_depends=mocha, npm
extra-restrictions=needs-internet
```

## Lintian profiles

pkg-js-tools provides a lintian profile:
 * pkg-js-extra: launches additional checks _(repo consistency see
   debcheck-node-repo below)_

To use them:
```shell
lintian --profile pkg-js-extra ../node-foo_1.2.3-1.changes
```
## Other tools

* add-node-component: automatically modifies gbp.conf and debian/watch to add
  a node component. See
  [JS Group Sources Tutorial](https://wiki.debian.org/Javascript/GroupSourcesTutorial).
  It can also list components or modules (real names)
* github-debian-upstream: launches it in source repo to create a
  debian/upstream/metadata _(works only if upstream repo is on GitHub)_
* nodepath: shows the path of a node module (npm name). You can use `-p` to show
  also the Debian package. Option `-o` shows only Debian package name.
* debcheck-node-repo: checks repo consistency: compares vcs repo registered in
  npm registry with the source repo declared in debian/watch"
* pkgjs-ls: same as `npm ls` but it search also in global nodejs paths
* pkgjs-depends: search recursively dependencies of the given module name (if
  not given, use current package.json) and displays related Debian packages and
  missing dependencies
