# pkg-js-tools(7) -- collection of tools to aid packaging Node modules in Debian.

[[_TOC_]]

## WORKING WITH SALSA.DEBIAN.ORG REPOSITORY

To use salsa(1) with pkg-javascript configuration, add something like that in
your .bashrc:

```shell
alias js-salsa='salsa --conf-file +/usr/share/pkg-js-tools/pkg-js-salsa.conf'
```

Then you can use salsa simply. Some examples:

* if you created a local repo and want to create and push it on
[salsa](https://salsa.debian.org/js-team), launch simply:

    js-salsa push_repo .

* to configure a repo already pushed:

    js-salsa update_safe node-foobar

* to clone locally a js-team package:

    js-salsa co node-foobar

See salsa(1) for more.

## DEBHELPER ADDON

**pkg-js-tools** debhelper addon is automatically loaded if a package
build-depends on **dh-sequence-nodejs** or _(old fashion)_ if `dh` is called
with **--with nodejs** in `debian/rules`.

### Quick use

Examples of basic migration to pkg-js-tools:
[Switch test and install to pkg-js-tools](https://salsa.debian.org/js-team/node-static-module/-/commit/2c6d9fb1)

### How it works

pkg-js-tools provides hooks for these steps:

|     Step        |                  Comment                  |
|-----------------|-------------------------------------------|
| **configure**   | populate `node_modules/`                  |
| **build**       | build components and main module          |
| **test**        | test components and main module           |
| **install**     | install components and main module        |
| **installdocs** | can auto-generate docs for each component |
| **clean**       | clean pkg-js-tools stuff                  |

Technically, it adds `--buildsystem=nodejs` to the corresponding `dh_auto_<step>`
command.

**Important note**. Here:

* **component** is the directory name of a submodule _(uscan(1) component or
   additional components listed in `debian/nodejs/additional_components`)_.
   Example: `types-glob`
* **module** is the npmjs name. Example: `@types/glob`

See [Group Sources Tutorial](https://wiki.debian.org/Javascript/GroupSourcesTutorial)
for more about embedding components.

Details:

* **dh\_auto\_clean**, cleans files automatically installed by **pkg-js-tools**
  itself
* **dh\_auto\_configure**, automatically populates `node_modules` directory:
  * links embedded components
  * links global modules listed in `debian/nodejs/extlinks`
  * copies global modules listed in `debian/nodejs/extcopies`
* **dh\_auto\_build**, Remember to add a `dh_auto_build --buildsystem=nodejs`
  in **override_dh_auto_build** section if your `debian/rules` file has such
  section, else this step will be ignored. Builds:
  * components by launching `sh -ex debian/nodejs/<component-name>/build` in
    this file exists
  * main module by launching `sh -ex debian/nodejs/build` if exists
* **dh\_auto\_test**, tests:
  * components by launching `sh -ex debian/nodejs/<component-name>/test` if
    this file exists
  * main module by launching `sh -ex debian/tests/pkg-js/test` if this file
    exists. This test is also used by pkg-js-autopkgtest(7) during autopkgtest.
    If you want to have a different test during build, set this test in
    `debian/nodejs/test`.
* **dh\_auto\_install**: installs modules in the good directories and provides
  some debhelper variables to be used in `debian/control`. Note that if your
  package provides more that one binary package, you have to use some
  `debian/<package-name>.install` files to distribute the files.
  Steps:
  * **components**: determine files to install using the same algorithm than
    main module
    and install them:
    * nowhere if component if `debian/nodejs/submodules` exists and component
      isn't listed in it _(an empty `debian/nodejs/submodules` drops all
      components)_
    * nowhere if component is listed in `debian/nodejs/additional_components`
      with a "!" prefix
    * in main nodejs directories if component is listed in
      `debian/nodejs/root_modules`
    * else: in a `node_modules` subdirectory of main module
  * **main module**, determine files to install _(see below)_ and install them
    in the "good" directory:
    * if "architecture" is "all": `/usr/share/nodejs`
    * else: `/usr/lib/${DEB_HOST_MULTIARCH}/nodejs`
  * **links**: builds symlinks listed in `debian/nodejs/links`. Same usage
    as `debian/links` except that source or destination not starting with `/`
    are related to arch path
    _(`/usr/share/nodejs` or `/usr/lib/<gnu-arch>/nodejs`)_
  * **Build `pkgjs-lock.json`** files: if package "maybe a bundle"
    _(built with webpack, browserify,...)_, pkg-js-tools builds a
    `pkgjs-lock.json` for each module. This files may help in Debian
    transitions
  * Variables usable in `debian/control`:
    * `${nodejs:Version}`: the version of nodejs used during build
    * `${nodejs:Provides}`: virtual names to be added into "Provides:" field.
      This lists all modules installed in nodejs root directories
    * `${nodeFoo:Provides}`: for a source package that provides several binary
      packages, **dh-sequence-nodejs** filters `${nodejs:Provides}` for each
      binary package. The package name is converted into its camelcase name:
      **node-jest-worker** becomes nodeJestWorker
    * `${nodejs:BuiltUsing}`: when package "maybe a bundle", lists packages
      and versions used to build package. Use it in
      **XB-Javascript-Built-Using** field
* **dh\_installdocs**: _dh-sequence-nodejs_ provides a tool named
  **dh\_nodejs\_autodocs** which can be used in a `override_dh_installdocs`
  to automatically generate documentation for each component. See related
  manpage
* **dh\_install**: _dh-sequence-nodejs_ provides a tool named
  **dh\_nodejs\_build\_debug\_package** which can be used to build a separate
  debug package with sourcemap files when package size is too big. See related
  manpage

### Automatically detect some additional components

Starting from 0.12.0, dh-sequence-nodejs automatically reads lerna.conf and
reads "packages" field to find additional components.

Starting from 0.12.7, it does the same when package.json has a "workspaces"
field.

This auto-detection automatically drops "test" and "tests" directories. You
can override this behavior using **debian/additional\_components**.

If a component should not be considered, insert its name preceded by a "!" in
**debian/nodejs/additional\_components**.

To disable this feature, use **dh-sequence-nodejs-no-lerna**.

### Algorithm to determine files to install

**pkg-js-tools** tries to reproduce **npm(1)** behavior: it reads `package.json`
and/or `.npmignore` files to determine files to install except that it drops
licenses, \*.md, doc\*, example\*, test\*, makefiles,...`.

This behavior is overridden if:

* `debian/nodejs/install` _(or `debian/nodejs/<component-name>/install`)_
  exists. This file uses the same format than `debian/install`.
* `debian/nodejs/files` _(or `debian/nodejs/<component-name>/files`)_ exists.
  the content of this file replaces "files" entry of `package.json`

### pkg-js-tools files

* all steps:
  * **debian/nodejs/additional\_components** is used to set some
    subdirectories that should be considered as components even if they
    are not listed in `debian/watch`. Content example: `packages/*`.
    **Important note**: in this example, component name is `packages/foo` in
    every other files, including paths
  * **debian/nodejs/main** is used to indicates where is the main module.
    In a package containing only components _(bundle package)_, you should
    choose one of them as main component
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
  * **debian/nodejs/\<component\>/build**: same for components
  * **debian/nodejs/build\_order** orders components build (one component
    per line). Else components are built in alphabetic order except components
    declared in **debian/nodejs/component\_links**: a component that depends
    on another is built after
* test step:
  * **debian/tests/test\_modules/**: additional modules needed for running tests can be
    added to this directory as subdirectories, which will be linked in `node_modules`
    directory during test step only
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
      * `extra_depends=p1, p2, p3` permits one to add p1, p2 and p3 packages
      * `extra-restrictions=needs-internet` permits one to add additional restrictions
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

```deb-control
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
  `usr/share/nodejs/foo/`

* debian/node-arch-dep.install: pick files from `debian/tmp`
  `usr/lib/*/nodejs/foo/`

* debian/libjs.install: pick files from sources
  `dist/* usr/share/javascript/foo/`

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

### Component docs

Starting from version 0.13.0, **pkg-js-tools** provides **dh\_nodejs\_autodocs**.
This tool automatically install README.md, CONTRIBUTING.md,... for each
root component in its `/usr/share/doc/node-<name>` directory. And if no
`debian/*docs` is found, it does the same for the main component. To use it:

```
override_dh_installdocs:
 dh_installdocs
 dh_nodejs_autodocs
```

### .eslint* files

pkg-js-tools auto installer always removes `.eslint*` files unless it
is explicitly specified in `debian/nodejs/**/files` or
`debian/nodejs/**/install`.

### Having different test between build and autopkgtest

When `debian/nodejs/test` exists, this file is used during build test instead
of `debian/tests/pkg-js/test`. This permits one to have a different test. You can
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

## LINTIAN PROFILES

pkg-js-tools provides a lintian profile:

* pkg-js-extra: launches additional checks _(repo consistency see
  debcheck-node-repo below)_

To use them:

```shell
lintian --profile pkg-js-extra ../node-foo_1.2.3-1.changes
```

## OTHER TOOLS

See related manpages.

* **add-node-component**: automatically modifies gbp.conf and debian/watch to add
  a node component. See
  [JS Group Sources Tutorial](https://wiki.debian.org/Javascript/GroupSourcesTutorial).
  It can also list components or modules (real names)
* **getFromNpmCache**: export npm cache content to standard output
* **github-debian-upstream**: launches it in source repo to create a
  debian/upstream/metadata _(works only if upstream repo is on GitHub)_
* **nodepath**: shows the path of a node module (npm name). You can use `-p` to
  show also the Debian package. Option `-o` shows only Debian package name.
* **debcheck-node-repo**: checks repo consistency: compares vcs repo registered
  in npm registry with the source repo declared in debian/watch"
* **dh\_nodejs\_autodocs**: automatically select and install documentation files
  toinstall for each component
* **dh\_nodejs\_build\_debug\_package**: move sourcemap files from binary
  packages to a separated debug package
* **mjs2cjs**: build commonjs file using rollup
* **pkgjs-audit**: creates a temporary `package-lock.json` file using Debian
  package values used by the module to analyze, and launch a `npm audit`. If
  module is a bundle _(and then has a `pkgjs-lock.json`)_, pkgjs-audit uses
  `pkgjs-lock.json`, else it generates its package-lock.json using available
  values
* **pkgjs-depends**: search recursively dependencies of the given module name
  (if not given, use current package.json) and displays related Debian packages
  and missing dependencies
* **pkgjs-install**: same as `npm install` but uses Debian JS modules when
  available
* **pkgjs-install-minimal**: same as pkgjs-install but uses only available
  Debian modules. It is included in dh-nodejs so can be used during build
* **pkgjs-ls**: same as `npm ls` but it search also in global nodejs paths
* **pkgjs-run**: same as `npm run`
* **pkgjs-lerna run**: same as `lerna run` _(only run command is implemented)_
* **pkgjs-utils**, **pkgjs-ln**, **pkgjs-main**, **pkgjs-pjson**: various
  utilities. See `pkgjs-utils(1)` manpage.

## SEE ALSO

debhelper(7), pkg-js-autopkgtest(7), uscan(1), add-node-component(1),
github-debian-upstream(1), nodepath(1), mjs2cjs(1), pkgjs-ls(1),
pkgjs-depends(1), pkgjs-audit(1), pkgjs-utils(1), pkgjs-install(1)

## FEATURES HISTORY

|               TOOL               | Minimal version |
|----------------------------------|-----------------|
| add-node-component               |      0.8.14     |
| add-node-component --cmp-tree    |      0.9.22     |
| debcheck-node-repo               |      0.8.14     |
| dh_nodejs_autodocs               |      0.13.0     |
| dh_nodejs_autodocs auto_dispatch |      0.14.5     |
| dh_nodejs_build_debug_package    |      0.15.5     |
| dh_nodejs_substvars              |      0.14.5     |
| dh-make-node                     |      0.9.18     |
| getFromNpmCache                  |      0.14.32    |
| mjs2cjs                          |      0.12.3     |
| mjs2cjs -a                       |      0.14.14    |
| pkgjs-audit                      |      0.11.2     |
| pkgjs-depends                    |      0.9.54     |
| pkgjs-depends --graph            |      0.14.34    |
| pkgjs-install                    |      0.14.20    |
| pkgjs-install-minimal            |      0.14.27    |
| pkgjs-ln                         |      0.9.76     |
| pkgjs-lerna                      |      0.15.13    |
| pkgjs-ls                         |      0.9.30     |
| pkgjs-main                       |      0.9.76     |
| pkgjs-pjson                      |      0.9.76     |
| pkgjs-run                        |      0.14.22    |
| pkgjs-utils                      |      0.9.75     |

|              FEATURE             | Minimal version |
|----------------------------------|-----------------|
| additional\_components           |      0.9.11     |
| auto build (grunt)               |      0.9.3      |
| autopkgtest skip                 |      0.9.30     |
| auto-install (arch-dep)          |      0.9.27     |
| build order                      |      0.9.10     |
| dh-sequence-nodejs               |      0.9.41     |
| follow lerna.json#useWorkspaces  |      0.14.8     |
| .npmignore support               |      0.9.53     |
| support lerna.conf               |      0.12.0     |
| support workspaces               |      0.12.7     |
| debian/nodejs/main               |      0.9.11     |
| debian/tests/test\_modules       |      0.9.33     |
| debian/build\_modules            |      0.9.33     |
| ${nodejs:BuiltUsing}             |      0.11.8     |
| ${nodejs:Provides}               |      0.9.10     |
| ${nodejs:Version}                |      0.9.38     |
| ${nodeFoo:Provides}              |      0.14.5     |
| ordered\_components\_list        |      0.15.13    |
| packages\_list                   |      0.15.13    |

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
