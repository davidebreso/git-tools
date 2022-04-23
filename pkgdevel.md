# Package Dev Kit

Package Development Kit for FreeDOS

This project is a work in progress and is far from done.

Excluding the fdvcs.sh utility, most others are just one-offs that were made
to simplify something that needed done one time. The one-offs aren't really
maintained.

The most useful thing in the project is the _**tools/fdvcs.sh**_ script. Among other
things, it can preserve timestamps. More functionality will be coming to it
and probably additional scripts/utilities will be added sooner or later. It
already simplifies several things.


For example, to checkout/clone a project from [this repository](https://gitlab.com/FDOS/). Like **APPEND**,
simply perform a

    fdvcs.sh -co append

It will query the [Official Software Repository](https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/repositories/latest/pkg-html/index.html) on IBIBLIO, to determine the
package's group. Then, it will clone the appropriate project (assuming it
exists and you have permission to view it). And then restore the timestamps.
This function is specific to FreeDOS packages stored in [this repository](https://gitlab.com/FDOS/).
Other functionality provided by the _**fdvcs.sh**_ script should function with
any Git repository.  Then after changes are made. If you have permission
to update that project, you can just issue a:

    fdvcs.sh -c "Some Message About My Changes"

It will check for any modified files. Then commit your changes, update the
timestamp recovery file, commit that and finally push all commits to the git
server. You can restore and/or preserve timestamps in the local repository
any time by running

    fdvcs.sh -s

Please note: only the timestamps of the files managed by git in the repository
are restored and preserved. Also, any files that have been modified will not
have their timestamps restored. However when they have been modified, they will
replace the old timestamp information in the timestamp file.

Additionally, you can override the automatic timestamp handling when doing a
commit or cloning a project. Just include a _**-x**_ option.

Also, you can clone every project from this repository (that you have
permission to access) with a simple

    fdvcs.sh -coa

But, that is time consuming and I don't recommend most people use that.

Anyhow, like I said it is a work in progress. Although the timestamp stuff
could be improved and faster, it works very well and it is "_good enough_"
for now as-is.

Oh, you don't need to memorize any of those switches. Just do a

    fdvcs.sh -h

when you forget them.

### editlsm.sh

Simple script to bulk edit numerous package metadata files. When invoked provided
the name of the package. It will open the file for editing. After saving and
closing the file. Just type the next package name and repeat the process. When
finished, just hit enter to exit the loop.

	editlsm.sh freecom
	<edit freecom's lsm file, save and exit>
	kernel
	<edit kernel's lsm file, save and exit>
	<....>
	<press enter to exit>

It will try to use bbedit to edit the files. If that fails, it will open them
in vi. (automatically commits edits)

### sumtext.sh

Simple script that by default outputs all checked out package Descriptions
and Summaries to a stdout.

If run using --apply filename, then it will use a sumtext.sh formated file to
update and replace the appropriate fields in the packages metadata and commit
the modifications.

### nomoddate.sh

Simple script that strips the Modified-Date out of the LSM metadata files for
packages and commits the changes.


:-)
